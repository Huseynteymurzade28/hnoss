package widgets

import "../buffer"

// A vertical scrollbar for content of `total` lines of which `visible` fit.
// The mouse can click the track to jump, drag the thumb, or use the wheel.
// `offset` is the first visible line; returns true if it changed.
scrollbar :: proc(ui: ^Ui, area: Rect, total, visible: int, offset: ^int) -> bool {
	h := area.height
	if h <= 0 || area.width <= 0 {
		return false
	}
	max_off := max(total - visible, 0)
	thumb := h if total <= visible else clamp(h * visible / max(total, 1), 1, h)
	old := offset^

	// Offset that puts the thumb's middle at row y.
	offset_at :: proc(y, top, h, thumb, max_off: int) -> int {
		travel := h - thumb
		if travel <= 0 {
			return 0
		}
		pos := clamp(y - top - thumb / 2, 0, travel)
		return (pos * max_off + travel / 2) / travel
	}

	it: Key_Iter
	for m, i in next_mouse(ui, offset, area, &it) {
		#partial switch m.kind {
		case .Press:
			if m.button != .Left { continue }
			ui.mem.active = offset
			offset^ = offset_at(m.y, area.y, h, thumb, max_off)
		case .Drag:
			if ui.mem.active != offset { continue }
			offset^ = offset_at(m.y, area.y, h, thumb, max_off)
		case .Release:
			if ui.mem.active != offset { continue }
			ui.mem.active = nil
		case .Scroll:
			#partial switch m.button {
			case .Wheel_Up:   offset^ -= 3
			case .Wheel_Down: offset^ += 3
			}
		case:
			continue
		}
		consume(ui, i)
	}
	offset^ = clamp(offset^, 0, max_off)

	top := 0 if max_off == 0 else ((h - thumb) * offset^ + max_off / 2) / max_off
	x := area.x + area.width - 1
	for row in 0 ..< h {
		if row >= top && row < top + thumb {
			buffer.set_symbol(ui.buf, x, area.y + row, "┃", 1, ui.theme.scrollbar_thumb)
		} else {
			buffer.set_symbol(ui.buf, x, area.y + row, "│", 1, ui.theme.scrollbar_track)
		}
	}
	return offset^ != old
}
