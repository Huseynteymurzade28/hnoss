package style

// The 16 ANSI colors plus `Reset` (the terminal's default fg/bg).
Named_Color :: enum u8 {
	Reset,
	Black, Red, Green, Yellow, Blue, Magenta, Cyan, White,
	Bright_Black, Bright_Red, Bright_Green, Bright_Yellow,
	Bright_Blue, Bright_Magenta, Bright_Cyan, Bright_White,
}

// Index into the 256-color palette (0-15 = named, 16-231 = 6x6x6 cube,
// 232-255 = grayscale ramp).
Indexed :: distinct u8

// 24-bit "truecolor".
Rgb :: struct {
	r, g, b: u8,
}

// A nil Color means "unspecified": in a Style it leaves the target alone,
// in a Cell it renders as the terminal default (same as `.Reset`).
Color :: union {
	Named_Color,
	Indexed,
	Rgb,
}

Modifier :: enum u8 {
	Bold,
	Dim,
	Italic,
	Underlined,
	Slow_Blink,
	Rapid_Blink,
	Reversed,
	Hidden,
	Crossed_Out,
}
Modifiers :: bit_set[Modifier; u16]

// The shape of an underline (SGR 4:1 … 4:5). It only shows while the
// `.Underlined` modifier is on. Terminals that can't draw the fancy ones
// get a plain underline instead (see buffer.Output_Feature).
Underline :: enum u8 {
	Single,
	Double,
	Curly,
	Dotted,
	Dashed,
}

// A patch applied on top of whatever is already in a cell: non-nil colors
// replace, `add` modifiers are turned on, `sub` modifiers turned off.
//
// `underline`, when set, picks the underline's shape and turns `.Underlined`
// on (unless `sub` turns it off). `underline_color` colors the underline
// (SGR 58) instead of letting it follow the text color.
//
// `link` makes the text an OSC 8 hyperlink, clickable in terminals that
// support them. Like the symbol, a link belongs to what is written with it:
// writing text without one over a linked cell drops the link. The buffer
// keeps its own copy of the URL.
Style :: struct {
	fg, bg:          Color,
	add:             Modifiers,
	sub:             Modifiers,
	underline:       Maybe(Underline),
	underline_color: Color,
	link:            string,
}

fg :: proc(c: Color) -> Style { return {fg = c} }
bg :: proc(c: Color) -> Style { return {bg = c} }

rgb :: proc(r, g, b: u8) -> Color { return Rgb{r, g, b} }

// An underline of shape `u`, optionally colored.
underline :: proc(u: Underline, color: Color = nil) -> Style {
	return {underline = u, underline_color = color}
}

// Text that links to `url`.
link :: proc(url: string) -> Style { return {link = url} }

// The modifiers `s` turns on, counting the `.Underlined` that `underline`
// implies.
added_modifiers :: proc(s: Style) -> Modifiers {
	add := s.add
	if s.underline != nil && .Underlined not_in s.sub {
		add += {.Underlined}
	}
	return add
}

// `b` on top of `a`.
patch :: proc(a, b: Style) -> Style {
	r := a
	if b.fg != nil { r.fg = b.fg }
	if b.bg != nil { r.bg = b.bg }
	if b.underline != nil { r.underline = b.underline }
	if b.underline_color != nil { r.underline_color = b.underline_color }
	if b.link != "" { r.link = b.link }
	add := added_modifiers(b)
	r.add = (r.add - b.sub) + add
	r.sub = (r.sub - add) + b.sub
	return r
}
