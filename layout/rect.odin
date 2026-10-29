package layout

// A rectangle of cells. (x, y) is the top-left corner, 0-based.
Rect :: struct {
	x, y:          int,
	width, height: int,
}

rect_area :: proc(r: Rect) -> int {
	return r.width * r.height
}

rect_is_empty :: proc(r: Rect) -> bool {
	return r.width <= 0 || r.height <= 0
}

rect_right :: proc(r: Rect) -> int { return r.x + r.width }
rect_bottom :: proc(r: Rect) -> int { return r.y + r.height }

rect_contains :: proc(r: Rect, x, y: int) -> bool {
	return x >= r.x && x < r.x + r.width && y >= r.y && y < r.y + r.height
}

rect_intersection :: proc(a, b: Rect) -> Rect {
	x0 := max(a.x, b.x)
	y0 := max(a.y, b.y)
	x1 := min(a.x + a.width, b.x + b.width)
	y1 := min(a.y + a.height, b.y + b.height)
	if x1 <= x0 || y1 <= y0 {
		return {x0, y0, 0, 0}
	}
	return {x0, y0, x1 - x0, y1 - y0}
}

// Shrinks `r` by `n` cells on every side (clamped at zero size).
rect_inner :: proc(r: Rect, n: int) -> Rect {
	w := max(r.width - 2 * n, 0)
	h := max(r.height - 2 * n, 0)
	return {r.x + n, r.y + n, w, h}
}
