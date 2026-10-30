// Widget example: a text area under a one-line title field. Tab moves focus;
// in the text: Enter new line, ↑↓ PgUp PgDn by row, Home End line, Ctrl+Home
// Ctrl+End text, the input's editing keys, paste with newlines, wheel.
//   Esc  quit
package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:unicode/utf8"
import hnoss "../.."
import "../../backend"

NOTE :: `Bakı, 30 oktyabr

Bu gün hnoss-a çoxsətirli mətn sahəsi əlavə etdik. Uzun sətirlər sözlərə görə bükülür, ↑ ↓ isə bükülmüş sətirlər üzrə gəzir və sütunu yadda saxlayır.

Siyahı:
- 世界 kimi enli simvollar
- 👩‍💻 və 🇦🇿 kimi qrafem klasterləri
- Ctrl+K sətrin sonunda növbəti sətri birləşdirir`

main :: proc() {
	context.assertion_failure_proc = backend.assertion_failure_proc

	term, err := hnoss.init(hnoss.DEFAULT_OPTIONS + {.Mouse_Capture})
	if err != .None {
		fmt.eprintfln("hnoss: init failed: %v", err)
		os.exit(1)
	}
	defer hnoss.deinit(&term)

	title, note: hnoss.Input_State
	defer hnoss.input_destroy(&title)
	defer hnoss.input_destroy(&note)
	hnoss.input_set(&title, "Gündəlik")
	hnoss.input_set(&note, NOTE)
	first := true
	events: []hnoss.Event
	loop: for {
		f := hnoss.begin_frame(&term)
		ui := hnoss.ui(f, events)
		if first {
			hnoss.focus(ui, &note)
			first = false
		}
		area := hnoss.inset(f.area, 1)
		footer := hnoss.cut_bottom(&area, 1)
		hnoss.focus_order(ui, {&title, &note})

		top := hnoss.box(ui, hnoss.cut_top(&area, 3), "[b]Title[/]", {focused = hnoss.focused(ui, &title)})
		hnoss.input(ui, top, &title, {placeholder = "Untitled"})

		inner := hnoss.box(ui, area, "[b]Note[/]", {focused = hnoss.focused(ui, &note)})
		hnoss.text_area(ui, inner, &note, {placeholder = "Write something…", scrollbar = true})

		text := hnoss.input_text(&note)
		lines := strings.count(text, "\n") + 1
		hnoss.label(ui, footer, fmt.tprintf("[dim]%d lines · %d chars · Tab focus · Esc quit[/]", lines, utf8.rune_count(text)))

		for ev in hnoss.unhandled(ui) {
			if hnoss.is_key(ev, .Esc) || hnoss.is_char(ev, 'c', {.Ctrl}) {
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
