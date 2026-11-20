package widgets

import "core:slice"
import "core:unicode/utf8"
import "../buffer"
import "../style"

// A drawing surface of braille dots over `area`: each cell holds 2×4 dots,
// so it is `area.width * 2` dots wide and `area.height * 4` tall, with
// (0, 0) at the top left. Dots outside it are ignored.
//
// A cell has one color: the color of the last dot set in it. A nil color
// is theme.accent.
//
//	c := hnoss.canvas(area)
//	hnoss.canvas_line(&c, 0, 0, c.width - 1, c.height - 1)
//	hnoss.canvas_circle(&c, c.width / 2, c.height / 2, 10, style.Rgb{255, 140, 66}, fill = true)
//	hnoss.canvas_draw(ui, &c)
//
// Its memory is from context.temp_allocator: make one each frame.
Canvas :: struct {
	area:          Rect,
	width, height: int, // in dots
	bits:          []u8,          // per cell, the braille dots set
	colors:        []style.Color, // per cell
}

// Braille dot layout (Unicode U+2800 block), as bits:
//	1 4      0x01 0x08
//	2 5      0x02 0x10
//	3 6      0x04 0x20
//	7 8      0x40 0x80
@(private, rodata)
BRAILLE_BIT := [4][2]u8{{0x01, 0x08}, {0x02, 0x10}, {0x04, 0x20}, {0x40, 0x80}}

canvas :: proc(area: Rect) -> Canvas {
	w, h := max(area.width, 0), max(area.height, 0)
	return {
		area   = {area.x, area.y, w, h},
		width  = w * 2,
		height = h * 4,
		bits   = make([]u8, w * h, context.temp_allocator),
		colors = make([]style.Color, w * h, context.temp_allocator),
	}
}

// Sets the dot at (x, y).
canvas_set :: proc(c: ^Canvas, x, y: int, color: style.Color = nil) {
	if x < 0 || y < 0 || x >= c.width || y >= c.height {
		return
	}
	i := (y / 4) * c.area.width + x / 2
	c.bits[i] |= BRAILLE_BIT[y % 4][x % 2]
	c.colors[i] = color
}

// Clears the dot at (x, y). The cell keeps its color.
canvas_unset :: proc(c: ^Canvas, x, y: int) {
	if x < 0 || y < 0 || x >= c.width || y >= c.height {
		return
	}
	c.bits[(y / 4) * c.area.width + x / 2] &~= BRAILLE_BIT[y % 4][x % 2]
}

// Whether the dot at (x, y) is set; false outside the canvas.
canvas_get :: proc(c: ^Canvas, x, y: int) -> bool {
	if x < 0 || y < 0 || x >= c.width || y >= c.height {
		return false
	}
	return c.bits[(y / 4) * c.area.width + x / 2] & BRAILLE_BIT[y % 4][x % 2] != 0
}

// A straight line from (x0, y0) to (x1, y1), both ends included.
canvas_line :: proc(c: ^Canvas, x0, y0, x1, y1: int, color: style.Color = nil) {
	// Entirely on one side of the canvas: nothing to draw, and no need to
	// walk a long line that is off screen.
	if (x0 < 0 && x1 < 0) || (y0 < 0 && y1 < 0) || (x0 >= c.width && x1 >= c.width) || (y0 >= c.height && y1 >= c.height) {
		return
	}
	dx, dy := abs(x1 - x0), -abs(y1 - y0)
	sx := 1 if x0 < x1 else -1
	sy := 1 if y0 < y1 else -1
	err := dx + dy
	x, y := x0, y0
	for {
		canvas_set(c, x, y, color)
		if x == x1 && y == y1 { break }
		e2 := 2 * err
		if e2 >= dy { err += dy; x += sx }
		if e2 <= dx { err += dx; y += sy }
	}
}

// The `w`×`h` dot rectangle with its top left at (x, y): its outline, or
// every dot in it with `fill`.
canvas_rect :: proc(c: ^Canvas, x, y, w, h: int, color: style.Color = nil, fill := false) {
	if w <= 0 || h <= 0 {
		return
	}
	if fill {
		for yy in max(y, 0) ..< min(y + h, c.height) {
			for xx in max(x, 0) ..< min(x + w, c.width) {
				canvas_set(c, xx, yy, color)
			}
		}
		return
	}
	r, b := x + w - 1, y + h - 1
	canvas_line(c, x, y, r, y, color)
	canvas_line(c, x, b, r, b, color)
	canvas_line(c, x, y, x, b, color)
	canvas_line(c, r, y, r, b, color)
}

// The circle of radius `r` dots around (cx, cy): its outline, or the disc
// with `fill`. Dots are about square (a cell is 2 dots wide and 4 tall,
// and about twice as tall as wide), so it looks round.
canvas_circle :: proc(c: ^Canvas, cx, cy, r: int, color: style.Color = nil, fill := false) {
	if r < 0 {
		return
	}
	// Midpoint circle: walk one octant, mirror it into the other seven.
	x, y := r, 0
	err := 1 - r
	for x >= y {
		if fill {
			canvas_hline(c, cx - x, cx + x, cy + y, color)
			canvas_hline(c, cx - x, cx + x, cy - y, color)
			canvas_hline(c, cx - y, cx + y, cy + x, color)
			canvas_hline(c, cx - y, cx + y, cy - x, color)
		} else {
			canvas_set(c, cx + x, cy + y, color); canvas_set(c, cx - x, cy + y, color)
			canvas_set(c, cx + x, cy - y, color); canvas_set(c, cx - x, cy - y, color)
			canvas_set(c, cx + y, cy + x, color); canvas_set(c, cx - y, cy + x, color)
			canvas_set(c, cx + y, cy - x, color); canvas_set(c, cx - y, cy - x, color)
		}
		y += 1
		if err < 0 {
			err += 2 * y + 1
		} else {
			x -= 1
			err += 2 * (y - x) + 1
		}
	}
}

// The polygon through `points` (closed back to the first): its outline,
// or with `fill` its inside as well, by the even-odd rule, so a
// self-crossing star has a hole in the middle.
canvas_polygon :: proc(c: ^Canvas, points: [][2]int, color: style.Color = nil, fill := false) {
	n := len(points)
	if n == 0 {
		return
	}
	if fill && n >= 3 {
		lo, hi := points[0].y, points[0].y
		for p in points {
			lo, hi = min(lo, p.y), max(hi, p.y)
		}
		xs := make([dynamic]f64, 0, n, context.temp_allocator)
		for y in max(lo, 0) ..= min(hi, c.height - 1) {
			// Where the row's center line crosses each edge.
			sy := f64(y) + 0.5
			clear(&xs)
			for i in 0 ..< n {
				a, b := points[i], points[(i + 1) % n]
				ay, by := f64(a.y), f64(b.y)
				if (ay <= sy) == (by <= sy) { continue } // doesn't cross this row
				append(&xs, f64(a.x) + (sy - ay) / (by - ay) * f64(b.x - a.x))
			}
			slice.sort(xs[:])
			for k := 0; k + 1 < len(xs); k += 2 {
				canvas_hline(c, int(xs[k] + 0.5), int(xs[k + 1] - 0.5), y, color)
			}
		}
	}
	for i in 0 ..< n {
		a, b := points[i], points[(i + 1) % n]
		canvas_line(c, a.x, a.y, b.x, b.y, color)
	}
}

// Puts the canvas on screen. Empty cells are left as they were, so a
// canvas can be drawn over a background.
canvas_draw :: proc(ui: ^Ui, c: ^Canvas) {
	for row in 0 ..< c.area.height {
		for col in 0 ..< c.area.width {
			i := row * c.area.width + col
			bits := c.bits[i]
			if bits == 0 { continue }
			st := ui.theme.accent
			if c.colors[i] != nil { st = {fg = c.colors[i]} }
			buf, n := utf8.encode_rune(rune(0x2800) + rune(bits))
			buffer.set_symbol(ui.buf, c.area.x + col, c.area.y + row, string(buf[:n]), 1, st)
		}
	}
}

@(private = "file")
canvas_hline :: proc(c: ^Canvas, x0, x1, y: int, color: style.Color) {
	if y < 0 || y >= c.height {
		return
	}
	for x in max(x0, 0) ..= min(x1, c.width - 1) {
		canvas_set(c, x, y, color)
	}
}
