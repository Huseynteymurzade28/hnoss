// The built-in themes on a handful of widgets: tabs, a list, a gauge, a
// slider, a field, a checkbox and buttons.
//   t  next theme    Tab  move focus    q / Esc  quit
package main

import "core:fmt"
import "core:os"
import hnoss "../.."
import "../../backend"

Preset :: struct {
	name:  string,
	theme: hnoss.Theme,
}

PRESETS :: [?]Preset{
	{"Default", hnoss.DEFAULT_THEME},
	{"Light", hnoss.LIGHT_THEME},
	{"High contrast", hnoss.HIGH_CONTRAST_THEME},
	{"Odlar Yurdu", hnoss.ODLAR_YURDU_THEME},
	{"Xəzər", hnoss.XEZER_THEME},
}

main :: proc() {
	context.assertion_failure_proc = backend.assertion_failure_proc

	term, err := hnoss.init(hnoss.DEFAULT_OPTIONS + {.Mouse_Capture})
	if err != .None {
		fmt.eprintfln("hnoss: init failed: %v", err)
		os.exit(1)
	}
	defer hnoss.deinit(&term)

	presets := PRESETS
	current := 0
	tab := 0
	cities: hnoss.List_State
	cities.selected = 2
	search: hnoss.Input_State
	defer hnoss.input_destroy(&search)
	hnoss.input_set(&search, "Şəki")
	volume := 70.0
	offline := true
	ok, cancel: hnoss.Button_State
	names := []string{"Bakı", "Gəncə", "Şəki", "Lənkəran", "Quba"}

	events: []hnoss.Event
	loop: for {
		f := hnoss.begin_frame(&term)
		ui := hnoss.ui(f, events, presets[current].theme)
		hnoss.focus_order(ui, {&cities, &search, &volume, &offline, &ok, &cancel})

		area := hnoss.inset(f.area, 1)
		hnoss.key_hints(ui, hnoss.cut_bottom(&area, 1), {{"t", "next theme"}, {"Tab", "focus"}, {"q", "quit"}})
		inner := hnoss.box(ui, area, fmt.tprintf("[b]%s[/]", presets[current].name), {focused = true})
		hnoss.tabs(ui, hnoss.cut_top(&inner, 1), {"Cities", "Weather", "About"}, &tab)
		hnoss.cut_top(&inner, 1)

		cols := hnoss.split(inner, .Horizontal, {16, hnoss.fill()}, gap = 2)
		list := hnoss.box(ui, cols[0], "Cities", {focused = hnoss.focused(ui, &cities)})
		hnoss.list(ui, list, names, &cities)

		right := cols[1]
		hnoss.input(ui, hnoss.cut_top(&right, 1), &search, {placeholder = "search…"})
		hnoss.cut_top(&right, 1)
		hnoss.gauge(ui, hnoss.cut_top(&right, 1), 0.62, "rain 62%")
		hnoss.cut_top(&right, 1)
		hnoss.slider(ui, hnoss.cut_top(&right, 1), &volume, 0, 100, {step = 5, show_value = true})
		hnoss.cut_top(&right, 1)
		hnoss.checkbox(ui, hnoss.cut_top(&right, 1), "Offline maps", &offline)
		hnoss.cut_top(&right, 1)
		buttons := hnoss.split(hnoss.cut_top(&right, 1), .Horizontal, {hnoss.fill(), hnoss.fill()}, gap = 2)
		hnoss.button(ui, buttons[0], "OK", &ok)
		hnoss.button(ui, buttons[1], "Cancel", &cancel)

		redraw := false // the theme applies from the next frame: draw it right away
		for ev in hnoss.unhandled(ui) {
			switch {
			case hnoss.is_char(ev, 't'):
				current = (current + 1) % len(presets)
				redraw = true
			case hnoss.is_char(ev, 'q') || hnoss.is_key(ev, .Esc) || hnoss.is_char(ev, 'c', {.Ctrl}):
				break loop
			}
		}
		hnoss.end_frame(&term)
		free_all(context.temp_allocator)
		events = hnoss.poll_events(&term, 0 if redraw else -1)
		if term.error != .None {
			break
		}
	}
}
