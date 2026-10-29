// Widget example: gauge. Smooth eighth-cell fill, labels, any height.
//   q / Esc  quit (unless a widget uses the key)
package main

import "core:fmt"
import "core:os"
import "core:math"
import hnoss "../.."
import "../../backend"

main :: proc() {
	context.assertion_failure_proc = backend.assertion_failure_proc

	term, err := hnoss.init(hnoss.DEFAULT_OPTIONS + {.Mouse_Capture})
	if err != .None {
		fmt.eprintfln("hnoss: init failed: %v", err)
		os.exit(1)
	}
	defer hnoss.deinit(&term)

	t := 0.0
	events: []hnoss.Event
	loop: for {
		f := hnoss.begin_frame(&term)
		ui := hnoss.ui(f, events)
		area := hnoss.inset(f.area, 1)
		footer := hnoss.cut_bottom(&area, 1)
		hnoss.label(ui, footer, "[dim]q quit[/]")
		t += 0.01
		rows := hnoss.split(area, .Vertical, {3, 3, 3, hnoss.fill()}, gap = 1)
		cpu := (math.sin(t * 2) + 1) / 2
		hnoss.gauge(ui, hnoss.box(ui, rows[0], "CPU"), cpu)
		disk := math.mod(t / 4, 1.0)
		hnoss.gauge(ui, hnoss.box(ui, rows[1], "Download"), disk, fmt.tprintf("%.1f / 100 MB", disk * 100))
		hnoss.gauge(ui, hnoss.box(ui, rows[2], "Battery"), 0.87)
		tall := hnoss.box(ui, rows[3], "any height")
		hnoss.gauge(ui, tall, (math.cos(t) + 1) / 2)
		for ev in hnoss.unhandled(ui) {
			if hnoss.is_char(ev, 'q') || hnoss.is_key(ev, .Esc) || hnoss.is_char(ev, 'c', {.Ctrl}) {
				break loop
			}
		}
		hnoss.end_frame(&term)
		free_all(context.temp_allocator)
		events = hnoss.poll_events(&term, 33)
		if term.error != .None {
			break
		}
	}
}
