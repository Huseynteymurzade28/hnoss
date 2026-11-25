package input

import "core:strings"
import "core:unicode"
import "core:unicode/utf8"

// Keys written as text: "q", "G", "Ctrl+S", "Alt+Enter", "Shift+Tab", "F5",
// "PgUp", "Space", "Ctrl++".

@(private, rodata)
KEY_NAMES := [Key_Code]string {
	.None      = "",
	.Char      = "",
	.Enter     = "Enter",
	.Tab       = "Tab",
	.Back_Tab  = "Shift+Tab",
	.Backspace = "Backspace",
	.Esc       = "Esc",
	.Up        = "Up",
	.Down      = "Down",
	.Left      = "Left",
	.Right     = "Right",
	.Home      = "Home",
	.End       = "End",
	.Page_Up   = "PgUp",
	.Page_Down = "PgDn",
	.Insert    = "Insert",
	.Delete    = "Delete",
	.F1        = "F1",
	.F2        = "F2",
	.F3        = "F3",
	.F4        = "F4",
	.F5        = "F5",
	.F6        = "F6",
	.F7        = "F7",
	.F8        = "F8",
	.F9        = "F9",
	.F10       = "F10",
	.F11       = "F11",
	.F12       = "F12",
}

// Reads one key: modifiers (Ctrl, Alt, Shift, Super) and then a character
// or a key's name, joined by '+'. Names and modifiers are read in any case,
// but "g" and "G" are different keys. The result is the Key the parser
// reports for it (see normalize_key).
parse_key :: proc(s: string) -> (k: Key, ok: bool) {
	rest := s
	for {
		i := strings.index_byte(rest, '+')
		if i <= 0 { break } // a '+' at the start is the key itself
		mod: Key_Modifier
		name := rest[:i]
		switch {
		case strings.equal_fold(name, "ctrl"):  mod = .Ctrl
		case strings.equal_fold(name, "alt"):   mod = .Alt
		case strings.equal_fold(name, "shift"): mod = .Shift
		case strings.equal_fold(name, "super"): mod = .Super
		case: return {}, false
		}
		if mod in k.mods { return {}, false }
		k.mods += {mod}
		rest = rest[i + 1:]
	}
	r, n := utf8.decode_rune(rest)
	switch {
	case rest == "":
		return {}, false
	case n == len(rest):
		if r == utf8.RUNE_ERROR || r <= ' ' || r == 0x7f { return {}, false }
		k.code, k.char = .Char, r
	case strings.equal_fold(rest, "space"):
		k.code, k.char = .Char, ' '
	case:
		for name, code in KEY_NAMES {
			if name != "" && strings.equal_fold(rest, name) { k.code = code }
		}
		if k.code == .None { return {}, false }
	}
	return normalize_key(k), true
}

// The one form of a key that terminals report in several: Ctrl+letter has
// the lowercase letter, a letter with Shift is the uppercase one without
// it, Shift+Tab is .Back_Tab.
normalize_key :: proc(k: Key) -> Key {
	k := k
	#partial switch k.code {
	case .Char:
		switch {
		case .Ctrl in k.mods:
			k.char = unicode.to_lower(k.char)
		case .Shift in k.mods && unicode.is_letter(k.char):
			k.char = unicode.to_upper(k.char)
			k.mods -= {.Shift}
		}
	case .Tab:
		if .Shift in k.mods { k.code = .Back_Tab }
	}
	if k.code == .Back_Tab { k.mods += {.Shift} }
	return k
}

// The text parse_key reads back as `k`, e.g. "Ctrl+S".
key_name :: proc(k: Key, allocator := context.temp_allocator) -> string {
	k := k
	k = normalize_key(k)
	sb := strings.builder_make(allocator)
	if .Ctrl in k.mods { strings.write_string(&sb, "Ctrl+") }
	if .Alt in k.mods { strings.write_string(&sb, "Alt+") }
	if .Super in k.mods { strings.write_string(&sb, "Super+") }
	if .Shift in k.mods && k.code != .Back_Tab { strings.write_string(&sb, "Shift+") }
	switch {
	case k.code != .Char:  strings.write_string(&sb, KEY_NAMES[k.code])
	case k.char == ' ':    strings.write_string(&sb, "Space")
	case .Ctrl in k.mods:  strings.write_rune(&sb, unicode.to_upper(k.char))
	case:                  strings.write_rune(&sb, k.char)
	}
	return strings.to_string(sb)
}
