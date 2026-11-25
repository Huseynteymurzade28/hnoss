package widgets

import "core:fmt"
import "../buffer"
import "../layout"
import "../pen"
import "../style"

Stepper_State :: struct {
	current: int,  // the step being done; as many as there are steps when all are
	blocked: bool, // the current step was not valid when it was to be left
}

Stepper_Options :: struct {
	// What is wrong with a step, "" if nothing is: called when it is to be
	// left forward, and while it is blocked, to show the message as it is now.
	validate: proc(step: int, data: rawptr) -> string,
	data:     rawptr, // for validate
}

// The steps of a wizard in a row, "✓ Account ── ● Profile ── ○ Confirm":
// done, current and still to do. Titles are markup. When they don't fit,
// only the current one is shown, as "● 2/3 Profile".
//
// While focused, ← → go back and on and Home to the first step; so does a
// click on a step. Going on asks `opts.validate` about every step that is
// left; the first that isn't valid becomes the current one, marked ✗, with
// its message on the second row of `area` if there is one. Next and Back
// buttons call `stepper_next` and `stepper_back`. Returns true when
// `state.current` changed; with every step done it is len(steps).
stepper :: proc(ui: ^Ui, area: Rect, steps: []string, state: ^Stepper_State, opts := Stepper_Options{}) -> (changed: bool) {
	n := len(steps)
	if area.width <= 0 || area.height <= 0 || n == 0 {
		return false
	}
	old := state.current
	state.current = clamp(state.current, 0, n)
	row := Rect{area.x, area.y, area.width, 1}

	// Where each step is; compact is one step over the whole row.
	xs := make([]int, n, context.temp_allocator)
	x := row.x
	for s, i in steps {
		xs[i] = x
		x += 2 + markup_width(s) + STEP_GAP
	}
	compact := x - STEP_GAP > row.x + row.width
	step_rect :: proc(row: Rect, steps: []string, xs: []int, i: int) -> Rect {
		return {xs[i], row.y, 2 + markup_width(steps[i]), 1}
	}

	it: Key_Iter
	for k, i in next_key(ui, state, &it) {
		if k.mods != {} { continue }
		#partial switch k.code {
		case .Left:  stepper_back(state)
		case .Right: stepper_next(state, n, opts)
		case .Home:  stepper_go(state, 0, n, opts)
		case:        continue
		}
		consume(ui, i)
	}
	mit: Key_Iter
	for m, i in next_mouse(ui, nil, row, &mit) {
		if m.kind != .Press || m.button != .Left { continue }
		ui.mem.focus = state
		if !compact {
			for s in 0 ..< n {
				if layout.rect_contains(step_rect(row, steps, xs, s), m.x, m.y) {
					stepper_go(state, s, n, opts)
					break
				}
			}
		}
		consume(ui, i)
	}

	// The message as of now; none left: no longer blocked.
	message := ""
	if state.blocked {
		if opts.validate != nil && state.current < n {
			message = opts.validate(state.current, opts.data)
		}
		state.blocked = message != ""
	}

	px, py, hot := hover(ui, state, row)
	draw :: proc(ui: ^Ui, area: Rect, title: string, i: int, state: ^Stepper_State, lit: bool) {
		mark, mark_st, st := "○", ui.theme.muted, ui.theme.muted
		switch {
		case i < state.current:
			mark, mark_st, st = "✓", ui.theme.success, ui.theme.text
		case i == state.current:
			mark, mark_st, st = "●", ui.theme.accent, ui.theme.title
			if state.blocked { mark, mark_st = "✗", ui.theme.error }
			if focused(ui, state) { st = style.patch(st, ui.theme.accent) }
		}
		if lit { st = style.patch(st, ui.theme.hover) }
		p := pen.begin(ui.buf, area, .Ellipsis)
		pen.write(&p, mark, mark_st)
		pen.write(&p, " ")
		pen.markup(&p, title, st)
		pen.finish(&p)
	}
	if compact {
		i := min(state.current, n - 1)
		draw(ui, row, fmt.tprintf("%d/%d %s", i + 1, n, steps[i]), i, state, false)
	} else {
		for s, i in steps {
			r := step_rect(row, steps, xs, i)
			draw(ui, r, s, i, state, hot && layout.rect_contains(r, px, py))
			if i < n - 1 {
				st := ui.theme.success if i < state.current else ui.theme.muted
				buffer.set_string(ui.buf, r.x + r.width + 1, row.y, "──", st)
			}
		}
	}
	if message != "" && area.height > 1 {
		buffer.set_string(ui.buf, area.x, area.y + 1, message, ui.theme.error, area.width)
	}
	return state.current != old
}

// Goes on from the current step if it is valid, past the last one when it
// is the last. Returns false, and blocks, if it is not.
stepper_next :: proc(state: ^Stepper_State, count: int, opts := Stepper_Options{}) -> (moved: bool) {
	if state.current >= count { return false }
	if opts.validate != nil && opts.validate(state.current, opts.data) != "" {
		state.blocked = true
		return false
	}
	state.current += 1
	state.blocked = false
	return true
}

// Goes back one step, whatever the state of the current one.
stepper_back :: proc(state: ^Stepper_State) -> (moved: bool) {
	if state.current <= 0 { return false }
	state.current -= 1
	state.blocked = false
	return true
}

// Goes to `step`: straight back, or on as far as the steps are valid.
stepper_go :: proc(state: ^Stepper_State, step, count: int, opts := Stepper_Options{}) -> (there: bool) {
	if step < state.current {
		state.current = max(step, 0)
		state.blocked = false
	}
	for state.current < min(step, count) {
		stepper_next(state, count, opts) or_return
	}
	return true
}

// " ── " between two steps.
@(private)
STEP_GAP :: 4
