// Widget example: buttons. Tab moves focus, Enter/Space presses, or click
// (drag off before releasing to cancel).
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

	save, discard, cancel: hnoss.Button_State
	status := "Nothing pressed yet."
	events: []hnoss.Event
	loop: for {
		f := hnoss.begin_frame(&term)
		ui := hnoss.ui(f, events)
		area := hnoss.inset(f.area, 1)
		footer := hnoss.cut_bottom(&area, 1)
		hnoss.label(ui, footer, "[dim]Tab focus · Enter/Space press · click · q quit[/]")
		hnoss.focus_order(ui, {&save, &discard, &cancel})

		inner := hnoss.box(ui, hnoss.center(area, 44, 8), "[b]Unsaved changes[/]")
		hnoss.label(ui, hnoss.cut_top(&inner, 2), "Save changes to [b]şəhərlər.txt[/]?")
		hnoss.label(ui, hnoss.cut_bottom(&inner, 1), fmt.tprintf("[dim]%s[/]", status))
		row := hnoss.cut_top(&inner, 1)
		cols := hnoss.split(row, .Horizontal, {hnoss.fill(), hnoss.fill(), hnoss.fill()}, gap = 2)
		if hnoss.button(ui, cols[0], "Save", &save) { status = "Saved." }
		if hnoss.button(ui, cols[1], "[red]Discard[/]", &discard) { status = "Discarded." }
		if hnoss.button(ui, cols[2], "Cancel", &cancel) { status = "Cancelled." }

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
