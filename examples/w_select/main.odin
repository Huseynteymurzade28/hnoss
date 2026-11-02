// Widget example: select. Tab moves between the fields; Enter, Space or a
// click opens one, ↑↓ PgUp PgDn Home End move, Enter or a click picks, Esc
// or a click outside closes. The last field opens upwards (no room below).
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

	cities := []string{"Bakı", "Gəncə", "Sumqayıt", "Mingəçevir", "Şəki", "Lənkəran", "Şirvan", "Naxçıvan", "Quba", "Qəbələ", "Şamaxı", "Zaqatala", "Xankəndi", "Şuşa"}
	languages := []string{"Azərbaycanca", "Türkçe", "English", "Deutsch", "日本語"}
	themes := []string{"[cyan]●[/] Xəzər", "[red]●[/] Odlar Yurdu", "[green]●[/] Göygöl", "[yellow]●[/] Qızıl"}
	city, language, theme: hnoss.Select_State
	changes := 0
	events: []hnoss.Event
	loop: for {
		f := hnoss.begin_frame(&term)
		ui := hnoss.ui(f, events)
		area := hnoss.inset(f.area, 1)
		footer := hnoss.cut_bottom(&area, 1)
		hnoss.label(ui, footer, "[dim]Tab next · Enter/Space/click open · ↑↓ move · Enter pick · Esc close · q quit[/]")
		hnoss.focus_order(ui, {&city, &language, &theme})

		inner := hnoss.box(ui, area, "[b]Settings[/]", {focused = true})
		field :: proc(ui: ^hnoss.Ui, r: ^hnoss.Rect, name: string) -> hnoss.Rect {
			row := hnoss.cut_top(r, 2)
			hnoss.label(ui, hnoss.cut_left(&row, 10), name)
			return {row.x, row.y, min(row.width, 24), 1}
		}
		if hnoss.select(ui, field(ui, &inner, "City"), cities, &city) { changes += 1 }
		if hnoss.select(ui, field(ui, &inner, "Language"), languages, &language) { changes += 1 }
		summary := hnoss.cut_top(&inner, 3)
		bottom := hnoss.cut_bottom(&inner, 1)
		hnoss.label(ui, hnoss.cut_left(&bottom, 10), "Theme")
		if hnoss.select(ui, {bottom.x, bottom.y, min(bottom.width, 24), 1}, themes, &theme, {markup = true, max_rows = 3}) {
			changes += 1
		}
		hnoss.label(ui, summary, fmt.tprintf("[dim]→[/] [b]%s[/], %s, %s\n[dim]%d change(s)[/]",
			cities[city.selected], languages[language.selected], themes[theme.selected], changes))

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
