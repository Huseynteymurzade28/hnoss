package widgets

import "../buffer"
import "../input"
import "../layout"
import "../style"

// A dialog over the rest of the frame: dims everything drawn so far, clears
// `area` and draws a focused box with a markup title. Returns the area
// inside it. Draw it last, then the widgets that go inside it.
//
// `open` is your flag for showing it. While it is true, the widgets drawn
// before the modal get no keys or mouse events (from the frame after it
// opened, since it is drawn last). Esc or a mouse press outside `area` set
// it to false; so does your own code, e.g. a Cancel button inside.
//
//	if confirm {
//		inner := hnoss.modal(ui, hnoss.center(f.area, 40, 7), &confirm, "[b]Delete?[/]")
//		...
//	}
modal :: proc(ui: ^Ui, area: Rect, open: ^bool, title := "") -> (inner: Rect) {
	ui.mem.modal = open
	if ui.held != nil {
		ui.events = ui.held
		ui.held = nil
	}
	ui.cursor.visible = false // a caret under the dialog

	for ev, i in ui.events {
		if ui.handled[i] { continue }
		#partial switch e in ev {
		case input.Key:
			if e.code == .Esc {
				open^ = false
				consume(ui, i)
			}
		case input.Mouse:
			if layout.rect_contains(area, e.x, e.y) { continue }
			if e.kind == .Press { open^ = false }
			consume(ui, i) // nothing outside the dialog reacts
		}
	}

	dim(ui.buf)
	// fill patches styles over what is there; start the dialog from nothing
	r := layout.rect_intersection(area, ui.buf.area)
	for y in r.y ..< r.y + r.height {
		for x in r.x ..< r.x + r.width {
			c := buffer.get(ui.buf, x, y)
			c.fg, c.bg, c.modifiers = nil, nil, {}
		}
	}
	return box(ui, area, title, {focused = true, fill = ui.theme.modal})
}

// Fades the whole buffer: truecolor is darkened; other foregrounds get Dim
// and other backgrounds (which can't be dimmed) are dropped.
@(private)
dim :: proc(b: ^buffer.Buffer) {
	fade :: proc(c: style.Color) -> (style.Color, bool) {
		if rgb, ok := c.(style.Rgb); ok {
			return style.Rgb{rgb.r / 3, rgb.g / 3, rgb.b / 3}, true
		}
		return c, false
	}
	for &c in b.cells {
		ok: bool
		if c.fg, ok = fade(c.fg); !ok { c.modifiers += {.Dim} }
		if c.bg, ok = fade(c.bg); !ok { c.bg = nil }
	}
}
