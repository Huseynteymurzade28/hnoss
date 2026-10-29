package tests

import "core:strings"
import "core:testing"
import "../buffer"
import "../pen"
import "../style"

// Renders through `draw` into a w x h buffer; returns the rows with
// trailing spaces trimmed, plus the line count from finish.
@(private = "file")
render :: proc(w, h: int, draw: proc(p: ^pen.Pen), wrap := pen.Wrap.Word, align := pen.Align.Left, scroll := 0) -> (rows: []string, lines: int, b: buffer.Buffer) {
	buffer.init(&b, {0, 0, w, h}, context.temp_allocator)
	p := pen.begin(&b, b.area, wrap, align, scroll = scroll)
	draw(&p)
	lines = pen.finish(&p)
	out := make([]string, h, context.temp_allocator)
	for y in 0 ..< h {
		sb := strings.builder_make(context.temp_allocator)
		for x := 0; x < w; {
			c := buffer.get(&b, x, y)
			strings.write_string(&sb, buffer.cell_symbol(c))
			x += max(int(c.width), 1)
		}
		out[y] = strings.trim_right(strings.to_string(sb), " ")
	}
	return out, lines, b
}

@(private = "file")
expect_rows :: proc(t: ^testing.T, got: []string, want: ..string, loc := #caller_location) {
	for i in 0 ..< max(len(got), len(want)) {
		g := got[i] if i < len(got) else "<none>"
		w := want[i] if i < len(want) else ""
		testing.expectf(t, g == w, "row %d = %q, want %q", i, g, w, loc = loc)
	}
}

@(test)
pen_word_wrap :: proc(t: ^testing.T) {
	rows, lines, _ := render(10, 3, proc(p: ^pen.Pen) { pen.write(p, "the quick brown fox") })
	expect_rows(t, rows, "the quick", "brown fox", "")
	testing.expect_value(t, lines, 2)
}

@(test)
pen_word_wrap_splits_across_writes_and_styles :: proc(t: ^testing.T) {
	rows, _, b := render(8, 2, proc(p: ^pen.Pen) {
		pen.write(p, "CPU ", {add = {.Bold}})
		pen.write(p, "load", {fg = .Red})
		pen.write(p, "ing ok")
	})
	expect_rows(t, rows, "CPU", "loading") // "ok" goes to a third, off-screen line
	// "loading" was written in two pieces with two styles and moved as one word.
	testing.expect_value(t, buffer.get(&b, 0, 0).modifiers, style.Modifiers{.Bold})
	testing.expect_value(t, buffer.get(&b, 0, 1).fg, style.Color(style.Named_Color.Red))
	testing.expect_value(t, buffer.get(&b, 4, 1).fg, nil)
}

@(test)
pen_long_word_breaks_anywhere :: proc(t: ^testing.T) {
	rows, lines, _ := render(5, 3, proc(p: ^pen.Pen) { pen.write(p, "abcdefghijkl") })
	expect_rows(t, rows, "abcde", "fghij", "kl")
	testing.expect_value(t, lines, 3)
}

@(test)
pen_char_wrap :: proc(t: ^testing.T) {
	rows, _, _ := render(4, 3, proc(p: ^pen.Pen) { pen.write(p, "hello world") }, wrap = .Char)
	expect_rows(t, rows, "hell", "o wo", "rld")
}

@(test)
pen_clip_and_ellipsis :: proc(t: ^testing.T) {
	rows, lines, _ := render(5, 2, proc(p: ^pen.Pen) { pen.write(p, "hello world\nok") }, wrap = .Clip)
	expect_rows(t, rows, "hello", "ok")
	testing.expect_value(t, lines, 2)
	rows, _, _ = render(5, 2, proc(p: ^pen.Pen) { pen.write(p, "hello world\nok") }, wrap = .Ellipsis)
	expect_rows(t, rows, "hell…", "ok")
	rows, _, _ = render(5, 1, proc(p: ^pen.Pen) { pen.write(p, "hello") }, wrap = .Ellipsis)
	expect_rows(t, rows, "hello") // fits exactly: no ellipsis
}

@(test)
pen_alignment :: proc(t: ^testing.T) {
	rows, _, _ := render(9, 2, proc(p: ^pen.Pen) { pen.write(p, "abc\nxy") }, align = .Center)
	expect_rows(t, rows, "   abc", "   xy")
	rows, _, _ = render(9, 1, proc(p: ^pen.Pen) { pen.write(p, "abc") }, align = .Right)
	expect_rows(t, rows, "      abc")
	// Wrapped lines are aligned without their trailing space.
	rows, _, _ = render(6, 2, proc(p: ^pen.Pen) { pen.write(p, "ab cdef") }, align = .Right)
	expect_rows(t, rows, "    ab", "  cdef")
}

@(test)
pen_newlines_scroll_and_count :: proc(t: ^testing.T) {
	rows, lines, _ := render(5, 2, proc(p: ^pen.Pen) { pen.write(p, "one\n\nthree\nfour") }, scroll = 2)
	expect_rows(t, rows, "three", "four")
	testing.expect_value(t, lines, 4)
}

@(test)
pen_wide_chars_and_tabs :: proc(t: ^testing.T) {
	rows, _, _ := render(5, 2, proc(p: ^pen.Pen) { pen.write(p, "世界世界") })
	expect_rows(t, rows, "世界", "世界")
	rows, _, _ = render(10, 1, proc(p: ^pen.Pen) { pen.write(p, "a\tb") })
	expect_rows(t, rows, "a   b")
}

@(test)
pen_measure :: proc(t: ^testing.T) {
	lines, widest := pen.measure("the quick brown fox", 10)
	testing.expect_value(t, lines, 2)
	testing.expect_value(t, widest, 9)
	lines, _ = pen.measure("", 10)
	testing.expect_value(t, lines, 0)
	lines, _ = pen.measure("a\n", 10)
	testing.expect_value(t, lines, 1)
}

@(test)
markup_styles :: proc(t: ^testing.T) {
	rows, _, b := render(20, 1, proc(p: ^pen.Pen) {
		pen.markup(p, "[b]CPU[/] [red on #102030]92[/]% [i u]x[/]")
	})
	expect_rows(t, rows, "CPU 92% x")
	testing.expect_value(t, buffer.get(&b, 0, 0).modifiers, style.Modifiers{.Bold})
	testing.expect_value(t, buffer.get(&b, 3, 0).modifiers, style.Modifiers{})
	testing.expect_value(t, buffer.get(&b, 4, 0).fg, style.Color(style.Named_Color.Red))
	testing.expect_value(t, buffer.get(&b, 4, 0).bg, style.Color(style.rgb(0x10, 0x20, 0x30)))
	testing.expect_value(t, buffer.get(&b, 6, 0).fg, nil)
	testing.expect_value(t, buffer.get(&b, 8, 0).modifiers, style.Modifiers{.Italic, .Underlined})
}

@(test)
markup_nesting_and_colors :: proc(t: ^testing.T) {
	_, _, b := render(10, 1, proc(p: ^pen.Pen) { pen.markup(p, "[b][bright_cyan]a[/]b[/]c[@200]d") })
	testing.expect_value(t, buffer.get(&b, 0, 0).fg, style.Color(style.Named_Color.Bright_Cyan))
	testing.expect_value(t, buffer.get(&b, 0, 0).modifiers, style.Modifiers{.Bold})
	testing.expect_value(t, buffer.get(&b, 1, 0).fg, nil)
	testing.expect_value(t, buffer.get(&b, 1, 0).modifiers, style.Modifiers{.Bold})
	testing.expect_value(t, buffer.get(&b, 2, 0).modifiers, style.Modifiers{})
	testing.expect_value(t, buffer.get(&b, 3, 0).fg, style.Color(style.Indexed(200)))
}

@(test)
markup_literals :: proc(t: ^testing.T) {
	rows, _, _ := render(40, 1, proc(p: ^pen.Pen) { pen.markup(p, "[[b] page [1/3] [x] [nope red] a]b [") })
	expect_rows(t, rows, "[b] page [1/3] [x] [nope red] a]b [")
}
