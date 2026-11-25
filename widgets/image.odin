package widgets

import "../buffer"
import "../graphics"
import "../style"

// Pixels to show with `image`: rows from the top, RGB or RGBA without
// padding. They stay yours and must be there whenever the image is drawn.
// After changing them call `image_changed`, when done with the image
// `image_destroy`.
Image :: struct {
	pixels:        []u8,
	width, height: int,
	channels:      int, // 3 or 4 (0: 3)

	id:    u32, // what the terminal knows it as; 0 until it was sent
	cells: [dynamic][4]u8, // scaled for half blocks, two pixels per cell
	cells_width, cells_height: int, // in pixels
}

// Draws an image as large as fits in `area` with its proportions kept,
// centered. Returns the cells it covers.
//
// In kitty and Ghostty it is the image itself: sent once, and from then on
// only placed. Elsewhere it is drawn with half blocks, two pixels per cell.
// Either way it is cells like any other: what is drawn later covers it, and
// scroll views clip it.
image :: proc(ui: ^Ui, area: Rect, img: ^Image) -> (drawn: Rect) {
	cols, rows := image_fit(ui, img, area.width, area.height)
	if cols == 0 {
		return {area.x, area.y, 0, 0}
	}
	drawn = {area.x + (area.width - cols) / 2, area.y + (area.height - rows) / 2, cols, rows}
	if ui.mem.images.kitty {
		buffer.set_image(ui.buf, drawn, show_image(&ui.mem.images, img, cols, rows))
	} else {
		draw_half_blocks(ui, drawn, img)
	}
	return drawn
}

// The cells an image covers when it has max_cols × max_rows of them; 0 × 0
// for one that is empty or has fewer pixels than its size says.
image_fit :: proc(ui: ^Ui, img: ^Image, max_cols, max_rows: int) -> (cols, rows: int) {
	if img.width <= 0 || img.height <= 0 || len(img.pixels) < img.width * img.height * image_channels(img) {
		return 0, 0
	}
	mem := &ui.mem.images
	return graphics.fit_cells(img.width, img.height, min(max_cols, buffer.MAX_IMAGE_CELLS), min(max_rows, buffer.MAX_IMAGE_CELLS), mem.cell_width, mem.cell_height)
}

// The pixels are not what they were: the image is sent and scaled again.
image_changed :: proc(img: ^Image) {
	img.id = 0
	img.cells_width, img.cells_height = 0, 0
}

// Frees what drawing the image allocated, not its pixels.
image_destroy :: proc(img: ^Image) {
	delete(img.cells)
	img^ = {}
}

// The images the terminal holds.
Images :: struct {
	kitty:       bool, // the terminal shows images itself
	cell_width, cell_height: int, // in pixels, 0 if unknown
	sent:        [dynamic]Sent_Image,
	out:         [dynamic]u8, // commands to write before the frame
	frame:       u64,
	next_id:     u32,
}

@(private)
Sent_Image :: struct {
	id:     u32,
	bytes:  int,
	frame:  u64, // last drawn in
	places: [MAX_PLACES]Image_Place,
}

// A size the image has a placement for.
@(private)
Image_Place :: struct {
	cols, rows: int,
	frame:      u64,
}

// Sizes one image can have at a time; more than are ever on screen at once.
@(private)
MAX_PLACES :: 8

// Images that are not on screen stay in the terminal, to be back at once,
// up to this many bytes of pixels.
IMAGE_CACHE_BYTES :: 64 << 20

// Makes sure the terminal has the image and a placement of this size, and
// returns its id.
@(private)
show_image :: proc(im: ^Images, img: ^Image, cols, rows: int) -> u32 {
	if img.id == 0 {
		im.next_id = im.next_id % 0xffffff + 1
		img.id = im.next_id
	}
	sent: ^Sent_Image
	for &s in im.sent {
		if s.id == img.id { sent = &s }
	}
	if sent == nil {
		channels := image_channels(img)
		size := img.width * img.height * channels
		graphics.append_transmit(&im.out, img.id, img.pixels[:size], img.width, img.height, channels)
		append(&im.sent, Sent_Image{id = img.id, bytes = size})
		sent = &im.sent[len(im.sent) - 1]
	}
	sent.frame = im.frame

	oldest := &sent.places[0]
	for &p in sent.places {
		if p.cols == cols && p.rows == rows {
			p.frame = im.frame
			return img.id
		}
		// A free one counts as older than all.
		if oldest.cols != 0 && (p.cols == 0 || p.frame < oldest.frame) { oldest = &p }
	}
	if oldest.cols != 0 {
		graphics.append_unplace(&im.out, img.id, buffer.image_placement(u16(oldest.cols), u16(oldest.rows)))
	}
	oldest^ = {cols, rows, im.frame}
	graphics.append_place(&im.out, img.id, buffer.image_placement(u16(cols), u16(rows)), cols, rows)
	return img.id
}

// Writes what the terminal needs before it is shown this frame.
images_flush :: proc(im: ^Images, out: ^[dynamic]u8) {
	append(out, ..im.out[:])
	clear(&im.out)
}

// Ends the frame, after it was drawn: deletes the images that have been off
// screen the longest while there are more than `cache` bytes of such.
images_end_frame :: proc(im: ^Images, out: ^[dynamic]u8, cache := IMAGE_CACHE_BYTES) {
	unused := 0
	for s in im.sent {
		if s.frame != im.frame { unused += s.bytes }
	}
	for unused > cache {
		oldest := -1
		for s, i in im.sent {
			if s.frame != im.frame && (oldest < 0 || s.frame < im.sent[oldest].frame) { oldest = i }
		}
		graphics.append_delete(out, im.sent[oldest].id)
		unused -= im.sent[oldest].bytes
		ordered_remove(&im.sent, oldest)
	}
	im.frame += 1
}

// The terminal has lost its images (it was used by another program): they
// are sent again when they are next drawn.
images_forget :: proc(im: ^Images) {
	clear(&im.sent)
	clear(&im.out)
}

// Deletes every image from the terminal.
images_delete :: proc(im: ^Images, out: ^[dynamic]u8) {
	for s in im.sent {
		graphics.append_delete(out, s.id)
	}
	images_forget(im)
}

images_destroy :: proc(im: ^Images) {
	delete(im.sent)
	delete(im.out)
	im^ = {}
}

@(private)
image_channels :: proc(img: ^Image) -> int {
	return 4 if img.channels == 4 else 3
}

// Upper half in the foreground color, lower half in the background.
// Transparent halves leave what is there.
@(private)
draw_half_blocks :: proc(ui: ^Ui, area: Rect, img: ^Image) {
	w, h := area.width, area.height * 2
	if img.cells_width != w || img.cells_height != h {
		resize(&img.cells, w * h)
		graphics.scale(img.cells[:], w, h, img.pixels, img.width, img.height, image_channels(img))
		img.cells_width, img.cells_height = w, h
	}
	rgb :: proc(p: [4]u8) -> style.Color { return style.Rgb{p.r, p.g, p.b} }
	for row in 0 ..< area.height {
		for col in 0 ..< w {
			top, bottom := img.cells[row * 2 * w + col], img.cells[(row * 2 + 1) * w + col]
			x, y := area.x + col, area.y + row
			switch {
			case top.a >= 128 && bottom.a >= 128:
				buffer.set_symbol(ui.buf, x, y, "▀", 1, {fg = rgb(top), bg = rgb(bottom)})
			case top.a >= 128:
				buffer.set_symbol(ui.buf, x, y, "▀", 1, {fg = rgb(top)})
			case bottom.a >= 128:
				buffer.set_symbol(ui.buf, x, y, "▄", 1, {fg = rgb(bottom)})
			}
		}
	}
}
