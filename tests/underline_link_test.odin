package tests

import "core:fmt"
import "core:hash"
import "core:testing"
import hnoss ".."
import "../buffer"
import "../pen"
import "../style"

@(private = "file")
pair :: proc(w: int) -> (prev, next: buffer.Buffer) {
	buffer.init(&prev, {0, 0, w, 1})
	buffer.init(&next, {0, 0, w, 1})
	return
}

@(private = "file")
unpair :: proc(prev, next: ^buffer.Buffer) {
	buffer.destroy(prev)
	buffer.destroy(next)
}

@(private = "file")
diff_with :: proc(prev, next: ^buffer.Buffer, features := buffer.ALL_OUTPUT_FEATURES, depth := style.Color_Depth.Truecolor) -> string {
	out := make([dynamic]u8, context.temp_allocator)
	buffer.diff(prev, next, &out, depth, features)
	return string(out[:])
}

@(private = "file")
open_link :: proc(url: string) -> string {
	return fmt.tprintf("\x1b]8;id=%08x;%s\x1b\\", hash.fnv32a(transmute([]u8)url), url)
}

CLOSE_LINK :: "\x1b]8;;\x1b\\"

@(test)
diff_underline_shapes :: proc(t: ^testing.T) {
	prev, next := pair(5)
	defer unpair(&prev, &next)
	buffer.set_string(&next, 0, 0, "a", {add = {.Underlined}})
	buffer.set_string(&next, 1, 0, "b", style.underline(.Curly))
	buffer.set_string(&next, 2, 0, "c", style.underline(.Double))
	buffer.set_string(&next, 3, 0, "d", style.underline(.Single))
	buffer.set_string(&next, 4, 0, "e")
	testing.expect_value(t, diff_with(&prev, &next),
		"\x1b[1;1H\x1b[4ma\x1b[4:3mb\x1b[4:2mc\x1b[4md\x1b[24me")
}

@(test)
diff_underline_shapes_fall_back_to_plain :: proc(t: ^testing.T) {
	prev, next := pair(3)
	defer unpair(&prev, &next)
	buffer.set_string(&next, 0, 0, "a", style.underline(.Curly, style.rgb(255, 0, 0)))
	buffer.set_string(&next, 1, 0, "b", style.underline(.Dashed))
	buffer.set_string(&next, 2, 0, "c", style.underline(.Dotted, .Red))
	// One plain underline throughout, and no SGR 58.
	testing.expect_value(t, diff_with(&prev, &next, {}), "\x1b[1;1H\x1b[4mabc\x1b[0m")
}

@(test)
diff_underline_color :: proc(t: ^testing.T) {
	prev, next := pair(5)
	defer unpair(&prev, &next)
	buffer.set_string(&next, 0, 0, "a", style.underline(.Curly, style.rgb(255, 0, 0)))
	buffer.set_string(&next, 1, 0, "b", style.underline(.Curly, style.Indexed(196)))
	buffer.set_string(&next, 2, 0, "c", style.underline(.Curly, .Bright_Blue))
	buffer.set_string(&next, 3, 0, "d", style.underline(.Curly))
	// A color with no underline to draw is left out.
	buffer.set_string(&next, 4, 0, "e", {underline_color = .Red})
	testing.expect_value(t, diff_with(&prev, &next),
		"\x1b[1;1H\x1b[4:3;58;2;255;0;0ma\x1b[58;5;196mb\x1b[58;5;12mc\x1b[59md\x1b[24me")
	// Downsampled like any other color; gone with NO_COLOR.
	testing.expect_value(t, diff_with(&prev, &next, depth = .No_Color), "\x1b[1;1H\x1b[4:3mabcd\x1b[24me")
}

@(test)
underline_style_patching :: proc(t: ^testing.T) {
	// `underline` implies .Underlined ...
	s := style.patch({sub = {.Underlined}}, style.underline(.Curly))
	testing.expect(t, .Underlined in s.add)
	testing.expect(t, .Underlined not_in s.sub)
	testing.expect_value(t, s.underline, style.Underline.Curly)
	// ... unless the same patch turns it off.
	s = style.patch({}, {underline = style.Underline.Curly, sub = {.Underlined}})
	testing.expect(t, .Underlined not_in s.add)

	b: buffer.Buffer
	buffer.init(&b, {0, 0, 2, 1})
	defer buffer.destroy(&b)
	buffer.set_string(&b, 0, 0, "ab", style.underline(.Dotted, .Red))
	c := buffer.get(&b, 1, 0)
	testing.expect(t, .Underlined in c.modifiers)
	testing.expect_value(t, c.underline, style.Underline.Dotted)
	testing.expect_value(t, c.underline_color, style.Color(style.Named_Color.Red))
	// A plain `u` keeps the shape that is there.
	buffer.set_style(&b, b.area, {add = {.Underlined}})
	testing.expect_value(t, c.underline, style.Underline.Dotted)
}

@(test)
diff_hyperlinks_open_and_close :: proc(t: ^testing.T) {
	prev, next := pair(8)
	defer unpair(&prev, &next)
	buffer.set_string(&next, 0, 0, "ab", style.link("https://a.example"))
	buffer.set_string(&next, 2, 0, "c")
	buffer.set_string(&next, 3, 0, "d", style.link("https://b.example"))
	buffer.set_string(&next, 5, 0, "e", style.link("https://a.example"))
	testing.expect_value(t, diff_with(&prev, &next), fmt.tprintf(
		"\x1b[1;1H%sab%sc%sd\x1b[1;6H%se%s",
		open_link("https://a.example"), CLOSE_LINK, open_link("https://b.example"),
		open_link("https://a.example"), CLOSE_LINK,
	))
	// Both runs of a.example share an id, and URLs are interned.
	testing.expect_value(t, buffer.get(&next, 0, 0).link, buffer.get(&next, 5, 0).link)
	testing.expect_value(t, len(next.links), 2)
	testing.expect_value(t, diff_with(&prev, &next, {}), "\x1b[1;1Habcd\x1b[1;6He")
}

@(test)
diff_hyperlinks_compare_by_url :: proc(t: ^testing.T) {
	prev, next := pair(4)
	defer unpair(&prev, &next)
	// Same URLs, different ids: nothing to redraw.
	buffer.set_string(&prev, 0, 0, "x", style.link("https://x"))
	buffer.set_string(&prev, 1, 0, "y", style.link("https://y"))
	buffer.set_string(&next, 1, 0, "y", style.link("https://y"))
	buffer.set_string(&next, 0, 0, "x", style.link("https://x"))
	testing.expect(t, buffer.get(&prev, 0, 0).link != buffer.get(&next, 0, 0).link)
	testing.expect_value(t, diff_with(&prev, &next), "")
	// Same id, different URL: redrawn.
	buffer.set_string(&prev, 2, 0, "z", style.link("https://old"))
	buffer.set_string(&next, 2, 0, "z", style.link("https://new"))
	testing.expect_value(t, buffer.get(&prev, 2, 0).link, buffer.get(&next, 2, 0).link)
	testing.expect_value(t, diff_with(&prev, &next), fmt.tprintf("\x1b[1;3H%sz%s", open_link("https://new"), CLOSE_LINK))
}

@(test)
links_follow_what_is_written :: proc(t: ^testing.T) {
	b: buffer.Buffer
	buffer.init(&b, {0, 0, 6, 1})
	defer buffer.destroy(&b)
	buffer.set_string(&b, 0, 0, "abcdef", style.link("https://a"))
	buffer.set_string(&b, 0, 0, "x") // new text, no link
	testing.expect_value(t, buffer.get(&b, 0, 0).link, 0)
	testing.expect_value(t, buffer.link_url(&b, buffer.get(&b, 1, 0).link), "https://a")
	buffer.fill(&b, {2, 0, 1, 1}, {}) // blanked
	testing.expect_value(t, buffer.get(&b, 2, 0).link, 0)
	buffer.set_style(&b, {3, 0, 1, 1}, {fg = .Red}) // restyled, still linked
	testing.expect_value(t, buffer.link_url(&b, buffer.get(&b, 3, 0).link), "https://a")
	buffer.set_style(&b, {4, 0, 2, 1}, style.link("https://b"))
	testing.expect_value(t, buffer.link_url(&b, buffer.get(&b, 5, 0).link), "https://b")
	// Wide characters link both halves.
	buffer.set_string(&b, 0, 0, "世", style.link("https://w"))
	testing.expect_value(t, buffer.get(&b, 0, 0).link, buffer.get(&b, 1, 0).link)
	// Control characters can't go into OSC 8.
	testing.expect_value(t, buffer.link_id(&b, "https://a\x1b]0;pwned\x07"), 0)
	testing.expect_value(t, buffer.link_id(&b, "https://ä"), 0)
	buffer.reset(&b)
	testing.expect_value(t, len(b.links), 0)
	testing.expect_value(t, buffer.link_url(&b, 1), "")
}

@(test)
markup_underlines_and_links :: proc(t: ^testing.T) {
	b: buffer.Buffer
	buffer.init(&b, {0, 0, 20, 1})
	defer buffer.destroy(&b)
	p := pen.begin(&b, b.area)
	pen.markup(&p, "[undercurl ul=#ff0000]typo[/] [link=https://odin-lang.org/docs]Odin[/] [underdashed]x[/][link=]")
	pen.finish(&p)
	c := buffer.get(&b, 0, 0)
	testing.expect(t, .Underlined in c.modifiers)
	testing.expect_value(t, c.underline, style.Underline.Curly)
	testing.expect_value(t, c.underline_color, style.rgb(255, 0, 0))
	testing.expect(t, .Underlined not_in buffer.get(&b, 4, 0).modifiers)
	testing.expect_value(t, buffer.link_url(&b, buffer.get(&b, 5, 0).link), "https://odin-lang.org/docs")
	testing.expect_value(t, buffer.link_url(&b, buffer.get(&b, 8, 0).link), "https://odin-lang.org/docs")
	testing.expect_value(t, buffer.get(&b, 9, 0).link, 0)
	testing.expect_value(t, buffer.get(&b, 10, 0).underline, style.Underline.Dashed)
	// `[link=]` is not a tag, so it is written as text.
	testing.expect_value(t, buffer.cell_symbol(buffer.get(&b, 11, 0)), "[")

	_, ok := pen.parse_tag("underdouble ul=nope")
	testing.expect(t, !ok)
	st, ok2 := pen.parse_tag("underdotted ul=@33 b")
	testing.expect(t, ok2)
	testing.expect_value(t, st.underline, style.Underline.Dotted)
	testing.expect_value(t, st.underline_color, style.Color(style.Indexed(33)))
}

@(test)
detect_output_features_from_env :: proc(t: ^testing.T) {
	f :: hnoss.output_features_for
	all :: hnoss.Output_Features{.Styled_Underlines, .Hyperlinks}
	testing.expect_value(t, f({term = "xterm-kitty"}), all)
	testing.expect_value(t, f({term = "foot-extra"}), all)
	testing.expect_value(t, f({term = "xterm-256color", term_program = "WezTerm"}), all)
	testing.expect_value(t, f({term = "xterm-256color", vte_version = "7600"}), all)
	testing.expect_value(t, f({term = "xterm-256color", vte_version = "5000"}), hnoss.Output_Features{.Hyperlinks})
	testing.expect_value(t, f({term = "xterm-256color"}), hnoss.Output_Features{.Hyperlinks})
	testing.expect_value(t, f({term = "tmux-256color"}), hnoss.Output_Features{.Hyperlinks})
	testing.expect_value(t, f({term = "linux"}), hnoss.Output_Features{})
	testing.expect_value(t, f({term = "dumb"}), hnoss.Output_Features{})
}
