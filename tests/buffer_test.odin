package tests

import "core:testing"
import "../buffer"
import "../style"

@(private = "file")
make_pair :: proc(w, h: int) -> (prev, next: buffer.Buffer) {
	buffer.init(&prev, {0, 0, w, h})
	buffer.init(&next, {0, 0, w, h})
	return
}

@(private = "file")
destroy_pair :: proc(prev, next: ^buffer.Buffer) {
	buffer.destroy(prev)
	buffer.destroy(next)
}

@(private = "file")
diff_string :: proc(prev, next: ^buffer.Buffer) -> string {
	out := make([dynamic]u8, context.temp_allocator)
	buffer.diff(prev, next, &out)
	return string(out[:])
}

@(test)
diff_identical_is_empty :: proc(t: ^testing.T) {
	prev, next := make_pair(10, 3)
	defer destroy_pair(&prev, &next)
	buffer.set_string(&prev, 0, 0, "same")
	buffer.set_string(&next, 0, 0, "same")
	testing.expect_value(t, diff_string(&prev, &next), "")
}

@(test)
diff_single_cell_moves_cursor_once :: proc(t: ^testing.T) {
	prev, next := make_pair(10, 3)
	defer destroy_pair(&prev, &next)
	buffer.set_string(&next, 3, 1, "x")
	testing.expect_value(t, diff_string(&prev, &next), "\x1b[2;4Hx")
}

@(test)
diff_contiguous_run_has_no_extra_moves :: proc(t: ^testing.T) {
	prev, next := make_pair(10, 3)
	defer destroy_pair(&prev, &next)
	buffer.set_string(&next, 0, 0, "abc")
	buffer.set_string(&next, 7, 0, "z")
	buffer.set_string(&next, 0, 2, "q")
	testing.expect_value(t, diff_string(&prev, &next), "\x1b[1;1Habc\x1b[1;8Hz\x1b[3;1Hq")
}

@(test)
diff_style_emitted_once_and_reset_at_end :: proc(t: ^testing.T) {
	prev, next := make_pair(10, 1)
	defer destroy_pair(&prev, &next)
	buffer.set_string(&next, 0, 0, "ab", {fg = style.Named_Color.Red, add = {.Bold}})
	testing.expect_value(t, diff_string(&prev, &next), "\x1b[1;1H\x1b[1;31mab\x1b[0m")
}

@(test)
diff_bold_to_dim_uses_22 :: proc(t: ^testing.T) {
	prev, next := make_pair(10, 1)
	defer destroy_pair(&prev, &next)
	buffer.set_string(&next, 0, 0, "a", {add = {.Bold}})
	buffer.set_string(&next, 1, 0, "b", {add = {.Dim}})
	buffer.set_string(&next, 2, 0, "c", {add = {.Dim, .Italic}})
	buffer.set_string(&next, 3, 0, "d")
	testing.expect_value(t, diff_string(&prev, &next), "\x1b[1;1H\x1b[1ma\x1b[22;2mb\x1b[3mc\x1b[22;23md")
}

@(test)
diff_color_encodings :: proc(t: ^testing.T) {
	prev, next := make_pair(10, 1)
	defer destroy_pair(&prev, &next)
	buffer.set_string(&next, 0, 0, "a", {fg = style.Named_Color.Bright_Red})
	buffer.set_string(&next, 1, 0, "b", {fg = style.Indexed(200)})
	buffer.set_string(&next, 2, 0, "c", {bg = style.rgb(1, 2, 3)})
	testing.expect_value(t, diff_string(&prev, &next),
		"\x1b[1;1H\x1b[91ma\x1b[38;5;200mb\x1b[39;48;2;1;2;3mc\x1b[0m")
}

@(test)
diff_reset_color_equals_default :: proc(t: ^testing.T) {
	prev, next := make_pair(4, 1)
	defer destroy_pair(&prev, &next)
	buffer.set_string(&next, 0, 0, "a", {fg = style.Named_Color.Reset})
	// The symbol changed but no SGR is needed: .Reset is the default.
	testing.expect_value(t, diff_string(&prev, &next), "\x1b[1;1Ha")
}

@(test)
diff_wide_char_skips_covered_cell :: proc(t: ^testing.T) {
	prev, next := make_pair(6, 1)
	defer destroy_pair(&prev, &next)
	end := buffer.set_string(&next, 0, 0, "世x")
	testing.expect_value(t, end, 3)
	testing.expect_value(t, diff_string(&prev, &next), "\x1b[1;1H世x")
}

@(test)
diff_wide_to_narrow_redraws_covered_cell :: proc(t: ^testing.T) {
	prev, next := make_pair(6, 1)
	defer destroy_pair(&prev, &next)
	buffer.set_string(&prev, 0, 0, "世")
	buffer.set_string(&next, 0, 0, "a")
	// Cell 1 is blank in both, but the old wide char covered it.
	testing.expect_value(t, diff_string(&prev, &next), "\x1b[1;1Ha ")
}

@(test)
set_string_clips_to_buffer_and_max_width :: proc(t: ^testing.T) {
	b: buffer.Buffer
	buffer.init(&b, {0, 0, 5, 1})
	defer buffer.destroy(&b)

	testing.expect_value(t, buffer.set_string(&b, 3, 0, "hello"), 5)
	testing.expect_value(t, buffer.cell_symbol(buffer.get(&b, 4, 0)), "e")

	buffer.reset(&b)
	testing.expect_value(t, buffer.set_string(&b, 0, 0, "hello", max_width = 2), 2)
	testing.expect_value(t, buffer.cell_symbol(buffer.get(&b, 2, 0)), " ")

	// A wide char that would straddle the edge is not written.
	buffer.reset(&b)
	testing.expect_value(t, buffer.set_string(&b, 4, 0, "世"), 4)
	testing.expect_value(t, buffer.cell_symbol(buffer.get(&b, 4, 0)), " ")

	testing.expect(t, buffer.get(&b, 5, 0) == nil)
	testing.expect_value(t, buffer.set_string(&b, 0, 3, "off"), 0)
}

@(test)
set_string_joins_combining_marks :: proc(t: ^testing.T) {
	b: buffer.Buffer
	buffer.init(&b, {0, 0, 5, 1})
	defer buffer.destroy(&b)
	end := buffer.set_string(&b, 0, 0, "éx") // e + COMBINING ACUTE ACCENT
	testing.expect_value(t, end, 2)
	testing.expect_value(t, buffer.cell_symbol(buffer.get(&b, 0, 0)), "é")
	testing.expect_value(t, buffer.cell_symbol(buffer.get(&b, 1, 0)), "x")
}

@(test)
overwriting_half_a_wide_char_blanks_the_other_half :: proc(t: ^testing.T) {
	b: buffer.Buffer
	buffer.init(&b, {0, 0, 4, 1})
	defer buffer.destroy(&b)

	buffer.set_string(&b, 0, 0, "世")
	buffer.set_string(&b, 1, 0, "x") // right half
	testing.expect_value(t, buffer.cell_symbol(buffer.get(&b, 0, 0)), " ")
	testing.expect_value(t, buffer.get(&b, 0, 0).width, 1)

	buffer.reset(&b)
	buffer.set_string(&b, 0, 0, "世")
	buffer.set_string(&b, 0, 0, "y") // left half
	testing.expect_value(t, buffer.cell_symbol(buffer.get(&b, 1, 0)), " ")
}

@(test)
style_patch_add_and_sub :: proc(t: ^testing.T) {
	a := style.Style{fg = style.Named_Color.Red, add = {.Bold, .Italic}}
	b := style.Style{bg = style.Named_Color.Blue, add = {.Underlined}, sub = {.Bold}}
	r := style.patch(a, b)
	testing.expect_value(t, r.fg, style.Color(style.Named_Color.Red))
	testing.expect_value(t, r.bg, style.Color(style.Named_Color.Blue))
	testing.expect_value(t, r.add, style.Modifiers{.Italic, .Underlined})
	testing.expect_value(t, r.sub, style.Modifiers{.Bold})
}

@(test)
cell_holds_long_zwj_sequences :: proc(t: ^testing.T) {
	b: buffer.Buffer
	buffer.init(&b, {0, 0, 4, 1})
	defer buffer.destroy(&b)
	family := "👨‍👩‍👧‍👦" // 25 bytes
	kiss := "👩🏽‍❤️‍💋‍👨🏻" // 35 bytes
	buffer.set_string(&b, 0, 0, family)
	buffer.set_string(&b, 2, 0, kiss)
	testing.expect_value(t, buffer.cell_symbol(buffer.get(&b, 0, 0)), family)
	testing.expect_value(t, buffer.cell_symbol(buffer.get(&b, 2, 0)), kiss)
}

@(test)
fill_blanks_and_styles_area :: proc(t: ^testing.T) {
	b: buffer.Buffer
	buffer.init(&b, {0, 0, 6, 2})
	defer buffer.destroy(&b)
	buffer.set_string(&b, 0, 0, "abcdef")
	buffer.set_string(&b, 0, 1, "x世yz") // 世 at cells 1-2
	buffer.fill(&b, {2, 0, 3, 2}, {bg = .Blue})
	testing.expect_value(t, buffer.cell_symbol(buffer.get(&b, 1, 0)), "b")
	testing.expect_value(t, buffer.cell_symbol(buffer.get(&b, 2, 0)), " ")
	testing.expect_value(t, buffer.get(&b, 4, 0).bg, style.Color(style.Named_Color.Blue))
	testing.expect_value(t, buffer.get(&b, 5, 0).bg, nil)
	// 世's right half was inside the area: its left half must not survive.
	testing.expect_value(t, buffer.cell_symbol(buffer.get(&b, 1, 1)), " ")
	testing.expect_value(t, buffer.get(&b, 1, 1).width, 1)
}

@(test)
clip_limits_drawing :: proc(t: ^testing.T) {
	b: buffer.Buffer
	buffer.init(&b, {0, 0, 6, 3}, context.temp_allocator)
	old := buffer.set_clip(&b, {1, 1, 3, 5})
	testing.expect_value(t, old, buffer.Rect{0, 0, 6, 3})
	testing.expect_value(t, b.clip, buffer.Rect{1, 1, 3, 2}) // kept inside the area

	buffer.set_string(&b, 0, 0, "aaaaaa")
	buffer.set_string(&b, 0, 1, "bbbbbb")
	buffer.fill(&b, {0, 2, 6, 1}, {bg = .Red})
	buffer.set_string(&b, 0, 2, "世界!")
	rows := screen_rows(&b)
	testing.expect_value(t, rows[0], "")
	testing.expect_value(t, rows[1], " bbb")
	testing.expect_value(t, rows[2], "  界")
	testing.expect_value(t, buffer.get(&b, 0, 2).bg, nil)
	testing.expect_value(t, buffer.get(&b, 1, 2).bg, style.Color(style.Named_Color.Red))
	// A wide char whose right half would fall outside isn't drawn.
	testing.expect(t, buffer.set_symbol(&b, 3, 1, "界", 2, {}) == nil)

	buffer.reset(&b)
	testing.expect_value(t, b.clip, b.area)
}
