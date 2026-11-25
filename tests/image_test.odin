package tests

import "core:encoding/base64"
import "core:strings"
import "core:testing"
import "../buffer"
import "../graphics"
import "../style"

@(private = "file")
diff_bytes :: proc(prev, next: ^buffer.Buffer, depth := style.Color_Depth.Truecolor) -> string {
	out := make([dynamic]u8, context.temp_allocator)
	buffer.diff(prev, next, &out, depth)
	return string(out[:])
}

@(private = "file")
two_buffers :: proc(w, h: int) -> (a, b: buffer.Buffer) {
	buffer.init(&a, {0, 0, w, h}, context.temp_allocator)
	buffer.init(&b, {0, 0, w, h}, context.temp_allocator)
	return
}

@(test)
image_cells_are_placeholders :: proc(t: ^testing.T) {
	prev, next := two_buffers(4, 2)
	buffer.set_image(&next, {1, 0, 2, 2}, 0x010203)
	// fg = the image, underline color = the placement (2 << 12 | 2).
	want := "\x1b[1;2H\x1b[38;2;1;2;3;58;2;0;32;2m" +
		"\U0010eeee̅̅\U0010eeee̅̍" +
		"\x1b[2;2H\U0010eeee̍̅\U0010eeee̍̍\x1b[0m"
	for depth in style.Color_Depth { // ids survive any depth
		got := diff_bytes(&prev, &next, depth)
		testing.expectf(t, got == want, "%v: %q", depth, got)
	}
	testing.expect_value(t, diff_bytes(&next, &next), "")
}

@(test)
image_cells_are_covered_clipped_and_styled :: proc(t: ^testing.T) {
	prev, next := two_buffers(4, 2)
	buffer.set_image(&prev, {0, 0, 4, 2}, 7)
	buffer.set_image(&next, {0, 0, 4, 2}, 7)
	buffer.set_string(&next, 1, 0, "x")
	testing.expect_value(t, diff_bytes(&prev, &next), "\x1b[1;2Hx") // only what is over it
	buffer.fill(&next, {0, 0, 4, 2}, {})
	for &c in next.cells { testing.expect_value(t, c.image.id, 0) }

	// A style over an image changes neither which image it is nor its part.
	buffer.reset(&next)
	buffer.set_clip(&next, {2, 0, 2, 1})
	buffer.set_image(&next, {0, -1, 4, 2}, 7)
	buffer.set_style(&next, next.area, {fg = .Red, add = {.Bold, .Underlined}})
	testing.expect_value(t, buffer.get(&next, 1, 0).image.id, 0)
	testing.expect_value(t, buffer.get(&next, 2, 0).image, buffer.Image_Part{7, 4, 2, 2, 1})
	empty, _ := two_buffers(4, 2)
	testing.expect(t, strings.contains(diff_bytes(&empty, &next), "\x1b[38;2;0;0;7;58;2;0;64;2m"))

	buffer.reset(&next)
	buffer.set_image(&next, {0, 0, 298, 1}, 7) // too wide
	buffer.set_image(&next, {0, 0, 4, 1}, 0x1000000)
	testing.expect_value(t, buffer.get(&next, 0, 0).image.id, 0)
}

@(test)
image_kitty_commands :: proc(t: ^testing.T) {
	out := make([dynamic]u8, context.temp_allocator)
	graphics.append_transmit(&out, 9, {1, 2, 3, 4}, 1, 1, 4)
	testing.expect_value(t, string(out[:]), "\x1b_Ga=t,q=2,i=9,f=32,s=1,v=1,m=0;AQIDBA==\x1b\\")
	clear(&out)
	graphics.append_place(&out, 9, 5, 4, 2)
	graphics.append_unplace(&out, 9, 5)
	graphics.append_delete(&out, 9)
	testing.expect_value(t, string(out[:]), "\x1b_Ga=p,U=1,q=2,i=9,p=5,c=4,r=2\x1b\\\x1b_Ga=d,d=i,q=2,i=9,p=5\x1b\\\x1b_Ga=d,d=I,q=2,i=9\x1b\\")

	// Several chunks, which put together are the pixels.
	for size in ([]int{3069, 3072, 3075, 10000}) {
		pixels := make([]u8, size, context.temp_allocator)
		for &p, i in pixels { p = u8(i * 7) }
		clear(&out)
		graphics.append_transmit(&out, 9, pixels, size, 1, 3)
		sb := strings.builder_make(context.temp_allocator)
		rest := string(out[:])
		chunks := strings.split(strings.trim_suffix(rest, "\x1b\\"), "\x1b\\", context.temp_allocator)
		for c, i in chunks {
			head, _, data := strings.partition(c, ";")
			testing.expect(t, len(data) <= 4096 && len(data) > 0)
			testing.expect_value(t, strings.has_suffix(head, "m=0"), i == len(chunks) - 1)
			strings.write_string(&sb, data)
		}
		decoded, _ := base64.decode(strings.to_string(sb), allocator = context.temp_allocator)
		testing.expectf(t, string(decoded) == string(pixels), "%d bytes", size)
	}
}

@(test)
image_terminals_with_placeholders :: proc(t: ^testing.T) {
	for v in ([]string{"kitty(0.28.0)", "kitty(0.49.2)", "kitty(1.0.0)", "ghostty 1.2.0"}) {
		testing.expectf(t, graphics.supports_placeholders(v), "%s", v)
	}
	for v in ([]string{"", "kitty(0.27.1)", "kitty(", "Konsole 25.08", "WezTerm 2024", "tmux 3.5", "foot(1.20)"}) {
		testing.expectf(t, !graphics.supports_placeholders(v), "%s", v)
	}
}

@(test)
image_fit_keeps_proportions :: proc(t: ^testing.T) {
	check :: proc(t: ^testing.T, w, h, max_cols, max_rows, cw, ch, cols, rows: int, loc := #caller_location) {
		c, r := graphics.fit_cells(w, h, max_cols, max_rows, cw, ch)
		testing.expectf(t, c == cols && r == rows, "%dx%d cells, want %dx%d", c, r, cols, rows, loc = loc)
	}
	check(t, 600, 900, 20, 40, 0, 0, 20, 15)     // a 2:3 poster, as wide as there is room
	check(t, 600, 900, 80, 15, 0, 0, 20, 15)     // as tall
	check(t, 600, 900, 20, 40, 10, 20, 20, 15)
	check(t, 100, 100, 20, 40, 9, 18, 20, 10)
	check(t, 100, 100, 20, 40, 10, 25, 20, 8)
	check(t, 10000, 1, 20, 40, 0, 0, 20, 1)      // never nothing
	check(t, 1, 10000, 20, 40, 0, 0, 1, 40)
	check(t, 0, 10, 20, 40, 0, 0, 0, 0)
	check(t, 10, 10, 0, 40, 0, 0, 0, 0)
}

@(test)
image_scale_averages :: proc(t: ^testing.T) {
	out: [4][4]u8
	// 4×1 down to 2×1
	graphics.scale(out[:2], 2, 1, {0, 0, 0, 100, 100, 100, 10, 20, 30, 30, 40, 50}, 4, 1, 3)
	testing.expect_value(t, out[0], [4]u8{50, 50, 50, 255})
	testing.expect_value(t, out[1], [4]u8{20, 30, 40, 255})
	// 1×1 up to 2×2
	graphics.scale(out[:], 2, 2, {1, 2, 3}, 1, 1, 3)
	for p in out { testing.expect_value(t, p, [4]u8{1, 2, 3, 255}) }
	// A transparent pixel's color doesn't count.
	graphics.scale(out[:1], 1, 1, {200, 0, 0, 255, 0, 250, 0, 0}, 2, 1, 4)
	testing.expect_value(t, out[0], [4]u8{200, 0, 0, 128})
	graphics.scale(out[:1], 1, 1, {9, 9, 9, 0}, 1, 1, 4)
	testing.expect_value(t, out[0], [4]u8{})
}
