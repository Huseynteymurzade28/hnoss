package layout

// Cutting: slice a piece off one edge of `r`, shrinking `r` in place. The
// natural way to lay out immediate-mode UI top-down:
//
//	area := f.area
//	header := layout.cut_top(&area, 1)
//	status := layout.cut_bottom(&area, 1)
//	sidebar := layout.cut_left(&area, 30)
//	// `area` is now what is left in the middle
//
// Asking for more than is available takes everything; negative sizes take
// nothing.

cut_top :: proc(r: ^Rect, n: int) -> Rect {
	k := clamp(n, 0, max(r.height, 0))
	piece := Rect{r.x, r.y, r.width, k}
	r.y += k
	r.height -= k
	return piece
}

cut_bottom :: proc(r: ^Rect, n: int) -> Rect {
	k := clamp(n, 0, max(r.height, 0))
	r.height -= k
	return {r.x, r.y + r.height, r.width, k}
}

cut_left :: proc(r: ^Rect, n: int) -> Rect {
	k := clamp(n, 0, max(r.width, 0))
	piece := Rect{r.x, r.y, k, r.height}
	r.x += k
	r.width -= k
	return piece
}

cut_right :: proc(r: ^Rect, n: int) -> Rect {
	k := clamp(n, 0, max(r.width, 0))
	r.width -= k
	return {r.x + r.width, r.y, k, r.height}
}

// `r` shrunk by `n` cells on every side (never below zero size).
inset :: proc(r: Rect, n: int) -> Rect {
	return pad(r, n, n, n, n)
}

// `r` shrunk by different amounts per side, CSS order: top, right, bottom, left.
pad :: proc(r: Rect, top, right, bottom, left: int) -> Rect {
	out := r
	cut_top(&out, top)
	cut_bottom(&out, bottom)
	cut_left(&out, left)
	cut_right(&out, right)
	return out
}

// A `width` x `height` rect centered in `r`, clamped to fit (for dialogs,
// splash text, ...).
center :: proc(r: Rect, width, height: int) -> Rect {
	w := clamp(width, 0, max(r.width, 0))
	h := clamp(height, 0, max(r.height, 0))
	return {r.x + (r.width - w) / 2, r.y + (r.height - h) / 2, w, h}
}

// Cell (col, row) of `r` divided into a cols x rows grid with `gap` cells
// between neighbours. Leftover cells from uneven division go to the first
// columns/rows, so the grid always fills `r` exactly.
grid_cell :: proc(r: Rect, cols, rows, col, row: int, gap := 0) -> Rect {
	if cols <= 0 || rows <= 0 {
		return {r.x, r.y, 0, 0}
	}
	x, w := even_slot(r.x, r.width, cols, col, gap)
	y, h := even_slot(r.y, r.height, rows, row, gap)
	return {x, y, w, h}
}

// Start and length of slot `i` when `length` cells are shared by `n` slots
// with `gap` between them.
@(private)
even_slot :: proc(start, length, n, i, gap: int) -> (pos, size: int) {
	avail := max(length - gap * (n - 1), 0)
	base, extra := avail / n, avail % n
	size = base + (1 if i < extra else 0)
	pos = start + i * (base + gap) + min(i, extra)
	return
}
