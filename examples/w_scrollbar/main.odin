// Widget example: scrollbar on its own: click the track, drag the thumb, use the wheel.
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

	offset := 0
	events: []hnoss.Event
	loop: for {
		f := hnoss.begin_frame(&term)
		ui := hnoss.ui(f, events)
		area := hnoss.inset(f.area, 1)
		footer := hnoss.cut_bottom(&area, 1)
		hnoss.label(ui, footer, "[dim]click · drag · wheel · q quit[/]")
		TOTAL :: 500
		inner := hnoss.box(ui, area, "[b]scrollbar[/]")
		bar := hnoss.cut_right(&inner, 1)
		hnoss.scrollbar(ui, bar, TOTAL, inner.height, &offset)
		for row in 0 ..< inner.height {
			hnoss.label(ui, hnoss.Rect{inner.x, inner.y + row, inner.width, 1}, fmt.tprintf("[dim]line[/] %d", offset + row + 1))
		}
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
