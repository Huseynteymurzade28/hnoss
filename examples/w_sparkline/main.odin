// Widget example: sparkline. Live data, one row and several rows.
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

	data := make([dynamic]f64)
	defer delete(data)
	t := 0.0
	events: []hnoss.Event
	loop: for {
		f := hnoss.begin_frame(&term)
		ui := hnoss.ui(f, events)
		area := hnoss.inset(f.area, 1)
		footer := hnoss.cut_bottom(&area, 1)
		hnoss.label(ui, footer, "[dim]q quit[/]")
		t += 0.15
		append(&data, 50 + 30 * math.sin(t) + 15 * math.sin(t * 3.7) + 5 * math.cos(t * 11))
		if len(data) > 1000 { remove_range(&data, 0, 500) }
		rows := hnoss.split(area, .Vertical, {3, hnoss.fill()}, gap = 1)
		hnoss.sparkline(ui, hnoss.box(ui, rows[0], "one row"), data[:], max_value = 100)
		hnoss.sparkline(ui, hnoss.box(ui, rows[1], fmt.tprintf("%d rows · latest [b]%.0f[/]", rows[1].height - 2, data[len(data) - 1])), data[:], max_value = 100, st = hnoss.Style{fg = .Green})
		for ev in hnoss.unhandled(ui) {
			if hnoss.is_char(ev, 'q') || hnoss.is_key(ev, .Esc) || hnoss.is_char(ev, 'c', {.Ctrl}) {
				break loop
			}
		}
		hnoss.end_frame(&term)
		free_all(context.temp_allocator)
		events = hnoss.poll_events(&term, 50)
		if term.error != .None {
			break
		}
	}
}
