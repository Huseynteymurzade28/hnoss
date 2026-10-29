package hnoss

import "core:mem"
import "backend"
import "buffer"
import "input"
import "layout"
import "widgets"

Rect :: layout.Rect
Buffer :: buffer.Buffer
Error :: backend.Error
Option :: backend.Option
Options :: backend.Options
DEFAULT_OPTIONS :: backend.DEFAULT_OPTIONS

// Install in main so a panic restores the terminal *before* its message is
// printed (otherwise the message lands on the alternate screen and is lost):
//	context.assertion_failure_proc = hnoss.assertion_failure_proc
assertion_failure_proc :: backend.assertion_failure_proc

Event :: input.Event
Key :: input.Key
Key_Code :: input.Key_Code
Key_Modifiers :: input.Key_Modifiers
Mouse :: input.Mouse
Paste :: input.Paste
Resize :: input.Resize
is_char :: input.is_char
is_key :: input.is_key

// How long a lone ESC waits for the rest of an escape sequence before it is
// reported as the Esc key. Long enough for sequences split by a slow link,
// short enough not to feel laggy.
DEFAULT_ESC_TIMEOUT_MS :: 25

// Owns the terminal and two buffers: `front` is what is on screen, `back`
// is what the current frame draws into. end_frame diffs back against front,
// writes the difference in one go, then swaps them.
Terminal :: struct {
	backend:      backend.Backend,
	buffers:      [2]Buffer,
	current:      int, // index of the back buffer
	frame:        Frame,
	frame_count:  u64,
	needs_clear:  bool,
	last_bytes:   int, // bytes written by the last end_frame, for diagnostics
	allocator:    mem.Allocator,

	parser:         input.Parser,
	read_buf:       [4096]u8,
	esc_timeout_ms: int,
	// Set when poll_events hits a terminal error (e.g. .Hangup); it then
	// returns no events. Check it in the main loop to exit cleanly.
	error:          Error,

	// The terminal confirmed the kitty keyboard protocol (see
	// Option.Kitty_Keyboard). Set after the first poll that sees the reply.
	kitty_keyboard: bool,

	widget_memory:  widgets.Memory, // focus / drag state that outlives a frame
	cursor_shown:   bool,
}

// What a frame's draw code works with. Valid between begin_frame and end_frame.
Frame :: struct {
	area:   Rect, // the whole terminal
	buffer: ^Buffer,
	count:  u64, // frame number, starting at 0
	cursor: widgets.Cursor, // set it visible to show the terminal cursor there
	memory: ^widgets.Memory,
}

init :: proc(opts := DEFAULT_OPTIONS, allocator := context.allocator) -> (t: Terminal, err: Error) {
	t.allocator = allocator
	t.esc_timeout_ms = DEFAULT_ESC_TIMEOUT_MS
	backend.init(&t.backend, opts, allocator) or_return
	defer if err != .None { backend.deinit(&t.backend) }

	sz := backend.size(&t.backend) or_return
	area := Rect{0, 0, sz.cols, sz.rows}
	for &b in t.buffers {
		if buffer.init(&b, area, allocator) != nil {
			return t, .Out_Of_Memory
		}
	}
	input.parser_init(&t.parser, allocator)
	return t, .None
}

deinit :: proc(t: ^Terminal) {
	input.parser_destroy(&t.parser)
	for &b in t.buffers {
		buffer.destroy(&b)
	}
	backend.deinit(&t.backend)
}

// Starts a frame. Picks up terminal resizes here, so a frame always matches
// the current size. The returned Frame starts blank.
begin_frame :: proc(t: ^Terminal) -> ^Frame {
	if sz, err := backend.size(&t.backend); err == .None {
		area := Rect{0, 0, sz.cols, sz.rows}
		if area != t.buffers[0].area {
			for &b in t.buffers {
				if buffer.resize(&b, area) != nil {
					panic("hnoss: out of memory resizing frame buffers")
				}
			}
			t.needs_clear = true
		}
	}
	back := &t.buffers[t.current]
	buffer.reset(back)
	t.frame = {area = back.area, buffer = back, count = t.frame_count, memory = &t.widget_memory}
	return &t.frame
}

// Diffs the frame against what is on screen and writes the changes with a
// single flush.
end_frame :: proc(t: ^Terminal) -> Error {
	back := &t.buffers[t.current]
	front := &t.buffers[1 - t.current]

	b := &t.backend
	start := len(b.out)
	backend.write(b, buffer.BEGIN_SYNC)
	if t.needs_clear {
		// After a clear the screen is blank, which is exactly an empty
		// buffer: diffing against one redraws everything that isn't blank.
		backend.write(b, backend.RESET_SGR)
		backend.write(b, backend.CLEAR_SCREEN)
		buffer.reset(front)
		t.needs_clear = false
	}
	buffer.diff(front, back, &b.out)
	if c := t.frame.cursor; c.visible && layout.rect_contains(back.area, c.x, c.y) {
		buffer.move_to(&b.out, c.x, c.y)
		backend.write(b, backend.SHOW_CURSOR)
		t.cursor_shown = true
	} else if t.cursor_shown {
		backend.write(b, backend.HIDE_CURSOR)
		t.cursor_shown = false
	}
	backend.write(b, buffer.END_SYNC)
	t.last_bytes = len(b.out) - start

	t.current = 1 - t.current
	t.frame_count += 1
	return backend.flush(b)
}

// Forces the next frame to repaint the whole screen (e.g. after something
// else wrote to the terminal).
clear :: proc(t: ^Terminal) {
	t.needs_clear = true
}

// Waits up to `timeout_ms` (-1 = forever, 0 = just check) for input and
// returns every event that arrived. The slice and any Paste text live in
// `allocator`, by default the frame's temp allocator.
//
//	for ev in hnoss.poll_events(&term, 16) {
//		if hnoss.is_char(ev, 'q') { running = false }
//	}
poll_events :: proc(t: ^Terminal, timeout_ms: int, allocator := context.temp_allocator) -> []Event {
	events := make([dynamic]Event, allocator)
	if t.error != .None {
		return events[:]
	}

	timeout := timeout_ms
	waited_for_esc := false
	for {
		res, err := backend.read(&t.backend, t.read_buf[:], timeout)
		if err != .None {
			t.error = err
			break
		}
		if res.resized {
			if sz, serr := backend.size(&t.backend); serr == .None {
				append(&events, Resize{sz.cols, sz.rows})
			}
		}
		if res.n > 0 {
			input.feed(&t.parser, t.read_buf[:res.n], &events, allocator)
			t.kitty_keyboard = t.parser.keyboard_flags > 0
		}

		switch {
		case res.n == len(t.read_buf):
			timeout = 0 // buffer was full: there is probably more waiting
		case input.has_pending(&t.parser):
			if res.n == 0 && waited_for_esc {
				// Nothing more arrived in time: a lone ESC really is Esc.
				input.flush(&t.parser, &events, allocator)
				return events[:]
			}
			timeout = t.esc_timeout_ms
			waited_for_esc = true
		case:
			return events[:]
		}
	}
	return events[:]
}
