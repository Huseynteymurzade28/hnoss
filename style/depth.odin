package style

import "core:strings"

// How many colors the terminal can show. The zero value is Truecolor, so a
// Color_Depth left unset changes nothing.
Color_Depth :: enum u8 {
	Truecolor, // 24-bit RGB: every Color is sent as is
	Ansi256,   // the 256-color palette: Rgb becomes the nearest Indexed
	Ansi16,    // the 16 named colors: Rgb and Indexed become the nearest Named_Color
	No_Color,  // no colors at all (NO_COLOR); modifiers like bold still apply
}

// The environment variables color detection looks at.
Color_Env :: struct {
	no_color:     string, // NO_COLOR
	colorterm:    string, // COLORTERM
	term:         string, // TERM
	term_program: string, // TERM_PROGRAM
}

// Guesses the color depth from the environment:
//  - NO_COLOR set to anything but "" turns colors off (https://no-color.org);
//  - COLORTERM=truecolor or 24bit, a TERM ending in -direct, or a terminal
//    known to support truecolor (kitty, ghostty, foot, alacritty, wezterm,
//    iTerm2, VS Code) gives Truecolor;
//  - a TERM containing 256color, or macOS Terminal.app, gives Ansi256;
//  - TERM=dumb gives No_Color; anything else Ansi16.
detect_color_depth :: proc(env: Color_Env) -> Color_Depth {
	if env.no_color != "" {
		return .No_Color
	}
	if env.colorterm == "truecolor" || env.colorterm == "24bit" {
		return .Truecolor
	}
	term := env.term
	if term == "dumb" {
		return .No_Color
	}
	if strings.has_suffix(term, "-direct") {
		return .Truecolor
	}
	for prefix in ([]string{"xterm-kitty", "xterm-ghostty", "foot", "alacritty", "wezterm", "contour"}) {
		if strings.has_prefix(term, prefix) {
			return .Truecolor
		}
	}
	switch env.term_program {
	case "iTerm.app", "WezTerm", "ghostty", "vscode":
		return .Truecolor
	case "Apple_Terminal":
		return .Ansi256
	}
	if strings.contains(term, "256color") {
		return .Ansi256
	}
	return .Ansi16
}

// `c` as the terminal can show it at `depth`. Colors the depth already
// covers come back unchanged; nil and .Reset stay as they are, except that
// No_Color turns every color into nil.
downsample :: proc(c: Color, depth: Color_Depth) -> Color {
	switch depth {
	case .Truecolor:
		return c
	case .No_Color:
		return nil
	case .Ansi256:
		if v, ok := c.(Rgb); ok {
			return rgb_to_indexed(v)
		}
		return c
	case .Ansi16:
		switch v in c {
		case nil, Named_Color:
			return c
		case Indexed:
			if v < 16 {
				return Named_Color(int(Named_Color.Black) + int(v))
			}
			return rgb_to_named(indexed_to_rgb(v))
		case Rgb:
			return rgb_to_named(v)
		}
	}
	return c
}

// Channel levels of the 6x6x6 cube (indices 16-231).
@(private)
CUBE_LEVELS := [6]u8{0, 95, 135, 175, 215, 255}

// The nearest entry in the 6x6x6 cube or the grayscale ramp (16-255).
// Entries 0-15 are skipped: terminals let users recolor them.
rgb_to_indexed :: proc(c: Rgb) -> Indexed {
	// Nearest cube level per channel: the levels are 0, then 95 + 40k, so
	// the midpoints are 48 and 115 + 40k.
	level :: proc(v: u8) -> int {
		switch {
		case v < 48:  return 0
		case v < 115: return 1
		case:         return (int(v) - 35) / 40
		}
	}
	r, g, b := level(c.r), level(c.g), level(c.b)
	cube := Rgb{CUBE_LEVELS[r], CUBE_LEVELS[g], CUBE_LEVELS[b]}
	cube_index := 16 + 36 * r + 6 * g + b
	if cube == c {
		return Indexed(cube_index)
	}

	// Ramp entry i (232 + i) is the gray 8 + 10i, i in 0..23.
	avg := (int(c.r) + int(c.g) + int(c.b)) / 3
	gi := clamp((avg - 3) / 10, 0, 23)
	gv := u8(8 + 10 * gi)
	if distance(c, {gv, gv, gv}) < distance(c, cube) {
		return Indexed(232 + gi)
	}
	return Indexed(cube_index)
}

// The color a 256-palette entry shows; 0-15 use xterm's defaults.
indexed_to_rgb :: proc(i: Indexed) -> Rgb {
	switch {
	case i < 16:
		return ANSI16_RGB[i]
	case i < 232:
		n := int(i) - 16
		return {CUBE_LEVELS[n / 36], CUBE_LEVELS[n / 6 % 6], CUBE_LEVELS[n % 6]}
	case:
		v := u8(8 + 10 * (int(i) - 232))
		return {v, v, v}
	}
}

// xterm's default colors for Black .. Bright_White. Real terminals differ
// (users pick their own), so this is only a best guess for matching.
ANSI16_RGB := [16]Rgb{
	{0, 0, 0}, {205, 0, 0}, {0, 205, 0}, {205, 205, 0},
	{0, 0, 238}, {205, 0, 205}, {0, 205, 205}, {229, 229, 229},
	{127, 127, 127}, {255, 0, 0}, {0, 255, 0}, {255, 255, 0},
	{92, 92, 255}, {255, 0, 255}, {0, 255, 255}, {255, 255, 255},
}

// The nearest of the 16 named colors (against ANSI16_RGB).
rgb_to_named :: proc(c: Rgb) -> Named_Color {
	best, best_d := 0, max(int)
	for p, i in ANSI16_RGB {
		if d := distance(c, p); d < best_d {
			best, best_d = i, d
		}
	}
	return Named_Color(int(Named_Color.Black) + best)
}

// Squared Euclidean distance in RGB.
@(private)
distance :: proc(a, b: Rgb) -> int {
	dr, dg, db := int(a.r) - int(b.r), int(a.g) - int(b.g), int(a.b) - int(b.b)
	return dr * dr + dg * dg + db * db
}
