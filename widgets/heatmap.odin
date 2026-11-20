package widgets

import "core:fmt"
import "core:math"
import "../buffer"
import "../style"
import "../text"

Heatmap_Options :: struct {
	min_value, max_value: Maybe(f64), // the ends of the scale; nil = the smallest / largest value
	gradient:    []style.Rgb, // colors from min to max; empty = a built-in cold-to-hot one
	cell_width:  int,         // cells across one value; 0 = 2, which looks roughly square
	half_blocks: bool,        // two rows of values per terminal row (▀), for dense data
	row_labels:  []string,    // left of each row (with half_blocks: of each terminal row)
	col_labels:  []string,    // above each column; ones that would overlap the previous are left out
	legend:      bool,        // a row under the last row: min, the gradient, max
	format:      string,      // fmt format for the legend's values; "" = "42" or "3.5"
}

// From cold to hot, for when Heatmap_Options.gradient is empty.
@(private, rodata)
HEATMAP_GRADIENT := []style.Rgb{
	{0x14, 0x21, 0x3d}, {0x2a, 0x6f, 0x97}, {0x61, 0xa5, 0xc2},
	{0xf9, 0xc7, 0x4f}, {0xf3, 0x72, 0x2c}, {0xd6, 0x28, 0x28},
}

// A grid of values drawn as colored cells. `values` is row-major with
// `columns` values per row; a NaN is a missing value, drawn as a muted `·`
// (or left blank with half_blocks). Rows and columns past the edge of
// `area` are left out.
//
//	hnoss.heatmap(ui, area, load[:], 24, {col_labels = hours, row_labels = days, legend = true})
heatmap :: proc(ui: ^Ui, area: Rect, values: []f64, columns: int, opts := Heatmap_Options{}) {
	if area.width <= 0 || area.height <= 0 || columns <= 0 || len(values) == 0 {
		return
	}
	rows := (len(values) + columns - 1) / columns
	cw := opts.cell_width if opts.cell_width > 0 else 2
	stops := opts.gradient if len(opts.gradient) > 0 else HEATMAP_GRADIENT

	lo, hi := math.INF_F64, math.NEG_INF_F64
	for v in values {
		if math.is_nan(v) { continue }
		lo, hi = min(lo, v), max(hi, v)
	}
	lo = opts.min_value.? or_else lo
	hi = opts.max_value.? or_else hi

	color :: proc(v, lo, hi: f64, stops: []style.Rgb) -> style.Color {
		if math.is_nan(v) { return nil }
		t := 0.5 if hi <= lo else (v - lo) / (hi - lo)
		return style.gradient(stops, t)
	}
	value :: proc(values: []f64, columns, r, c: int) -> f64 {
		i := r * columns + c
		return values[i] if i < len(values) else math.nan_f64()
	}

	grid := area
	legend := opts.legend && grid.height > 1 && !math.is_inf(lo)
	if legend {
		grid.height -= 1 // keep a row for it, under the last row drawn
	}
	label_w := 0
	for l in opts.row_labels {
		label_w = max(label_w, text.width(l))
	}
	if label_w > 0 {
		label_w = min(label_w + 1, grid.width)
	}
	if len(opts.col_labels) > 0 && grid.height > 1 {
		next_free := grid.x + label_w
		for l, c in opts.col_labels {
			x := grid.x + label_w + c * cw
			if x >= grid.x + grid.width { break }
			if l == "" || x < next_free { continue }
			next_free = buffer.set_string(ui.buf, x, grid.y, l, ui.theme.muted, grid.x + grid.width - x) + 1
		}
		grid.y += 1
		grid.height -= 1
	}

	per_row := 2 if opts.half_blocks else 1
	drawn := min(grid.height, (rows + per_row - 1) / per_row)
	if legend {
		lx := grid.x + label_w
		draw_legend(ui, {lx, grid.y + drawn, grid.x + grid.width - lx, 1}, lo, hi, stops, opts.format)
	}
	for ty in 0 ..< drawn {
		r := ty * per_row
		y := grid.y + ty
		if ty < len(opts.row_labels) && label_w > 0 {
			buffer.set_string(ui.buf, grid.x, y, opts.row_labels[ty], ui.theme.muted, label_w - 1)
		}
		for c in 0 ..< columns {
			x := grid.x + label_w + c * cw
			w := min(cw, grid.x + grid.width - x)
			if w <= 0 { break }
			top := color(value(values, columns, r, c), lo, hi, stops)
			if !opts.half_blocks {
				if top == nil {
					buffer.set_string(ui.buf, x + (w - 1) / 2, y, "·", ui.theme.muted)
				} else {
					buffer.fill(ui.buf, {x, y, w, 1}, {bg = top})
				}
				continue
			}
			bottom := color(value(values, columns, r + 1, c), lo, hi, stops) if r + 1 < rows else nil
			for dx in 0 ..< w {
				switch {
				case top != nil:    buffer.set_symbol(ui.buf, x + dx, y, "▀", 1, {fg = top, bg = bottom})
				case bottom != nil: buffer.set_symbol(ui.buf, x + dx, y, "▄", 1, {fg = bottom})
				}
			}
		}
	}
}

// `lo ████ hi`: the scale, as wide as there is room for, up to 24 cells.
@(private = "file")
draw_legend :: proc(ui: ^Ui, area: Rect, lo, hi: f64, stops: []style.Rgb, format: string) {
	lo_s, hi_s := legend_value(lo, format), legend_value(hi, format)
	bar_w := min(24, area.width - text.width(lo_s) - text.width(hi_s) - 2)
	if bar_w < 2 {
		return
	}
	x := buffer.set_string(ui.buf, area.x, area.y, lo_s, ui.theme.muted) + 1
	for i in 0 ..< bar_w {
		t := f64(i) / f64(bar_w - 1)
		buffer.set_symbol(ui.buf, x + i, area.y, " ", 1, {bg = style.gradient(stops, t)})
	}
	buffer.set_string(ui.buf, x + bar_w + 1, area.y, hi_s, ui.theme.muted)
}

@(private = "file")
legend_value :: proc(v: f64, format: string) -> string {
	if format != "" {
		return fmt.tprintf(format, v)
	}
	if v == math.trunc(v) && abs(v) < 1e15 {
		return fmt.tprintf("%d", i64(v))
	}
	return fmt.tprintf("%.1f", v)
}
