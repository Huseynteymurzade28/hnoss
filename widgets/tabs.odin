package widgets

import "../buffer"
import "../pen"

// A row of tab titles (markup) separated by "│". ← → (h l) Home End switch
// while focused; clicking a title selects it. Returns true when
// `selected^` changed.
tabs :: proc(ui: ^Ui, area: Rect, titles: []string, selected: ^int) -> (changed: bool) {
	if area.width <= 0 || area.height <= 0 || len(titles) == 0 {
		return false
	}
	old := selected^

	// Lay the titles out first so clicks can be hit-tested.
	xs := make([]int, len(titles) + 1, context.temp_allocator)
	x := area.x
	for t, i in titles {
		xs[i] = x
		x += markup_width(t) + 2 + 1 // " title " + separator
	}
	xs[len(titles)] = x

	it: Key_Iter
	for k, i in next_key(ui, selected, &it) {
		used := true
		#partial switch k.code {
		case .Left:  selected^ -= 1
		case .Right: selected^ += 1
		case .Home:  selected^ = 0
		case .End:   selected^ = len(titles) - 1
		case .Char:
			switch {
			case k.char == 'h' && k.mods == {}: selected^ -= 1
			case k.char == 'l' && k.mods == {}: selected^ += 1
			case: used = false
			}
		case:
			used = false
		}
		if used { consume(ui, i) }
	}
	mit: Key_Iter
	for m, i in next_mouse(ui, nil, area, &mit) {
		if m.kind != .Press { continue }
		ui.mem.focus = selected
		for t in 0 ..< len(titles) {
			if m.x >= xs[t] && m.x < xs[t + 1] - 1 { selected^ = t }
		}
		consume(ui, i)
	}
	selected^ = clamp(selected^, 0, len(titles) - 1)

	right := area.x + area.width
	for t, i in titles {
		if xs[i] >= right { break }
		st := ui.theme.tab_selected if i == selected^ else ui.theme.tab
		pad := st
		pad.add -= {.Underlined} // underline the title, not its padding
		p := pen.begin(ui.buf, {xs[i], area.y, min(xs[i + 1] - 1, right) - xs[i], 1}, .Clip)
		pen.write(&p, " ", pad)
		pen.markup(&p, t, st)
		pen.write(&p, " ", pad)
		pen.finish(&p)
		if i < len(titles) - 1 && xs[i + 1] - 1 < right {
			buffer.set_symbol(ui.buf, xs[i + 1] - 1, area.y, "│", 1, ui.theme.muted)
		}
	}
	return selected^ != old
}
