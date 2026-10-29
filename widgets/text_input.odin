package widgets

import "core:strings"
import "core:unicode/utf8"
import "../buffer"
import "../input"
import "../text"

// State of a single-line text field. `text` grows with the allocator it
// was created with (context.allocator on first use); free it with
// input_destroy.
Input_State :: struct {
	text:      [dynamic]u8, // UTF-8
	cursor:    int,         // byte offset, always on a grapheme boundary
	scroll:    int,         // first visible cell
	submitted: bool,        // Enter was pressed this frame
}

Input_Options :: struct {
	placeholder: string, // shown (muted) while the field is empty
	mask:        string, // e.g. "•" for passwords: drawn once per grapheme
}

// A one-line text field. While focused, it takes printable keys and paste
// and supports:
//   ← →  Home End  Ctrl+A Ctrl+E     move (by grapheme)
//   Ctrl+← Ctrl+→  Alt+B Alt+F        move by word
//   Backspace Delete Ctrl+D            delete a grapheme
//   Ctrl+W Alt+Backspace               delete the previous word
//   Ctrl+U Ctrl+K                      delete to start / to end
//   Enter                              sets state.submitted
// Clicking focuses it and places the cursor. Shows the terminal cursor at
// the caret. Returns true when the text changed.
input :: proc(ui: ^Ui, area: Rect, state: ^Input_State, opts := Input_Options{}) -> (changed: bool) {
	state.submitted = false
	if area.width <= 0 || area.height <= 0 {
		return false
	}
	state.cursor = clamp(state.cursor, 0, len(state.text))

	if focused(ui, state) {
		for ev, i in ui.events {
			if ui.handled[i] { continue }
			switch e in ev {
			case input.Key:
				used, edited := edit_key(state, e)
				if used { consume(ui, i) }
				changed ||= edited
			case input.Paste:
				insert(state, single_line(e.text))
				consume(ui, i)
				changed = true
			case input.Mouse, input.Resize:
			}
		}
	}

	it: Key_Iter
	for m, i in next_mouse(ui, nil, area, &it) {
		if m.kind != .Press || m.button != .Left { continue }
		ui.mem.focus = state
		state.cursor = byte_at_cell(state, opts, m.x - area.x + state.scroll)
		consume(ui, i)
	}

	// Keep the caret on screen (the last cell is kept for it at the end).
	caret := cells_before(state, opts, state.cursor)
	W := area.width
	if caret - state.scroll >= W { state.scroll = caret - W + 1 }
	if caret < state.scroll { state.scroll = caret }
	state.scroll = max(state.scroll, 0)

	row := Rect{area.x, area.y, W, 1}
	buffer.fill(ui.buf, row, ui.theme.input)
	if len(state.text) == 0 && opts.placeholder != "" {
		buffer.set_string(ui.buf, area.x, area.y, opts.placeholder, ui.theme.muted, W)
	} else {
		col := 0
		s := string(state.text[:])
		for len(s) > 0 {
			cluster, w, rest := text.next_grapheme(s)
			s = rest
			if opts.mask != "" {
				cluster, w = opts.mask, text.width(opts.mask)
			}
			if col >= state.scroll && col + w <= state.scroll + W {
				buffer.set_symbol(ui.buf, area.x + col - state.scroll, area.y, cluster, w, ui.theme.input)
			}
			col += w
			if col >= state.scroll + W { break }
		}
	}

	if focused(ui, state) {
		ui.cursor^ = {area.x + caret - state.scroll, area.y, true}
	}
	return changed
}

input_text :: proc(state: ^Input_State) -> string {
	return string(state.text[:])
}

// Replaces the text and puts the cursor at the end.
input_set :: proc(state: ^Input_State, s: string) {
	clear(&state.text)
	append(&state.text, s)
	state.cursor = len(state.text)
}

input_destroy :: proc(state: ^Input_State) {
	delete(state.text)
	state^ = {}
}

// Applies one key. `used`: the key was meant for the field (so consume it);
// `edited`: the text changed.
@(private)
edit_key :: proc(state: ^Input_State, k: input.Key) -> (used, edited: bool) {
	s := string(state.text[:])
	ctrl := .Ctrl in k.mods
	alt := .Alt in k.mods
	used = true
	#partial switch k.code {
	case .Char:
		switch {
		case !ctrl && !alt:
			buf, n := utf8.encode_rune(k.char)
			insert(state, string(buf[:n]))
			edited = true
		case ctrl && k.char == 'a': state.cursor = 0
		case ctrl && k.char == 'e': state.cursor = len(s)
		case ctrl && k.char == 'u': edited = delete_range(state, 0, state.cursor)
		case ctrl && k.char == 'k': edited = delete_range(state, state.cursor, len(s))
		case ctrl && k.char == 'w': edited = delete_range(state, word_start(s, state.cursor), state.cursor)
		case ctrl && k.char == 'd': edited = delete_range(state, state.cursor, next_boundary(s, state.cursor))
		case alt && k.char == 'b':  state.cursor = word_start(s, state.cursor)
		case alt && k.char == 'f':  state.cursor = word_end(s, state.cursor)
		case: used = false
		}
	case .Backspace:
		if alt || ctrl {
			edited = delete_range(state, word_start(s, state.cursor), state.cursor)
		} else {
			edited = delete_range(state, prev_boundary(s, state.cursor), state.cursor)
		}
	case .Delete:
		edited = delete_range(state, state.cursor, next_boundary(s, state.cursor))
	case .Left:
		state.cursor = word_start(s, state.cursor) if ctrl || alt else prev_boundary(s, state.cursor)
	case .Right:
		state.cursor = word_end(s, state.cursor) if ctrl || alt else next_boundary(s, state.cursor)
	case .Home:
		state.cursor = 0
	case .End:
		state.cursor = len(s)
	case .Enter:
		state.submitted = true
	case:
		used = false
	}
	return
}

@(private)
insert :: proc(state: ^Input_State, s: string) {
	if len(s) == 0 { return }
	inject_at(&state.text, state.cursor, s)
	state.cursor += len(s)
}

@(private)
delete_range :: proc(state: ^Input_State, from, to: int) -> bool {
	if from >= to { return false }
	remove_range(&state.text, from, to)
	state.cursor = from
	return true
}

// Paste into a one-line field: newlines and tabs become spaces, other
// control characters are dropped.
@(private)
single_line :: proc(s: string) -> string {
	sb := strings.builder_make(context.temp_allocator)
	for r in s {
		switch {
		case r == '\n' || r == '\t': strings.write_byte(&sb, ' ')
		case r < 0x20 || r == 0x7f:
		case: strings.write_rune(&sb, r)
		}
	}
	return strings.to_string(sb)
}

@(private)
next_boundary :: proc(s: string, i: int) -> int {
	if i >= len(s) { return len(s) }
	c, _, _ := text.next_grapheme(s[i:])
	return i + len(c)
}

@(private)
prev_boundary :: proc(s: string, i: int) -> int {
	last := 0
	for pos := 0; pos < i; {
		last = pos
		pos = next_boundary(s, pos)
	}
	return last
}

// Start of the word before i (skipping spaces first), like readline.
@(private)
word_start :: proc(s: string, i: int) -> int {
	j := i
	for j > 0 && s[j - 1] == ' ' { j -= 1 }
	for j > 0 && s[j - 1] != ' ' { j -= 1 }
	return j
}

@(private)
word_end :: proc(s: string, i: int) -> int {
	j := i
	for j < len(s) && s[j] == ' ' { j += 1 }
	for j < len(s) && s[j] != ' ' { j += 1 }
	return j
}

// Display cells taken by the text before byte offset `upto`.
@(private)
cells_before :: proc(state: ^Input_State, opts: Input_Options, upto: int) -> int {
	cells := 0
	s := string(state.text[:upto])
	mw := text.width(opts.mask)
	for len(s) > 0 {
		_, w, rest := text.next_grapheme(s)
		s = rest
		cells += mw if opts.mask != "" else w
	}
	return cells
}

// Byte offset of the grapheme boundary nearest to display cell `cell`.
@(private)
byte_at_cell :: proc(state: ^Input_State, opts: Input_Options, cell: int) -> int {
	s := string(state.text[:])
	mw := text.width(opts.mask)
	col, pos := 0, 0
	for pos < len(s) {
		c, w, _ := text.next_grapheme(s[pos:])
		if opts.mask != "" { w = mw }
		if col + w / 2 >= cell { break } // closer to this grapheme's left edge
		col += w
		pos += len(c)
	}
	return pos
}
