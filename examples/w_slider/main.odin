// Widget example: sliders and number inputs, as the settings of a tea
// house's sound system and an order form. Tab moves focus; sliders take
// ← → (Shift: ×10) Home End, number fields ↑ ↓ and typing; drag, click
// and the wheel work on both.
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

	volume, bass, tempo := 60.0, 0.5, 1.0
	guests := hnoss.Number_State{value = 4}
	glasses := hnoss.Number_State{value = 2}
	price := hnoss.Number_State{value = 3.5}
	events: []hnoss.Event
	loop: for {
		f := hnoss.begin_frame(&term)
		ui := hnoss.ui(f, events)
		area := hnoss.inset(f.area, 1)
		footer := hnoss.cut_bottom(&area, 1)
		hnoss.key_hints(ui, footer, {{"Tab", "focus"}, {"← →", "slide"}, {"↑ ↓", "step"}, {"q", "quit"}})
		hnoss.focus_order(ui, {&volume, &bass, &tempo, &guests, &glasses, &price})

		cols := hnoss.split(area, .Horizontal, {hnoss.fill(), hnoss.fill()}, gap = 1)
		left := hnoss.box(ui, cols[0], "[b]Səs[/] [dim]· sound[/]")
		row :: proc(ui: ^hnoss.Ui, area: ^hnoss.Rect, name: string) -> hnoss.Rect {
			r := hnoss.cut_top(area, 1)
			hnoss.label(ui, hnoss.cut_left(&r, 9), name)
			hnoss.cut_top(area, 1)
			return r
		}
		hnoss.slider(ui, row(ui, &left, "Volume"), &volume, 0, 100, {step = 5, show_value = true, format = "%.0f%%"})
		hnoss.slider(ui, row(ui, &left, "Bass"), &bass, -1, 1, {step = 0.1, show_value = true})
		hnoss.slider(ui, row(ui, &left, "Tempo"), &tempo, 0.5, 2, {step = 0.25, show_value = true, format = "%.2f×"})

		right := hnoss.box(ui, cols[1], "[b]Sifariş[/] [dim]· order[/]")
		hnoss.number_input(ui, row(ui, &right, "Guests"), &guests, {min = 1, max = 20})
		hnoss.number_input(ui, row(ui, &right, "Glasses"), &glasses, {min = 0, max = 10})
		hnoss.number_input(ui, row(ui, &right, "Price ₼"), &price, {min = 0, step = 0.5, decimals = 2})
		total := guests.value * glasses.value * price.value
		hnoss.label(ui, hnoss.cut_top(&right, 1), fmt.tprintf("[dim]Total[/]    [b]%.2f ₼[/]", total))

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
