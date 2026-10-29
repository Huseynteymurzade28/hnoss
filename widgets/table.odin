package widgets

import "../buffer"
import "../layout"
import "../pen"

Table_State :: List_State

Column :: struct {
	title: string, // markup
	width: layout.Size,
	align: pen.Align,
}

Table_Options :: struct {
	scrollbar: bool,
	gap:       int, // cells between columns (0 means the default, 1)
}

// Rows of cells under a header. Columns are sized like a split (cells,
// percent(), fill()). Navigation and mouse work like list. Returns true
// when the selection changed.
table :: proc(ui: ^Ui, area: Rect, columns: []Column, rows: [][]string, state: ^Table_State, opts := Table_Options{}) -> (changed: bool) {
	state.activated = false
	if area.width <= 0 || area.height <= 0 || len(columns) == 0 {
		return false
	}
	body := area
	bar: Rect
	if opts.scrollbar && len(rows) > area.height - 1 {
		bar = layout.cut_right(&body, 1)
	}
	header := layout.cut_top(&body, 1)

	old := state.selected
	select_rows(ui, state, body, 1, len(rows))

	sizes := make([]layout.Size, len(columns), context.temp_allocator)
	for c, i in columns { sizes[i] = c.width }
	gap := opts.gap if opts.gap > 0 else 1
	cols := layout.split_slice(header, .Horizontal, sizes, gap)

	for c, i in columns {
		p := pen.begin(ui.buf, cols[i], .Ellipsis, c.align, base = ui.theme.header)
		pen.markup(&p, c.title)
		pen.finish(&p)
	}

	row_style := ui.theme.selected if focused(ui, state) else ui.theme.selected_unfocused
	for r in state.offset ..< min(state.offset + body.height, len(rows)) {
		y := body.y + r - state.offset
		if r == state.selected {
			buffer.fill(ui.buf, {body.x, y, body.width, 1}, row_style)
		}
		for c, i in columns {
			if i >= len(rows[r]) { break }
			cell := Rect{cols[i].x, y, cols[i].width, 1}
			p := pen.begin(ui.buf, cell, .Ellipsis, c.align, base = ui.theme.text)
			pen.write(&p, rows[r][i])
			pen.finish(&p)
		}
	}

	if bar.width > 0 {
		scrollbar(ui, {bar.x, body.y, 1, body.height}, len(rows), body.height, &state.offset)
	}
	return state.selected != old
}
