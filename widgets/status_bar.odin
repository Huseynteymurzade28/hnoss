package widgets

import "../buffer"
import "../style"
import "../text"

// What a status bar shows. Every part is optional.
Status_Bar :: struct {
	mode:   string,   // a badge at the far left in theme.selected: "NORMAL", "INSERT"
	left:   []string, // segments after the mode: a file name, a branch
	center: string,   // centered on the bar, if there is room between left and right
	right:  []string, // segments at the far right: a position, a clock
}

// The one-line bar at the bottom (or top) of a screen, on the first row of
// `area`, in theme.status_bar. Segments are separated by `separator`.
//
// When the row is too narrow, the right side loses segments from its
// front, down to the last one, so put the one that matters most last; then
// the left segments are cut with a `…` or dropped; the mode badge is
// always drawn. The center is drawn only in
// the room that is left, cut to fit.
//
// Returns the part of the row nobody drew on (empty when there is a
// center), so key hints can go in the middle of the same bar:
//
//	free := hnoss.status_bar(ui, footer, {mode = "NORMAL", left = {"main.odin"}, right = {"12:4"}})
//	hnoss.key_hints(ui, free, hints)
status_bar :: proc(ui: ^Ui, area: Rect, bar: Status_Bar, separator := " │ ") -> (free: Rect) {
	if area.width <= 0 || area.height <= 0 {
		return
	}
	st := ui.theme.status_bar
	y := area.y
	buffer.fill(ui.buf, {area.x, y, area.width, 1}, st)

	// The span still free, [x0, x1).
	x0, x1 := area.x, area.x + area.width

	if bar.mode != "" {
		badge := style.patch(st, ui.theme.selected)
		w := min(text.width(bar.mode) + 2, x1 - x0)
		buffer.fill(ui.buf, {x0, y, w, 1}, badge)
		draw_cut(ui.buf, x0 + 1, y, bar.mode, badge, w - 2)
		x0 += w
	}

	sep_w := text.width(separator)
	right := bar.right
	// A space on each side of the right group keeps it off the edge and
	// away from whatever ends at x0; the left group has one before it.
	left_w := 1 + segments_width(bar.left, sep_w) if len(bar.left) > 0 else 0
	for len(right) > 1 && left_w + segments_width(right, sep_w) + 2 > x1 - x0 {
		right = right[1:]
	}
	if len(right) == 1 && text.width(right[0]) + 2 > x1 - x0 {
		right = nil
	}
	if len(right) > 0 {
		w := segments_width(right, sep_w)
		x := x1 - 1 - w
		for s, i in right {
			if i > 0 { x = buffer.set_string(ui.buf, x, y, separator, st) }
			x = buffer.set_string(ui.buf, x, y, s, st)
		}
		x1 -= w + 2
	}

	if len(bar.left) > 0 && x1 - x0 > 1 {
		x := x0 + 1
		for s, i in bar.left {
			if i > 0 {
				if x + sep_w >= x1 { break }
				x = buffer.set_string(ui.buf, x, y, separator, st)
			}
			x = draw_cut(ui.buf, x, y, s, st, x1 - x)
			if x >= x1 { break }
		}
		x0 = min(x + 1, x1)
	}

	if bar.center != "" {
		if x1 - x0 <= 0 {
			return
		}
		w := min(text.width(bar.center), x1 - x0)
		cx := clamp(area.x + (area.width - w) / 2, x0, x1 - w)
		draw_cut(ui.buf, cx, y, bar.center, st, w)
		return
	}
	if x1 > x0 {
		free = {x0, y, x1 - x0, 1}
	}
	return
}

@(private)
segments_width :: proc(segs: []string, sep_w: int) -> int {
	w := 0
	for s, i in segs {
		w += text.width(s) + (sep_w if i > 0 else 0)
	}
	return w
}

// Writes `s` in at most `room` cells, ending in `…` when it had to be cut.
// Returns the x just past what was written.
@(private)
draw_cut :: proc(b: ^buffer.Buffer, x, y: int, s: string, st: Style, room: int) -> int {
	if room <= 0 {
		return x
	}
	if text.width(s) <= room {
		return buffer.set_string(b, x, y, s, st)
	}
	end := buffer.set_string(b, x, y, s, st, room - 1)
	return buffer.set_string(b, end, y, "…", st)
}
