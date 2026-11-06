package hnoss

import "core:encoding/base64"
import "core:mem"
import "core:os"
import "core:time"
import "core:unicode/utf8"
import "backend"
import "buffer"
import "input"
import "layout"
import "style"
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
Focus :: input.Focus
is_char :: input.is_char
is_focus :: input.is_focus
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

	// Counts double / triple clicks into Mouse.clicks. Set
	// `clicks.interval` to change how fast they must be (default 400 ms).
	clicks:         input.Click_Tracker,

	// What the diff downsamples colors to. init detects it from the
	// environment (see detect_color_depth); change it with set_color_depth.
	color_depth:    Color_Depth,

	widget_memory:  widgets.Memory, // focus / drag state that outlives a frame
	cursor_shown:   bool,
	cursor_shape:   [2]u8, // shape and blink last sent with DECSCUSR; {0, 0} = the terminal default
}

// What a frame's draw code works with. Valid between begin_frame and end_frame.
Frame :: struct {
	area:   Rect, // the whole terminal
	buffer: ^Buffer,
	count:  u64, // frame number, starting at 0
	cursor: widgets.Cursor, // set it visible to show the terminal cursor there
	memory: ^widgets.Memory,
	ui:     ^widgets.Ui, // set by `ui`; end_frame draws its overlay layer
}

init :: proc(opts := DEFAULT_OPTIONS, allocator := context.allocator) -> (t: Terminal, err: Error) {
	t.allocator = allocator
	t.esc_timeout_ms = DEFAULT_ESC_TIMEOUT_MS
	t.color_depth = detect_color_depth()
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
	if t.frame.ui != nil {
		widgets.end(t.frame.ui)
		t.frame.ui = nil
	}
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
	buffer.diff(front, back, &b.out, t.color_depth)
	if c := t.frame.cursor; c.visible && layout.rect_contains(back.area, c.x, c.y) {
		buffer.move_to(&b.out, c.x, c.y)
		shape := [2]u8{u8(c.shape), u8(c.blink)}
		if shape != t.cursor_shape {
			append_cursor_shape(&b.out, c.shape, c.blink)
			t.cursor_shape = shape
		}
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

// Appends DECSCUSR: CSI n SP q, n = 1/2 block, 3/4 underline, 5/6 bar
// (odd ones blink), 0 the terminal's default.
append_cursor_shape :: proc(out: ^[dynamic]u8, shape: widgets.Cursor_Shape, blink: bool) {
	n := 0
	if shape != .Default {
		n = 2 * int(shape) - (1 if blink else 0)
	}
	append(out, "\x1b[")
	append(out, u8('0' + n))
	append(out, " q")
}

// Copies `text` to the system clipboard with OSC 52. It works over SSH too,
// as the terminal does the copying; terminals that don't support it (or
// have it turned off) ignore it. Sent with the next end_frame.
set_clipboard :: proc(t: ^Terminal, text: string) {
	encoded := base64.encode(transmute([]u8)text, allocator = context.temp_allocator)
	backend.write(&t.backend, "\x1b]52;c;")
	backend.write(&t.backend, encoded)
	backend.write(&t.backend, "\x07")
}

// Sets the window title (OSC 2). The original title comes back on deinit
// (on terminals with a title stack, XTWINOPS 22/23). Control characters
// are dropped so the title can't end the sequence early. Sent with the
// next end_frame.
set_title :: proc(t: ^Terminal, title: string) {
	backend.write(&t.backend, "\x1b]2;")
	for r in title {
		if r >= ' ' && r != 0x7f && !(r >= 0x80 && r < 0xa0) {
			buf, n := utf8.encode_rune(r)
			backend.write(&t.backend, string(buf[:n]))
		}
	}
	backend.write(&t.backend, "\x07")
}

// Overrides the detected color depth, e.g. from a --color flag. The next
// frame repaints the whole screen in the new depth.
set_color_depth :: proc(t: ^Terminal, depth: Color_Depth) {
	if depth != t.color_depth {
		t.color_depth = depth
		t.needs_clear = true
	}
}

// The color depth the environment asks for: NO_COLOR, COLORTERM, TERM and
// TERM_PROGRAM, as style.detect_color_depth reads them.
detect_color_depth :: proc() -> Color_Depth {
	return style.detect_color_depth({
		no_color     = os.get_env("NO_COLOR", context.temp_allocator),
		colorterm    = os.get_env("COLORTERM", context.temp_allocator),
		term         = os.get_env("TERM", context.temp_allocator),
		term_program = os.get_env("TERM_PROGRAM", context.temp_allocator),
	})
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
			first := len(events)
			input.feed(&t.parser, t.read_buf[:res.n], &events, allocator)
			now := time.tick_now()
			for &ev in events[first:] {
				if m, ok := &ev.(Mouse); ok {
					input.track_click(&t.clicks, m, now)
				}
			}
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
