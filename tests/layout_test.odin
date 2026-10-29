package tests

import "core:testing"
import "../layout"

Rect :: layout.Rect

@(test)
layout_cuts :: proc(t: ^testing.T) {
	area := Rect{0, 0, 80, 24}
	header := layout.cut_top(&area, 1)
	status := layout.cut_bottom(&area, 2)
	side := layout.cut_left(&area, 20)
	right := layout.cut_right(&area, 10)
	testing.expect_value(t, header, Rect{0, 0, 80, 1})
	testing.expect_value(t, status, Rect{0, 22, 80, 2})
	testing.expect_value(t, side, Rect{0, 1, 20, 21})
	testing.expect_value(t, right, Rect{70, 1, 10, 21})
	testing.expect_value(t, area, Rect{20, 1, 50, 21})

	// Over-asking takes what is there; negative takes nothing.
	small := Rect{5, 5, 3, 2}
	testing.expect_value(t, layout.cut_top(&small, 10), Rect{5, 5, 3, 2})
	testing.expect_value(t, small, Rect{5, 7, 3, 0})
	testing.expect_value(t, layout.cut_left(&small, -4), Rect{5, 7, 0, 0})
}

@(test)
layout_inset_pad_center :: proc(t: ^testing.T) {
	r := Rect{0, 0, 10, 6}
	testing.expect_value(t, layout.inset(r, 1), Rect{1, 1, 8, 4})
	testing.expect_value(t, layout.inset(r, 4), Rect{4, 4, 2, 0}) // height runs out: top is cut first
	testing.expect_value(t, layout.pad(r, 1, 2, 0, 3), Rect{3, 1, 5, 5})
	testing.expect_value(t, layout.center(r, 4, 2), Rect{3, 2, 4, 2})
	testing.expect_value(t, layout.center(r, 50, 50), r)
}

@(test)
layout_split_cells_and_fill :: proc(t: ^testing.T) {
	r := Rect{0, 0, 80, 24}
	a := layout.split(r, .Vertical, {1, layout.fill(), 3})
	testing.expect_value(t, a[0], Rect{0, 0, 80, 1})
	testing.expect_value(t, a[1], Rect{0, 1, 80, 20})
	testing.expect_value(t, a[2], Rect{0, 21, 80, 3})
}

@(test)
layout_split_percent_and_weights :: proc(t: ^testing.T) {
	r := Rect{10, 0, 100, 5}
	a := layout.split(r, .Horizontal, {layout.percent(30), layout.fill(2), layout.fill(1)})
	testing.expect_value(t, a[0], Rect{10, 0, 30, 5})
	testing.expect_value(t, a[1], Rect{40, 0, 47, 5}) // 70 * 2/3 = 46.67 -> 47
	testing.expect_value(t, a[2], Rect{87, 0, 23, 5})
}

@(test)
layout_split_rounding_adds_up :: proc(t: ^testing.T) {
	for width in 0 ..< 60 {
		a := layout.split(Rect{0, 0, width, 1}, .Horizontal, {layout.fill(), layout.fill(), layout.fill()}, gap = 1)
		sum := a[0].width + a[1].width + a[2].width + 2
		testing.expectf(t, sum == max(width, 2), "width %d: pieces+gaps = %d", width, sum)
		testing.expectf(t, abs(a[0].width - a[2].width) <= 1, "width %d: uneven %v", width, a)
		testing.expectf(t, a[2].x + a[2].width == max(width, 2) || width < 2, "width %d: does not reach the end", width)
	}
}

@(test)
layout_split_gap :: proc(t: ^testing.T) {
	a := layout.split(Rect{0, 0, 10, 1}, .Horizontal, {3, layout.fill(), 3}, gap = 1)
	testing.expect_value(t, a[0], Rect{0, 0, 3, 1})
	testing.expect_value(t, a[1], Rect{4, 0, 2, 1})
	testing.expect_value(t, a[2], Rect{7, 0, 3, 1})
}

@(test)
layout_split_overflow_first_come_first_served :: proc(t: ^testing.T) {
	a := layout.split(Rect{0, 0, 10, 1}, .Horizontal, {6, 6, layout.fill()})
	testing.expect_value(t, a[0].width, 6)
	testing.expect_value(t, a[1].width, 4)
	testing.expect_value(t, a[2].width, 0)
	// No fill: leftover space stays unused at the end.
	b := layout.split(Rect{0, 0, 10, 1}, .Horizontal, {2, 3})
	testing.expect_value(t, b[1], Rect{2, 0, 3, 1})
}

@(test)
layout_split_nested :: proc(t: ^testing.T) {
	rows := layout.split(Rect{0, 0, 40, 10}, .Vertical, {layout.fill(), layout.fill()})
	cols := layout.split(rows[1], .Horizontal, {layout.percent(50), layout.fill()})
	testing.expect_value(t, cols[0], Rect{0, 5, 20, 5})
	testing.expect_value(t, cols[1], Rect{20, 5, 20, 5})
}

@(test)
layout_grid :: proc(t: ^testing.T) {
	r := Rect{0, 0, 11, 7}
	testing.expect_value(t, layout.grid_cell(r, 3, 2, 0, 0, gap = 1), Rect{0, 0, 3, 3})
	testing.expect_value(t, layout.grid_cell(r, 3, 2, 1, 0, gap = 1), Rect{4, 0, 3, 3})
	testing.expect_value(t, layout.grid_cell(r, 3, 2, 2, 1, gap = 1), Rect{8, 4, 3, 3})
	// Uneven: 10 cells / 3 cols = 4, 3, 3 and the last cell ends at the edge.
	last := layout.grid_cell(Rect{0, 0, 10, 1}, 3, 1, 2, 0)
	testing.expect_value(t, layout.grid_cell(Rect{0, 0, 10, 1}, 3, 1, 0, 0).width, 4)
	testing.expect_value(t, last.x + last.width, 10)
}
