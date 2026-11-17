package buffer

import "core:mem"
import "core:strings"
import "core:unicode/utf8"
import "../layout"
import "../style"
import "../text"

Rect :: layout.Rect

// Room for one grapheme. 35 bytes fits every RGI emoji ZWJ sequence (the
// longest, e.g. kiss with two skin tones, is 35); anything longer is
// truncated at a rune boundary.
MAX_SYMBOL :: 35

Cell :: struct {
	symbol:    [MAX_SYMBOL]u8, // UTF-8, `len` bytes used
	len:       u8,
	width:     u8, // display width; 2 for wide chars, whose right-hand cell is blank
	fg, bg:    style.Color,
	modifiers: style.Modifiers,
	underline: style.Underline, // shape, while .Underlined is on
	underline_color: style.Color, // nil: the text color
	link:      u32, // OSC 8 hyperlink: 0 for none, else see link_url
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

// Applies everything in `s` but its link, which only a Buffer can hold
// (set_symbol, set_style and fill take care of it).
cell_set_style :: proc(c: ^Cell, s: style.Style) {
	if s.fg != nil { c.fg = s.fg }
	if s.bg != nil { c.bg = s.bg }
	if u, ok := s.underline.?; ok { c.underline = u }
	if s.underline_color != nil { c.underline_color = s.underline_color }
	c.modifiers = (c.modifiers - s.sub) + style.added_modifiers(s)
}

// A grid of cells covering `area`. Row-major; cell (x, y) is at
// `(y - area.y) * area.width + (x - area.x)`.
//
// Drawing (set_symbol, set_string, set_style, fill) only touches cells
// inside `clip`, which is the whole area unless set_clip narrowed it.
//
// The URLs of hyperlinked cells live in the buffer: Cell.link n is
// `links[n - 1]`. reset forgets them.
Buffer :: struct {
	area:      Rect,
	clip:      Rect,
	cells:     []Cell,
	links:     [dynamic]string,
	link_ids:  map[string]u32,
	allocator: mem.Allocator,
}

init :: proc(b: ^Buffer, area: Rect, allocator := context.allocator) -> mem.Allocator_Error {
	b.allocator = allocator
	b.area = {}
	return resize(b, area)
}

destroy :: proc(b: ^Buffer) {
	clear_links(b)
	delete(b.links)
	delete(b.link_ids)
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

// Limits drawing to `r` (within the area). Returns the clip it replaces,
// to put back with another set_clip when done.
set_clip :: proc(b: ^Buffer, r: Rect) -> (old: Rect) {
	old = b.clip
	b.clip = layout.rect_intersection(r, b.area)
	return
}

// Blanks every cell, forgets the links and lifts any clip.
reset :: proc(b: ^Buffer) {
	b.clip = b.area
	for &c in b.cells {
		c = EMPTY_CELL
	}
	clear_links(b)
}

// The id Cell.link uses for `url` in this buffer, adding it if new; 0 for
// "" or a URL that can't go into an OSC 8 sequence. OSC 8 takes URIs of
// printable ASCII only (anything else has to be percent-encoded), and a
// control character would end the sequence early.
link_id :: proc(b: ^Buffer, url: string) -> u32 {
	if url == "" {
		return 0
	}
	if id, ok := b.link_ids[url]; ok {
		return id
	}
	for i in 0 ..< len(url) {
		if url[i] < 0x20 || url[i] > 0x7e {
			return 0
		}
	}
	if b.links.allocator.procedure == nil {
		b.links.allocator = b.allocator
		b.link_ids.allocator = b.allocator
	}
	owned, err := strings.clone(url, b.allocator)
	if err != nil {
		return 0
	}
	append(&b.links, owned)
	id := u32(len(b.links))
	b.link_ids[owned] = id
	return id
}

// The URL behind a Cell.link id, "" for 0.
link_url :: proc(b: ^Buffer, id: u32) -> string {
	if id == 0 || int(id) > len(b.links) {
		return ""
	}
	return b.links[id - 1]
}

@(private)
clear_links :: proc(b: ^Buffer) {
	for url in b.links {
		delete(url, b.allocator)
	}
	clear(&b.links)
	clear(&b.link_ids)
}

index_of :: proc(b: ^Buffer, x, y: int) -> int {
	return (y - b.area.y) * b.area.width + (x - b.area.x)
}

// nil when (x, y) is outside the buffer. Reading ignores the clip.
get :: proc(b: ^Buffer, x, y: int) -> ^Cell {
	if !layout.rect_contains(b.area, x, y) {
		return nil
	}
	return &b.cells[index_of(b, x, y)]
}

// Puts one grapheme at (x, y), keeping wide characters consistent: a wide
// symbol blanks the cell it covers, and writing over either half of an
// existing wide symbol blanks the other half (even outside the clip).
// Returns the cell written, or nil if it does not fit in the clip.
set_symbol :: proc(b: ^Buffer, x, y: int, symbol: string, width: int, s: style.Style) -> ^Cell {
	if !layout.rect_contains(b.clip, x, y) || (width == 2 && !layout.rect_contains(b.clip, x + 1, y)) {
		return nil
	}
	c := get(b, x, y)
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
	link := link_id(b, s.link)
	cell_set_symbol(c, symbol, width)
	cell_set_style(c, s)
	c.link = link
	if width == 2 {
		right := get(b, x + 1, y)
		if right.width == 2 {
			if rr := get(b, x + 2, y); rr != nil { cell_set_symbol(rr, " ", 1) }
		}
		cell_set_symbol(right, " ", 1)
		cell_set_style(right, s)
		right.link = link
	}
	return c
}

// Writes `s` starting at (x, y), one grapheme per cell (two for wide
// ones), clipped to the clip and to `max_width` cells. Control characters
// are skipped. Returns the x just past the last cell written.
// For wrapping, alignment and markup use the pen package.
set_string :: proc(b: ^Buffer, x, y: int, s: string, st: style.Style = {}, max_width := max(int)) -> int {
	if y < b.clip.y || y >= layout.rect_bottom(b.clip) {
		return x
	}
	right := layout.rect_right(b.clip)
	if max_width < right - x {
		right = x + max_width
	}
	cx := x
	for rest := s; len(rest) > 0; {
		cluster, w, r := text.next_grapheme(rest)
		rest = r
		if w == 0 {
			continue
		}
		if cx + w > right {
			break
		}
		if cx >= b.clip.x {
			set_symbol(b, cx, y, cluster, w, st)
		}
		cx += w
	}
	return cx
}

// Applies `s` to every cell in `area` (clipped). A link in `s` links the
// cells; without one they keep the link they have.
set_style :: proc(b: ^Buffer, area: Rect, s: style.Style) {
	r := layout.rect_intersection(area, b.clip)
	link := link_id(b, s.link)
	for y in r.y ..< r.y + r.height {
		for x in r.x ..< r.x + r.width {
			c := &b.cells[index_of(b, x, y)]
			cell_set_style(c, s)
			if link != 0 { c.link = link }
		}
	}
}

// Blanks every cell in `area` (clipped) and applies `s`:
// a solid background. A wide char whose right half falls inside the area
// loses its left half too (via set_symbol on the first column); one whose
// left half is the last column simply becomes a blank, as its right half
// already is.
fill :: proc(b: ^Buffer, area: Rect, s: style.Style) {
	r := layout.rect_intersection(area, b.clip)
	link := link_id(b, s.link)
	for y in r.y ..< r.y + r.height {
		set_symbol(b, r.x, y, " ", 1, s)
		for x in r.x + 1 ..< r.x + r.width {
			c := &b.cells[index_of(b, x, y)]
			cell_set_symbol(c, " ", 1)
			cell_set_style(c, s)
			c.link = link
		}
	}
}
