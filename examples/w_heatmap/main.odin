// Widget example: heatmap. A week of hourly load, with labels and a legend.
//   h        toggle half blocks (two rows of values per terminal row)
//   q / Esc  quit
package main

import "core:fmt"
import "core:math"
import "core:os"
import hnoss "../.."
import "../../backend"

DAYS :: []string{"Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"}
HOURS :: 24

main :: proc() {
	context.assertion_failure_proc = backend.assertion_failure_proc

	term, err := hnoss.init(hnoss.DEFAULT_OPTIONS)
	if err != .None {
		fmt.eprintfln("hnoss: init failed: %v", err)
		os.exit(1)
	}
	defer hnoss.deinit(&term)

	// Busy in working hours on weekdays, a quieter bump in the evening on
	// weekends, a bit of noise, and one hour where the probe was down.
	load: [7 * HOURS]f64
	for &v, i in load {
		day, hour := i / HOURS, f64(i % HOURS)
		weekend := day >= 5
		work := math.exp(-math.pow((hour - 13) / 4, 2)) * (0.3 if weekend else 1)
		evening := math.exp(-math.pow((hour - 20) / 2.5, 2)) * (0.8 if weekend else 0.4)
		noise := 0.08 * math.sin(f64(i) * 12.9898)
		v = math.round(100 * clamp(work + evening + noise, 0, 1))
	}
	load[2 * HOURS + 4] = math.nan_f64()

	col_labels: [HOURS]string
	for h := 0; h < HOURS; h += 3 {
		col_labels[h] = fmt.aprintf("%02d", h)
	}

	half := false
	events: []hnoss.Event
	loop: for {
		was_half := half
		f := hnoss.begin_frame(&term)
		ui := hnoss.ui(f, events)
		area := hnoss.inset(f.area, 1)
		footer := hnoss.cut_bottom(&area, 1)
		hnoss.key_hints(ui, footer, {{"h", "half blocks"}, {"q", "quit"}})

		inner := hnoss.box(ui, area, "Load by hour, last week")
		hnoss.heatmap(ui, hnoss.inset(inner, 1), load[:], HOURS, {
			row_labels  = {} if half else DAYS,
			col_labels  = col_labels[:],
			half_blocks = half,
			legend      = true,
			format      = "%.0f%%",
		})

		for ev in hnoss.unhandled(ui) {
			switch {
			case hnoss.is_char(ev, 'h'):
				half = !half
			case hnoss.is_char(ev, 'q') || hnoss.is_key(ev, .Esc) || hnoss.is_char(ev, 'c', {.Ctrl}):
				break loop
			}
		}
		hnoss.end_frame(&term)
		free_all(context.temp_allocator)
		events = hnoss.poll_events(&term, 0 if half != was_half else -1)
		if term.error != .None {
			break
		}
	}
}
