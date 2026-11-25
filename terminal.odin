package hnoss

import "core:encoding/base64"
import "core:mem"
import "core:os"
import "core:strings"
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
Output_Feature :: buffer.Output_Feature
Output_Features :: buffer.Output_Features

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
Caps :: input.Caps
Mode_State :: input.Mode_State
mode_supported :: input.mode_supported
caps_version :: input.caps_version
is_char :: input.is_char
is_focus :: input.is_focus
is_key :: input.is_key
parse_key :: input.parse_key
key_name :: input.key_name
Binding :: input.Binding
Keymap :: input.Keymap
keymap_init :: input.keymap_init
keymap_destroy :: input.keymap_destroy
keymap_bind :: input.keymap_bind
keymap_unbind :: input.keymap_unbind
keymap_rebind :: input.keymap_rebind
keymap_lookup :: input.keymap_lookup
keymap_keys :: input.keymap_keys
keymap_pending :: input.keymap_pending

// How long a lone ESC waits for the rest of an escape sequence before it is
// reported as the Esc key. Long enough for sequences split by a slow link,
// short enough not to feel laggy.
DEFAULT_ESC_TIMEOUT_MS :: 25

// How long init waits for the terminal to answer the capability queries.
// Local terminals answer in a millisecond or two; on a slow link the
// replies that come later are still picked up by poll_events.
CAPS_TIMEOUT_MS :: 100
// After this long without the closing DA1 reply, stop expecting replies.
CAPS_GIVE_UP_MS :: 2000

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
	// Underline shapes / colors and hyperlinks, as far as the terminal
	// shows them. init detects them (see detect_output_features); change
	// them with set_output_features.
	output_features: Output_Features,

	// What the terminal said about itself (Option.Query_Caps).
	// `caps.answered` is true once all replies are in; init waits up to
	// CAPS_TIMEOUT_MS for them. A confirmed truecolor or a terminal known
	// for styled underlines upgrades color_depth and output_features,
	// unless set_color_depth / set_output_features chose them.
	caps:             Caps,
	caps_sent:        time.Tick,
	caps_applied:     bool,
	depth_chosen:     bool,
	features_chosen:  bool,
	early_events:     [dynamic]Event, // input that arrived while init waited for caps

	widget_memory:  widgets.Memory, // focus / drag state that outlives a frame
	cursor_shown:   bool,
	cursor_shape:   [2]u8, // shape and blink last sent with DECSCUSR; {0, 0} = the terminal default
	title_buf:      [256]u8, // last set_title (truncated), sent again after a suspend
	title_len:      int,
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
	t.output_features = detect_output_features()
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
	t.early_events = make([dynamic]Event, allocator)
	if .Query_Caps in opts {
		query_caps(&t)
	}
	return t, .None
}

@(private = "file")
query_caps :: proc(t: ^Terminal) {
	backend.write(&t.backend, input.CAPS_QUERY)
	if backend.flush(&t.backend) != .None {
		return
	}
	input.await_replies(&t.parser)
	t.caps_sent = time.tick_now()
	for !t.parser.caps.answered {
		left := CAPS_TIMEOUT_MS - int(time.duration_milliseconds(time.tick_since(t.caps_sent)))
		if left <= 0 {
			break
		}
		res, err := backend.read(&t.backend, t.read_buf[:], left)
		if err != .None {
			break
		}
		// Anything typed meanwhile is kept for the first poll_events.
		input.feed(&t.parser, t.read_buf[:res.n], &t.early_events, t.allocator)
	}
	t.kitty_keyboard = t.parser.keyboard_flags > 0
	sync_caps(t)
}

// Copies the parser's caps and, once they are complete, lets them upgrade
// what the environment guessed.
@(private = "file")
sync_caps :: proc(t: ^Terminal) {
	if t.parser.awaiting_replies && time.duration_milliseconds(time.tick_since(t.caps_sent)) > CAPS_GIVE_UP_MS {
		input.stop_awaiting_replies(&t.parser)
	}
	t.caps = t.parser.caps
	if !t.caps.answered || t.caps_applied {
		return
	}
	t.caps_applied = true
	depth, features := upgrade_from_caps(&t.caps, t.color_depth, t.output_features)
	if !t.depth_chosen && depth != t.color_depth {
		t.color_depth = depth
		t.needs_clear = true
	}
	if !t.features_chosen && features != t.output_features {
		t.output_features = features
		t.needs_clear = true
	}
}

// What `caps` adds to the color depth and output features guessed from
// the environment. It only ever upgrades: NO_COLOR stays No_Color, and a
// terminal that doesn't answer changes nothing.
upgrade_from_caps :: proc(caps: ^Caps, depth: Color_Depth, features: Output_Features) -> (Color_Depth, Output_Features) {
	d, f := depth, features
	if caps.truecolor && (d == .Ansi16 || d == .Ansi256) {
		d = .Truecolor
	}
	if style.detect_styled_underlines({xtversion = input.caps_version(caps)}) {
		f += {.Styled_Underlines}
	}
	return d, f
}

deinit :: proc(t: ^Terminal) {
	for ev in t.early_events {
		if p, ok := ev.(Paste); ok { delete(p.text, t.allocator) }
	}
	delete(t.early_events)
	input.parser_destroy(&t.parser)
	for &b in t.buffers {
		buffer.destroy(&b)
	}
	backend.deinit(&t.backend)
}

// Starts a frame. Picks up terminal resizes here, so a frame always matches
// the current size. The returned Frame starts blank.
begin_frame :: proc(t: ^Terminal) -> ^Frame {
	check_resumed(t)
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
	buffer.diff(front, back, &b.out, t.color_depth, t.output_features)
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
	n := copy(t.title_buf[:], title)
	for n < len(title) && n > 0 && title[n] & 0xc0 == 0x80 {
		n -= 1 // don't cut a UTF-8 sequence in half
	}
	t.title_len = n
	write_title(t, title)
}

@(private = "file")
write_title :: proc(t: ^Terminal, title: string) {
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
	t.depth_chosen = true
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

// Overrides the detected output features. The next frame repaints the
// whole screen with them.
set_output_features :: proc(t: ^Terminal, features: Output_Features) {
	t.features_chosen = true
	if features != t.output_features {
		t.output_features = features
		t.needs_clear = true
	}
}

// What the environment says the terminal can show: underline shapes and
// colors as style.detect_styled_underlines guesses them; hyperlinks
// everywhere but TERM=dumb and the Linux console (terminals that don't
// know OSC 8 ignore it).
detect_output_features :: proc() -> Output_Features {
	env := style.Color_Env {
		term         = os.get_env("TERM", context.temp_allocator),
		term_program = os.get_env("TERM_PROGRAM", context.temp_allocator),
		vte_version  = os.get_env("VTE_VERSION", context.temp_allocator),
	}
	return output_features_for(env)
}

// detect_output_features for a given environment.
output_features_for :: proc(env: style.Color_Env) -> Output_Features {
	f: Output_Features
	if style.detect_styled_underlines(env) {
		f += {.Styled_Underlines}
	}
	if env.term != "dumb" && env.term != "linux" {
		f += {.Hyperlinks}
	}
	return f
}

// Restores the terminal and stops the process, as Ctrl+Z does in a shell;
// with Option.Ctrl_Z_Suspends (on by default) poll_events calls it for
// Ctrl+Z. Returns once the shell continues the process (`fg`), with raw
// mode, the alt screen, mouse capture etc. back and a full redraw due on the
// next frame.
suspend :: proc(t: ^Terminal) -> Error {
	err := backend.suspend(&t.backend)
	check_resumed(t)
	return err
}

// After a stop and continue (ours or from outside) the screen is not what
// `front` says, and the terminal forgot the title and cursor shape.
@(private = "file")
check_resumed :: proc(t: ^Terminal) -> bool {
	if !backend.take_resumed() {
		return false
	}
	t.needs_clear = true
	t.cursor_shape = {}
	t.cursor_shown = false
	if t.title_len > 0 {
		write_title(t, string(t.title_buf[:t.title_len]))
	}
	return true
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
	if len(t.early_events) > 0 {
		for ev in t.early_events {
			if p, ok := ev.(Paste); ok {
				append(&events, Paste{strings.clone(p.text, allocator)})
				delete(p.text, t.allocator)
			} else {
				append(&events, ev)
			}
		}
		resize(&t.early_events, 0)
		timeout = 0 // they are waiting already
	}
	waited_for_esc := false
	for {
		res, err := backend.read(&t.backend, t.read_buf[:], timeout)
		if err != .None {
			t.error = err
			break
		}
		resumed := check_resumed(t)
		if res.resized || resumed {
			// A Resize after a resume too, so an app that only redraws on
			// events repaints (the size may have changed meanwhile anyway).
			if sz, serr := backend.size(&t.backend); serr == .None {
				append(&events, Resize{sz.cols, sz.rows})
			}
		}
		if res.n > 0 {
			first := len(events)
			input.feed(&t.parser, t.read_buf[:res.n], &events, allocator)
			now := time.tick_now()
			for i := first; i < len(events); i += 1 {
				if m, ok := &events[i].(Mouse); ok {
					input.track_click(&t.clicks, m, now)
				} else if .Ctrl_Z_Suspends in t.backend.opts && input.is_char(events[i], 'z', {.Ctrl}) {
					ordered_remove(&events, i)
					i -= 1
					if suspend(t) == .None {
						resumed = true
						if sz, serr := backend.size(&t.backend); serr == .None {
							append(&events, Resize{sz.cols, sz.rows})
						}
					}
				}
			}
			t.kitty_keyboard = t.parser.keyboard_flags > 0
			sync_caps(t)
		}
		if resumed && !input.has_pending(&t.parser) {
			return events[:]
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
