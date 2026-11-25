package tests

import "core:fmt"
import "core:strconv"
import "core:strings"
import "core:testing"
import "core:unicode/utf8"
import "../buffer"
import "../input"
import "../widgets"

// Input written as text, for tests that take a widget through several
// frames. Steps are separated by spaces, frames by `|` or a line break:
//
//	Down Ctrl+S          keys, as in input.parse_key
//	"hello"              one key per character; \" and \\ inside
//	paste:"two words"    a bracketed paste
//	click:4,2            press and release of the left button
//	double-click:4,2     the same twice, right-click:4,2
//	press:4,2 drag:6,2 release:6,2 move:1,1 wheel-up:4,2 wheel-down:4,2
//	focus-in focus-out   the terminal window
//	resize:80x24
//
// The key | is written "|".
parse_script :: proc(script: string) -> (frames: [][]input.Event, err: string) {
	out := make([dynamic][]input.Event, context.temp_allocator)
	cur := make([dynamic]input.Event, context.temp_allocator)
	rest := strings.trim_space(script)
	for {
		rest = strings.trim_left(rest, " \t\r")
		if rest == "" { break }
		if rest[0] == '|' || rest[0] == '\n' {
			// One break, whether a `|`, line breaks or both around each other.
			rest = strings.trim_left_space(rest)
			if strings.has_prefix(rest, "|") {
				rest = strings.trim_left_space(rest[1:])
			}
			append(&out, cur[:])
			cur = make([dynamic]input.Event, context.temp_allocator)
			continue
		}
		word: string
		if word, err = next_word(&rest); err != "" { return nil, err }
		if err = script_step(word, &cur); err != "" { return nil, err }
	}
	append(&out, cur[:])
	return out[:], ""
}

// Runs script frames against a widget: a screen, and the memory a Terminal
// would keep.
Driver :: struct {
	buf:    buffer.Buffer,
	mem:    widgets.Memory,
	cursor: widgets.Cursor,
}

driver :: proc(w, h: int) -> ^Driver {
	d := new(Driver, context.temp_allocator)
	buffer.init(&d.buf, {0, 0, w, h}, context.temp_allocator)
	return d
}

// Draws one frame per script frame by calling `draw` with `state`; an empty
// script is one frame without input. Check the screen after it:
//
//	drive(t, d, `"ab" | Left "x"`, &st, draw)
//	expect_screen(t, &d.buf, `axb`)
drive :: proc(t: ^testing.T, d: ^Driver, script: string, state: ^$S, draw: proc(ui: ^widgets.Ui, state: ^S), loc := #caller_location) -> bool {
	frames, err := parse_script(script)
	testing.expectf(t, err == "", "script: %s", err, loc = loc) or_return
	for events in frames {
		for ev in events {
			if r, ok := ev.(input.Resize); ok {
				buffer.init(&d.buf, {0, 0, r.cols, r.rows}, context.temp_allocator)
			}
		}
		buffer.reset(&d.buf)
		d.cursor = {}
		ui := widgets.begin(&d.buf, events, &d.mem, &d.cursor)
		draw(ui, state)
		widgets.end(ui)
	}
	return true
}

// Cuts the next step off `rest`: up to white space or `|`, quoted parts
// kept whole.
@(private = "file")
next_word :: proc(rest: ^string) -> (word: string, err: string) {
	s := rest^
	quoted := false
	i := 0
	loop: for i < len(s) {
		switch s[i] {
		case '"':
			quoted = !quoted
		case '\\':
			if quoted { i += 1 }
		case ' ', '\t', '\r', '\n', '|':
			if !quoted { break loop }
		}
		i += 1
	}
	if quoted || i > len(s) { return "", fmt.tprintf("unclosed quote: %s", s) }
	rest^ = s[i:]
	return s[:i], ""
}

@(private = "file")
script_step :: proc(word: string, out: ^[dynamic]input.Event) -> (err: string) {
	if len(word) > 1 && word[0] == '"' {
		text: string
		if text, err = unquote(word); err != "" { return }
		for r in text {
			append(out, input.Key{code = .Char, char = r})
		}
		return ""
	}
	// A key first: names hold no ':', and ":" alone is one.
	if k, ok := input.parse_key(word); ok {
		append(out, k)
		return ""
	}
	switch word {
	case "focus-in":
		append(out, input.Focus{true})
		return ""
	case "focus-out":
		append(out, input.Focus{false})
		return ""
	}
	colon := strings.index_byte(word, ':')
	if colon < 0 { return fmt.tprintf("unknown step: %s", word) }
	name, arg := word[:colon], word[colon + 1:]

	if name == "paste" {
		p: input.Paste
		if p.text, err = unquote(arg); err != "" { return }
		append(out, p)
		return
	}
	if name == "resize" {
		w, h, ok := two_numbers(arg, 'x')
		if !ok || w < 1 || h < 1 { return fmt.tprintf("bad size: %s", word) }
		append(out, input.Resize{w, h})
		return ""
	}

	x, y, ok := two_numbers(arg, ',')
	if !ok { return fmt.tprintf("bad position: %s", word) }
	click :: proc(out: ^[dynamic]input.Event, button: input.Mouse_Button, x, y: int, clicks: u8) {
		append(out, input.Mouse{kind = .Press, button = button, x = x, y = y, clicks = clicks})
		append(out, input.Mouse{kind = .Release, button = button, x = x, y = y, clicks = clicks})
	}
	switch name {
	case "click":       click(out, .Left, x, y, 1)
	case "right-click": click(out, .Right, x, y, 1)
	case "double-click":
		click(out, .Left, x, y, 1)
		click(out, .Left, x, y, 2)
	case "press":       append(out, input.Mouse{kind = .Press, button = .Left, x = x, y = y, clicks = 1})
	case "release":     append(out, input.Mouse{kind = .Release, button = .Left, x = x, y = y, clicks = 1})
	case "drag":        append(out, input.Mouse{kind = .Drag, button = .Left, x = x, y = y})
	case "move":        append(out, input.Mouse{kind = .Move, x = x, y = y})
	case "wheel-up":    append(out, input.Mouse{kind = .Scroll, button = .Wheel_Up, x = x, y = y})
	case "wheel-down":  append(out, input.Mouse{kind = .Scroll, button = .Wheel_Down, x = x, y = y})
	case:               return fmt.tprintf("unknown step: %s", word)
	}
	return ""
}

@(private = "file")
unquote :: proc(s: string) -> (text: string, err: string) {
	if len(s) < 2 || s[0] != '"' || s[len(s) - 1] != '"' {
		return "", fmt.tprintf("not a quoted string: %s", s)
	}
	sb := strings.builder_make(context.temp_allocator)
	body := s[1:len(s) - 1]
	for i := 0; i < len(body); {
		switch body[i] {
		case '"':
			return "", fmt.tprintf("text after a quoted string: %s", s)
		case '\\':
			i += 1
			if i >= len(body) { return "", fmt.tprintf("unclosed quote: %s", s) }
		}
		r, n := utf8.decode_rune(body[i:])
		strings.write_rune(&sb, r)
		i += n
	}
	return strings.to_string(sb), ""
}

@(private = "file")
two_numbers :: proc(s: string, sep: u8) -> (a, b: int, ok: bool) {
	i := strings.index_byte(s, sep)
	if i < 0 { return }
	a = strconv.parse_int(s[:i], 10) or_return
	b = strconv.parse_int(s[i + 1:], 10) or_return
	return a, b, true
}
