package widgets

import "../buffer"
import "../layout"
import "../pen"
import "../style"

Box_Options :: struct {
	border:  Maybe(Border), // default: theme.border_kind
	focused: bool,          // draw with theme.border_focused
	align:   pen.Align,     // title alignment
	style:   Style,         // patched over the border style
	fill:    Maybe(Style),  // blank the inside with this style first
}

// A border with an optional markup title. Returns the area inside it.
//
//	inner := hnoss.box(ui, area, "[b]Processes[/] (42)")
box :: proc(ui: ^Ui, area: Rect, title := "", opts := Box_Options{}) -> Rect {
	if area.width <= 0 || area.height <= 0 {
		return {area.x, area.y, 0, 0}
	}
	if fill, ok := opts.fill.?; ok {
		buffer.fill(ui.buf, area, fill)
	}
	kind := opts.border.? or_else ui.theme.border_kind
	if kind == .None {
		draw_title(ui, {area.x, area.y, area.width, 1}, title, opts.align)
		return layout.pad(area, 1 if title != "" else 0, 0, 0, 0)
	}

	g := BORDER_GLYPHS[kind]
	st := style.patch(ui.theme.border_focused if opts.focused else ui.theme.border, opts.style)
	x0, y0 := area.x, area.y
	x1, y1 := area.x + area.width - 1, area.y + area.height - 1
	for x in x0 + 1 ..< x1 {
		buffer.set_symbol(ui.buf, x, y0, g.horizontal, 1, st)
		buffer.set_symbol(ui.buf, x, y1, g.horizontal, 1, st)
	}
	for y in y0 + 1 ..< y1 {
		buffer.set_symbol(ui.buf, x0, y, g.vertical, 1, st)
		buffer.set_symbol(ui.buf, x1, y, g.vertical, 1, st)
	}
	buffer.set_symbol(ui.buf, x0, y0, g.top_left, 1, st)
	buffer.set_symbol(ui.buf, x1, y0, g.top_right, 1, st)
	buffer.set_symbol(ui.buf, x0, y1, g.bottom_left, 1, st)
	buffer.set_symbol(ui.buf, x1, y1, g.bottom_right, 1, st)

	// Title sits on the top border with a space either side: ╭ Title ───╮
	draw_title(ui, {x0 + 1, y0, area.width - 2, 1}, title, opts.align)
	return layout.inset(area, 1)
}

// Title text with one space of padding either side; the text itself is
// cut with an ellipsis if it doesn't fit, the padding always stays.
@(private)
draw_title :: proc(ui: ^Ui, r: Rect, title: string, align: pen.Align) {
	if title == "" || r.width < 3 {
		return
	}
	tw := min(markup_width(title), r.width - 2)
	x := r.x
	switch align {
	case .Left:
	case .Center: x += (r.width - tw - 2) / 2
	case .Right:  x += r.width - tw - 2
	}
	buffer.set_symbol(ui.buf, x, r.y, " ", 1, ui.theme.title)
	p := pen.begin(ui.buf, {x + 1, r.y, tw, 1}, .Ellipsis)
	pen.markup(&p, title, ui.theme.title)
	pen.finish(&p)
	buffer.set_symbol(ui.buf, x + 1 + tw, r.y, " ", 1, ui.theme.title)
}

// Display width of markup text on one line (tags don't count).
@(private)
markup_width :: proc(src: string) -> int {
	p := pen.begin(nil, {0, 0, max(int) / 2, 0}, .Clip)
	pen.markup(&p, src)
	pen.finish(&p)
	return p.max_width
}

@(private)
Border_Glyphs :: struct {
	horizontal, vertical:                                string,
	top_left, top_right, bottom_left, bottom_right: string,
}

@(private, rodata)
BORDER_GLYPHS := [Border]Border_Glyphs {
	.None    = {},
	.Plain   = {"─", "│", "┌", "┐", "└", "┘"},
	.Rounded = {"─", "│", "╭", "╮", "╰", "╯"},
	.Double  = {"═", "║", "╔", "╗", "╚", "╝"},
	.Thick   = {"━", "┃", "┏", "┓", "┗", "┛"},
}
