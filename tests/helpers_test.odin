package tests

import "core:testing"
import "../buffer"
import "../style"

@(test)
snapshot_lines_strips_common_tab_indent :: proc(t: ^testing.T) {
	lines := snapshot_lines(`
		╭──╮
		  x
			y
	`)
	testing.expect_value(t, len(lines), 3)
	testing.expect_value(t, lines[0], "╭──╮")
	testing.expect_value(t, lines[1], "  x") // leading spaces kept, trailing trimmed
	testing.expect_value(t, lines[2], "\ty") // only the common indent goes

	// Blank lines inside don't count toward the indent.
	lines = snapshot_lines("\n\t\ta\n\n\t\tb\n\t")
	testing.expect_value(t, len(lines), 3)
	testing.expect_value(t, lines[1], "")
	testing.expect_value(t, lines[2], "b")

	testing.expect_value(t, len(snapshot_lines("one line")), 1)
}

@(test)
compare_screen_reports_differing_rows :: proc(t: ^testing.T) {
	_, ok := compare_screen({"ab", "cd", ""}, {"ab", "cd"}) // a missing row is a blank row
	testing.expect(t, ok)

	report: string
	report, ok = compare_screen({"ab", "cx", "ef"}, {"ab", "cd", "ef"})
	testing.expect(t, !ok)
	testing.expect_value(t, report, "   0 |ab\n!  1 |cx\nwant |cd\n   2 |ef\n1 of 3 rows differ")

	report, ok = compare_screen({"ab"}, {"ab", "cd"})
	testing.expect(t, !ok)
	testing.expect_value(t, report, "   0 |ab\n!  1 |<no row>\nwant |cd\n1 of 2 rows differ")
}

@(test)
expect_screen_and_style_on_a_buffer :: proc(t: ^testing.T) {
	buf: buffer.Buffer
	buffer.init(&buf, {0, 0, 6, 2}, context.temp_allocator)
	buffer.set_string(&buf, 0, 0, "ab", {})
	buffer.set_string(&buf, 2, 0, "世", {fg = style.Named_Color.Red, add = {.Bold}})
	buffer.set_string(&buf, 1, 1, "x", {add = {.Bold}})

	expect_screen(t, &buf, `
		ab世
		 x
	`)
	expect_style(t, &buf, {add = {.Bold}}, `
		  **
		 *
	`)
	expect_style(t, &buf, {fg = style.Named_Color.Red}, "  ##") // both halves of the wide char
	expect_style(t, &buf, {sub = {.Bold}}, `
		##  ##
		# ####
	`)
}
