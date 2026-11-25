// Keymap example: named actions, chords, a generated help page, rebinding.
//   ?            help
//   g g, G       first / last line
//   Ctrl+K ...   chords
//   r            rebind the selected action: type a key
//   q            quit
package main

import "core:fmt"
import "core:os"
import hnoss "../.."
import "../../backend"

BINDINGS := []hnoss.Binding {
	{"", "", "Moving"},
	{"j", "down", "next line"},
	{"k", "up", "previous line"},
	{"g g", "top", "first line"},
	{"G", "bottom", "last line"},
	{"", "", "File"},
	{"Ctrl+S", "save", "save"},
	{"Ctrl+K Ctrl+S", "save_all", "save everything"},
	{"", "", "Other"},
	{"r", "rebind", "rebind the selected action"},
	{"?", "help", "this help"},
	{"q", "quit", "quit"},
	{"Ctrl+C", "quit", ""},
}

main :: proc() {
	context.assertion_failure_proc = backend.assertion_failure_proc

	term, err := hnoss.init(hnoss.DEFAULT_OPTIONS)
	if err != .None {
		fmt.eprintfln("hnoss: init failed: %v", err)
		os.exit(1)
	}
	defer hnoss.deinit(&term)

	km: hnoss.Keymap
	hnoss.keymap_init(&km, BINDINGS)
	defer hnoss.keymap_destroy(&km)

	// The rows of the list: every action that isn't a heading.
	names: [dynamic]string
	defer delete(names)
	for a in km.actions {
		if a.name != "" { append(&names, a.name) }
	}

	last := "none"
	help, rebinding: bool
	list: hnoss.List_State
	events: []hnoss.Event
	loop: for {
		changed := false
		was_open := help
		f := hnoss.begin_frame(&term)
		ui := hnoss.ui(f, events)

		// While rebinding, the next key is the new binding. Esc cancels.
		if rebinding {
			for ev, i in ui.events {
				k, is_key := ev.(hnoss.Key)
				if !is_key { continue }
				ui.handled[i] = true
				rebinding = false
				changed = true
				if k.code != .Esc { hnoss.keymap_rebind(&km, names[list.selected], hnoss.key_name(k)) }
				break
			}
		}

		// The help is drawn last, so while it is open its Esc comes first and
		// these see no keys.
		for action in hnoss.actions(ui, &km) {
			changed = true
			last = action
			switch action {
			case "down":   list.selected = min(list.selected + 1, len(names) - 1)
			case "up":     list.selected = max(list.selected - 1, 0)
			case "top":    list.selected = 0
			case "bottom": list.selected = len(names) - 1
			case "rebind": rebinding = true
			case "help":   help = true
			case "quit":   break loop
			}
		}

		area := hnoss.inset(f.area, 1)
		footer := hnoss.cut_bottom(&area, 1)
		rows := make([]string, len(names), context.temp_allocator)
		for name, i in names {
			rows[i] = fmt.tprintf("%-10s %s", name, hnoss.keymap_keys(&km, name))
		}
		inner := hnoss.box(ui, area, "Actions")
		hnoss.focus(ui, &list)
		hnoss.list(ui, inner, rows, &list)

		pending := hnoss.keymap_pending(&km)
		hnoss.status_bar(ui, footer, {
			mode  = "PRESS A KEY" if rebinding else "NORMAL",
			left  = {fmt.tprintf("last: %s", last)},
			right = {fmt.tprintf("%s …", pending) if pending != "" else "? help"},
		})

		if help {
			hints := hnoss.keymap_hints(&km)
			dialog := hnoss.modal(ui, hnoss.center(f.area, 48, len(hints) + 2), &help, "[b]Keys[/]")
			hnoss.key_help(ui, hnoss.pad(dialog, 0, 1, 0, 1), hints)
		}
		hnoss.end_frame(&term)
		free_all(context.temp_allocator)
		wait := 0 if changed || help != was_open else -1 // what that changed is drawn next frame
		events = hnoss.poll_events(&term, hnoss.keymap_timeout(&km, wait))
		if term.error != .None {
			break
		}
	}
}
