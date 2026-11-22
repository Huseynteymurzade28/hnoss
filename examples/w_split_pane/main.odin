// Widget example: split panes. A list of regions beside a preview, and the
// preview split again into its description and notes. Drag a divider,
// double-click it to center it, or Tab to it and use the arrows
// (Shift: ×10, Home End: the ends).
//   q / Esc  quit
package main

import "core:fmt"
import "core:os"
import hnoss "../.."
import "../../backend"

REGIONS := []string{"Abşeron", "Gəncə-Daşkəsən", "Şəki-Zaqatala", "Lənkəran-Astara", "Quba-Xaçmaz", "Naxçıvan"}
NOTES := []string{
	"The peninsula around Bakı: oil fields, beaches and the old city.",
	"Gəncə, the second city, and the iron mines of Daşkəsən.",
	"Silk, the Xan Sarayı and the forests of the Greater Caucasus.",
	"Tea, citrus and the Hirkan forest by the Caspian.",
	"Apples, carpets and the mountain village of Xınalıq.",
	"An exclave between Armenia, Iran and Türkiye.",
}

main :: proc() {
	context.assertion_failure_proc = backend.assertion_failure_proc

	term, err := hnoss.init(hnoss.DEFAULT_OPTIONS + {.Mouse_Capture})
	if err != .None {
		fmt.eprintfln("hnoss: init failed: %v", err)
		os.exit(1)
	}
	defer hnoss.deinit(&term)

	sidebar := hnoss.Split_State{ratio = 0.3}
	preview: hnoss.Split_State
	regions: hnoss.List_State
	events: []hnoss.Event
	loop: for {
		f := hnoss.begin_frame(&term)
		ui := hnoss.ui(f, events)
		area := hnoss.inset(f.area, 1)
		footer := hnoss.cut_bottom(&area, 1)
		hnoss.key_hints(ui, footer, {{"Tab", "focus"}, {"← → ↑ ↓", "move"}, {"drag", "resize"}, {"q", "quit"}})
		hnoss.focus_order(ui, {&regions, &sidebar, &preview})

		inner := hnoss.box(ui, area, "[b]Azərbaycan[/] [dim]· regions[/]")
		left, right := hnoss.split_pane(ui, inner, .Horizontal, &sidebar, {min_first = 14, min_second = 20, join = true})
		top, bottom := hnoss.split_pane(ui, right, .Vertical, &preview, {min_first = 3, min_second = 3, join = true})

		hnoss.list(ui, hnoss.pad(left, 0, 1, 0, 0), REGIONS, &regions)

		sel := clamp(regions.selected, 0, len(REGIONS) - 1)
		desc := hnoss.pad(top, 0, 1, 0, 1)
		hnoss.label(ui, hnoss.cut_top(&desc, 1), fmt.tprintf("[b]%s[/]", REGIONS[sel]))
		hnoss.paragraph(ui, desc, NOTES[sel])
		hnoss.paragraph(ui, hnoss.pad(bottom, 0, 1, 0, 1), fmt.tprintf(
			"[dim]sidebar[/] %d cols (%.0f%%)\n[dim]description[/] %d rows (%.0f%%)",
			left.width, sidebar.ratio * 100, top.height, preview.ratio * 100,
		))

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
