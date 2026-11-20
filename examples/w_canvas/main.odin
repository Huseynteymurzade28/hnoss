// Widget example: braille canvas. Lines, rectangles, circles and polygons
// on 2×4 dots per cell, each cell in its own color.
//   f        toggle fill
//   q / Esc  quit
package main

import "core:fmt"
import "core:math"
import "core:os"
import hnoss "../.."
import "../../backend"
import "../../style"

SUN    :: style.Rgb{0xf9, 0xc7, 0x4f}
STAR   :: style.Rgb{0x4c, 0xc9, 0xf0}
HOUSE  :: style.Rgb{0xf3, 0x72, 0x2c}
GROUND :: style.Rgb{0x7f, 0xd8, 0x8f}

main :: proc() {
	context.assertion_failure_proc = backend.assertion_failure_proc

	term, err := hnoss.init(hnoss.DEFAULT_OPTIONS)
	if err != .None {
		fmt.eprintfln("hnoss: init failed: %v", err)
		os.exit(1)
	}
	defer hnoss.deinit(&term)

	fill := true
	events: []hnoss.Event
	loop: for {
		was_fill := fill
		f := hnoss.begin_frame(&term)
		ui := hnoss.ui(f, events)
		area := hnoss.inset(f.area, 1)
		footer := hnoss.cut_bottom(&area, 1)
		hnoss.key_hints(ui, footer, {{"f", "fill"}, {"q", "quit"}})

		inner := hnoss.box(ui, area, "Canvas")
		c := hnoss.canvas(inner)
		W, H := c.width, c.height
		ground := H * 3 / 4

		// The sun and its rays.
		sx, sy, sr := W / 5, H / 4, max(min(W, H) / 8, 2)
		hnoss.canvas_circle(&c, sx, sy, sr, SUN, fill)
		for i in 0 ..< 12 {
			a := f64(i) / 12 * math.TAU
			hnoss.canvas_line(&c,
				sx + int(f64(sr + 3) * math.cos(a)), sy + int(f64(sr + 3) * math.sin(a)),
				sx + int(f64(sr + 8) * math.cos(a)), sy + int(f64(sr + 8) * math.sin(a)), SUN)
		}

		// A five-pointed star drawn in one stroke: it crosses itself, so a
		// fill by the even-odd rule leaves a hole in the middle.
		star: [5][2]int
		tx, ty, tr := W * 3 / 4, H * 2 / 5, max(H / 3, 4)
		for &p, i in star {
			a := -math.PI / 2 + f64(i * 2) / 5 * math.TAU
			p = {tx + int(f64(tr) * math.cos(a)), ty + int(f64(tr) * math.sin(a))}
		}
		hnoss.canvas_polygon(&c, star[:], STAR, fill)

		// A house on the ground line.
		hw, hh := W / 6, H / 6
		hx := W / 2 - hw / 2
		hnoss.canvas_rect(&c, hx, ground - hh, hw, hh, HOUSE, fill)
		hnoss.canvas_polygon(&c, {{hx - 2, ground - hh}, {hx + hw / 2, ground - hh - hh / 2 - 2}, {hx + hw + 1, ground - hh}}, HOUSE, fill)
		hnoss.canvas_line(&c, 0, ground, W - 1, ground, GROUND)
		hnoss.canvas_draw(ui, &c)

		for ev in hnoss.unhandled(ui) {
			switch {
			case hnoss.is_char(ev, 'f'):
				fill = !fill
			case hnoss.is_char(ev, 'q') || hnoss.is_key(ev, .Esc) || hnoss.is_char(ev, 'c', {.Ctrl}):
				break loop
			}
		}
		hnoss.end_frame(&term)
		free_all(context.temp_allocator)
		events = hnoss.poll_events(&term, 0 if fill != was_fill else -1)
		if term.error != .None {
			break
		}
	}
}
