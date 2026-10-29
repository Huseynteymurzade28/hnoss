package widgets

import "core:math"
import "core:unicode/utf8"
import "../buffer"
import "../style"

Graph_Options :: struct {
	max_value: f64,         // value that fills the height; 0 = largest value shown
	gradient:  []style.Rgb, // bottom-to-top colors; empty = theme.accent
	downward:  bool,        // grow from the top edge (for mirrored graphs)
}

// An area chart drawn with braille dots: each cell is 2 samples wide and
// 4 dots tall, so the resolution is 2x horizontally and 4x vertically
// compared to block characters. Newest sample on the right.
// Braille dot layout (Unicode U+2800 block):
//	1 4      bits 0x01 0x08
//	2 5           0x02 0x10
//	3 6           0x04 0x20
//	7 8           0x40 0x80
graph :: proc(ui: ^Ui, area: Rect, data: []f64, opts := Graph_Options{}) {
	W, H := area.width, area.height
	if W <= 0 || H <= 0 || len(data) == 0 {
		return
	}
	shown := data[max(len(data) - W * 2, 0):]
	top := opts.max_value
	if top <= 0 {
		for v in shown { top = max(top, v) }
	}
	if top <= 0 {
		top = 1
	}

	cells := make([]u8, W * H, context.temp_allocator)
	start := W * 2 - len(shown) // right-align while history is short
	for v, j in shown {
		s := start + j
		col, sub := s / 2, s % 2
		dots := int(math.round(clamp(v / top, 0, 1) * f64(H * 4)))
		if v > 0 && dots == 0 { dots = 1 } // anything non-zero is visible
		for d in 0 ..< dots {
			row := H - 1 - d / 4 // cell row, counted from the top
			in_cell := 3 - d % 4 // dot row inside the cell, from the top
			if opts.downward {
				row = d / 4
				in_cell = d % 4
			}
			cells[row * W + col] |= DOT_BIT[sub][in_cell]
		}
	}

	for row in 0 ..< H {
		height_t := (f64(H - 1 - row) + 0.5) / f64(H)
		if opts.downward { height_t = (f64(row) + 0.5) / f64(H) }
		st := ui.theme.accent
		if len(opts.gradient) > 0 {
			st = {fg = style.gradient(opts.gradient, height_t)}
		}
		for col in 0 ..< W {
			bits := cells[row * W + col]
			if bits == 0 { continue }
			buf, n := utf8.encode_rune(rune(0x2800) + rune(bits))
			buffer.set_symbol(ui.buf, area.x + col, area.y + row, string(buf[:n]), 1, st)
		}
	}
}

@(private, rodata)
DOT_BIT := [2][4]u8{
	{0x01, 0x02, 0x04, 0x40}, // left column, top to bottom
	{0x08, 0x10, 0x20, 0x80}, // right column
}
