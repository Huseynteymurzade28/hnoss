package widgets

import "core:fmt"
import "core:math"
import "../buffer"
import "../style"
import "../text"

// A horizontal progress bar filling `area` (any height), with sub-cell
// precision: the leading edge is drawn in eighths of a cell. `label`
// defaults to the percentage; it is centered and drawn inverted where it
// sits on the filled part.
gauge :: proc(ui: ^Ui, area: Rect, ratio: f64, label: Maybe(string) = nil) {
	W := area.width
	if W <= 0 || area.height <= 0 {
		return
	}
	r := clamp(ratio, 0, 1)
	eighths := int(math.round(r * f64(W * 8)))
	full, part := eighths / 8, eighths % 8

	fill_c := ui.theme.gauge_filled.fg
	track_c := ui.theme.gauge_empty.bg
	bar_st := style.Style{fg = fill_c, bg = track_c}
	for y in area.y ..< area.y + area.height {
		for col in 0 ..< W {
			sym := " "
			switch {
			case col < full:                 sym = "█"
			case col == full && part > 0:    sym = PARTIAL_BLOCK[part]
			}
			buffer.set_symbol(ui.buf, area.x + col, y, sym, 1, bar_st)
		}
	}

	lbl := label.? or_else fmt.tprintf("%d%%", int(math.round(r * 100)))
	lw := min(text.width(lbl), W)
	col := (W - lw) / 2
	y := area.y + area.height / 2
	on_fill := style.Style{fg = track_c if track_c != nil else style.Named_Color.Black, bg = fill_c, add = {.Bold}}
	on_track := style.Style{fg = ui.theme.text.fg, bg = track_c, add = {.Bold}}
	for rest := lbl; len(rest) > 0; {
		cluster, w, next := text.next_grapheme(rest)
		rest = next
		if w == 0 { continue }
		if col + w > W { break }
		st := on_fill if col < full else on_track
		if fill_c == nil && col < full { st.add += {.Reversed} } // no bar color: invert instead
		buffer.set_symbol(ui.buf, area.x + col, y, cluster, w, st)
		col += w
	}
}

@(private, rodata)
PARTIAL_BLOCK := [8]string{" ", "▏", "▎", "▍", "▌", "▋", "▊", "▉"}
