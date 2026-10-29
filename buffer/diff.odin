package buffer

import "core:strconv"
import "../style"

// Synchronized output (DEC private mode 2026): the terminal holds the frame
// until the end marker, so it never displays a half-drawn frame. Terminals
// that don't know the mode ignore it.
// https://gist.github.com/christianparpart/d8a62cc1ab659194337d73e399004036
BEGIN_SYNC :: "\x1b[?2026h"
END_SYNC   :: "\x1b[?2026l"

// Appends to `out` the bytes that turn a screen showing `prev` into one
// showing `next`. Both buffers must cover the same area.
//
// Assumes the terminal starts with default SGR attributes and leaves it that
// way: if anything was styled, it ends with a reset. The cursor position is
// treated as unknown, so the first update always moves explicitly.
diff :: proc(prev, next: ^Buffer, out: ^[dynamic]u8) {
	assert(prev.area == next.area, "diff: buffers cover different areas")

	pen: Pen // what the terminal's SGR state currently is
	cur_x, cur_y := -1, -1
	w := next.area.width

	for row in 0 ..< next.area.height {
		// Port of Ratatui's Buffer::diff skip logic, per row:
		//  - `to_skip`: cells covered by the wide char just emitted.
		//  - `invalidated`: cells the *previous* frame's wide char covered;
		//    they must be redrawn even if unchanged, because writing a
		//    narrow char over half a wide one erases the other half.
		to_skip, invalidated := 0, 0
		for col in 0 ..< w {
			i := row * w + col
			n, p := &next.cells[i], &prev.cells[i]
			if to_skip == 0 && (invalidated > 0 || n^ != p^) {
				x, y := next.area.x + col, next.area.y + row
				if x != cur_x || y != cur_y {
					move_to(out, x, y)
				}
				update_pen(out, &pen, n)
				append(out, ..n.symbol[:n.len])
				cur_x, cur_y = x + max(int(n.width), 1), y
			}
			to_skip = max(int(n.width) - 1, 0)
			invalidated = max(max(int(n.width), int(p.width)), invalidated) - 1
		}
	}

	if pen != {} {
		append(out, "\x1b[0m")
	}
}

@(private)
Pen :: struct {
	fg, bg:    style.Color,
	modifiers: style.Modifiers,
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
update_pen :: proc(out: ^[dynamic]u8, pen: ^Pen, c: ^Cell) {
	want := Pen{normalize(c.fg), normalize(c.bg), c.modifiers}
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
	if .Underlined in added { sgr_param(&sgr, 4) }
	if .Slow_Blink in added { sgr_param(&sgr, 5) }
	if .Rapid_Blink in added { sgr_param(&sgr, 6) }
	if .Reversed in added { sgr_param(&sgr, 7) }
	if .Hidden in added { sgr_param(&sgr, 8) }
	if .Crossed_Out in added { sgr_param(&sgr, 9) }

	if want.fg != pen.fg { sgr_color(&sgr, want.fg, false) }
	if want.bg != pen.bg { sgr_color(&sgr, want.bg, true) }

	if sgr.open {
		append(out, 'm')
	}
	pen^ = want
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

@(private)
append_uint :: proc(out: ^[dynamic]u8, n: int) {
	buf: [20]u8
	append(out, strconv.write_int(buf[:], i64(n), 10))
}
