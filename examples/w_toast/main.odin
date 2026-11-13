// Widget example: toast notifications. Each button (or 1-4) shows one kind;
// they stack in the top-right corner, go away by themselves and slide up
// when one leaves. Click a toast to dismiss it.
//   Tab  focus   Enter / Space  press   1-4  a toast   q / Esc  quit
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

	buttons: [4]hnoss.Button_State
	labels := [4]string{"[b]1[/] Info", "[b]2[/] Success", "[b]3[/] Warning", "[b]4[/] Error"}
	count := 0
	events: []hnoss.Event
	loop: for {
		f := hnoss.begin_frame(&term)
		ui := hnoss.ui(f, events)
		area := hnoss.inset(f.area, 1)
		hnoss.key_hints(ui, hnoss.cut_bottom(&area, 1), {{"Tab", "focus"}, {"1-4", "toast"}, {"click", "dismiss"}, {"q", "quit"}})
		hnoss.focus_order(ui, {&buttons[0], &buttons[1], &buttons[2], &buttons[3]})

		inner := hnoss.box(ui, hnoss.Rect{area.x, area.y, min(area.width, 24), min(area.height, 11)}, "[b]Çayxana[/]")
		pressed := -1
		for &b, i in buttons {
			if hnoss.button(ui, hnoss.cut_top(&inner, 1), labels[i], &b) { pressed = i }
			hnoss.cut_top(&inner, 1)
		}

		for ev in hnoss.unhandled(ui) {
			switch {
			case hnoss.is_char(ev, '1'): pressed = 0
			case hnoss.is_char(ev, '2'): pressed = 1
			case hnoss.is_char(ev, '3'): pressed = 2
			case hnoss.is_char(ev, '4'): pressed = 3
			case hnoss.is_char(ev, 'q') || hnoss.is_key(ev, .Esc) || hnoss.is_char(ev, 'c', {.Ctrl}):
				break loop
			}
		}
		count += 1 if pressed >= 0 else 0
		switch pressed {
		case 0: hnoss.toast(ui, fmt.tprintf("Order [b]#%d[/] received", count))
		case 1: hnoss.toast(ui, "Tea is ready: [b]armudu[/] glasses, lemon on the side", .Success)
		case 2: hnoss.toast(ui, "Only [b]3[/] boxes of sugar left", .Warning)
		case 3: hnoss.toast(ui, "The samovar is out of water; refill it before the next order", .Error)
		}

		hnoss.end_frame(&term) // the toasts are drawn here, over everything
		free_all(context.temp_allocator)
		events = hnoss.poll_events(&term, hnoss.toast_timeout(&term, -1))
		if term.error != .None {
			break
		}
	}
}
