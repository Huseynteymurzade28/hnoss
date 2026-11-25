package widgets

import "core:time"
import "../anim"
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
// With `fade`, what is behind it darkens over that time instead of at once
// (truecolor only; other colors are dimmed right away). It needs frames:
// wait with `hnoss.timeout`.
//
//	if confirm {
//		inner := hnoss.modal(ui, hnoss.center(f.area, 40, 7), &confirm, "[b]Delete?[/]")
//		...
//	}
modal :: proc(ui: ^Ui, area: Rect, open: ^bool, title := "", fade: time.Duration = 0) -> (inner: Rect) {
	ui.mem.modal = open
	if ui.held != nil {
		ui.events = ui.held
		ui.held = nil
	}
	if ui.pointer_held == .Modal { ui.pointer_held = .No }
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

	if ui.mem.fade.open != open {
		ui.mem.fade = {open = open}
		anim.tween_set(&ui.mem.fade.tween, 0)
	}
	dim(ui.buf, tween(ui, &ui.mem.fade.tween, 1, fade))
	blank(ui.buf, area)
	return box(ui, area, title, {focused = true, fill = ui.theme.modal})
}

// Fades the whole buffer: truecolor is darkened, by `amount` (0 to 1) of
// the way to a third; other foregrounds get Dim
// and other backgrounds (which can't be dimmed) are dropped.
@(private)
dim :: proc(b: ^buffer.Buffer, amount: f64) {
	fade :: proc(c: style.Color, amount: f64) -> (style.Color, bool) {
		if rgb, ok := c.(style.Rgb); ok {
			if amount >= 1 { return style.Rgb{rgb.r / 3, rgb.g / 3, rgb.b / 3}, true }
			k := 1 - amount * 2 / 3
			return style.Rgb{u8(f64(rgb.r) * k), u8(f64(rgb.g) * k), u8(f64(rgb.b) * k)}, true
		}
		return c, false
	}
	for &c in b.cells {
		ok: bool
		if c.fg, ok = fade(c.fg, amount); !ok { c.modifiers += {.Dim} }
		if c.bg, ok = fade(c.bg, amount); !ok { c.bg = nil }
	}
}

// Clears the styles in `area`: fill patches styles over what is there, and
// a dialog or popup should start from nothing.
@(private)
blank :: proc(b: ^buffer.Buffer, area: Rect) {
	r := layout.rect_intersection(area, b.area)
	for y in r.y ..< r.y + r.height {
		for x in r.x ..< r.x + r.width {
			c := buffer.get(b, x, y)
			c.fg, c.bg, c.modifiers = nil, nil, {}
			c.underline, c.underline_color, c.link = {}, nil, 0
		}
	}
}
