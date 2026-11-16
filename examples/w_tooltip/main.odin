// Widget example: tooltips. Rest the mouse on a button for half a second
// and a short text opens next to it; moving away, a key or a click closes it.
//   Tab  focus   Enter / Space  press   q / Esc  quit
package main

import "core:fmt"
import "core:os"
import hnoss "../.."
import "../../backend"

Action :: struct {
	label, tip, done: string,
}

main :: proc() {
	context.assertion_failure_proc = backend.assertion_failure_proc

	term, err := hnoss.init(hnoss.DEFAULT_OPTIONS + {.Mouse_Capture})
	if err != .None {
		fmt.eprintfln("hnoss: init failed: %v", err)
		os.exit(1)
	}
	defer hnoss.deinit(&term)

	actions := [4]Action {
		{"Brew", "Put the samovar on ([b]Ctrl+B[/])", "The samovar is on"},
		{"Pour", "Fill an [b]armudu[/] glass; the first one goes to the guest", "Poured a glass"},
		{"Sweeten", "Jam on the side, never in the glass", "Jam is on the table"},
		{"Clear", "Collect the glasses and wipe the table", "The table is clear"},
	}
	buttons: [4]hnoss.Button_State
	events: []hnoss.Event
	loop: for {
		f := hnoss.begin_frame(&term)
		ui := hnoss.ui(f, events)
		area := hnoss.inset(f.area, 1)
		hints := hnoss.cut_bottom(&area, 1)
		hnoss.key_hints(ui, hints, {{"rest the mouse", "tooltip"}, {"Tab", "focus"}, {"q", "quit"}})
		hnoss.tooltip(ui, &events, hints, "Tooltips open above when there is no room below")
		hnoss.focus_order(ui, {&buttons[0], &buttons[1], &buttons[2], &buttons[3]})

		inner := hnoss.box(ui, hnoss.Rect{area.x, area.y, min(area.width, 24), min(area.height, 11)}, "[b]Çayxana[/]")
		for &b, i in buttons {
			row := hnoss.cut_top(&inner, 1)
			if hnoss.button(ui, row, actions[i].label, &b) {
				hnoss.toast(ui, actions[i].done, .Success)
			}
			hnoss.tooltip(ui, &b, row, actions[i].tip)
			hnoss.cut_top(&inner, 1)
		}

		for ev in hnoss.unhandled(ui) {
			if hnoss.is_char(ev, 'q') || hnoss.is_key(ev, .Esc) || hnoss.is_char(ev, 'c', {.Ctrl}) {
				break loop
			}
		}

		hnoss.end_frame(&term) // the tooltip is drawn here, over everything
		free_all(context.temp_allocator)
		// A tooltip opens without any input: let it wake the loop.
		events = hnoss.poll_events(&term, hnoss.timeout(&term, -1))
		if term.error != .None {
			break
		}
	}
}
