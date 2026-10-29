// Widget example: text input. Two fields, Tab moves focus, Enter submits; q typed into a field does not quit.
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

	name, pass: hnoss.Input_State
	defer hnoss.input_destroy(&name)
	defer hnoss.input_destroy(&pass)
	log: [dynamic]string
	defer { for l in log { delete(l) }; delete(log) }
	events: []hnoss.Event
	loop: for {
		f := hnoss.begin_frame(&term)
		ui := hnoss.ui(f, events)
		area := hnoss.inset(f.area, 1)
		footer := hnoss.cut_bottom(&area, 1)
		hnoss.label(ui, footer, "[dim]Tab focus · Enter submit · Esc quit[/]")
		hnoss.focus_order(ui, {&name, &pass})
		rows := hnoss.split(area, .Vertical, {3, 3, hnoss.fill()}, gap = 1)
		f1 := hnoss.box(ui, rows[0], "Name", {focused = hnoss.focused(ui, &name)})
		hnoss.input(ui, f1, &name, {placeholder = "Adınız…"})
		f2 := hnoss.box(ui, rows[1], "Password", {focused = hnoss.focused(ui, &pass)})
		hnoss.input(ui, f2, &pass, {mask = "•"})
		if name.submitted || pass.submitted {
			append(&log, fmt.aprintf("submitted: name=\"%s\", password has %d bytes", hnoss.input_text(&name), len(pass.text)))
		}
		out := hnoss.box(ui, rows[2], "log")
		for l, i in log[max(len(log) - out.height, 0):] {
			hnoss.label(ui, hnoss.Rect{out.x, out.y + i, out.width, 1}, l, wrap = .Ellipsis)
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
