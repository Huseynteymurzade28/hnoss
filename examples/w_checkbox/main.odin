// Widget example: checkbox, toggle and radio. Tab moves focus, Space/Enter
// toggles, ↑↓ (jk) choose a radio option, click anything.
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

	wifi, bluetooth, dark := true, false, true
	city := 0
	cities := [?]string{"Bakı", "Gəncə", "Şəki", "Lənkəran"}
	events: []hnoss.Event
	loop: for {
		f := hnoss.begin_frame(&term)
		ui := hnoss.ui(f, events)
		area := hnoss.inset(f.area, 1)
		footer := hnoss.cut_bottom(&area, 1)
		hnoss.label(ui, footer, "[dim]Tab focus · Space toggle · ↑↓ choose · click · q quit[/]")
		hnoss.focus_order(ui, {&wifi, &bluetooth, &dark, &city})

		cols := hnoss.split(area, .Horizontal, {hnoss.fill(), hnoss.fill()}, gap = 1)
		left := hnoss.box(ui, cols[0], "[b]Settings[/]")
		hnoss.checkbox(ui, hnoss.cut_top(&left, 1), "Wi-Fi", &wifi)
		hnoss.checkbox(ui, hnoss.cut_top(&left, 1), "Bluetooth", &bluetooth)
		hnoss.cut_top(&left, 1)
		hnoss.toggle(ui, hnoss.cut_top(&left, 1), "Dark mode", &dark)

		right := hnoss.box(ui, cols[1], fmt.tprintf("[b]City[/] [dim]%s[/]", cities[city]), {focused = hnoss.focused(ui, &city)})
		hnoss.radio(ui, right, cities[:], &city)

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
