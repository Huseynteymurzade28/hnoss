package tests

import "core:encoding/base64"
import "core:strings"
import "core:testing"
import "../buffer"
import "../graphics"
import "../style"
import "../widgets"

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

// A w × h image of one color.
@(private = "file")
plain :: proc(w, h: int, channels := 3) -> widgets.Image {
	px := make([]u8, w * h * channels, context.temp_allocator)
	for &p in px { p = 200 }
	return {pixels = px, width = w, height = h, channels = channels}
}

@(private = "file")
Shown :: struct {
	img:   widgets.Image,
	area:  widgets.Rect,
	drawn: widgets.Rect,
	modal: bool,
}

@(private = "file")
draw_image :: proc(ui: ^widgets.Ui, s: ^Shown) {
	s.drawn = widgets.image(ui, s.area, &s.img)
	if s.modal { widgets.modal(ui, {1, 0, 4, 2}, &s.modal) }
}

@(private = "file")
kitty_driver :: proc(w, h: int) -> ^Driver {
	d := driver(w, h)
	d.mem.images.kitty = true
	d.mem.images.sent.allocator = context.temp_allocator
	d.mem.images.out.allocator = context.temp_allocator
	return d
}

// What the frame writes before and after it is drawn.
@(private = "file")
end_images :: proc(d: ^Driver, cache := widgets.IMAGE_CACHE_BYTES) -> (before, after: string) {
	a := make([dynamic]u8, context.temp_allocator)
	b := make([dynamic]u8, context.temp_allocator)
	widgets.images_flush(&d.mem.images, &a)
	widgets.images_end_frame(&d.mem.images, &b, cache)
	return string(a[:]), string(b[:])
}

@(test)
widget_image_half_blocks :: proc(t: ^testing.T) {
	d := driver(6, 3)
	s := Shown{img = {pixels = {255, 0, 0, 255, 0, 0, 255, 255}, width = 1, height = 2, channels = 4}, area = {0, 0, 6, 3}}
	defer widgets.image_destroy(&s.img)
	drive(t, d, "", &s, draw_image)
	testing.expect_value(t, s.drawn, widgets.Rect{1, 0, 3, 3})
	expect_screen(t, &d.buf, `
		 ▀▀▀
		 ▀▀▀
		 ▀▀▀
	`)
	testing.expect_value(t, buffer.get(&d.buf, 1, 0).fg, style.Rgb{255, 0, 0})
	testing.expect_value(t, buffer.get(&d.buf, 1, 2).bg, style.Rgb{0, 0, 255})

	// Transparent: nothing there.
	s.img.pixels = {255, 0, 0, 0, 0, 0, 255, 255}
	widgets.image_changed(&s.img)
	s.area.height = 1
	drive(t, d, "", &s, draw_image)
	expect_screen(t, &d.buf, "  ▄")

	s.img.pixels = s.img.pixels[:7] // too few
	drive(t, d, "", &s, draw_image)
	expect_screen(t, &d.buf, "")
	testing.expect_value(t, s.drawn.width, 0)
}

@(test)
widget_image_is_sent_once :: proc(t: ^testing.T) {
	d := kitty_driver(6, 3)
	s := Shown{img = plain(2, 2), area = {0, 0, 6, 2}}
	drive(t, d, "", &s, draw_image)
	testing.expect_value(t, s.drawn, widgets.Rect{1, 0, 4, 2})
	testing.expect_value(t, buffer.get(&d.buf, 4, 1).image, buffer.Image_Part{s.img.id, 4, 2, 3, 1})
	before, after := end_images(d)
	testing.expect(t, strings.has_prefix(before, "\x1b_Ga=t,q=2,i=1,f=24,s=2,v=2,m=0;"))
	testing.expect(t, strings.has_suffix(before, "\x1b_Ga=p,U=1,q=2,i=1,p=16386,c=4,r=2\x1b\\"))
	testing.expect_value(t, after, "")

	drive(t, d, "", &s, draw_image)
	before, _ = end_images(d)
	testing.expect_value(t, before, "")

	s.area = {0, 0, 2, 1} // another size: only placed
	drive(t, d, "", &s, draw_image)
	before, _ = end_images(d)
	testing.expect_value(t, before, "\x1b_Ga=p,U=1,q=2,i=1,p=8193,c=2,r=1\x1b\\")

	widgets.image_changed(&s.img)
	drive(t, d, "", &s, draw_image)
	before, _ = end_images(d)
	testing.expect(t, strings.has_prefix(before, "\x1b_Ga=t,q=2,i=2,"))

	widgets.images_forget(&d.mem.images)
	drive(t, d, "", &s, draw_image)
	before, _ = end_images(d)
	testing.expect(t, strings.has_prefix(before, "\x1b_Ga=t,q=2,i=2,"))
}

@(test)
widget_image_under_a_modal :: proc(t: ^testing.T) {
	d := kitty_driver(6, 2)
	s := Shown{img = plain(2, 2), area = {0, 0, 6, 2}, modal = true}
	s.area.width = 4
	drive(t, d, "", &s, draw_image)
	testing.expect(t, buffer.get(&d.buf, 0, 0).image.id != 0)
	testing.expect_value(t, buffer.get(&d.buf, 1, 0).image.id, 0)
	testing.expect_value(t, buffer.cell_symbol(buffer.get(&d.buf, 1, 0)), "╭")
}

@(test)
widget_image_cache :: proc(t: ^testing.T) {
	d := kitty_driver(6, 2)
	imgs: [3]Shown
	for &s in imgs { s = {img = plain(10, 10), area = {0, 0, 4, 2}} } // 300 bytes each
	for &s in imgs {
		drive(t, d, "", &s, draw_image)
		_, after := end_images(d, 600)
		testing.expect_value(t, after, "")
	}
	drive(t, d, "", &imgs[1], draw_image)
	_, after := end_images(d, 300) // 1 and 3 are off screen, 1 the longest
	testing.expect_value(t, after, "\x1b_Ga=d,d=I,q=2,i=1\x1b\\")
	drive(t, d, "", &imgs[0], draw_image) // back: sent again
	before, _ := end_images(d)
	testing.expect(t, strings.has_prefix(before, "\x1b_Ga=t,q=2,i=1,"))

	// Many sizes: the placements not used lately go.
	s := &imgs[0]
	for w in 1 ..= 12 {
		s.area = {0, 0, w, 100}
		drive(t, d, "", s, draw_image)
		before, _ = end_images(d)
	}
	testing.expect_value(t, strings.count(before, "a=d,d=i,"), 1)
	out := make([dynamic]u8, context.temp_allocator)
	widgets.images_delete(&d.mem.images, &out)
	testing.expect_value(t, strings.count(string(out[:]), "d=I"), 3)
}
