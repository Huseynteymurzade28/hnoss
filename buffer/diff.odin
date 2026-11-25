package buffer

import "core:hash"
import "core:strconv"
import "core:unicode/utf8"
import "../style"

// Synchronized output (DEC private mode 2026): the terminal holds the frame
// until the end marker, so it never displays a half-drawn frame. Terminals
// that don't know the mode ignore it.
// https://gist.github.com/christianparpart/d8a62cc1ab659194337d73e399004036
BEGIN_SYNC :: "\x1b[?2026h"
END_SYNC   :: "\x1b[?2026l"

// What the terminal can show beyond colors and the classic modifiers.
Output_Feature :: enum u8 {
	// Underline shapes (SGR 4:2 … 4:5) and colors (SGR 58 / 59). Without
	// it every underline is a plain one in the text color.
	Styled_Underlines,
	// OSC 8 hyperlinks. Without it links are plain text.
	Hyperlinks,
}
Output_Features :: bit_set[Output_Feature; u8]

ALL_OUTPUT_FEATURES :: Output_Features{.Styled_Underlines, .Hyperlinks}

// Appends to `out` the bytes that turn a screen showing `prev` into one
// showing `next`. Both buffers must cover the same area.
//
// Colors are downsampled to `depth` on the way out (see style.downsample);
// the buffers themselves keep the colors the frame drew. What `features`
// leaves out falls back to what every terminal can show.
//
// Assumes the terminal starts with default SGR attributes and no open
// hyperlink, and leaves it that way: if anything was styled, it ends with a
// reset (and a link that is still open gets closed). The cursor position is
// treated as unknown, so the first update always moves explicitly.
diff :: proc(
	prev, next: ^Buffer,
	out: ^[dynamic]u8,
	depth := style.Color_Depth.Truecolor,
	features := ALL_OUTPUT_FEATURES,
) {
	assert(prev.area == next.area, "diff: buffers cover different areas")

	pen: Pen // what the terminal's SGR state currently is
	link: u32 // the hyperlink currently open, an id in `next`
	cur_x, cur_y := -1, -1
	w := next.area.width

	for row in 0 ..< next.area.height {
		// Wide-character bookkeeping, per row:
		//  - `to_skip`: cells covered by the wide char just emitted.
		//  - `invalidated`: cells the *previous* frame's wide char covered;
		//    they must be redrawn even if unchanged, because writing a
		//    narrow char over half a wide one erases the other half.
		to_skip, invalidated := 0, 0
		for col in 0 ..< w {
			i := row * w + col
			n, p := &next.cells[i], &prev.cells[i]
			if to_skip == 0 && (invalidated > 0 || cells_differ(prev, next, p, n)) {
				x, y := next.area.x + col, next.area.y + row
				if x != cur_x || y != cur_y {
					move_to(out, x, y)
				}
				update_pen(out, &pen, n, depth, features)
				if want := n.link if .Hyperlinks in features else 0; want != link {
					set_link(out, link_url(next, want))
					link = want
				}
				if n.image.id != 0 {
					append_placeholder(out, n.image)
				} else {
					append(out, ..n.symbol[:n.len])
				}
				cur_x, cur_y = x + max(int(n.width), 1), y
			}
			to_skip = max(int(n.width) - 1, 0)
			invalidated = max(max(int(n.width), int(p.width)), invalidated) - 1
		}
	}

	if link != 0 {
		set_link(out, "")
	}
	if pen != {} {
		append(out, "\x1b[0m")
	}
}

// Link ids are per buffer, so linked cells compare by URL.
@(private)
cells_differ :: proc(prev, next: ^Buffer, p, n: ^Cell) -> bool {
	if p.link == 0 && n.link == 0 {
		return p^ != n^
	}
	if link_url(prev, p.link) != link_url(next, n.link) {
		return true
	}
	a, b := p^, n^
	a.link, b.link = 0, 0
	return a != b
}

// OSC 8 ; params ; URI ST opens a link, an empty URI closes it. Cells of
// one link drawn in separate runs (a wrapped line, a partial redraw) share
// an `id` derived from the URL, so the terminal treats them as one link.
@(private)
set_link :: proc(out: ^[dynamic]u8, url: string) {
	append(out, "\x1b]8;")
	if url != "" {
		append(out, "id=")
		h := hash.fnv32a(transmute([]u8)url)
		hex := "0123456789abcdef"
		for shift := 28; shift >= 0; shift -= 4 {
			append(out, hex[(h >> uint(shift)) & 0xf])
		}
	}
	append(out, ';')
	append(out, url)
	append(out, "\x1b\\")
}

@(private)
Pen :: struct {
	fg, bg:          style.Color,
	modifiers:       style.Modifiers,
	underline:       style.Underline,
	underline_color: style.Color,
}

// CUP is 1-based: ESC [ row ; col H
move_to :: proc(out: ^[dynamic]u8, x, y: int) {
	append(out, "\x1b[")
	append_uint(out, y + 1)
	append(out, ';')
	append_uint(out, x + 1)
	append(out, 'H')
}

// Emits one SGR sequence covering every attribute that differs between the
// pen and the cell, then updates the pen.
@(private)
update_pen :: proc(out: ^[dynamic]u8, pen: ^Pen, c: ^Cell, depth: style.Color_Depth, features: Output_Features) {
	want := Pen {
		fg        = normalize(style.downsample(c.fg, depth)),
		bg        = normalize(style.downsample(c.bg, depth)),
		modifiers = c.modifiers,
	}
	// Shape and color only matter while underlined; keep them zero
	// otherwise so they don't cause SGR churn.
	if .Underlined in c.modifiers && .Styled_Underlines in features {
		want.underline = c.underline
		want.underline_color = normalize(style.downsample(c.underline_color, depth))
	}
	if c.image.id != 0 {
		// The colors of a placeholder say which image and placement it
		// belongs to, so they are exact whatever the depth.
		want = {
			fg              = id_color(c.image.id),
			bg              = want.bg,
			underline_color = id_color(image_placement(c.image.cols, c.image.rows)),
		}
	}
	if want == pen^ {
		return
	}
	sgr := Sgr{out = out}

	removed := pen.modifiers - want.modifiers
	added := want.modifiers - pen.modifiers
	// SGR 22 turns off *both* bold and dim, so removing one of them means
	// re-adding the other if it should stay on.
	if removed & {.Bold, .Dim} != {} {
		sgr_param(&sgr, 22)
		added += want.modifiers & {.Bold, .Dim}
	}
	if .Italic in removed { sgr_param(&sgr, 23) }
	if .Underlined in removed { sgr_param(&sgr, 24) }
	if removed & {.Slow_Blink, .Rapid_Blink} != {} {
		sgr_param(&sgr, 25)
		added += want.modifiers & {.Slow_Blink, .Rapid_Blink}
	}
	if .Reversed in removed { sgr_param(&sgr, 27) }
	if .Hidden in removed { sgr_param(&sgr, 28) }
	if .Crossed_Out in removed { sgr_param(&sgr, 29) }

	if .Bold in added { sgr_param(&sgr, 1) }
	if .Dim in added { sgr_param(&sgr, 2) }
	if .Italic in added { sgr_param(&sgr, 3) }
	if .Underlined in added || (.Underlined in want.modifiers && want.underline != pen.underline) {
		// 4 is a single underline; 4:2 … 4:5 the other shapes.
		sgr_param(&sgr, 4)
		if want.underline != .Single {
			append(out, ':')
			append_uint(out, int(want.underline) + 1)
		}
	}
	if .Slow_Blink in added { sgr_param(&sgr, 5) }
	if .Rapid_Blink in added { sgr_param(&sgr, 6) }
	if .Reversed in added { sgr_param(&sgr, 7) }
	if .Hidden in added { sgr_param(&sgr, 8) }
	if .Crossed_Out in added { sgr_param(&sgr, 9) }

	if want.fg != pen.fg { sgr_color(&sgr, want.fg, false) }
	if want.bg != pen.bg { sgr_color(&sgr, want.bg, true) }
	if want.underline_color != pen.underline_color { sgr_underline_color(&sgr, want.underline_color) }

	if sgr.open {
		append(out, 'm')
	}
	pen^ = want
}

@(private)
id_color :: proc(id: u32) -> style.Color {
	return style.Rgb{u8(id >> 16), u8(id >> 8), u8(id)}
}

// U+10EEEE with the row and column as combining characters.
// https://sw.kovidgoyal.net/kitty/graphics-protocol/#unicode-placeholders
@(private)
append_placeholder :: proc(out: ^[dynamic]u8, p: Image_Part) {
	for r in ([3]rune{0x10eeee, DIACRITICS[p.row], DIACRITICS[p.col]}) {
		buf, n := utf8.encode_rune(r)
		append(out, ..buf[:n])
	}
}

// nil and .Reset mean the same thing on screen; fold them so they compare equal.
@(private)
normalize :: proc(c: style.Color) -> style.Color {
	if n, ok := c.(style.Named_Color); ok && n == .Reset {
		return nil
	}
	return c
}

@(private)
Sgr :: struct {
	out:  ^[dynamic]u8,
	open: bool,
}

@(private)
sgr_param :: proc(s: ^Sgr, n: int) {
	if s.open {
		append(s.out, ';')
	} else {
		append(s.out, "\x1b[")
		s.open = true
	}
	append_uint(s.out, n)
}

// 30-37 / 40-47 normal, 90-97 / 100-107 bright, 39 / 49 default,
// 38;5;n / 48;5;n indexed, 38;2;r;g;b / 48;2;r;g;b truecolor.
@(private)
sgr_color :: proc(s: ^Sgr, c: style.Color, background: bool) {
	base := 40 if background else 30
	switch v in c {
	case nil:
		sgr_param(s, base + 9)
	case style.Named_Color:
		i := int(v) - int(style.Named_Color.Black)
		switch {
		case v == .Reset: sgr_param(s, base + 9)
		case i < 8:       sgr_param(s, base + i)
		case:             sgr_param(s, base + 60 + (i - 8))
		}
	case style.Indexed:
		sgr_param(s, base + 8)
		sgr_param(s, 5)
		sgr_param(s, int(v))
	case style.Rgb:
		sgr_param(s, base + 8)
		sgr_param(s, 2)
		sgr_param(s, int(v.r))
		sgr_param(s, int(v.g))
		sgr_param(s, int(v.b))
	}
}

// 58;5;n / 58;2;r;g;b like 38 and 48 (no short form for the named
// colors, which are 0-15 in the 256 palette), 59 back to the text color.
@(private)
sgr_underline_color :: proc(s: ^Sgr, c: style.Color) {
	switch v in c {
	case nil:
		sgr_param(s, 59)
	case style.Named_Color:
		if v == .Reset {
			sgr_param(s, 59)
		} else {
			sgr_param(s, 58)
			sgr_param(s, 5)
			sgr_param(s, int(v) - int(style.Named_Color.Black))
		}
	case style.Indexed:
		sgr_param(s, 58)
		sgr_param(s, 5)
		sgr_param(s, int(v))
	case style.Rgb:
		sgr_param(s, 58)
		sgr_param(s, 2)
		sgr_param(s, int(v.r))
		sgr_param(s, int(v.g))
		sgr_param(s, int(v.b))
	}
}

@(private)
append_uint :: proc(out: ^[dynamic]u8, n: int) {
	buf: [20]u8
	append(out, strconv.write_int(buf[:], i64(n), 10))
}
