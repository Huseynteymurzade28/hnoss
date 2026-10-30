package widgets

import "../buffer"
import "../layout"

// Where a scroll view is scrolled to, plus what scroll_view_end needs.
View_State :: struct {
	x, y: int,  // the content cell shown at the viewport's top-left
	clip: Rect, // the clip in effect before scroll_view, put back by scroll_view_end
}

// A viewport onto content larger than `area`, `width` × `height` cells
// (0 for either: as wide or as tall as the viewport). Returns where the
// content is on screen, shifted by the scroll offset: draw into it, then
// call scroll_view_end. Drawing is clipped to the viewport, and mouse
// events outside it don't reach the widgets inside.
//
// Scrollbars appear along the right and bottom edges when the content
// overflows. While focused: ↑ ↓ ← → PgUp PgDn Home End. The wheel scrolls
// it anywhere over the viewport (Shift+wheel sideways), so widgets inside
// that scroll themselves do it with the keyboard; clicking it focuses it,
// unless a widget inside takes the click.
//
//	content := hnoss.scroll_view(ui, area, &view, 0, 40)
//	hnoss.label(ui, content, long_text)
//	hnoss.scroll_view_end(ui, &view)
scroll_view :: proc(ui: ^Ui, area: Rect, state: ^View_State, width, height: int) -> (content: Rect) {
	// Each scrollbar takes a line from the viewport, which can make the other
	// one necessary; settles within three rounds.
	vbar, hbar := false, false
	view := area
	for _ in 0 ..< 3 {
		view = area
		if vbar { view.width -= 1 }
		if hbar { view.height -= 1 }
		vbar = height > view.height
		hbar = width > view.width
	}
	view.width, view.height = max(view.width, 0), max(view.height, 0)
	w := width if width > 0 else view.width
	h := height if height > 0 else view.height
	max_x, max_y := max(w - view.width, 0), max(h - view.height, 0)
	page := max(view.height - 1, 1)

	it: Key_Iter
	for k, i in next_key(ui, state, &it) {
		used := true
		#partial switch k.code {
		case .Up:        state.y -= 1
		case .Down:      state.y += 1
		case .Left:      state.x -= 1
		case .Right:     state.x += 1
		case .Page_Up:   state.y -= page
		case .Page_Down: state.y += page
		case .Home:      state.y = 0
		case .End:       state.y = max_y
		case:            used = false
		}
		if used { consume(ui, i) }
	}
	mit: Key_Iter
	for m, i in next_mouse(ui, nil, view, &mit) {
		#partial switch m.kind {
		case .Scroll:
			sideways := .Shift in m.mods
			#partial switch m.button {
			case .Wheel_Up:    if sideways { state.x -= 3 } else { state.y -= 3 }
			case .Wheel_Down:  if sideways { state.x += 3 } else { state.y += 3 }
			case .Wheel_Left:  state.x -= 3
			case .Wheel_Right: state.x += 3
			}
			consume(ui, i)
		case .Press:
			ui.mem.focus = state // left for a widget inside to take back
		}
	}
	state.x = clamp(state.x, 0, max_x)
	state.y = clamp(state.y, 0, max_y)

	if vbar {
		scrollbar(ui, {view.x + view.width, view.y, 1, view.height}, h, view.height, &state.y)
	}
	if hbar {
		hscrollbar(ui, {view.x, view.y + view.height, view.width, 1}, w, view.width, &state.x)
	}

	state.clip = buffer.set_clip(ui.buf, layout.rect_intersection(view, ui.buf.clip))
	return {view.x - state.x, view.y - state.y, w, h}
}

// Ends the scroll view begun with the same state: drawing is no longer
// clipped to its viewport.
scroll_view_end :: proc(ui: ^Ui, state: ^View_State) {
	buffer.set_clip(ui.buf, state.clip)
}
