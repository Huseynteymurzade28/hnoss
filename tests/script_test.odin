package tests

import "core:strings"
import "core:testing"
import "../input"
import "../widgets"

@(private = "file")
expect_script :: proc(t: ^testing.T, script: string, want: ..[]input.Event, loc := #caller_location) {
	got, err := parse_script(script)
	testing.expectf(t, err == "", "%s: %s", script, err, loc = loc)
	if !testing.expectf(t, len(got) == len(want), "%s: %d frames, want %d", script, len(got), len(want), loc = loc) { return }
	for frame, i in want {
		same := len(got[i]) == len(frame)
		for ev, j in frame { same = same && got[i][j] == ev }
		testing.expectf(t, same, "%s: frame %d is %v, want %v", script, i, got[i], frame, loc = loc)
	}
}

@(private = "file")
ch :: proc(r: rune, mods: input.Key_Modifiers = {}) -> input.Event {
	return input.Key{code = .Char, char = r, mods = mods}
}

@(test)
script_steps :: proc(t: ^testing.T) {
	down := input.Event(input.Key{code = .Down})
	expect_script(t, "", {})
	expect_script(t, "Down Ctrl+S", {down, ch('s', {.Ctrl})})
	expect_script(t, `"a ö"`, {ch('a'), ch(' '), ch('ö')})
	expect_script(t, `"\"\\"`, {ch('"'), ch('\\')})
	expect_script(t, `:`, {ch(':')})
	expect_script(t, `paste:"two | words"`, {input.Paste{"two | words"}})
	expect_script(t, "press:4,2 drag:6,3", {
		input.Mouse{kind = .Press, button = .Left, x = 4, y = 2, clicks = 1},
		input.Mouse{kind = .Drag, button = .Left, x = 6, y = 3},
	})
	frames, _ := parse_script("double-click:1,0")
	testing.expect_value(t, len(frames[0]), 4)
	testing.expect_value(t, frames[0][2].(input.Mouse).clicks, 2)
	expect_script(t, "focus-out resize:80x24", {input.Focus{false}, input.Resize{80, 24}})
}

@(test)
script_frames :: proc(t: ^testing.T) {
	a, b := ch('a'), ch('b')
	expect_script(t, "a | b", {a}, {b})
	expect_script(t, "a|b", {a}, {b})
	expect_script(t, "a || b", {a}, {}, {b})
	expect_script(t, `a "|" | b`, {a, ch('|')}, {b})
	expect_script(t, `
		a

		b
	`, {a}, {b})
	expect_script(t, "a |\n | b", {a}, {}, {b})
	expect_script(t, "a\n| b", {a}, {b})
	expect_script(t, "a |\nb", {a}, {b})
}

@(test)
script_errors :: proc(t: ^testing.T) {
	for bad in ([]string{`"open`, `"a"b"`, "nonsense", "click:1", "click:a,b", "fly:1,2", "resize:0x4", "paste:x", `"a\`}) {
		_, err := parse_script(bad)
		testing.expectf(t, err != "", "%s parsed", bad)
		testing.expect(t, !strings.contains(err, "\n"))
	}
}

@(private = "file")
Form :: struct {
	name:   widgets.Input_State,
	agree:  bool,
	submit: widgets.Button_State,
	sure:   bool, // the dialog is open
	yes:    widgets.Button_State,
	sent:   int,
}

@(private = "file")
draw_form :: proc(ui: ^widgets.Ui, f: ^Form) {
	if !f.sure { widgets.focus_order(ui, {&f.name, &f.agree, &f.submit}) }
	widgets.input(ui, {0, 0, 20, 1}, &f.name)
	widgets.checkbox(ui, {0, 1, 20, 1}, "agree", &f.agree)
	if widgets.button(ui, {0, 2, 8, 1}, "Send", &f.submit) { f.sure = f.agree }
	if f.sure {
		inner := widgets.modal(ui, {4, 0, 12, 3}, &f.sure, "Sure?")
		widgets.focus(ui, &f.yes)
		if widgets.button(ui, inner, "Yes", &f.yes) {
			f.sent += 1
			f.sure = false
		}
	}
}

@(test)
script_drives_a_form_with_the_keyboard :: proc(t: ^testing.T) {
	f: Form
	defer widgets.input_destroy(&f.name)
	d := driver(20, 3)

	drive(t, d, `"Huso" | Left Left "s" paste:"yn"`, &f, draw_form)
	expect_screen(t, &d.buf, `
		Husynso
		[ ] agree
		  Send
	`)
	drive(t, d, "Tab Tab | Enter", &f, draw_form) // not agreed: nothing
	testing.expect(t, !f.sure)
	drive(t, d, "Shift+Tab | Space | Tab | Enter |", &f, draw_form)
	testing.expect(t, f.sure)
	expect_screen(t, &d.buf, `
		Husy╭ Sure? ───╮
		[✓] │   Yes    │
		  Se╰──────────╯
	`)
	drive(t, d, "Esc", &f, draw_form)
	testing.expect(t, !f.sure)
	testing.expect_value(t, f.sent, 0)
}

@(test)
script_drives_a_form_with_the_mouse :: proc(t: ^testing.T) {
	f: Form
	defer widgets.input_destroy(&f.name)
	d := driver(20, 3)

	drive(t, d, `click:1,1 | press:3,2 | drag:15,0 | release:15,0`, &f, draw_form) // dragged off the button
	testing.expect(t, f.agree && !f.sure)
	drive(t, d, "click:3,2 | | click:0,0", &f, draw_form) // the press outside closes the dialog
	testing.expect(t, !f.sure)
	drive(t, d, "click:3,2 | | click:9,1", &f, draw_form)
	testing.expect_value(t, f.sent, 1)
}
