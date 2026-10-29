// Widget example: tabs. ←→ (hl) or click to switch.
//   q / Esc  quit (unless a widget uses the key)
package main

import "core:fmt"
import "core:os"
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

	titles := [?]string{"🇦🇿 Azərbaycan", "Overview", "[red]Alerts[/] 3", "Settings"}
	sel := 0
	events: []hnoss.Event
	loop: for {
		f := hnoss.begin_frame(&term)
		ui := hnoss.ui(f, events)
		area := hnoss.inset(f.area, 1)
		footer := hnoss.cut_bottom(&area, 1)
		hnoss.label(ui, footer, "[dim]←→ hl · click · q quit[/]")
		hnoss.focus(ui, &sel)
		bar := hnoss.cut_top(&area, 1)
		hnoss.tabs(ui, bar, titles[:], &sel)
		inner := hnoss.box(ui, area, titles[sel])
		hnoss.label(ui, hnoss.center(inner, 40, 3), fmt.tprintf("This is tab [b]%d[/].\nSalam! 👋", sel + 1), align = .Center)
		for ev in hnoss.unhandled(ui) {
			if hnoss.is_char(ev, 'q') || hnoss.is_key(ev, .Esc) || hnoss.is_char(ev, 'c', {.Ctrl}) {
				break loop
			}
		}
		hnoss.end_frame(&term)
		free_all(context.temp_allocator)
		events = hnoss.poll_events(&term, -1)
		if term.error != .None {
			break
		}
	}
}
