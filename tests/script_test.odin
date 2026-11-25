package tests

import "core:strings"
import "core:testing"
import "../input"

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
