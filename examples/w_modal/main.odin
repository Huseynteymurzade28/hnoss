// Widget example: a modal dialog. Enter on a city asks to delete it; in the
// dialog Tab moves between the buttons, Esc or a click outside closes it.
//   q  quit
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

	cities := make([dynamic]string)
	defer delete(cities)
	append(&cities, "Bakı", "Gəncə", "Sumqayıt", "Şəki", "Lənkəran", "Naxçıvan", "Quba")
	list: hnoss.List_State
	confirm := false
	delete_btn, cancel_btn: hnoss.Button_State
	events: []hnoss.Event
	loop: for {
		f := hnoss.begin_frame(&term)
		ui := hnoss.ui(f, events)
		area := hnoss.inset(f.area, 1)
		footer := hnoss.cut_bottom(&area, 1)
		hnoss.label(ui, footer, "[dim]↑↓ select · Enter delete · q quit[/]")

		inner := hnoss.box(ui, area, fmt.tprintf("[b]Cities[/] [dim]%d[/]", len(cities)), {focused = !confirm})
		hnoss.focus(ui, &list)
		hnoss.list(ui, inner, cities[:], &list)
		if list.activated && len(cities) > 0 {
			confirm = true
		}

		if confirm {
			d := hnoss.modal(ui, hnoss.center(f.area, 36, 7), &confirm, "[b]Delete city[/]")
			hnoss.focus_order(ui, {&cancel_btn, &delete_btn})
			hnoss.label(ui, hnoss.cut_top(&d, 2), fmt.tprintf("Delete [b]%s[/]?", cities[list.selected]), align = .Center)
			cols := hnoss.split(hnoss.cut_top(&d, 1), .Horizontal, {hnoss.fill(), hnoss.fill()}, gap = 2)
			if hnoss.button(ui, cols[0], "Cancel", &cancel_btn) {
				confirm = false
			}
			if hnoss.button(ui, cols[1], "[red]Delete[/]", &delete_btn) {
				ordered_remove(&cities, list.selected)
				confirm = false
			}
		}

		for ev in hnoss.unhandled(ui) {
			if hnoss.is_char(ev, 'q') || hnoss.is_char(ev, 'c', {.Ctrl}) {
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
