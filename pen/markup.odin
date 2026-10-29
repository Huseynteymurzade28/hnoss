package pen

import "core:strconv"
import "core:strings"
import "../style"

// Writes `src` through the pen, interpreting inline style tags:
//
//	"[b]CPU[/] [red]92%[/]  [i dim]idle[/]  [black on #ffcc00] warn [/]"
//
// A tag is a space-separated list of attributes, applied on top of the
// style outside it; `[/]` closes the innermost open tag.
//   modifiers  b bold  d dim  i italic  u underline  blink  r reverse  hidden  s strike
//   colors     black red green yellow blue magenta cyan white, bright_<name>,
//              default, #rrggbb, @n (256-color index)
//   background `on <color>`
// `[[` is a literal `[`. Anything in brackets that is not a valid tag is
// written as-is, so "[1/3]" or "[x]" need no escaping.
markup :: proc(p: ^Pen, src: string, base: style.Style = {}) {
	MAX_DEPTH :: 16
	stack: [MAX_DEPTH]style.Style
	depth := 0
	current := base

	rest := src
	for len(rest) > 0 {
		open := strings.index_byte(rest, '[')
		if open < 0 {
			write(p, rest, current)
			break
		}
		write(p, rest[:open], current)
		rest = rest[open:]

		if strings.has_prefix(rest, "[[") {
			write(p, "[", current)
			rest = rest[2:]
			continue
		}
		close := strings.index_byte(rest, ']')
		if close < 0 {
			write(p, rest, current)
			break
		}
		tag := rest[1:close]
		if tag == "/" {
			if depth > 0 {
				depth -= 1
				current = stack[depth]
			}
		} else if patch, ok := parse_tag(tag); ok {
			if depth < MAX_DEPTH {
				stack[depth] = current
				depth += 1
			}
			current = style.patch(current, patch)
		} else {
			write(p, rest[:close + 1], current) // not a tag: literal text
		}
		rest = rest[close + 1:]
	}
}

// Parses the inside of a tag ("b red on #202020"). ok is false if any word
// is not a known attribute.
parse_tag :: proc(tag: string) -> (st: style.Style, ok: bool) {
	words := tag
	saw_any := false
	for word in strings.fields_iterator(&words) {
		saw_any = true
		if word == "on" {
			next, found := strings.fields_iterator(&words)
			if !found { return {}, false }
			st.bg = parse_color(next) or_return
			continue
		}
		if m, is_mod := parse_modifier(word); is_mod {
			st.add += {m}
			continue
		}
		st.fg = parse_color(word) or_return
	}
	return st, saw_any
}

@(private)
parse_modifier :: proc(word: string) -> (style.Modifier, bool) {
	switch word {
	case "b", "bold":                  return .Bold, true
	case "d", "dim":                   return .Dim, true
	case "i", "italic":                return .Italic, true
	case "u", "underline":             return .Underlined, true
	case "blink":                      return .Slow_Blink, true
	case "r", "reverse":               return .Reversed, true
	case "hidden":                     return .Hidden, true
	case "s", "strike":                return .Crossed_Out, true
	}
	return {}, false
}

parse_color :: proc(word: string) -> (style.Color, bool) {
	if len(word) == 7 && word[0] == '#' {
		v, ok := strconv.parse_uint(word[1:], 16)
		if !ok { return nil, false }
		return style.rgb(u8(v >> 16), u8(v >> 8), u8(v)), true
	}
	if len(word) > 1 && word[0] == '@' {
		v, ok := strconv.parse_uint(word[1:], 10)
		if !ok || v > 255 { return nil, false }
		return style.Indexed(v), true
	}
	name := word
	bright := strings.has_prefix(name, "bright_")
	if bright {
		name = name[len("bright_"):]
	}
	c: style.Named_Color
	switch name {
	case "default": return style.Named_Color.Reset, !bright
	case "black":   c = .Black
	case "red":     c = .Red
	case "green":   c = .Green
	case "yellow":  c = .Yellow
	case "blue":    c = .Blue
	case "magenta": c = .Magenta
	case "cyan":    c = .Cyan
	case "white":   c = .White
	case:           return nil, false
	}
	if bright {
		c = style.Named_Color(int(c) + 8)
	}
	return c, true
}
