package widgets

import "../buffer"

// A vertical scrollbar for content of `total` lines of which `visible` fit.
// The mouse can click the track to jump, drag the thumb, or use the wheel.
// `offset` is the first visible line; returns true if it changed.
scrollbar :: proc(ui: ^Ui, area: Rect, total, visible: int, offset: ^int) -> bool {
	return scroll_track(ui, area, total, visible, offset, true)
}

// The horizontal twin of scrollbar, drawn along the bottom row of `area`:
// `offset` is the first visible column. The wheel scrolls it too.
hscrollbar :: proc(ui: ^Ui, area: Rect, total, visible: int, offset: ^int) -> bool {
	return scroll_track(ui, area, total, visible, offset, false)
}

@(private)
scroll_track :: proc(ui: ^Ui, area: Rect, total, visible: int, offset: ^int, vertical: bool) -> bool {
	if area.height <= 0 || area.width <= 0 {
		return false
	}
	// Along the track: `start` is its first cell, `n` its length.
	start, n := area.y, area.height
	if !vertical {
		start, n = area.x, area.width
	}
	max_off := max(total - visible, 0)
	thumb := n if total <= visible else clamp(n * visible / max(total, 1), 1, n)
	old := offset^

	// Offset that puts the thumb's middle at cell p.
	offset_at :: proc(p, start, n, thumb, max_off: int) -> int {
		travel := n - thumb
		if travel <= 0 {
			return 0
		}
		pos := clamp(p - start - thumb / 2, 0, travel)
		return (pos * max_off + travel / 2) / travel
	}

	it: Key_Iter
	for m, i in next_mouse(ui, offset, area, &it) {
		p := m.y if vertical else m.x
		#partial switch m.kind {
		case .Press:
			if m.button != .Left { continue }
			ui.mem.active = offset
			offset^ = offset_at(p, start, n, thumb, max_off)
		case .Drag:
			if ui.mem.active != offset { continue }
			offset^ = offset_at(p, start, n, thumb, max_off)
		case .Release:
			if ui.mem.active != offset { continue }
			ui.mem.active = nil
		case .Scroll:
			#partial switch m.button {
			case .Wheel_Up, .Wheel_Left:    offset^ -= 3
			case .Wheel_Down, .Wheel_Right: offset^ += 3
			}
		case:
			continue
		}
		consume(ui, i)
	}
	offset^ = clamp(offset^, 0, max_off)

	top := 0 if max_off == 0 else ((n - thumb) * offset^ + max_off / 2) / max_off
	for k in 0 ..< n {
		on := k >= top && k < top + thumb
		if vertical {
			x := area.x + area.width - 1
			buffer.set_symbol(ui.buf, x, start + k, "┃" if on else "│", 1, ui.theme.scrollbar_thumb if on else ui.theme.scrollbar_track)
		} else {
			y := area.y + area.height - 1
			buffer.set_symbol(ui.buf, start + k, y, "━" if on else "─", 1, ui.theme.scrollbar_thumb if on else ui.theme.scrollbar_track)
		}
	}
	return offset^ != old
}
