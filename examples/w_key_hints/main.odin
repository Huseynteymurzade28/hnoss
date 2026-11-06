// Widget example: key hints. A hint bar that drops what doesn't fit, and a help page.
//   ?        help
//   q / Esc  quit
package main

import "core:fmt"
import "core:os"
import hnoss "../.."
import "../../backend"

HINTS := []hnoss.Key_Hint{
	{"q", "quit"}, {"?", "help"}, {"↑↓", "move"}, {"Enter", "open"},
	{"/", "search"}, {"Space", "mark"}, {"Ctrl+S", "save"}, {"Tab", "next pane"},
}

HELP := []hnoss.Key_Hint{
	{"", "Moving"},
	{"↑↓ j k", "move the selection"},
	{"PgUp PgDn", "a page at a time"},
	{"Home End", "first / last"},
	{"", "Actions"},
	{"Enter", "open"},
	{"Space", "mark"},
	{"Ctrl+S", "save"},
	{"", ""},
	{"q", "quit"},
}

main :: proc() {
	context.assertion_failure_proc = backend.assertion_failure_proc

	term, err := hnoss.init(hnoss.DEFAULT_OPTIONS)
	if err != .None {
		fmt.eprintfln("hnoss: init failed: %v", err)
		os.exit(1)
	}
	defer hnoss.deinit(&term)

	help := false
	events: []hnoss.Event
	loop: for {
		was_open := help
		f := hnoss.begin_frame(&term)
		ui := hnoss.ui(f, events)
		area := hnoss.inset(f.area, 1)
		footer := hnoss.cut_bottom(&area, 1)
		hnoss.key_hints(ui, footer, HINTS)

		inner := hnoss.box(ui, area, "Key hints")
		hnoss.label(ui, inner, "Resize the window: hints that don't fit drop off the end of the bar, and [dim]…[/] shows some are missing.\n\nPress [b]?[/] for the full list.")

		if help {
			dialog := hnoss.modal(ui, hnoss.center(f.area, 36, len(HELP) + 2), &help, "[b]Keys[/]")
			hnoss.key_help(ui, hnoss.pad(dialog, 0, 1, 0, 1), HELP)
		}

		for ev in hnoss.unhandled(ui) {
			switch {
			case hnoss.is_char(ev, '?'):
				help = true
			case hnoss.is_char(ev, 'q') || hnoss.is_key(ev, .Esc) || hnoss.is_char(ev, 'c', {.Ctrl}):
				break loop
			}
		}
		hnoss.end_frame(&term)
		free_all(context.temp_allocator)
		// Opening or closing the help changes what to draw: redraw now
		// rather than on the next key.
		events = hnoss.poll_events(&term, 0 if help != was_open else -1)
		if term.error != .None {
			break
		}
	}
}
