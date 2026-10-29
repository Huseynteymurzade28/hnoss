// Widget example: list. ↑↓/jk select, Enter activates, click, wheel.
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

	items := [?]string{"Bakı", "Gəncə", "Sumqayıt", "Mingəçevir", "Şəki", "Lənkəran", "Şirvan", "Naxçıvan", "Quba", "Qəbələ", "Şamaxı", "Zaqatala", "Xankəndi", "Şuşa", "Ağdam", "Füzuli", "İstanbul", "Ankara", "İzmir", "Tokyo", "Berlin", "Lisbon"}
	st: hnoss.List_State
	picked := ""
	events: []hnoss.Event
	loop: for {
		f := hnoss.begin_frame(&term)
		ui := hnoss.ui(f, events)
		area := hnoss.inset(f.area, 1)
		footer := hnoss.cut_bottom(&area, 1)
		hnoss.label(ui, footer, "[dim]↑↓ jk PgUp PgDn · Enter · click · wheel · q quit[/]")
		hnoss.focus(ui, &st)
		cols := hnoss.split(area, .Horizontal, {hnoss.fill(), hnoss.fill()}, gap = 1)
		inner := hnoss.box(ui, cols[0], "🇦🇿 [b]Cities[/]", {focused = true})
		hnoss.list(ui, inner, items[:], &st, {scrollbar = true})
		if st.activated {
			picked = items[st.selected]
		}
		info := hnoss.box(ui, cols[1], "selection")
		hnoss.label(ui, info, fmt.tprintf("selected: [b]%s[/] (%d)\nactivated: [b green]%s[/]", items[st.selected], st.selected, picked))
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
