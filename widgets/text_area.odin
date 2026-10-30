package widgets

import "core:strings"
import "../buffer"
import "../input"
import "../layout"
import "../text"

Text_Area_Options :: struct {
	placeholder: string, // shown (muted) while the text is empty
	scrollbar:   bool,   // when the text is taller than the area
}

// A multi-line text field, word-wrapped to the area's width. It edits an
// Input_State like `input` does (state.scroll is the first visible row),
// with the same keys plus:
//   Enter                       new line
//   ↑ ↓  PgUp PgDn              move by wrapped row, keeping the column
//   Home End  Ctrl+A Ctrl+E     start / end of the line
//   Ctrl+Home Ctrl+End          start / end of the text
//   Ctrl+U Ctrl+K               delete to the line's start / end
// Pastes keep their newlines. Clicking focuses it and places the cursor,
// the wheel scrolls. Returns true when the text changed.
text_area :: proc(ui: ^Ui, area: Rect, state: ^Input_State, opts := Text_Area_Options{}) -> (changed: bool) {
	state.submitted = false
	if area.width <= 0 || area.height <= 0 {
		return false
	}
	state.cursor = clamp(state.cursor, 0, len(state.text))

	body := area
	bar: Rect
	rows := wrap_rows(string(state.text[:]), body.width)
	if opts.scrollbar && len(rows) > body.height {
		bar = layout.cut_right(&body, 1)
		rows = wrap_rows(string(state.text[:]), body.width)
	}
	h := body.height

	moved := false
	if focused(ui, state) {
		for ev, i in ui.events {
			if ui.handled[i] { continue }
			edited := false
			switch e in ev {
			case input.Key:
				used, mv: bool
				used, edited, mv = area_key(state, e, rows, max(h - 1, 1))
				if used { consume(ui, i) }
				moved ||= used
				if !mv { state.goal = nil }
			case input.Paste:
				insert(state, multi_line(e.text))
				consume(ui, i)
				edited, moved = true, true
				state.goal = nil
			case input.Mouse, input.Resize:
			}
			if edited {
				changed = true
				rows = wrap_rows(string(state.text[:]), body.width)
			}
		}
	}

	it: Key_Iter
	for m, i in next_mouse(ui, nil, body, &it) {
		#partial switch m.kind {
		case .Press:
			if m.button != .Left { continue }
			ui.mem.focus = state
			r := clamp(state.scroll + m.y - body.y, 0, len(rows) - 1)
			state.cursor = byte_in_row(string(state.text[:]), rows[r], m.x - body.x)
			state.goal = nil
			moved = true
			consume(ui, i)
		case .Scroll:
			#partial switch m.button {
			case .Wheel_Up:   state.scroll -= 3
			case .Wheel_Down: state.scroll += 3
			}
			consume(ui, i)
		}
	}

	s := string(state.text[:])
	caret_row := row_of(rows, state.cursor)
	if moved {
		if caret_row < state.scroll { state.scroll = caret_row }
		if caret_row >= state.scroll + h { state.scroll = caret_row - h + 1 }
	}
	state.scroll = clamp(state.scroll, 0, max(len(rows) - h, 0))

	buffer.fill(ui.buf, body, ui.theme.input)
	if len(s) == 0 && opts.placeholder != "" {
		buffer.set_string(ui.buf, body.x, body.y, opts.placeholder, ui.theme.muted, body.width)
	}
	for r in state.scroll ..< min(state.scroll + h, len(rows)) {
		y := body.y + r - state.scroll
		col := 0
		for rest := s[rows[r].start:rows[r].end]; len(rest) > 0; {
			cluster, w, next := text.next_grapheme(rest)
			rest = next
			if col + w > body.width { break }
			if w > 0 {
				buffer.set_symbol(ui.buf, body.x + col, y, cluster, w, ui.theme.input)
			}
			col += w
		}
	}

	if bar.width > 0 {
		scrollbar(ui, bar, len(rows), h, &state.scroll)
	}

	cx := body.x + min(text.width(s[rows[caret_row].start:state.cursor]), body.width - 1)
	cy := body.y + caret_row - state.scroll
	if focused(ui, state) && caret_row >= state.scroll && caret_row < state.scroll + h && layout.rect_contains(ui.buf.clip, cx, cy) {
		ui.cursor^ = {cx, cy, true}
	}
	return changed
}

// One screen row of wrapped text: bytes [start, end) of it. `soft` rows
// end where the text was wrapped rather than at a newline or the end.
@(private)
Row :: struct {
	start, end: int,
	soft:       bool,
}

// Splits `s` into rows at most `width` cells wide, breaking after spaces
// where possible (a word longer than a row breaks anywhere). The last
// column is kept free for the caret; spaces may run into it and beyond.
@(private)
wrap_rows :: proc(s: string, width: int) -> []Row {
	w_max := max(width - 1, 1)
	rows := make([dynamic]Row, 0, 16, context.temp_allocator)
	start := 0
	for {
		line_end := len(s)
		if nl := strings.index_byte(s[start:], '\n'); nl >= 0 {
			line_end = start + nl
		}
		row_start, col, brk := start, 0, -1
		for pos := start; pos < line_end; {
			c, w, _ := text.next_grapheme(s[pos:line_end])
			if c == " " {
				col += w
				pos += len(c)
				brk = pos
				continue
			}
			if col + w > w_max && pos > row_start {
				cut := brk if brk > row_start else pos
				append(&rows, Row{row_start, cut, true})
				row_start = cut
				col = text.width(s[cut:pos])
				brk = -1
			}
			col += w
			pos += len(c)
		}
		append(&rows, Row{row_start, line_end, false})
		if line_end >= len(s) {
			break
		}
		start = line_end + 1
	}
	return rows[:]
}

// The row the caret at byte `c` is drawn on: the end of a soft row is the
// start of the next one.
@(private)
row_of :: proc(rows: []Row, c: int) -> int {
	for r, i in rows {
		if c >= r.start && (c < r.end || (c == r.end && !r.soft)) {
			return i
		}
	}
	return len(rows) - 1
}

// Byte offset in `row` nearest to display column `cell`. Never the end of a
// soft row, which would put the caret on the next one.
@(private)
byte_in_row :: proc(s: string, row: Row, cell: int) -> int {
	col, pos := 0, row.start
	for pos < row.end {
		c, w, _ := text.next_grapheme(s[pos:row.end])
		if col + w / 2 >= cell { break }
		if row.soft && pos + len(c) == row.end { break }
		col += w
		pos += len(c)
	}
	return pos
}

// Keys that mean something different in several lines; the rest go to
// edit_key. `moved`: an ↑↓ move, which keeps the goal column.
@(private)
area_key :: proc(state: ^Input_State, k: input.Key, rows: []Row, page: int) -> (used, edited, moved: bool) {
	s := string(state.text[:])
	ctrl := .Ctrl in k.mods
	used = true
	ls := strings.last_index_byte(s[:state.cursor], '\n') + 1
	le := len(s)
	if nl := strings.index_byte(s[state.cursor:], '\n'); nl >= 0 { le = state.cursor + nl }

	vertical := 0
	#partial switch k.code {
	case .Enter:     insert(state, "\n"); edited = true
	case .Up:        vertical = -1
	case .Down:      vertical = 1
	case .Page_Up:   vertical = -page
	case .Page_Down: vertical = page
	case .Home:      state.cursor = 0 if ctrl else ls
	case .End:       state.cursor = len(s) if ctrl else le
	case .Char:
		switch {
		case ctrl && k.char == 'a': state.cursor = ls
		case ctrl && k.char == 'e': state.cursor = le
		case ctrl && k.char == 'u': edited = delete_range(state, ls, state.cursor)
		case ctrl && k.char == 'k':
			// at the end of a line, joins the next one
			edited = delete_range(state, state.cursor, le if le > state.cursor else min(le + 1, len(s)))
		case:
			used, edited = edit_key(state, k)
		}
	case:
		used, edited = edit_key(state, k)
	}
	if vertical == 0 {
		return
	}

	r := row_of(rows, state.cursor)
	goal := state.goal.? or_else text.width(s[rows[r].start:state.cursor])
	state.goal = goal
	target := r + vertical
	switch {
	case target < 0:          state.cursor = 0
	case target >= len(rows): state.cursor = len(s)
	case:                     state.cursor = byte_in_row(s, rows[target], goal)
	}
	return used, edited, true
}

// Paste into a text area: CR LF and lone CR become newlines, tabs four
// spaces, other control characters are dropped.
@(private)
multi_line :: proc(s: string) -> string {
	sb := strings.builder_make(context.temp_allocator)
	for i := 0; i < len(s); i += 1 {
		switch b := s[i]; {
		case b == '\r':
			strings.write_byte(&sb, '\n')
			if i + 1 < len(s) && s[i + 1] == '\n' { i += 1 }
		case b == '\n': strings.write_byte(&sb, '\n')
		case b == '\t': strings.write_string(&sb, "    ")
		case b < 0x20 || b == 0x7f:
		case: strings.write_byte(&sb, b)
		}
	}
	return strings.to_string(sb)
}
