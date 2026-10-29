package pen

import "../buffer"
import "../layout"
import "../style"
import "../text"

Wrap :: enum u8 {
	Word,     // break at spaces; a word longer than a line breaks anywhere
	Char,     // break anywhere
	Clip,     // no wrapping: what doesn't fit is cut off
	Ellipsis, // no wrapping: cut off lines end in "…"
}

Align :: enum u8 {
	Left,
	Center,
	Right,
}

// A pen writes styled text into an area of a buffer, flowing it into lines
// as it goes: there is no intermediate text structure to build. The line
// being written is held back until it is complete (alignment and word
// wrap need to see the whole line), so call `finish` at the end.
//
//	p := pen.begin(buf, area)
//	pen.write(&p, "CPU ", {add = {.Bold}})
//	pen.write(&p, "92%", {fg = .Red})
//	pen.finish(&p)
//
// With `buf = nil` nothing is drawn but lines are still counted, which
// makes a pen a measuring tool too (see `measure`).
Pen :: struct {
	buf:       ^buffer.Buffer,
	area:      layout.Rect,
	wrap:      Wrap,
	align:     Align,
	base:      style.Style, // under every write's own style
	scroll:    int,         // lines to skip at the top
	tab_width: int,

	lines:     int, // completed lines, including scrolled-off and overflowing ones
	max_width: int, // widest completed line

	line:      [dynamic]Glyph, // current line, not placed yet
	line_w:    int,
	break_at:  int,  // index just past the last space in `line`, or -1
	clipped:   bool, // Clip/Ellipsis: dropping the rest of this line
	wrapped:   bool, // current line started by a wrap (drop leading spaces)
}

@(private)
Glyph :: struct {
	sym:   [buffer.MAX_SYMBOL]u8,
	len:   u8,
	width: u8,
	space: bool,
	style: style.Style,
}

begin :: proc(
	buf: ^buffer.Buffer,
	area: layout.Rect,
	wrap := Wrap.Word,
	align := Align.Left,
	base: style.Style = {},
	scroll := 0,
	allocator := context.temp_allocator,
) -> Pen {
	return Pen {
		buf       = buf,
		area      = area,
		wrap      = wrap,
		align     = align,
		base      = base,
		scroll    = scroll,
		tab_width = 4,
		line      = make([dynamic]Glyph, 0, clamp(area.width, 0, 256) + 1, allocator), // grows if needed
		break_at  = -1,
	}
}

// Places the last line and releases the pen's scratch memory. Returns the
// total number of lines the text took (which can exceed the area's height).
finish :: proc(p: ^Pen) -> int {
	if len(p.line) > 0 {
		emit_line(p, len(p.line), soft = false)
	}
	delete(p.line)
	p.line = nil
	return p.lines
}

// True once text has run past the bottom of the area.
overflowed :: proc(p: ^Pen) -> bool {
	return p.lines - p.scroll > p.area.height || (p.lines - p.scroll == p.area.height && len(p.line) > 0)
}

write :: proc(p: ^Pen, s: string, st: style.Style = {}) {
	if p.area.width <= 0 {
		return
	}
	gs := style.patch(p.base, st)
	for rest := s; len(rest) > 0; {
		cluster, w, r := text.next_grapheme(rest)
		rest = r
		switch {
		case cluster == "\n" || cluster == "\r\n":
			newline(p)
		case cluster == "\t":
			n := p.tab_width - p.line_w % p.tab_width
			for _ in 0 ..< n {
				add_glyph(p, glyph(" ", 1, gs))
			}
		case w == 0:
			// Control characters, or a combining mark with nothing before it.
		case:
			add_glyph(p, glyph(cluster, w, gs))
		}
	}
}

// Ends the current line (a hard line break).
newline :: proc(p: ^Pen) {
	emit_line(p, len(p.line), soft = false)
	p.clipped = false
	p.wrapped = false
}

// Number of lines `s` takes at `width` cells, and its widest line.
measure :: proc(s: string, width: int, wrap := Wrap.Word) -> (lines, max_width: int) {
	p := begin(nil, {0, 0, width, 0}, wrap)
	write(&p, s)
	lines = finish(&p)
	return lines, p.max_width
}

@(private)
glyph :: proc(cluster: string, w: int, st: style.Style) -> Glyph {
	g := Glyph{width = u8(w), space = cluster == " ", style = st}
	n := copy(g.sym[:], cluster) // longer clusters are cut, like in Cell
	g.len = u8(n)
	return g
}

@(private)
add_glyph :: proc(p: ^Pen, g: Glyph) {
	W := p.area.width
	if p.clipped {
		return
	}
	if p.line_w + int(g.width) > W {
		switch p.wrap {
		case .Clip:
			p.clipped = true
			return
		case .Ellipsis:
			p.clipped = true
			for len(p.line) > 0 && p.line_w + 1 > W {
				last := pop(&p.line)
				p.line_w -= int(last.width)
			}
			if W >= 1 {
				append(&p.line, glyph("…", 1, g.style))
				p.line_w += 1
			}
			return
		case .Word, .Char:
			for p.line_w + int(g.width) > W && len(p.line) > 0 {
				n := len(p.line)
				if p.wrap == .Word && !g.space && p.break_at > 0 {
					n = p.break_at // carry the unfinished word to the next line
				}
				emit_line(p, n, soft = true)
				p.wrapped = true
			}
			if int(g.width) > W {
				return // can never fit (wide char in a 1-cell area)
			}
		}
	}
	if g.space && p.wrapped && len(p.line) == 0 {
		return // no leading spaces on a wrapped line
	}
	append(&p.line, g)
	p.line_w += int(g.width)
	if g.space {
		p.break_at = len(p.line)
	}
}

// Places line[:n] at the next row and keeps line[n:] as the start of the
// next line. Soft (wrapped) lines drop their trailing spaces.
@(private)
emit_line :: proc(p: ^Pen, n: int, soft: bool) {
	end := n
	if soft {
		for end > 0 && p.line[end - 1].space {
			end -= 1
		}
	}
	lw := 0
	for g in p.line[:end] {
		lw += int(g.width)
	}

	row := p.lines - p.scroll
	if p.buf != nil && row >= 0 && row < p.area.height {
		x := p.area.x
		switch p.align {
		case .Left:
		case .Center: x += (p.area.width - lw) / 2
		case .Right:  x += p.area.width - lw
		}
		y := p.area.y + row
		for &g in p.line[:end] {
			buffer.set_symbol(p.buf, x, y, string(g.sym[:g.len]), int(g.width), g.style)
			x += int(g.width)
		}
	}
	p.max_width = max(p.max_width, lw)
	p.lines += 1

	remove_range(&p.line, 0, n)
	p.line_w = 0
	p.break_at = -1
	for g, i in p.line {
		p.line_w += int(g.width)
		if g.space {
			p.break_at = i + 1
		}
	}
}
