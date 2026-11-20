package widgets

import "core:math"
import "../style"

Graph_Options :: struct {
	max_value: f64,         // value that fills the height; 0 = largest value shown
	gradient:  []style.Rgb, // bottom-to-top colors; empty = theme.accent
	downward:  bool,        // grow from the top edge (for mirrored graphs)
}

// An area chart drawn with braille dots: each cell is 2 samples wide and
// 4 dots tall, so the resolution is 2x horizontally and 4x vertically
// compared to block characters. Newest sample on the right.
// For other shapes, draw on a Canvas.
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

	// One color per cell row, by its height: nil (theme.accent) without
	// a gradient.
	row_color := make([]style.Color, H, context.temp_allocator)
	if len(opts.gradient) > 0 {
		for row in 0 ..< H {
			height_t := (f64(H - 1 - row) + 0.5) / f64(H)
			if opts.downward { height_t = (f64(row) + 0.5) / f64(H) }
			row_color[row] = style.gradient(opts.gradient, height_t)
		}
	}

	c := canvas(area)
	start := W * 2 - len(shown) // right-align while history is short
	for v, j in shown {
		x := start + j
		dots := int(math.round(clamp(v / top, 0, 1) * f64(H * 4)))
		if v > 0 && dots == 0 { dots = 1 } // anything non-zero is visible
		for d in 0 ..< dots {
			y := d if opts.downward else c.height - 1 - d
			canvas_set(&c, x, y, row_color[y / 4])
		}
	}
	canvas_draw(ui, &c)
}
