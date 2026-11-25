// Widget example: stepper. A form in three steps; Next is blocked until the
// step is filled in. Click a step, or Tab to the steps and use ← →.
//   Enter        in a field: next step
//   Esc / Ctrl+C quit
package main

import "core:fmt"
import "core:os"
import "core:strings"
import hnoss "../.."
import "../../backend"

Form :: struct {
	steps: hnoss.Stepper_State,
	name:  hnoss.Input_State,
	email: hnoss.Input_State,
	plan:  int,
	terms: bool,
	back, next: hnoss.Button_State,
}

STEPS := []string{"Account", "Plan", "Confirm"}
PLANS := []string{"Free", "Team", "Company"}

validate :: proc(step: int, data: rawptr) -> string {
	form := (^Form)(data)
	switch step {
	case 0:
		if hnoss.input_text(&form.name) == "" { return "Your name is missing." }
		if !strings.contains(hnoss.input_text(&form.email), "@") { return "That is not an email address." }
	case 2:
		if !form.terms { return "Accept the terms first." }
	}
	return ""
}

main :: proc() {
	context.assertion_failure_proc = backend.assertion_failure_proc

	term, err := hnoss.init(hnoss.DEFAULT_OPTIONS + {.Mouse_Capture})
	if err != .None {
		fmt.eprintfln("hnoss: init failed: %v", err)
		os.exit(1)
	}
	defer hnoss.deinit(&term)

	form: Form
	defer hnoss.input_destroy(&form.name)
	defer hnoss.input_destroy(&form.email)
	opts := hnoss.Stepper_Options{validate = validate, data = &form}

	events: []hnoss.Event
	loop: for {
		before := form.steps
		f := hnoss.begin_frame(&term)
		ui := hnoss.ui(f, events)
		area := hnoss.box(ui, hnoss.center(f.area, 50, 12), "Sign up")
		area = hnoss.pad(area, 0, 1, 0, 1)

		buttons := hnoss.cut_bottom(&area, 1)
		hnoss.cut_bottom(&area, 1)
		head := hnoss.cut_top(&area, 3)
		done := form.steps.current >= len(STEPS)
		switch form.steps.current {
		case 0: hnoss.focus_order(ui, {&form.name, &form.email, &form.next, &form.steps})
		case 1: hnoss.focus_order(ui, {&form.plan, &form.back, &form.next, &form.steps})
		case 2: hnoss.focus_order(ui, {&form.terms, &form.back, &form.next, &form.steps})
		case:   hnoss.focus_order(ui, {&form.back})
		}

		// The step it was when the focus order was set.
		switch before.current {
		case 0:
			hnoss.label(ui, hnoss.cut_top(&area, 1), "[dim]Name[/]")
			hnoss.input(ui, hnoss.cut_top(&area, 1), &form.name, {placeholder = "Hüseyn"})
			hnoss.label(ui, hnoss.cut_top(&area, 1), "[dim]Email[/]")
			hnoss.input(ui, hnoss.cut_top(&area, 1), &form.email, {placeholder = "name@example.com"})
			if form.name.submitted || form.email.submitted { hnoss.stepper_next(&form.steps, len(STEPS), opts) }
		case 1:
			hnoss.radio(ui, area, PLANS, &form.plan)
		case 2:
			hnoss.label(ui, hnoss.cut_top(&area, 2), fmt.tprintf("%s, %s plan", hnoss.input_text(&form.name), PLANS[form.plan]))
			hnoss.checkbox(ui, hnoss.cut_top(&area, 1), "I accept the terms", &form.terms)
		case:
			hnoss.label(ui, area, "Welcome aboard!")
		}

		back := hnoss.cut_left(&buttons, 10)
		next := hnoss.cut_right(&buttons, 10)
		if before.current > 0 && hnoss.button(ui, back, "Back", &form.back) { hnoss.stepper_back(&form.steps) }
		if !done && hnoss.button(ui, next, "Finish" if before.current == 2 else "Next", &form.next) {
			hnoss.stepper_next(&form.steps, len(STEPS), opts)
		}

		// After the fields, so its message is about what they hold now.
		hnoss.stepper(ui, head, STEPS, &form.steps, opts)

		for ev in hnoss.unhandled(ui) {
			if hnoss.is_key(ev, .Esc) || hnoss.is_char(ev, 'c', {.Ctrl}) || (done && hnoss.is_char(ev, 'q')) {
				break loop
			}
		}
		hnoss.end_frame(&term)
		free_all(context.temp_allocator)
		// Another step is drawn next frame.
		events = hnoss.poll_events(&term, 0 if form.steps != before else -1)
		if term.error != .None {
			break
		}
	}
}
