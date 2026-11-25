package tests

import "core:strings"
import "core:testing"
import "core:time"
import "../input"

@(test)
key_names_parse :: proc(t: ^testing.T) {
	cases := []struct {
		text: string,
		want: input.Key,
	} {
		{"q", {code = .Char, char = 'q'}},
		{"G", {code = .Char, char = 'G'}},
		{"ə", {code = .Char, char = 'ə'}},
		{"+", {code = .Char, char = '+'}},
		{"Ctrl++", {code = .Char, char = '+', mods = {.Ctrl}}},
		{"Space", {code = .Char, char = ' '}},
		{"Ctrl+S", {code = .Char, char = 's', mods = {.Ctrl}}},
		{"ctrl+s", {code = .Char, char = 's', mods = {.Ctrl}}},
		{"Ctrl+Shift+k", {code = .Char, char = 'k', mods = {.Ctrl, .Shift}}},
		{"Shift+g", {code = .Char, char = 'G'}},
		{"Alt+x", {code = .Char, char = 'x', mods = {.Alt}}},
		{"Shift+Tab", {code = .Back_Tab, mods = {.Shift}}},
		{"Alt+Enter", {code = .Enter, mods = {.Alt}}},
		{"pgdn", {code = .Page_Down}},
		{"Super+F12", {code = .F12, mods = {.Super}}},
	}
	for c in cases {
		k, ok := input.parse_key(c.text)
		testing.expectf(t, ok && k == c.want, "%q: %v %v, want %v", c.text, k, ok, c.want)
	}
	for bad in ([]string{"", "Ctrl+", "Hyper+x", "Ctrl+Ctrl+x", "gg", " ", "\x1b", "F13"}) {
		_, ok := input.parse_key(bad)
		testing.expectf(t, !ok, "%q parsed", bad)
	}
}

@(test)
key_names_round_trip :: proc(t: ^testing.T) {
	for name in ([]string{"q", "G", "+", "Ctrl++", "Space", "Ctrl+S", "Ctrl+Shift+K", "Alt+x", "Alt+X", "Shift+Tab", "Ctrl+Shift+Tab", "Shift+Up", "PgUp", "F5", "Ctrl+Alt+Super+Delete"}) {
		k, ok := input.parse_key(name)
		testing.expect(t, ok)
		again, _ := input.parse_key(input.key_name(k))
		testing.expectf(t, again == k, "%q: %q reads back as %v", name, input.key_name(k), again)
	}
	k, _ := input.parse_key("ctrl+pgup")
	testing.expect_value(t, input.key_name(k), "Ctrl+PgUp")
	k, _ = input.parse_key("ctrl+s")
	testing.expect_value(t, input.key_name(k), "Ctrl+S")
}

@(private = "file")
BINDINGS := []input.Binding {
	{"", "", "Moving"},
	{"g", "go", "go somewhere"},
	{"g g", "top", "first line"},
	{"G", "bottom", "last line"},
	{"", "", "File"},
	{"Ctrl+S", "save", "save"},
	{"F2", "save", ""},
	{"Ctrl+K Ctrl+S", "save_all", "save everything"},
}

@(private = "file")
keymap :: proc(t: ^testing.T) -> (km: input.Keymap) {
	testing.expect_value(t, input.keymap_init(&km, BINDINGS, context.temp_allocator), -1)
	return
}

// Types `keys` (a chord's syntax, any length), one every `gap`, and returns
// the actions joined by spaces.
@(private = "file")
typed :: proc(km: ^input.Keymap, keys: string, gap: time.Duration = 0) -> string {
	out := make([dynamic]string, context.temp_allocator)
	now := time.Tick{1}
	for word in strings.fields(keys, context.temp_allocator) {
		k, _ := input.parse_key(word)
		input.keymap_feed(km, k, now, &out)
		now._nsec += i64(gap)
	}
	return strings.join(out[:], " ", context.temp_allocator)
}

@(test)
keymap_single_keys_and_chords :: proc(t: ^testing.T) {
	km := keymap(t)
	testing.expect_value(t, typed(&km, "G"), "bottom")
	testing.expect_value(t, typed(&km, "Ctrl+S F2"), "save save")
	testing.expect_value(t, typed(&km, "g g"), "top")
	testing.expect_value(t, typed(&km, "g g g g"), "top top")
	testing.expect_value(t, typed(&km, "Ctrl+K Ctrl+S"), "save_all")
	testing.expect_value(t, typed(&km, "x"), "")
	testing.expect_value(t, km.pending.len, 0)
}

@(test)
keymap_broken_chords :: proc(t: ^testing.T) {
	km := keymap(t)
	testing.expect_value(t, typed(&km, "g G"), "go bottom") // g alone, then G afresh
	testing.expect_value(t, typed(&km, "Ctrl+K G"), "bottom") // Ctrl+K alone means nothing
	testing.expect_value(t, typed(&km, "Ctrl+K Ctrl+K Ctrl+S"), "save_all")
	testing.expect_value(t, typed(&km, "Ctrl+K Esc Ctrl+S"), "save")

	// Esc is used up by the chord it cancels, and only then.
	out := make([dynamic]string, context.temp_allocator)
	esc := input.Key{code = .Esc}
	typed(&km, "Ctrl+K")
	testing.expect_value(t, input.keymap_pending(&km), "Ctrl+K")
	testing.expect(t, input.keymap_feed(&km, esc, time.Tick{1}, &out))
	testing.expect(t, !input.keymap_feed(&km, esc, time.Tick{1}, &out))
	testing.expect_value(t, len(out), 0)
}

@(test)
keymap_chord_timeout :: proc(t: ^testing.T) {
	km := keymap(t)
	testing.expect_value(t, typed(&km, "g g", 2 * time.Second), "go") // the second g waits again
	testing.expect_value(t, input.keymap_pending(&km), "g")

	out := make([dynamic]string, context.temp_allocator)
	km.at = {1}
	left, waiting := input.keymap_waiting(&km, {1 + i64(400 * time.Millisecond)})
	testing.expect(t, waiting)
	testing.expect_value(t, left, 600 * time.Millisecond)
	input.keymap_expire(&km, {1 + i64(400 * time.Millisecond)}, &out)
	testing.expect_value(t, len(out), 0)
	input.keymap_expire(&km, {1 + i64(time.Second)}, &out)
	testing.expect_value(t, len(out), 1)
	_, waiting = input.keymap_waiting(&km, {})
	testing.expect(t, !waiting)

	km.timeout = -1
	testing.expect_value(t, typed(&km, "g g", time.Hour), "top")
}

@(test)
keymap_matches_keys_as_terminals_send_them :: proc(t: ^testing.T) {
	km := keymap(t)
	input.keymap_bind(&km, {"Shift+Tab", "back", ""})
	out := make([dynamic]string, context.temp_allocator)
	for k in ([]input.Key{{.Back_Tab, 0, {}}, {.Back_Tab, 0, {.Shift}}, {.Tab, 0, {.Shift}}, {.Char, 'G', {.Shift}}, {.Char, 'G', {}}}) {
		input.keymap_feed(&km, k, {1}, &out)
	}
	testing.expect_value(t, strings.join(out[:], " ", context.temp_allocator), "back back back bottom bottom")
}

@(test)
keymap_rebinding :: proc(t: ^testing.T) {
	km := keymap(t)
	testing.expect_value(t, input.keymap_keys(&km, "save"), "Ctrl+S, F2")
	testing.expect(t, input.keymap_rebind(&km, "save", "Ctrl+W"))
	testing.expect_value(t, input.keymap_keys(&km, "save"), "Ctrl+W")
	testing.expect_value(t, typed(&km, "Ctrl+S Ctrl+W"), "save")

	// Keys taken from another action leave it without any.
	testing.expect(t, input.keymap_rebind(&km, "save", "G"))
	testing.expect_value(t, input.keymap_lookup(&km, "G"), "save")
	testing.expect_value(t, input.keymap_keys(&km, "bottom"), "")
	testing.expect(t, input.keymap_rebind(&km, "bottom", "End"))
	testing.expect_value(t, typed(&km, "End"), "bottom")

	testing.expect(t, !input.keymap_rebind(&km, "nothing", "x"))
	testing.expect(t, !input.keymap_rebind(&km, "save", "Hyper+x"))
	testing.expect_value(t, input.keymap_keys(&km, "save"), "G") // unchanged

	testing.expect(t, input.keymap_unbind(&km, "g g"))
	testing.expect(t, !input.keymap_unbind(&km, "g g"))
	testing.expect_value(t, typed(&km, "g"), "go") // nothing to wait for now
}

@(test)
keymap_reports_bad_bindings :: proc(t: ^testing.T) {
	km: input.Keymap
	bad := input.keymap_init(&km, {{"a", "one", ""}, {"Ctrl+", "two", ""}, {"a b c d e", "three", ""}, {"b", "four", ""}}, context.temp_allocator)
	testing.expect_value(t, bad, 1)
	testing.expect_value(t, typed(&km, "a b"), "one four")
}
