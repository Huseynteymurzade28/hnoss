package widgets

import "../buffer"
import "../layout"
import "../pen"
import "../text"

List_State :: struct {
	selected:  int,  // index of the selected item
	offset:    int,  // first visible item
	activated: bool, // Enter was pressed on the selection this frame
}

List_Options :: struct {
	marker:    Maybe(string), // drawn before the selected item (default "› ")
	markup:    bool,          // items are markup instead of plain text
	scrollbar: bool,          // when the items don't fit
}

// A scrollable, selectable list. While focused: ↑ ↓ (or k j), PgUp PgDn,
// Home End move, Enter activates. Clicking selects (and focuses), the wheel
// scrolls. Returns true when the selection changed.
list :: proc(ui: ^Ui, area: Rect, items: []string, state: ^List_State, opts := List_Options{}) -> (changed: bool) {
	state.activated = false
	if area.width <= 0 || area.height <= 0 {
		return false
	}
	body := area
	bar: Rect
	if opts.scrollbar && len(items) > area.height {
		bar = layout.cut_right(&body, 1)
	}

	old := state.selected
	n := len(items)
	select_rows(ui, state, body, 0, n)
	marker := opts.marker.? or_else "› "

	row_style := ui.theme.selected if focused(ui, state) else ui.theme.selected_unfocused
	mw := text.width(marker)
	for i in state.offset ..< min(state.offset + body.height, n) {
		y := body.y + i - state.offset
		row := Rect{body.x, y, body.width, 1}
		selected := i == state.selected
		if selected {
			buffer.fill(ui.buf, row, row_style)
			p := pen.begin(ui.buf, row, .Clip)
			pen.write(&p, marker)
			pen.finish(&p)
		}
		item := Rect{body.x + mw, y, body.width - mw, 1}
		p := pen.begin(ui.buf, item, .Ellipsis, base = ui.theme.text)
		if opts.markup { pen.markup(&p, items[i]) } else { pen.write(&p, items[i]) }
		pen.finish(&p)
	}

	if bar.width > 0 {
		scrollbar(ui, bar, n, body.height, &state.offset)
	}
	return state.selected != old
}

// Keyboard and mouse handling shared by list and table: `rows` is the
// area the items occupy (after any header), `header` rows above it are
// part of the widget but not selectable.
@(private)
select_rows :: proc(ui: ^Ui, state: ^List_State, rows: Rect, header, n: int) {
	h := rows.height
	page := max(h - 1, 1)
	by_key := false

	it: Key_Iter
	for k, i in next_key(ui, state, &it) {
		used := true
		#partial switch k.code {
		case .Up:        state.selected -= 1
		case .Down:      state.selected += 1
		case .Page_Up:   state.selected -= page
		case .Page_Down: state.selected += page
		case .Home:      state.selected = 0
		case .End:       state.selected = n - 1
		case .Enter:     state.activated = n > 0
		case .Char:
			switch {
			case k.char == 'k' && k.mods == {}: state.selected -= 1
			case k.char == 'j' && k.mods == {}: state.selected += 1
			case: used = false
			}
		case:
			used = false
		}
		if used {
			consume(ui, i)
			by_key = true
		}
	}

	whole := Rect{rows.x, rows.y - header, rows.width, rows.height + header}
	mit: Key_Iter
	for m, i in next_mouse(ui, nil, whole, &mit) {
		#partial switch m.kind {
		case .Press:
			ui.mem.focus = state
			if m.button == .Left && m.y >= rows.y {
				if idx := state.offset + m.y - rows.y; idx < n {
					state.selected = idx
				}
			}
			consume(ui, i)
		case .Scroll:
			#partial switch m.button {
			case .Wheel_Up:   state.offset -= 3
			case .Wheel_Down: state.offset += 3
			}
			consume(ui, i)
		}
	}

	state.selected = clamp(state.selected, 0, max(n - 1, 0))
	if by_key {
		// keep the selection on screen
		if state.selected < state.offset { state.offset = state.selected }
		if state.selected >= state.offset + h { state.offset = state.selected - h + 1 }
	}
	state.offset = clamp(state.offset, 0, max(n - h, 0))
}
