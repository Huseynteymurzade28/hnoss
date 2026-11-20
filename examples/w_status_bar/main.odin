// Widget example: status bar. A mode badge, left and right segments, and
// key hints in the free middle of the same row.
//   i        insert mode
//   Esc      normal mode
//   q        quit (in normal mode)
package main

import "core:fmt"
import "core:os"
import hnoss "../.."
import "../../backend"

HINTS := []hnoss.Key_Hint{{"i", "insert"}, {"Esc", "normal"}, {"q", "quit"}}

main :: proc() {
	context.assertion_failure_proc = backend.assertion_failure_proc

	term, err := hnoss.init(hnoss.DEFAULT_OPTIONS)
	if err != .None {
		fmt.eprintfln("hnoss: init failed: %v", err)
		os.exit(1)
	}
	defer hnoss.deinit(&term)

	insert := false
	keys := 0
	events: []hnoss.Event
	loop: for {
		was_insert, was_keys := insert, keys
		f := hnoss.begin_frame(&term)
		ui := hnoss.ui(f, events)
		area := f.area
		footer := hnoss.cut_bottom(&area, 1)

		bar := hnoss.Status_Bar{
			mode  = "INSERT" if insert else "NORMAL",
			left  = {"main.odin", "git:main"},
			right = {"utf-8", fmt.tprintf("%d keys", keys), fmt.tprintf("%dx%d", f.area.width, f.area.height)},
		}
		free := hnoss.status_bar(ui, footer, bar)
		hnoss.key_hints(ui, hnoss.pad(free, 0, 1, 0, 1), HINTS)

		inner := hnoss.box(ui, hnoss.inset(area, 1), "Status bar")
		hnoss.label(ui, inner, "Resize the window: the right side drops segments from its front, then the left side is cut. The mode badge always stays.\n\nKey hints sit in what the bar leaves free.")

		for ev in hnoss.unhandled(ui) {
			if _, is_key := ev.(hnoss.Key); is_key { keys += 1 }
			switch {
			case hnoss.is_key(ev, .Esc):
				insert = false
			case !insert && hnoss.is_char(ev, 'i'):
				insert = true
			case !insert && hnoss.is_char(ev, 'q') || hnoss.is_char(ev, 'c', {.Ctrl}):
				break loop
			}
		}
		hnoss.end_frame(&term)
		free_all(context.temp_allocator)
		// The mode or the count changed after this frame was drawn: draw
		// the next one now rather than on the next key.
		redraw := insert != was_insert || keys != was_keys
		events = hnoss.poll_events(&term, 0 if redraw else -1)
		if term.error != .None {
			break
		}
	}
}
