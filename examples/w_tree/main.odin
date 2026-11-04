// Widget example: tree. The app keeps its own nodes (a flat list with
// depths) and an `open` flag per folder; the tree reads and flips them.
//   ↑↓ (k j) PgUp PgDn Home End  move
//   → (l)  open / first child    ← (h)  close / parent
//   Space  toggle                Enter  pick a file
//   click  select, on ▸ toggle   wheel  scroll
//   q      quit
package main

import "core:fmt"
import "core:os"
import hnoss "../.."
import "../../backend"

Node :: struct {
	name:   string,
	depth:  int,
	folder: bool,
	open:   bool,
}

main :: proc() {
	context.assertion_failure_proc = backend.assertion_failure_proc

	term, err := hnoss.init(hnoss.DEFAULT_OPTIONS + {.Mouse_Capture})
	if err != .None {
		fmt.eprintfln("hnoss: init failed: %v", err)
		os.exit(1)
	}
	defer hnoss.deinit(&term)

	nodes := [?]Node{
		{"hnoss", 0, true, true},
		{"backend", 1, true, false},
		{"backend_linux.odin", 2, false, false},
		{"backend_darwin.odin", 2, false, false},
		{"widgets", 1, true, true},
		{"list.odin", 2, false, false},
		{"table.odin", 2, false, false},
		{"tree.odin", 2, false, false},
		{"select.odin", 2, false, false},
		{"text", 1, true, false},
		{"width.odin", 2, false, false},
		{"grapheme.odin", 2, false, false},
		{"examples", 1, true, false},
		{"demo", 2, true, false},
		{"main.odin", 3, false, false},
		{"w_tree", 2, true, false},
		{"main.odin", 3, false, false},
		{"README.md", 1, false, false},
		{"LICENSE", 1, false, false},
		{"Xəritə", 0, true, false},
		{"Bakı", 1, true, false},
		{"Səbail", 2, false, false},
		{"Yasamal", 2, false, false},
		{"Gəncə", 1, false, false},
		{"Şəki", 1, false, false},
	}
	items: [len(nodes)]hnoss.Tree_Item
	for &n, i in nodes {
		items[i] = {n.name, n.depth, &n.open if n.folder else nil}
	}

	st: hnoss.Tree_State
	picked := "—"
	events: []hnoss.Event
	loop: for {
		f := hnoss.begin_frame(&term)
		ui := hnoss.ui(f, events)
		area := hnoss.inset(f.area, 1)
		footer := hnoss.cut_bottom(&area, 1)
		hnoss.label(ui, footer, "[dim]↑↓ move · → open · ← close · Space toggle · Enter pick · q quit[/]")
		status := hnoss.cut_bottom(&area, 1)

		hnoss.focus(ui, &st)
		inner := hnoss.box(ui, {area.x, area.y, min(area.width, 40), area.height}, "[b]Files[/]", {focused = true})
		hnoss.tree(ui, inner, items[:], &st, {scrollbar = true, guides = true})
		if st.activated && !nodes[st.selected].folder {
			picked = nodes[st.selected].name
		}
		hnoss.label(ui, status, fmt.tprintf("[dim]selected[/] [b]%s[/] · [dim]picked[/] %s", nodes[st.selected].name, picked))

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
