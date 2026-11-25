// Tween example: every easing curve, smooth gauges, scrolling and a modal
// that fades in.
//   Space    move everything to the other side
//   ↑ ↓      scroll the text, smoothly
//   m        modal
//   q / Esc  quit
package main

import "core:fmt"
import "core:math"
import "core:os"
import "core:strings"
import "core:time"
import hnoss "../.."
import "../../backend"
import "../../buffer"

LINES :: 60

main :: proc() {
	context.assertion_failure_proc = backend.assertion_failure_proc

	term, err := hnoss.init(hnoss.DEFAULT_OPTIONS + {.Mouse_Capture})
	if err != .None {
		fmt.eprintfln("hnoss: init failed: %v", err)
		os.exit(1)
	}
	defer hnoss.deinit(&term)

	side: [hnoss.Ease]hnoss.Tween
	progress, scroll: hnoss.Tween
	right, dialog: bool
	top := 0 // the line to scroll to
	events: []hnoss.Event
	loop: for {
		f := hnoss.begin_frame(&term)
		ui := hnoss.ui(f, events)
		theme := ui.theme
		area := hnoss.inset(f.area, 1)
		hnoss.label(ui, hnoss.cut_bottom(&area, 1), "[dim]Space move · ↑↓ scroll · m modal · q quit[/]")
		hnoss.gauge(ui, hnoss.box(ui, hnoss.cut_top(&area, 3), "Progress"), hnoss.tween(ui, &progress, 0.9 if right else 0.1, 600 * time.Millisecond))

		text := hnoss.cut_right(&area, 24)
		rows := hnoss.box(ui, area, "Easing")
		for e in hnoss.Ease {
			if rows.height <= 0 { break }
			row := hnoss.cut_top(&rows, 1)
			name := hnoss.cut_left(&row, 16)
			hnoss.label(ui, name, fmt.tprintf("%v", e))
			// Room at both ends for the curves that overshoot.
			track := hnoss.pad(row, 0, row.width / 4, 0, row.width / 4)
			x := hnoss.tween(ui, &side[e], 1 if right else 0, time.Second, e)
			buffer.set_string(f.buffer, track.x + int(math.round(x * f64(track.width - 1))), row.y, "●", theme.accent)
		}

		view := hnoss.box(ui, text, "Scrolling")
		line := int(math.round(hnoss.tween(ui, &scroll, f64(top))))
		for y in 0 ..< view.height {
			if line + y >= LINES { break }
			hnoss.label(ui, {view.x, view.y + y, view.width, 1}, strings.repeat("·", (line + y) % 7 + 1, context.temp_allocator))
			hnoss.label(ui, {view.x + 9, view.y + y, view.width - 9, 1}, fmt.tprintf("line %d", line + y + 1))
		}

		was_open := dialog
		if dialog {
			d := hnoss.modal(ui, hnoss.center(f.area, 34, 5), &dialog, "[b]Modal[/]", 250 * time.Millisecond)
			hnoss.label(ui, hnoss.pad(d, 1, 1, 0, 1), "The rest fades behind this.\nEsc closes it.")
		}

		moved := false
		for ev in hnoss.unhandled(ui) {
			switch {
			case hnoss.is_char(ev, ' '):  right = !right
			case hnoss.is_char(ev, 'm'):  dialog = true
			case hnoss.is_key(ev, .Down): top = min(top + 8, LINES - 8)
			case hnoss.is_key(ev, .Up):   top = max(top - 8, 0)
			case hnoss.is_char(ev, 'q') || hnoss.is_key(ev, .Esc) || hnoss.is_char(ev, 'c', {.Ctrl}):
				break loop
			}
			moved = true
		}
		hnoss.end_frame(&term)
		free_all(context.temp_allocator)
		// Nothing is drawn while nothing moves.
		events = hnoss.poll_events(&term, 0 if moved || dialog != was_open else hnoss.timeout(&term, -1))
		if term.error != .None {
			break
		}
	}
}
