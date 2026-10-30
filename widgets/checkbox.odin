package widgets

import "../buffer"
import "../pen"

// A checkbox: "[✓] label" (markup). Space or Enter toggles while focused,
// clicking toggles and focuses. `checked` is also the widget's identity
// for focus. Returns true when it was toggled.
checkbox :: proc(ui: ^Ui, area: Rect, label: string, checked: ^bool) -> (changed: bool) {
	if area.width <= 0 || area.height <= 0 {
		return false
	}
	changed = toggled(ui, area, checked)
	mark := "[✓]" if checked^ else "[ ]"
	mark_style := ui.theme.check if checked^ else ui.theme.muted
	draw_choice(ui, area, mark, mark_style, label, focused(ui, checked))
	return
}

// An on/off switch: "━━● label" when on, "●━━ label" when off. Same keys
// and mouse as checkbox.
toggle :: proc(ui: ^Ui, area: Rect, label: string, on: ^bool) -> (changed: bool) {
	if area.width <= 0 || area.height <= 0 {
		return false
	}
	changed = toggled(ui, area, on)
	mark := "━━●" if on^ else "●━━"
	mark_style := ui.theme.check if on^ else ui.theme.muted
	draw_choice(ui, area, mark, mark_style, label, focused(ui, on))
	return
}

// A group of options (markup), one per row, exactly one chosen:
// "◉ chosen" / "○ other". While focused, ↑ ↓ (k j) Home End move the
// choice; clicking a row chooses it and focuses the group. Returns true
// when `selected^` changed.
radio :: proc(ui: ^Ui, area: Rect, options: []string, selected: ^int) -> (changed: bool) {
	if area.width <= 0 || area.height <= 0 || len(options) == 0 {
		return false
	}
	old := selected^
	n := len(options)

	it: Key_Iter
	for k, i in next_key(ui, selected, &it) {
		used := true
		#partial switch k.code {
		case .Up:   selected^ -= 1
		case .Down: selected^ += 1
		case .Home: selected^ = 0
		case .End:  selected^ = n - 1
		case .Char:
			switch {
			case k.char == 'k' && k.mods == {}: selected^ -= 1
			case k.char == 'j' && k.mods == {}: selected^ += 1
			case: used = false
			}
		case:
			used = false
		}
		if used { consume(ui, i) }
	}
	mit: Key_Iter
	for m, i in next_mouse(ui, nil, area, &mit) {
		if m.kind != .Press || m.button != .Left { continue }
		ui.mem.focus = selected
		if row := m.y - area.y; row < n { selected^ = row }
		consume(ui, i)
	}
	selected^ = clamp(selected^, 0, n - 1)

	has_focus := focused(ui, selected)
	for opt, i in options[:min(n, area.height)] {
		row := Rect{area.x, area.y + i, area.width, 1}
		chosen := i == selected^
		mark := "◉" if chosen else "○"
		mark_style := ui.theme.check if chosen else ui.theme.muted
		draw_choice(ui, row, mark, mark_style, opt, has_focus && chosen)
	}
	return selected^ != old
}

// Space / Enter (while focused) and left clicks flip `value`.
@(private)
toggled :: proc(ui: ^Ui, area: Rect, value: ^bool) -> (changed: bool) {
	it: Key_Iter
	for k, i in next_key(ui, value, &it) {
		if k.code == .Enter || (k.code == .Char && k.char == ' ' && k.mods == {}) {
			value^ = !value^
			changed = true
			consume(ui, i)
		}
	}
	mit: Key_Iter
	for m, i in next_mouse(ui, nil, area, &mit) {
		if m.kind != .Press || m.button != .Left { continue }
		ui.mem.focus = value
		value^ = !value^
		changed = true
		consume(ui, i)
	}
	return
}

// "mark label" on the first row of `area`; a focused choice is drawn like
// a selected list row.
@(private)
draw_choice :: proc(ui: ^Ui, area: Rect, mark: string, mark_style: Style, label: string, has_focus: bool) {
	row := Rect{area.x, area.y, area.width, 1}
	base, mark_st := ui.theme.text, mark_style
	if has_focus {
		buffer.fill(ui.buf, row, ui.theme.selected)
		base, mark_st = ui.theme.selected, ui.theme.selected
	}
	p := pen.begin(ui.buf, row, .Ellipsis, base = base)
	pen.write(&p, mark, mark_st)
	pen.write(&p, " ")
	pen.markup(&p, label)
	pen.finish(&p)
}
