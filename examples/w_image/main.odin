// Widget example: image. The picture itself in kitty and Ghostty, half
// blocks elsewhere. Drawn in code, so there is no file to load.
//   b        half blocks / the terminal's own images
//   + -      size
//   m        modal over it
//   q / Esc  quit
package main

import "core:fmt"
import "core:math"
import "core:os"
import hnoss "../.."
import "../../backend"
import "../../style"

W :: 400
H :: 600

// A poster: the sun going down behind mountains.
paint :: proc(px: []u8) {
	for y in 0 ..< H {
		for x in 0 ..< W {
			fx, fy := f64(x) / W, f64(y) / H
			c := style.lerp_rgb({24, 16, 64}, {255, 120, 60}, clamp(fy * 1.5, 0, 1))
			dx, dy := (fx - 0.5) * W, (fy - 0.48) * H
			if dx * dx + dy * dy < 80 * 80 { c = {255, 225, 140} }
			for i in 0 ..< 3 {
				k := f64(i)
				ridge := 0.55 + 0.13 * k + 0.05 * math.sin(fx * (7 + 3 * k) + k * 2) + 0.02 * math.sin(fx * 31 + k)
				if fy > ridge { c = style.lerp_rgb({120, 50, 90}, {14, 10, 30}, k / 2) }
			}
			i := (y * W + x) * 3
			px[i], px[i + 1], px[i + 2] = c.r, c.g, c.b
		}
	}
}

main :: proc() {
	context.assertion_failure_proc = backend.assertion_failure_proc

	term, err := hnoss.init(hnoss.DEFAULT_OPTIONS)
	if err != .None {
		fmt.eprintfln("hnoss: init failed: %v", err)
		os.exit(1)
	}
	defer hnoss.deinit(&term)

	px := make([]u8, W * H * 3)
	defer delete(px)
	paint(px)
	img := hnoss.Image{pixels = px, width = W, height = H}
	defer hnoss.image_destroy(&img)

	shrink := 0
	open: bool
	events: []hnoss.Event
	loop: for {
		was_open := open
		f := hnoss.begin_frame(&term)
		ui := hnoss.ui(f, events)
		area := hnoss.inset(f.area, 1)
		hnoss.label(ui, hnoss.cut_bottom(&area, 1), "[dim]b half blocks · + - size · m modal · q quit[/]")
		how := "kitty graphics" if hnoss.kitty_images(&term) else "half blocks"
		inner := hnoss.box(ui, area, fmt.tprintf("Image: %s", how))
		hnoss.image(ui, hnoss.inset(inner, shrink), &img)
		if open {
			d := hnoss.modal(ui, hnoss.center(f.area, 24, 5), &open, "[b]Modal[/]")
			hnoss.label(ui, hnoss.pad(d, 1, 1, 0, 1), "over the image")
		}

		changed := false
		for ev in hnoss.unhandled(ui) {
			changed = true
			switch {
			case hnoss.is_char(ev, 'b'): hnoss.set_kitty_images(&term, !hnoss.kitty_images(&term))
			case hnoss.is_char(ev, '-'): shrink = min(shrink + 1, 8)
			case hnoss.is_char(ev, '+'): shrink = max(shrink - 1, 0)
			case hnoss.is_char(ev, 'm'): open = true
			case hnoss.is_char(ev, 'q') || hnoss.is_key(ev, .Esc) || hnoss.is_char(ev, 'c', {.Ctrl}):
				break loop
			}
		}
		hnoss.end_frame(&term)
		free_all(context.temp_allocator)
		events = hnoss.poll_events(&term, 0 if changed || open != was_open else -1)
		if term.error != .None {
			break
		}
	}
}
