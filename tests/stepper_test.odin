package tests

import "core:testing"
import "../widgets"

@(private = "file")
Wizard :: struct {
	steps:   widgets.Stepper_State,
	name:    string,
	age:     int,
	changed: bool, // in the last frame
}

@(private = "file")
TITLES := []string{"Name", "Age", "[b]Done[/]"}

@(private = "file")
options :: proc(w: ^Wizard) -> widgets.Stepper_Options {
	return {
		validate = proc(step: int, data: rawptr) -> string {
			w := (^Wizard)(data)
			switch step {
			case 0: return "" if w.name != "" else "a name is required"
			case 1: return "" if w.age >= 18 else "too young"
			}
			return ""
		},
		data = w,
	}
}

@(private = "file")
draw :: proc(ui: ^widgets.Ui, w: ^Wizard) {
	w.changed = widgets.stepper(ui, ui.area, TITLES, &w.steps, options(w))
}

@(test)
stepper_blocks_on_an_invalid_step :: proc(t: ^testing.T) {
	w: Wizard
	d := driver(30, 2)
	widgets.focus(&widgets.Ui{mem = &d.mem}, &w.steps)

	drive(t, d, "", &w, draw)
	expect_screen(t, &d.buf, "● Name ── ○ Age ── ○ Done")
	drive(t, d, "Right", &w, draw)
	testing.expect(t, !w.changed && w.steps.blocked)
	expect_screen(t, &d.buf, `
		✗ Name ── ○ Age ── ○ Done
		a name is required
	`)

	w.name = "Huso" // fixed: the message goes by itself
	drive(t, d, "", &w, draw)
	testing.expect(t, !w.steps.blocked)
	expect_screen(t, &d.buf, "● Name ── ○ Age ── ○ Done")

	drive(t, d, "Right", &w, draw)
	testing.expect(t, w.changed)
	expect_screen(t, &d.buf, "✓ Name ── ● Age ── ○ Done")
	drive(t, d, "Right Left", &w, draw) // back is always possible
	testing.expect_value(t, w.steps.current, 0)
	testing.expect(t, !w.steps.blocked)

	w.age = 30
	drive(t, d, "Right Right Right Right", &w, draw)
	testing.expect_value(t, w.steps.current, 3)
	expect_screen(t, &d.buf, "✓ Name ── ✓ Age ── ✓ Done")
	drive(t, d, "Home", &w, draw)
	testing.expect_value(t, w.steps.current, 0)
}

@(test)
stepper_clicks :: proc(t: ^testing.T) {
	w := Wizard{name = "Huso"}
	d := driver(30, 2)
	drive(t, d, "click:20,0", &w, draw) // the last: stops at the first invalid one
	testing.expect_value(t, w.steps.current, 1)
	testing.expect(t, w.steps.blocked)
	expect_screen(t, &d.buf, `
		✓ Name ── ✗ Age ── ○ Done
		too young
	`)
	drive(t, d, "click:8,0", &w, draw) // between steps
	testing.expect_value(t, w.steps.current, 1)
	drive(t, d, "click:0,0", &w, draw)
	testing.expect_value(t, w.steps.current, 0)
	testing.expect(t, w.changed)
}

@(test)
stepper_without_room :: proc(t: ^testing.T) {
	w := Wizard{name = "Huso"}
	d := driver(25, 1)
	drive(t, d, "", &w, draw) // just fits
	expect_screen(t, &d.buf, "● Name ── ○ Age ── ○ Done")
	d = driver(24, 1)
	drive(t, d, "", &w, draw)
	expect_screen(t, &d.buf, "● 1/3 Name")
	w.steps.current = 3
	drive(t, d, "", &w, draw)
	expect_screen(t, &d.buf, "✓ 3/3 Done")
	d = driver(6, 1)
	drive(t, d, "", &w, draw)
	expect_screen(t, &d.buf, "✓ 3/3…")
	w.steps.current = 99 // out of range
	drive(t, d, "", &w, draw)
	testing.expect_value(t, w.steps.current, 3)
}

@(test)
stepper_next_and_back :: proc(t: ^testing.T) {
	s: widgets.Stepper_State
	testing.expect(t, !widgets.stepper_back(&s))
	testing.expect(t, widgets.stepper_next(&s, 2)) // nothing to validate
	testing.expect(t, widgets.stepper_go(&s, 2, 2))
	testing.expect(t, !widgets.stepper_next(&s, 2))
	testing.expect_value(t, s.current, 2)
}
