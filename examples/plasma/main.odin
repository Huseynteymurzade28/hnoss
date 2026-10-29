// Phase 2 example: a full-screen truecolor plasma at 60 fps through the
// double-buffered diff renderer. Every cell changes every frame, which is
// the worst case for the diff; the status line shows what it costs.
//   q / Ctrl+C  quit
//   space       pause
package main

import "core:fmt"
import "core:math"
import "core:os"
import "core:time"
import hnoss "../.."
import "../../backend"
import "../../buffer"
import "../../style"

FRAME_TIME :: time.Second / 60

main :: proc() {
	context.assertion_failure_proc = backend.assertion_failure_proc

	term, err := hnoss.init()
	if err != .None {
		fmt.eprintfln("hnoss: init failed: %v", err)
		os.exit(1)
	}
	defer hnoss.deinit(&term)

	paused := false
	t: f64
	fps: f64 = 60
	last := time.tick_now()

	loop: for {
		frame_start := time.tick_now()
		dt := time.duration_seconds(time.tick_diff(last, frame_start))
		last = frame_start
		if dt > 0 {
			fps = fps * 0.95 + (1 / dt) * 0.05
		}
		if !paused {
			t += dt
		}

		f := hnoss.begin_frame(&term)
		draw_plasma(f, t)
		draw_status(f, fps, term.last_bytes, paused)
		if hnoss.end_frame(&term) != .None {
			break
		}

		// Sleep until the next frame is due, waking early for input.
		remaining := FRAME_TIME - time.tick_since(frame_start)
		for ev in hnoss.poll_events(&term, max(int(remaining / time.Millisecond), 0)) {
			switch {
			case hnoss.is_char(ev, 'q'), hnoss.is_char(ev, 'c', {.Ctrl}):
				break loop
			case hnoss.is_char(ev, ' '):
				paused = !paused
			}
		}
		free_all(context.temp_allocator)
		if term.error != .None {
			break
		}
	}
}

// "▀" with fg = upper pixel and bg = lower pixel doubles vertical resolution.
//
// Classic demoscene plasma: the value at (x, y) is a sum of sines of x, of y
// and of x+y, so each term is computed once per column/row/diagonal instead
// of once per pixel, and mapped to a color through a fixed palette.
draw_plasma :: proc(f: ^hnoss.Frame, t: f64) {
	w, h := f.area.width, f.area.height * 2
	col := make([]f64, w, context.temp_allocator)
	row := make([]f64, h, context.temp_allocator)
	diag := make([]f64, w + h, context.temp_allocator)
	for x in 0 ..< w { col[x] = math.sin(f64(x) * 0.08 + t) }
	for y in 0 ..< h { row[y] = math.sin(f64(y) * 0.11 - t * 1.3) }
	for d in 0 ..< w + h { diag[d] = math.sin(f64(d) * 0.05 + t * 0.7) }

	palette := get_palette()
	shift := int(t * 40) // also cycle the palette over time
	color :: proc(palette: ^[256]style.Color, v: f64, shift: int) -> style.Color {
		// v is in [-3, 3]
		return palette[(int((v + 3) * 42.5) + shift) & 0xff]
	}
	for y in 0 ..< f.area.height {
		top, bot := y * 2, y * 2 + 1
		for x in 0 ..< w {
			fg := color(palette, col[x] + row[top] + diag[x + top], shift)
			bg := color(palette, col[x] + row[bot] + diag[x + bot], shift)
			buffer.set_symbol(f.buffer, x, y, "▀", 1, {fg = fg, bg = bg})
		}
	}
}

get_palette :: proc() -> ^[256]style.Color {
	@(static) palette: [256]style.Color
	@(static) ready: bool
	if !ready {
		for &c, i in palette {
			a := f64(i) / 256 * 2 * math.PI
			c = style.rgb(channel(a, 0), channel(a, 2.1), channel(a, 4.2))
		}
		ready = true
	}
	return &palette
}

channel :: proc(a, phase: f64) -> u8 {
	return u8(127.5 + 127.5 * math.sin(a + phase))
}

draw_status :: proc(f: ^hnoss.Frame, fps: f64, bytes: int, paused: bool) {
	msg := fmt.tprintf(
		" hnoss plasma  %dx%d  %.0f fps  %d KiB/frame  %s  q quit ",
		f.area.width, f.area.height, fps, bytes / 1024,
		"paused" if paused else "space pause",
	)
	st := style.Style {
		fg  = style.Named_Color.Black,
		bg  = style.Named_Color.White,
		add = {.Bold},
	}
	buffer.set_string(f.buffer, 0, 0, msg, st)
}
