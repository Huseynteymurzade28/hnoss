// hnoss monitor: a live system monitor built from hnoss widgets.
//
//   t          next theme (Odlar Yurdu · Xəzər · Aurora · Mono)
//   c m p n    sort processes by cpu / memory / pid / name, r reverses
//   /          filter processes (Enter or Esc to leave the field)
//   ↑↓ PgUp    move in the process table, mouse works everywhere
//   + -        sample faster / slower, space pauses
//   q          quit
package main

import "core:fmt"
import "core:os"
import "core:time"
import "core:time/datetime"
import "core:time/timezone"
import hnoss "../.."
import "../../backend"

App :: struct {
	sys:          System,
	themes:       [4]Palette,
	theme:        int,
	table:        hnoss.Table_State,
	search:       hnoss.Input_State,
	selected_pid: int,
	sort:         Sort_Key,
	reverse:      bool,
	paused:       bool,
	interval:     time.Duration, // between system samples; processes every 3rd
	tz:           ^datetime.TZ_Region,
	dirty:        bool, // a key changed something: redraw right away
}

main :: proc() {
	context.assertion_failure_proc = backend.assertion_failure_proc

	app: App
	app.themes = palettes()
	app.interval = 500 * time.Millisecond
	app.tz, _ = timezone.region_load("local")
	defer timezone.region_destroy(app.tz)
	system_init(&app.sys)
	defer system_destroy(&app.sys)
	defer hnoss.input_destroy(&app.search)

	term, err := hnoss.init(hnoss.DEFAULT_OPTIONS + {.Mouse_Capture})
	if err != .None {
		fmt.eprintfln("hnoss: init failed: %v", err)
		os.exit(1)
	}
	defer hnoss.deinit(&term)

	next_sample := time.tick_now()
	ticks := 0
	events: []hnoss.Event
	loop: for {
		if time.tick_diff(next_sample, time.tick_now()) >= 0 {
			if !app.paused {
				sample_system(&app.sys)
				if ticks % 3 == 0 { sample_procs(&app.sys) }
				ticks += 1
			}
			next_sample = time.tick_add(next_sample, app.interval)
			if time.tick_diff(next_sample, time.tick_now()) > 0 {
				next_sample = time.tick_add(time.tick_now(), app.interval) // fell behind: don't burst
			}
		}

		f := hnoss.begin_frame(&term)
		pal := &app.themes[app.theme]
		ui := hnoss.ui(f, events, pal.ui)
		if !draw(ui, f, &app) {
			break
		}
		hnoss.end_frame(&term)
		free_all(context.temp_allocator)

		// App keys are handled after the widgets drew this frame, so if one
		// changed something, draw again now instead of at the next sample.
		wait := time.tick_diff(time.tick_now(), next_sample)
		timeout := 0 if app.dirty else max(int(wait / time.Millisecond), 0) + 1
		app.dirty = false
		events = hnoss.poll_events(&term, timeout)
		if term.error != .None {
			break loop
		}
	}
}

// App-level keys, after the widgets had their turn. Returns false to quit.
handle_keys :: proc(ui: ^hnoss.Ui, app: ^App) -> bool {
	searching := hnoss.focused(ui, &app.search)
	for ev in hnoss.unhandled(ui) {
		k, is_key := ev.(hnoss.Key)
		if !is_key { continue }
		if searching {
			if k.code == .Esc || k.code == .Enter {
				if k.code == .Esc { hnoss.input_set(&app.search, "") }
				hnoss.focus(ui, &app.table)
				app.dirty = true
			}
			continue
		}
		app.dirty = true
		switch {
		case hnoss.is_char(ev, 'q'), hnoss.is_char(ev, 'c', {.Ctrl}):
			return false
		case hnoss.is_char(ev, 't'):
			app.theme = (app.theme + 1) % len(app.themes)
		case hnoss.is_char(ev, 'c'): set_sort(app, .Cpu)
		case hnoss.is_char(ev, 'm'): set_sort(app, .Mem)
		case hnoss.is_char(ev, 'p'): set_sort(app, .Pid)
		case hnoss.is_char(ev, 'n'): set_sort(app, .Name)
		case hnoss.is_char(ev, 'r'): app.reverse = !app.reverse
		case hnoss.is_char(ev, ' '): app.paused = !app.paused
		case hnoss.is_char(ev, '+'), hnoss.is_char(ev, '='):
			app.interval = max(app.interval / 2, 125 * time.Millisecond)
		case hnoss.is_char(ev, '-'):
			app.interval = min(app.interval * 2, 4 * time.Second)
		case k.code == .Esc:
			hnoss.input_set(&app.search, "")
		}
	}
	return true
}

set_sort :: proc(app: ^App, key: Sort_Key) {
	if app.sort == key {
		app.reverse = !app.reverse
	} else {
		app.sort, app.reverse = key, false
	}
}
