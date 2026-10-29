package buffer

import "core:mem"
import "core:unicode/utf8"
import "../layout"
import "../style"
import "../text"

Rect :: layout.Rect

// Room for one grapheme: a base rune plus a few combining marks, or a short
// ZWJ emoji sequence. Longer clusters are truncated at a rune boundary.
MAX_SYMBOL :: 14

Cell :: struct {
	symbol:    [MAX_SYMBOL]u8, // UTF-8, `len` bytes used
	len:       u8,
	width:     u8, // display width; 2 for wide chars, whose right-hand cell is blank
	fg, bg:    style.Color,
	modifiers: style.Modifiers,
}

EMPTY_CELL :: Cell{symbol = {0 = ' '}, len = 1, width = 1}

cell_symbol :: proc(c: ^Cell) -> string {
	return string(c.symbol[:c.len])
}

cell_set_symbol :: proc(c: ^Cell, s: string, width: int) {
	n := min(len(s), MAX_SYMBOL)
	// Don't cut a UTF-8 sequence in half.
	for n > 0 && n < len(s) && !utf8.rune_start(s[n]) {
		n -= 1
	}
	c.symbol = {} // keep unused bytes zero so Cells compare with ==
	copy(c.symbol[:], s[:n])
	c.len = u8(n)
	c.width = u8(width)
}

cell_set_style :: proc(c: ^Cell, s: style.Style) {
	if s.fg != nil { c.fg = s.fg }
	if s.bg != nil { c.bg = s.bg }
	c.modifiers = (c.modifiers - s.sub) + s.add
}

// A grid of cells covering `area`. Row-major; cell (x, y) is at
// `(y - area.y) * area.width + (x - area.x)`.
Buffer :: struct {
	area:      Rect,
	cells:     []Cell,
	allocator: mem.Allocator,
}

init :: proc(b: ^Buffer, area: Rect, allocator := context.allocator) -> mem.Allocator_Error {
	b.allocator = allocator
	b.area = {}
	return resize(b, area)
}

destroy :: proc(b: ^Buffer) {
	delete(b.cells, b.allocator)
	b^ = {}
}

// Changes the area and blanks every cell.
resize :: proc(b: ^Buffer, area: Rect) -> mem.Allocator_Error {
	n := max(area.width, 0) * max(area.height, 0)
	if n != len(b.cells) {
		delete(b.cells, b.allocator)
		b.cells = make([]Cell, n, b.allocator) or_return
	}
	b.area = area
	reset(b)
	return nil
}

reset :: proc(b: ^Buffer) {
	for &c in b.cells {
		c = EMPTY_CELL
	}
}

index_of :: proc(b: ^Buffer, x, y: int) -> int {
	return (y - b.area.y) * b.area.width + (x - b.area.x)
}

// nil when (x, y) is outside the buffer.
get :: proc(b: ^Buffer, x, y: int) -> ^Cell {
	if !layout.rect_contains(b.area, x, y) {
		return nil
	}
	return &b.cells[index_of(b, x, y)]
}

// Puts one grapheme at (x, y), keeping wide characters consistent: a wide
// symbol blanks the cell it covers, and writing over either half of an
// existing wide symbol blanks the other half. Returns the cell written, or
// nil if it does not fit.
set_symbol :: proc(b: ^Buffer, x, y: int, symbol: string, width: int, s: style.Style) -> ^Cell {
	c := get(b, x, y)
	if c == nil || (width == 2 && !layout.rect_contains(b.area, x + 1, y)) {
		return nil
	}
	// Overwriting the right half of a wide char: the left half is now a lie.
	if left := get(b, x - 1, y); left != nil && left.width == 2 {
		cell_set_symbol(left, " ", 1)
	}
	// Overwriting the left half of a wide char with something narrow.
	if c.width == 2 && width < 2 {
		if right := get(b, x + 1, y); right != nil {
			cell_set_symbol(right, " ", 1)
		}
	}
	cell_set_symbol(c, symbol, width)
	cell_set_style(c, s)
	if width == 2 {
		right := get(b, x + 1, y)
		if right.width == 2 {
			if rr := get(b, x + 2, y); rr != nil { cell_set_symbol(rr, " ", 1) }
		}
		cell_set_symbol(right, " ", 1)
		cell_set_style(right, s)
	}
	return c
}

// Writes `s` starting at (x, y), clipped to the buffer and to `max_width`
// cells. Zero-width runes (combining marks) join the previous cell.
// Returns the x just past the last cell written.
set_string :: proc(b: ^Buffer, x, y: int, s: string, st: style.Style = {}, max_width := max(int)) -> int {
	if y < b.area.y || y >= layout.rect_bottom(b.area) {
		return x
	}
	right := layout.rect_right(b.area)
	if max_width < right - x {
		right = x + max_width
	}
	cx := x
	prev: ^Cell
	for i := 0; i < len(s); {
		r, n := utf8.decode_rune_in_string(s[i:])
		cluster := s[i:i + n]
		i += n
		w := text.rune_width(r)
		if w == 0 {
			if prev != nil && r >= 0x20 && int(prev.len) + n <= MAX_SYMBOL {
				copy(prev.symbol[prev.len:], cluster)
				prev.len += u8(n)
			}
			continue
		}
		if cx + w > right {
			break
		}
		if cx >= b.area.x {
			prev = set_symbol(b, cx, y, cluster, w, st)
		} else {
			prev = nil
		}
		cx += w
	}
	return cx
}

// Applies `s` to every cell in `area` (clipped to the buffer).
set_style :: proc(b: ^Buffer, area: Rect, s: style.Style) {
	r := layout.rect_intersection(area, b.area)
	for y in r.y ..< r.y + r.height {
		for x in r.x ..< r.x + r.width {
			cell_set_style(&b.cells[index_of(b, x, y)], s)
		}
	}
}
