package graphics

// The largest cols × rows that fits in max_cols × max_rows cells and keeps
// the proportions of a width × height image, for cells of cell_w × cell_h
// pixels (0: unknown, taken as 1 × 2). At least one cell.
fit_cells :: proc(width, height, max_cols, max_rows, cell_w, cell_h: int) -> (cols, rows: int) {
	if width <= 0 || height <= 0 || max_cols <= 0 || max_rows <= 0 {
		return 0, 0
	}
	cw, ch := cell_w, cell_h
	if cw <= 0 || ch <= 0 { cw, ch = 1, 2 }
	// The scale that fills the columns, or the rows if that is too tall.
	if height * max_cols * cw <= max_rows * ch * width {
		return max_cols, clamp(round_div(height * max_cols * cw, width * ch), 1, max_rows)
	}
	return clamp(round_div(width * max_rows * ch, height * cw), 1, max_cols), max_rows
}

// Scales `pixels` to w × h RGBA into `out` (w * h long), each the average of
// the pixels it covers. Transparent pixels don't color their neighbors.
scale :: proc(out: [][4]u8, w, h: int, pixels: []u8, width, height, channels: int) {
	for y in 0 ..< h {
		y0, y1 := span(y, h, height)
		for x in 0 ..< w {
			x0, x1 := span(x, w, width)
			sum: [3]int
			alpha, n := 0, 0
			for sy in y0 ..< y1 {
				row := pixels[(sy * width + x0) * channels:]
				for i := 0; i < (x1 - x0) * channels; i += channels {
					a := int(row[i + 3]) if channels == 4 else 255
					sum[0] += int(row[i]) * a
					sum[1] += int(row[i + 1]) * a
					sum[2] += int(row[i + 2]) * a
					alpha += a
					n += 1
				}
			}
			p: [4]u8
			if alpha > 0 {
				for s, c in sum { p[c] = u8(round_div(s, alpha)) }
				p[3] = u8(round_div(alpha, n))
			}
			out[y * w + x] = p
		}
	}
}

// The source pixels that pixel `i` of `n` covers, of `size`: at least one.
@(private)
span :: proc(i, n, size: int) -> (from, to: int) {
	from = i * size / n
	to = max((i + 1) * size / n, from + 1)
	return
}

@(private)
round_div :: proc(a, b: int) -> int {
	return (a + b / 2) / b
}
