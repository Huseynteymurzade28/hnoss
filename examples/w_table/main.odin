// Widget example: table. Column sizing with cells/percent/fill, alignment, selection.
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

	st: hnoss.Table_State
	cols := [?]hnoss.Column{
		{title = "PID", width = 7, align = .Right},
		{title = "Name", width = hnoss.fill()},
		{title = "User", width = hnoss.percent(15)},
		{title = "CPU %", width = 7, align = .Right},
		{title = "Mem", width = 9, align = .Right},
	}
	// Each row owns its slice and its formatted cells (names and users are
	// string literals). A []string{...} literal here would live on the stack.
	rows := make([dynamic][]string)
	names := [?]string{"odin", "hnoss_demo", "bash", "nvim", "firefox", "kitty", "pipewire", "Xwayland", "sshd", "systemd"}
	for i in 0 ..< 60 {
		row := make([]string, 5)
		row[0] = fmt.aprint(1000 + i * 37)
		row[1] = names[i % len(names)]
		row[2] = "huso" if i % 3 != 0 else "root"
		row[3] = fmt.aprintf("%.1f", f64((i * 7919) % 1000) / 10)
		row[4] = fmt.aprintf("%d MiB", (i * 131) % 900 + 12)
		append(&rows, row)
	}
	defer {
		for r in rows {
			delete(r[0]); delete(r[3]); delete(r[4])
			delete(r)
		}
		delete(rows)
	}

	events: []hnoss.Event
	loop: for {
		f := hnoss.begin_frame(&term)
		ui := hnoss.ui(f, events)
		area := hnoss.inset(f.area, 1)
		footer := hnoss.cut_bottom(&area, 1)
		hnoss.label(ui, footer, "[dim]↑↓ jk · click · wheel · q quit[/]")
		hnoss.focus(ui, &st)
		inner := hnoss.box(ui, area, fmt.tprintf("[b]processes[/] %d", len(rows)), {focused = true})
		hnoss.table(ui, inner, cols[:], rows[:], &st, {scrollbar = true})
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
