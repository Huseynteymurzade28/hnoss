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

// A patch applied on top of whatever is already in a cell: non-nil colors
// replace, `add` modifiers are turned on, `sub` modifiers turned off.
Style :: struct {
	fg, bg: Color,
	add:    Modifiers,
	sub:    Modifiers,
}

fg :: proc(c: Color) -> Style { return {fg = c} }
bg :: proc(c: Color) -> Style { return {bg = c} }

rgb :: proc(r, g, b: u8) -> Color { return Rgb{r, g, b} }

// `b` on top of `a`.
patch :: proc(a, b: Style) -> Style {
	r := a
	if b.fg != nil { r.fg = b.fg }
	if b.bg != nil { r.bg = b.bg }
	r.add = (r.add - b.sub) + b.add
	r.sub = (r.sub - b.add) + b.sub
	return r
}
