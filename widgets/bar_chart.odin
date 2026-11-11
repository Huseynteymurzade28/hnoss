package widgets

import "core:fmt"
import "core:math"
import "../buffer"
import "../style"
import "../text"

Bar :: struct {
	label: string, // under the bar (vertical) or left of it (horizontal); may be empty
	value: f64,    // negative values draw as 0
}

Bar_Chart_Options :: struct {
	max_value:   f64,         // value that fills the length; 0 = the largest value
	horizontal:  bool,        // bars grow to the right, labels on the left
	bar_width:   int,         // cells across a bar; 0 = vertical: share the width, horizontal: 1 row
	gap:         Maybe(int),  // cells between bars; nil = 1 vertical, 0 horizontal
	gradient:    []style.Rgb, // colors from the base of a bar to its tip; empty = theme.accent
	colors:      []Style,     // colors[i] for bar i, over the gradient (bars past its end use the gradient)
	format:      string,      // fmt format for the values, e.g. "%.0f°C"; "" = "42" or "3.5"
	hide_values: bool,
}

// Bars with labels and values, next to gauge / sparkline / graph. The tip
// of each bar is drawn in eighths of a cell. Vertical bars are laid out
// left to right with their value above and label below; horizontal ones
// top to bottom with the label on the left and the value after the tip.
// Bars that don't fit are left out.
//
//	hnoss.bar_chart(ui, area, {{"Bakı", 31}, {"Gəncə", 27}, {"Şəki", 22}}, {format = "%v°"})
bar_chart :: proc(ui: ^Ui, area: Rect, bars: []Bar, opts := Bar_Chart_Options{}) {
	if area.width <= 0 || area.height <= 0 || len(bars) == 0 {
		return
	}
	top := opts.max_value
	if top <= 0 {
		for b in bars { top = max(top, b.value) }
	}
	if top <= 0 {
		top = 1
	}
	if opts.horizontal {
		horizontal_bars(ui, area, bars, top, opts)
	} else {
		vertical_bars(ui, area, bars, top, opts)
	}
}

@(private = "file")
vertical_bars :: proc(ui: ^Ui, area: Rect, bars: []Bar, top: f64, opts: Bar_Chart_Options) {
	n := len(bars)
	gap := max(opts.gap.? or_else 1, 0)
	bw := opts.bar_width
	if bw <= 0 {
		bw = max((area.width + gap) / n - gap, 1)
	}
	has_labels := false
	for b in bars { has_labels ||= b.label != "" }

	// Rows: the value row on top (so the tallest bar's value fits), the
	// bars, the label row at the bottom.
	value_rows := 0 if opts.hide_values else 1
	label_rows := 1 if has_labels else 0
	bar_h := area.height - value_rows - label_rows
	if bar_h <= 0 {
		value_rows, label_rows = 0, 0
		bar_h = area.height
	}
	base := area.y + value_rows + bar_h - 1 // bottom row of the bars

	for b, i in bars {
		x := area.x + i * (bw + gap)
		if x + bw > area.x + area.width { break }
		levels := int(math.round(clamp(b.value / top, 0, 1) * f64(bar_h * 8)))
		if b.value > 0 && levels == 0 { levels = 1 } // anything non-zero is visible
		for row in 0 ..< bar_h {
			k := clamp(levels - row * 8, 0, 8)
			if k == 0 { break }
			st := bar_style(ui, i, opts, (f64(row) + 0.5) / f64(bar_h))
			for c in 0 ..< bw {
				buffer.set_symbol(ui.buf, x + c, base - row, SPARK_LEVEL[k], 1, st)
			}
		}
		// A number cut short would be a wrong number: left out instead.
		if v := value_text(b, opts); value_rows > 0 && text.width(v) <= bw {
			filled := (levels + 7) / 8
			centered(ui, x, base - filled, bw, v, ui.theme.text)
		}
		if label_rows > 0 {
			centered(ui, x, base + 1, bw, b.label, ui.theme.muted)
		}
	}
}

@(private = "file")
horizontal_bars :: proc(ui: ^Ui, area: Rect, bars: []Bar, top: f64, opts: Bar_Chart_Options) {
	gap := max(opts.gap.? or_else 0, 0)
	bh := max(opts.bar_width, 1)

	// Columns: labels (as wide as the widest, up to a third of the area),
	// the bars, then room for the widest value after the longest bar.
	label_w, value_w := 0, 0
	for b in bars {
		label_w = max(label_w, text.width(b.label))
		if !opts.hide_values { value_w = max(value_w, text.width(value_text(b, opts))) }
	}
	label_w = min(label_w, area.width / 3)
	x0 := area.x + (label_w + 1 if label_w > 0 else 0)
	bar_w := area.x + area.width - x0 - (value_w + 1 if value_w > 0 else 0)
	if bar_w <= 0 {
		return
	}

	for b, i in bars {
		y := area.y + i * (bh + gap)
		if y + bh > area.y + area.height { break }
		eighths := int(math.round(clamp(b.value / top, 0, 1) * f64(bar_w * 8)))
		if b.value > 0 && eighths == 0 { eighths = 1 }
		full, part := eighths / 8, eighths % 8
		for row in y ..< y + bh {
			for c in 0 ..< full + (1 if part > 0 else 0) {
				sym := "█" if c < full else PARTIAL_BLOCK[part]
				st := bar_style(ui, i, opts, (f64(c) + 0.5) / f64(bar_w))
				buffer.set_symbol(ui.buf, x0 + c, row, sym, 1, st)
			}
		}
		mid := y + bh / 2 if bh > 1 else y
		if label_w > 0 {
			label, _ := text.truncate(b.label, label_w)
			buffer.set_string(ui.buf, area.x, mid, label, ui.theme.muted, label_w)
		}
		if value_w > 0 {
			tip := full + (1 if part > 0 else 0)
			buffer.set_string(ui.buf, x0 + tip + 1, mid, value_text(b, opts), ui.theme.text, value_w)
		}
	}
}

// Bar i's color at `t` (0 = base, 1 = tip of a full-length bar).
@(private = "file")
bar_style :: proc(ui: ^Ui, i: int, opts: Bar_Chart_Options, t: f64) -> Style {
	if i < len(opts.colors) {
		return style.patch(ui.theme.accent, opts.colors[i])
	}
	if len(opts.gradient) > 0 {
		return {fg = style.gradient(opts.gradient, t)}
	}
	return ui.theme.accent
}

// "42" for whole numbers, "3.5" otherwise, or as opts.format says.
@(private = "file")
value_text :: proc(b: Bar, opts: Bar_Chart_Options) -> string {
	if opts.format != "" {
		return fmt.tprintf(opts.format, b.value)
	}
	if b.value == math.trunc(b.value) && abs(b.value) < 1e15 {
		return fmt.tprintf("%d", i64(b.value))
	}
	return fmt.tprintf("%.1f", b.value)
}

// `s` centered in the `w` cells from x, cut off to fit.
@(private = "file")
centered :: proc(ui: ^Ui, x, y, w: int, s: string, st: Style) {
	if s == "" {
		return
	}
	fit, sw := text.truncate(s, w)
	buffer.set_string(ui.buf, x + (w - sw) / 2, y, fit, st, w)
}
