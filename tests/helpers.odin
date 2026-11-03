package tests

import "core:fmt"
import "core:strings"
import "core:testing"
import "../buffer"
import "../style"

// The buffer's rows as text, trailing spaces trimmed (temp allocator).
screen_rows :: proc(b: ^buffer.Buffer) -> []string {
	out := make([]string, b.area.height, context.temp_allocator)
	for y in 0 ..< b.area.height {
		sb := strings.builder_make(context.temp_allocator)
		for x := 0; x < b.area.width; {
			c := buffer.get(b, b.area.x + x, b.area.y + y)
			strings.write_string(&sb, buffer.cell_symbol(c))
			x += max(int(c.width), 1)
		}
		out[y] = strings.trim_right(strings.to_string(sb), " ")
	}
	return out
}

// Checks the whole screen against a multi-line snapshot:
//
//	expect_screen(t, &buf, `
//		╭ Hi ──╮
//		│      │
//		╰──────╯
//	`)
//
// The snapshot is normalized by `snapshot_lines`. Rows past its last line
// must be blank. On a mismatch the report shows every row and, under each
// one that differs, the expected text.
expect_screen :: proc(t: ^testing.T, b: ^buffer.Buffer, want: string, loc := #caller_location) -> bool {
	report, ok := compare_screen(screen_rows(b), snapshot_lines(want))
	testing.expectf(t, ok, "screen mismatch\n%s", report, loc = loc)
	return ok
}

// Checks which cells have style `st`, as a grid with one character per
// cell (a wide character covers two): any non-space marks a cell that has
// it, a space one that doesn't. A cell has `st` when it has every part `st`
// sets: its fg and bg if not nil, all of `add`, none of `sub`.
//
//	expect_style(t, &buf, {add = {.Bold}}, `
//		 ####
//	`)
expect_style :: proc(t: ^testing.T, b: ^buffer.Buffer, st: style.Style, want: string, loc := #caller_location) -> bool {
	lines := snapshot_lines(want)
	for &l in lines {
		bytes := make([]u8, strings.rune_count(l), context.temp_allocator)
		i := 0
		for r in l {
			bytes[i] = ' ' if r == ' ' else '#'
			i += 1
		}
		l = string(bytes)
	}
	report, ok := compare_screen(style_rows(b, st), lines)
	testing.expectf(t, ok, "style mismatch (# = cell has %v)\n%s", st, report, loc = loc)
	return ok
}

// One string per row, '#' where the cell has style `st` (see
// expect_style), trailing spaces trimmed.
style_rows :: proc(b: ^buffer.Buffer, st: style.Style) -> []string {
	out := make([]string, b.area.height, context.temp_allocator)
	for y in 0 ..< b.area.height {
		row := make([]u8, b.area.width, context.temp_allocator)
		for x in 0 ..< b.area.width {
			row[x] = '#' if cell_has_style(buffer.get(b, b.area.x + x, b.area.y + y), st) else ' '
		}
		out[y] = strings.trim_right(string(row), " ")
	}
	return out
}

cell_has_style :: proc(c: ^buffer.Cell, st: style.Style) -> bool {
	return (st.fg == nil || c.fg == st.fg) &&
	       (st.bg == nil || c.bg == st.bg) &&
	       st.add <= c.modifiers &&
	       st.sub & c.modifiers == {}
}

// Turns an indented raw-string snapshot into its lines: drops the line
// break right after the opening backtick and the whitespace-only line
// before the closing one, removes the tabs common to every line's indent,
// and trims trailing spaces. Only tabs count as indentation, so a row that
// starts with spaces keeps them (a rendered screen never holds a tab).
snapshot_lines :: proc(snapshot: string) -> []string {
	s := strings.trim_prefix(snapshot, "\n")
	if i := strings.last_index_byte(s, '\n'); i >= 0 && strings.trim_space(s[i:]) == "" {
		s = s[:i]
	}
	lines := strings.split_lines(s, context.temp_allocator)
	indent := max(int)
	for l in lines {
		if strings.trim_space(l) == "" { continue }
		n := 0
		for n < len(l) && l[n] == '\t' { n += 1 }
		indent = min(indent, n)
	}
	for &l in lines {
		l = l[min(indent, len(l) - len(strings.trim_left(l, "\t"))):]
		l = strings.trim_right(l, " \t")
	}
	return lines
}

// Compares rendered rows with expected ones (missing expected rows count
// as blank). On a mismatch `report` lists every row, marks the ones that
// differ with `!` and puts the expected text under each:
//
//	   0 |╭ Hi ──╮
//	 ! 1 |│ a    │
//	want |│ b    │
//	   2 |╰──────╯
//
// The `|` marks where the row starts; trailing spaces are trimmed on both
// sides, so a row ends where its last visible cell does.
compare_screen :: proc(got, want: []string) -> (report: string, ok: bool) {
	ok = true
	for i in 0 ..< max(len(got), len(want)) {
		if row_or(got, i, "") != row_or(want, i, "") { ok = false }
	}
	if ok { return "", true }

	sb := strings.builder_make(context.temp_allocator)
	differ := 0
	for i in 0 ..< max(len(got), len(want)) {
		g := row_or(got, i, "<no row>")
		w := row_or(want, i, "")
		if g == w {
			fmt.sbprintf(&sb, "  %s%d |%s\n", pad(i), i, g)
		} else {
			differ += 1
			fmt.sbprintf(&sb, "! %s%d |%s\nwant |%s\n", pad(i), i, g, w)
		}
	}
	fmt.sbprintf(&sb, "%d of %d rows differ", differ, max(len(got), len(want)))
	return strings.to_string(sb), false
}

// fmt's %2d pads with zeros.
@(private = "file")
pad :: proc(i: int) -> string {
	return " " if i < 10 else ""
}

@(private = "file")
row_or :: proc(rows: []string, i: int, missing: string) -> string {
	return rows[i] if i < len(rows) else missing
}
