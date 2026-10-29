// Widget example: box. Border styles and title alignment.
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


	events: []hnoss.Event
	loop: for {
		f := hnoss.begin_frame(&term)
		ui := hnoss.ui(f, events)
		area := hnoss.inset(f.area, 1)
		footer := hnoss.cut_bottom(&area, 1)
		hnoss.label(ui, footer, "[dim]q quit[/]")
		kinds := [?]hnoss.Border{.Plain, .Rounded, .Double, .Thick}
		aligns := [?]hnoss.Align{.Left, .Center, .Right, .Left}
		for kind, i in kinds {
			cell := hnoss.grid_cell(area, 2, 2, i % 2, i / 2, gap = 1)
			inner := hnoss.box(ui, cell, fmt.tprintf("[b]%v[/] border", kind), {border = kind, align = aligns[i], focused = i == 1})
			hnoss.label(ui, inner, fmt.tprintf("title aligned [cyan]%v[/]\n\nhnoss.box returns the area inside the border: [b]%dx%d[/]", aligns[i], inner.width, inner.height))
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
