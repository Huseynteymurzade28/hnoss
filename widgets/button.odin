package widgets

import "../buffer"
import "../layout"
import "../pen"

Button_State :: struct {
	pressed: bool, // pressed this frame (same as the return value)
}

// A push button: `label` (markup) centered in `area`, which it fills.
// Enter or Space press it while focused. With the mouse it presses on
// release, and only if the pointer is still over it, so a click can be
// cancelled by dragging away; while held it is drawn pressed.
// Returns true on the frame it was pressed.
button :: proc(ui: ^Ui, area: Rect, label: string, state: ^Button_State) -> (pressed: bool) {
	state.pressed = false
	if area.width <= 0 || area.height <= 0 {
		return false
	}

	it: Key_Iter
	for k, i in next_key(ui, state, &it) {
		if k.code == .Enter || (k.code == .Char && k.char == ' ' && k.mods == {}) {
			state.pressed = true
			consume(ui, i)
		}
	}

	mit: Key_Iter
	for m, i in next_mouse(ui, state, area, &mit) {
		inside := layout.rect_contains(area, m.x, m.y)
		#partial switch m.kind {
		case .Press:
			if m.button != .Left || !inside { continue }
			ui.mem.focus = state
			ui.mem.active = state
		case .Drag:
			if ui.mem.active != state { continue }
		case .Release:
			if ui.mem.active != state { continue }
			ui.mem.active = nil
			state.pressed ||= inside
		case:
			continue
		}
		consume(ui, i)
	}

	st := ui.theme.button
	switch {
	case ui.mem.active == state: st = ui.theme.button_pressed
	case focused(ui, state):     st = ui.theme.button_focused
	}
	buffer.fill(ui.buf, area, st)
	w := markup_width(label)
	row := Rect{area.x, area.y + (area.height - 1) / 2, area.width, 1}
	p := pen.begin(ui.buf, row, .Ellipsis, .Center if w <= area.width else .Left, base = st)
	pen.markup(&p, label)
	pen.finish(&p)
	return state.pressed
}
