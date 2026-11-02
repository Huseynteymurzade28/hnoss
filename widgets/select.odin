package widgets

import "../buffer"
import "../input"
import "../layout"
import "../pen"

Select_State :: struct {
	selected:  int,  // index of the chosen item
	open:      bool, // the options are showing
	highlight: int,  // option under the cursor while open
	offset:    int,  // first option shown while open
}

Select_Options :: struct {
	max_rows: int,  // options shown at once (default 8); the rest scroll
	markup:   bool, // items are markup instead of plain text
}

// A closed field showing the chosen item, with a list of the options that
// opens under it (or above, when there is more room there), over every
// other widget. Enter, Space or a click open it. While open it takes all
// input: ↑ ↓ (or k j), PgUp PgDn, Home End move, Enter or a click picks,
// Esc or a click outside closes it. Returns true when the choice changed.
//
//	cities := []string{"Bakı", "Gəncə", "Şəki"}
//	city: hnoss.Select_State
//	...
//	if hnoss.select(ui, row, cities, &city) { ... cities[city.selected] ... }
select :: proc(ui: ^Ui, area: Rect, items: []string, state: ^Select_State, opts := Select_Options{}) -> (changed: bool) {
	n := len(items)
	old := state.selected
	state.selected = clamp(state.selected, 0, max(n - 1, 0))
	if area.width <= 0 || area.height <= 0 || n == 0 {
		state.open = false
		return state.selected != old
	}
	popup := popup_area(ui.area, area, n, opts.max_rows if opts.max_rows > 0 else 8)
	rows := layout.inset(popup, 1)

	if state.open && ui.popup == &state.open {
		ui.popup = nil
		popup_input(state, ui.popup_events, rows, n)
	} else {
		was_open := state.open
		it: Key_Iter
		for k, i in next_key(ui, state, &it) {
			if k.code == .Enter || (k.code == .Char && k.char == ' ' && k.mods == {}) {
				state.open = true
				consume(ui, i)
			}
		}
		mit: Key_Iter
		for m, i in next_mouse(ui, nil, area, &mit) {
			if m.kind == .Press && m.button == .Left {
				ui.mem.focus = state
				state.open = !state.open
				consume(ui, i)
			}
		}
		if state.open && !was_open {
			state.highlight = state.selected
			state.offset = state.selected - rows.height / 2
		}
	}
	state.highlight = clamp(state.highlight, 0, n - 1)
	state.offset = clamp(state.offset, 0, max(n - rows.height, 0))

	st := ui.theme.button
	if state.open || focused(ui, state) {
		st = ui.theme.button_focused
	}
	buffer.fill(ui.buf, area, st)
	y := area.y + (area.height - 1) / 2
	p := pen.begin(ui.buf, {area.x + 1, y, area.width - 3, 1}, .Ellipsis, base = st)
	if opts.markup { pen.markup(&p, items[state.selected]) } else { pen.write(&p, items[state.selected]) }
	pen.finish(&p)
	if area.width >= 3 {
		buffer.set_symbol(ui.buf, area.x + area.width - 2, y, "▴" if state.open else "▾", 1, st)
	}

	if state.open {
		ui.mem.popup = &state.open
		ui.overlay = Overlay{popup, items, state.highlight, state.offset, opts.markup}
	}
	return state.selected != old
}

// Where the options go: under `field` if they fit there or there is more
// room below than above, otherwise above it; as wide as the field.
@(private)
popup_area :: proc(screen, field: Rect, n, max_rows: int) -> Rect {
	h := min(n, max_rows) + 2
	below := layout.rect_bottom(screen) - layout.rect_bottom(field)
	above := field.y - screen.y
	w := min(field.width, screen.width)
	x := clamp(field.x, screen.x, layout.rect_right(screen) - w)
	if below >= h || below >= above {
		return {x, layout.rect_bottom(field), w, min(h, below)}
	}
	h = min(h, above)
	return {x, field.y - h, w, h}
}

// One frame of input for an open select. It takes every event; once it
// closes, the rest of the frame's events are dropped with it.
@(private)
popup_input :: proc(state: ^Select_State, events: []input.Event, rows: Rect, n: int) {
	page := max(rows.height - 1, 1)
	for ev in events {
		moved := false
		#partial switch e in ev {
		case input.Key:
			moved = true
			#partial switch e.code {
			case .Up:        state.highlight -= 1
			case .Down:      state.highlight += 1
			case .Page_Up:   state.highlight -= page
			case .Page_Down: state.highlight += page
			case .Home:      state.highlight = 0
			case .End:       state.highlight = n - 1
			case .Enter:     state.selected = state.highlight; state.open = false
			case .Esc:       state.open = false
			case .Char:
				switch {
				case e.char == 'k' && e.mods == {}: state.highlight -= 1
				case e.char == 'j' && e.mods == {}: state.highlight += 1
				case e.char == ' ' && e.mods == {}: state.selected = state.highlight; state.open = false
				}
			}
		case input.Mouse:
			in_rows := layout.rect_contains(rows, e.x, e.y)
			#partial switch e.kind {
			case .Press:
				if in_rows && e.button == .Left {
					if idx := state.offset + e.y - rows.y; idx < n {
						state.selected = idx
					}
				}
				state.open = false // a pick, or a click anywhere else
			case .Move, .Drag:
				if in_rows {
					state.highlight = min(state.offset + e.y - rows.y, n - 1)
				}
			case .Scroll:
				#partial switch e.button {
				case .Wheel_Up:   state.offset -= 3
				case .Wheel_Down: state.offset += 3
				}
				state.offset = clamp(state.offset, 0, max(n - rows.height, 0))
			}
		}
		if !state.open {
			return
		}
		if moved {
			state.highlight = clamp(state.highlight, 0, n - 1)
			if state.highlight < state.offset { state.offset = state.highlight }
			if state.highlight >= state.offset + rows.height { state.offset = state.highlight - rows.height + 1 }
		}
	}
}
