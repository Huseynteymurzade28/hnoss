// Widget example: paragraph. Scrolling markup text with a scrollbar (↑↓ PgUp PgDn Home End, wheel, drag the bar).
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

	scroll: hnoss.Scroll_State
	text := LOREM
	events: []hnoss.Event
	loop: for {
		f := hnoss.begin_frame(&term)
		ui := hnoss.ui(f, events)
		area := hnoss.inset(f.area, 1)
		footer := hnoss.cut_bottom(&area, 1)
		hnoss.label(ui, footer, "[dim]↑↓ PgUp PgDn Home End · wheel · drag the bar · q quit[/]")
		hnoss.focus(ui, &scroll)
		inner := hnoss.box(ui, area, "[b]paragraph[/]", {focused = true})
		total := hnoss.paragraph(ui, inner, text, &scroll, {scrollbar = true})
		hnoss.label(ui, hnoss.Rect{area.x + 2, area.y + area.height - 1, area.width - 4, 1}, fmt.tprintf(" line %d of %d ", scroll.offset + 1, total), align = .Right)
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

LOREM :: `[b]hnoss[/] widgets are procedures: calling one draws it, handles the input meant for it and tells you what happened.

This paragraph is [i]markup[/]: [red]red[/], [green]green[/], [b u]bold underline[/], [black on yellow] badges [/] and so on. It wraps at word boundaries and scrolls with the arrow keys, Page Up/Down, Home/End or the mouse wheel. The scrollbar on the right can be clicked or dragged.

🇦🇿 Azərbaycan dili: Salam, dünya! Bu mətn sürüşdürülə bilər. Hərflər: ə, ğ, ı, ö, ş, ü, ç.

` + LOREM_TAIL

LOREM_TAIL :: `Line one of a long tail.
Line two of a long tail.
Line three of a long tail.
Line four of a long tail.
Line five of a long tail.
Line six of a long tail.
Line seven of a long tail.
Line eight of a long tail.
Line nine of a long tail.
Line ten of a long tail.
Line eleven of a long tail.
Line twelve of a long tail.
Line thirteen of a long tail.
Line fourteen of a long tail.
Line fifteen of a long tail.
Line sixteen of a long tail.
Line seventeen of a long tail.
Line eighteen of a long tail.
Line nineteen of a long tail.
The end.`
