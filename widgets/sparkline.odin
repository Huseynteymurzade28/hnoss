package widgets

import "core:math"
import "../buffer"
import "../style"

// Bars for the most recent values of `data`, newest on the right, one
// column each, scaled so `max_value` (default: the largest value shown)
// fills the area's height. Each row adds 8 levels of resolution.
sparkline :: proc(ui: ^Ui, area: Rect, data: []f64, max_value := 0.0, st: Maybe(Style) = nil) {
	W, H := area.width, area.height
	if W <= 0 || H <= 0 || len(data) == 0 {
		return
	}
	shown := data[max(len(data) - W, 0):]
	top := max_value
	if top <= 0 {
		for v in shown { top = max(top, v) }
	}
	if top <= 0 {
		top = 1
	}
	bar_st := style.patch(ui.theme.accent, st.? or_else {})
	x0 := area.x + W - len(shown) // right-aligned while there is less data than width
	for v, i in shown {
		levels := int(math.round(clamp(v / top, 0, 1) * f64(H * 8)))
		for row in 0 ..< H {
			n := clamp(levels - row * 8, 0, 8)
			if n == 0 { break }
			buffer.set_symbol(ui.buf, x0 + i, area.y + H - 1 - row, SPARK_LEVEL[n], 1, bar_st)
		}
	}
}

@(private, rodata)
SPARK_LEVEL := [9]string{" ", "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"}
