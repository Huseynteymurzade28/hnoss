package hnoss

import pen_ "pen"
import "style"

Style :: style.Style
Color :: style.Color
Pen :: pen_.Pen
Wrap :: pen_.Wrap
Align :: pen_.Align

rgb :: style.rgb
hex :: style.hex
gradient :: style.gradient
Rgb :: style.Rgb

// Starts writing text into `area` of the frame. Finish with `finish`.
//
//	p := hnoss.pen(f, area)
//	hnoss.write(&p, "CPU ", {add = {.Bold}})
//	hnoss.write(&p, "92%", {fg = .Red})
//	hnoss.finish(&p)
pen :: proc(f: ^Frame, area: Rect, wrap := Wrap.Word, align := Align.Left, base: Style = {}, scroll := 0) -> Pen {
	return pen_.begin(f.buffer, area, wrap, align, base, scroll)
}

write :: pen_.write
newline :: pen_.newline
finish :: pen_.finish
measure :: pen_.measure

// Draws markup text into `area` in one call; returns the number of lines
// it took. See pen.markup for the tag syntax.
//
//	hnoss.markup(f, area, "[b]CPU[/] [red]92%[/]")
markup :: proc(f: ^Frame, area: Rect, src: string, wrap := Wrap.Word, align := Align.Left, base: Style = {}) -> int {
	p := pen_.begin(f.buffer, area, wrap, align)
	pen_.markup(&p, src, base)
	return pen_.finish(&p)
}

// Markup into an existing pen, mixed with plain writes.
write_markup :: pen_.markup
