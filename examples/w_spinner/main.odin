// Widget example: spinner. Three frame sets, speed from elapsed time, markup labels.
//   q / Esc  quit
package main

import "core:fmt"
import "core:os"
import "core:time"
import hnoss "../.."
import "../../backend"

main :: proc() {
	context.assertion_failure_proc = backend.assertion_failure_proc

	term, err := hnoss.init(hnoss.DEFAULT_OPTIONS)
	if err != .None {
		fmt.eprintfln("hnoss: init failed: %v", err)
		os.exit(1)
	}
	defer hnoss.deinit(&term)

	start := time.tick_now()
	events: []hnoss.Event
	loop: for {
		f := hnoss.begin_frame(&term)
		ui := hnoss.ui(f, events)
		area := hnoss.inset(f.area, 1)
		footer := hnoss.cut_bottom(&area, 1)
		hnoss.label(ui, footer, "[dim]q quit[/]")

		elapsed := time.tick_since(start)
		inner := hnoss.box(ui, hnoss.cut_top(&area, 6), "Spinners")
		rows := hnoss.split(inner, .Vertical, {1, 1, 1, 1})
		hnoss.spinner(ui, rows[0], elapsed, "Resolving [b]dependencies[/]")
		hnoss.spinner(ui, rows[1], elapsed, "Compiling [cyan]hnoss[/] [dim](line)[/]", {kind = .Line})
		hnoss.spinner(ui, rows[2], elapsed, "Fetching [yellow]index[/] [dim](arc)[/]", {kind = .Arc, style = hnoss.Style{fg = .Yellow}})
		hnoss.spinner(ui, rows[3], elapsed, "[dim]slow, 400 ms a frame[/]", {interval = 400 * time.Millisecond, style = hnoss.Style{fg = .Magenta}})

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
