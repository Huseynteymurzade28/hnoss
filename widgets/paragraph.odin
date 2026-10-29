package widgets

import "../layout"
import "../pen"

// One-off markup text. Returns the number of lines it took.
label :: proc(ui: ^Ui, area: Rect, src: string, align := pen.Align.Left, wrap := pen.Wrap.Word) -> int {
	p := pen.begin(ui.buf, area, wrap, align)
	pen.markup(&p, src, ui.theme.text)
	return pen.finish(&p)
}

Scroll_State :: struct {
	offset: int,
}

Paragraph_Options :: struct {
	wrap:      pen.Wrap,
	align:     pen.Align,
	scrollbar: bool, // draw one in the rightmost column when the text overflows
}

// Wrapped markup text that scrolls. With a state it handles ↑ ↓ PgUp PgDn
// Home End while focused, and the mouse wheel when hovered; clicking it
// takes focus. Returns the total number of lines.
paragraph :: proc(ui: ^Ui, area: Rect, src: string, state: ^Scroll_State = nil, opts := Paragraph_Options{}) -> int {
	if area.width <= 0 || area.height <= 0 {
		return 0
	}
	text_area := area
	total := count_lines(src, text_area.width, opts.wrap)
	bar: Rect
	if opts.scrollbar && total > area.height {
		bar = layout.cut_right(&text_area, 1)
		total = count_lines(src, text_area.width, opts.wrap)
	}

	offset := 0
	if state != nil {
		max_off := max(total - text_area.height, 0)
		page := max(text_area.height - 1, 1)
		it: Key_Iter
		for k, i in next_key(ui, state, &it) {
			used := true
			#partial switch k.code {
			case .Up:        state.offset -= 1
			case .Down:      state.offset += 1
			case .Page_Up:   state.offset -= page
			case .Page_Down: state.offset += page
			case .Home:      state.offset = 0
			case .End:       state.offset = max_off
			case:            used = false
			}
			if used { consume(ui, i) }
		}
		scroll_with_mouse(ui, state, area, &state.offset)
		state.offset = clamp(state.offset, 0, max_off)
		offset = state.offset
	}

	p := pen.begin(ui.buf, text_area, opts.wrap, opts.align, scroll = offset)
	pen.markup(&p, src, ui.theme.text)
	pen.finish(&p)

	if bar.width > 0 && state != nil {
		scrollbar(ui, bar, total, text_area.height, &state.offset)
	}
	return total
}

@(private)
count_lines :: proc(src: string, width: int, wrap: pen.Wrap) -> int {
	p := pen.begin(nil, {0, 0, width, 0}, wrap)
	pen.markup(&p, src)
	return pen.finish(&p)
}

// Wheel scrolls `offset` by 3 lines; a click focuses `id`.
@(private)
scroll_with_mouse :: proc(ui: ^Ui, id: rawptr, area: Rect, offset: ^int) {
	it: Key_Iter
	for m, i in next_mouse(ui, nil, area, &it) {
		#partial switch m.kind {
		case .Scroll:
			#partial switch m.button {
			case .Wheel_Up:   offset^ -= 3
			case .Wheel_Down: offset^ += 3
			}
			consume(ui, i)
		case .Press:
			ui.mem.focus = id
		}
	}
}
