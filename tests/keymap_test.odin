package tests

import "core:testing"
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
