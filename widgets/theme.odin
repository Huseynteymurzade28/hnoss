package widgets

import "../style"

Border :: enum u8 {
	None,
	Plain,
	Rounded,
	Double,
	Thick,
}

// Every color a widget uses comes from here, so restyling an app is
// swapping one value: `ui.theme = my_theme`.
Theme :: struct {
	background:         Style, // fills the frame before any widget, if set (light themes need it)
	text:               Style,
	muted:              Style, // secondary text, placeholders, empty tracks
	accent:             Style, // bars, sparklines, highlights

	border_kind:        Border,
	border:             Style,
	border_focused:     Style,
	title:              Style,

	selected:           Style, // selected row of a focused list/table
	selected_unfocused: Style,
	header:             Style, // table header row

	gauge_filled:       Style, // fg = the bar color
	gauge_empty:        Style, // bg = the track color

	tab:                Style,
	tab_selected:       Style,

	input:              Style,
	check:              Style, // the mark of a checked box, an on toggle, the chosen radio
	button:             Style,
	button_focused:     Style,
	button_pressed:     Style, // held down with the mouse
	modal:              Style, // the inside of a modal (its border is border_focused)
	scrollbar_track:    Style,
	scrollbar_thumb:    Style,
	key:                Style, // a key in key_hints / key_help
	match:              Style, // the characters a filtered list matched

	// What a message is about: toasts color their border and icon with these.
	info:               Style,
	success:            Style,
	warning:            Style,
	error:              Style,
}

DEFAULT_THEME :: Theme {
	text               = {},
	muted              = {fg = .Bright_Black},
	accent             = {fg = .Cyan},

	border_kind        = .Rounded,
	border             = {fg = .Bright_Black},
	border_focused     = {fg = .Cyan},
	title              = {add = {.Bold}},

	selected           = {fg = .Black, bg = .Cyan, add = {.Bold}},
	selected_unfocused = {bg = .Bright_Black},
	header             = {fg = .Cyan, add = {.Bold}},

	gauge_filled       = {fg = .Cyan},
	gauge_empty        = {bg = .Bright_Black},

	tab                = {fg = .Bright_Black},
	tab_selected       = {fg = .Cyan, add = {.Bold, .Underlined}},

	input              = {},
	check              = {fg = .Cyan, add = {.Bold}},
	button             = {bg = .Bright_Black},
	button_focused     = {fg = .Black, bg = .Cyan, add = {.Bold}},
	button_pressed     = {fg = .Black, bg = .White, add = {.Bold}},
	modal              = {},
	scrollbar_track    = {fg = .Bright_Black},
	scrollbar_thumb    = {fg = .Cyan},
	key                = {fg = .Cyan, add = {.Bold}},
	match              = {add = {.Bold, .Underlined}},

	info               = {fg = .Blue},
	success            = {fg = .Green},
	warning            = {fg = .Yellow, add = {.Bold}},
	error              = {fg = .Red, add = {.Bold}},
}

// The presets below all fill the frame with their background, so they
// look the same whatever the terminal's own colors are.

// "Odlar Yurdu", the Land of Fire: embers on a dark brown.
ODLAR_YURDU_THEME :: Theme {
	background         = {fg = ODLAR_TEXT, bg = ODLAR_BG},
	text               = {fg = ODLAR_TEXT},
	muted              = {fg = ODLAR_DIM},
	accent             = {fg = ODLAR_ACCENT},

	border_kind        = .Rounded,
	border             = {fg = ODLAR_FRAME},
	border_focused     = {fg = ODLAR_ACCENT},
	title              = {fg = ODLAR_TEXT, add = {.Bold}},

	selected           = {fg = ODLAR_BG, bg = ODLAR_ACCENT, add = {.Bold}},
	selected_unfocused = {bg = ODLAR_FRAME},
	header             = {fg = ODLAR_ACCENT, add = {.Bold}},

	gauge_filled       = {fg = ODLAR_ACCENT},
	gauge_empty        = {bg = ODLAR_TRACK},

	tab                = {fg = ODLAR_DIM},
	tab_selected       = {fg = ODLAR_ACCENT, add = {.Bold}},

	input              = {fg = ODLAR_TEXT, bg = ODLAR_TRACK},
	check              = {fg = ODLAR_ACCENT, add = {.Bold}},
	button             = {fg = ODLAR_TEXT, bg = ODLAR_FRAME},
	button_focused     = {fg = ODLAR_BG, bg = ODLAR_ACCENT, add = {.Bold}},
	button_pressed     = {fg = ODLAR_BG, bg = ODLAR_TEXT, add = {.Bold}},
	modal              = {fg = ODLAR_TEXT, bg = ODLAR_BG},
	scrollbar_track    = {fg = ODLAR_FRAME},
	scrollbar_thumb    = {fg = ODLAR_ACCENT},
	key                = {fg = ODLAR_ACCENT, add = {.Bold}},
	match              = {fg = ODLAR_ACCENT, add = {.Bold, .Underlined}},

	info               = {fg = style.Rgb{0x8e, 0xca, 0xe6}},
	success            = {fg = style.Rgb{0x95, 0xd5, 0xb2}},
	warning            = {fg = style.Rgb{0xff, 0xd1, 0x66}, add = {.Bold}},
	error              = {fg = style.Rgb{0xe6, 0x39, 0x46}, add = {.Bold}},
}

// "Xəzər", the Caspian: shallow teal on deep blue.
XEZER_THEME :: Theme {
	background         = {fg = XEZER_TEXT, bg = XEZER_BG},
	text               = {fg = XEZER_TEXT},
	muted              = {fg = XEZER_DIM},
	accent             = {fg = XEZER_ACCENT},

	border_kind        = .Rounded,
	border             = {fg = XEZER_FRAME},
	border_focused     = {fg = XEZER_ACCENT},
	title              = {fg = XEZER_TEXT, add = {.Bold}},

	selected           = {fg = XEZER_BG, bg = XEZER_ACCENT, add = {.Bold}},
	selected_unfocused = {bg = XEZER_FRAME},
	header             = {fg = XEZER_ACCENT, add = {.Bold}},

	gauge_filled       = {fg = XEZER_ACCENT},
	gauge_empty        = {bg = XEZER_TRACK},

	tab                = {fg = XEZER_DIM},
	tab_selected       = {fg = XEZER_ACCENT, add = {.Bold}},

	input              = {fg = XEZER_TEXT, bg = XEZER_TRACK},
	check              = {fg = XEZER_ACCENT, add = {.Bold}},
	button             = {fg = XEZER_TEXT, bg = XEZER_FRAME},
	button_focused     = {fg = XEZER_BG, bg = XEZER_ACCENT, add = {.Bold}},
	button_pressed     = {fg = XEZER_BG, bg = XEZER_TEXT, add = {.Bold}},
	modal              = {fg = XEZER_TEXT, bg = XEZER_BG},
	scrollbar_track    = {fg = XEZER_FRAME},
	scrollbar_thumb    = {fg = XEZER_ACCENT},
	key                = {fg = XEZER_ACCENT, add = {.Bold}},
	match              = {fg = XEZER_ACCENT, add = {.Bold, .Underlined}},

	info               = {fg = XEZER_ACCENT},
	success            = {fg = style.Rgb{0x80, 0xff, 0xdb}},
	warning            = {fg = style.Rgb{0xff, 0xd1, 0x66}, add = {.Bold}},
	error              = {fg = style.Rgb{0xff, 0x6b, 0x6b}, add = {.Bold}},
}

// Dark text on near-white, with a blue accent.
LIGHT_THEME :: Theme {
	background         = {fg = LIGHT_TEXT, bg = LIGHT_BG},
	text               = {fg = LIGHT_TEXT},
	muted              = {fg = LIGHT_DIM},
	accent             = {fg = LIGHT_ACCENT},

	border_kind        = .Rounded,
	border             = {fg = LIGHT_FRAME},
	border_focused     = {fg = LIGHT_ACCENT},
	title              = {fg = LIGHT_TEXT, add = {.Bold}},

	selected           = {fg = LIGHT_BG, bg = LIGHT_ACCENT, add = {.Bold}},
	selected_unfocused = {bg = LIGHT_TRACK},
	header             = {fg = LIGHT_ACCENT, add = {.Bold}},

	gauge_filled       = {fg = LIGHT_ACCENT},
	gauge_empty        = {bg = LIGHT_TRACK},

	tab                = {fg = LIGHT_DIM},
	tab_selected       = {fg = LIGHT_ACCENT, add = {.Bold, .Underlined}},

	input              = {fg = LIGHT_TEXT, bg = LIGHT_TRACK},
	check              = {fg = LIGHT_ACCENT, add = {.Bold}},
	button             = {fg = LIGHT_TEXT, bg = LIGHT_TRACK},
	button_focused     = {fg = LIGHT_BG, bg = LIGHT_ACCENT, add = {.Bold}},
	button_pressed     = {fg = LIGHT_BG, bg = LIGHT_TEXT, add = {.Bold}},
	modal              = {fg = LIGHT_TEXT, bg = LIGHT_BG},
	scrollbar_track    = {fg = LIGHT_FRAME},
	scrollbar_thumb    = {fg = LIGHT_ACCENT},
	key                = {fg = LIGHT_ACCENT, add = {.Bold}},
	match              = {fg = LIGHT_ACCENT, add = {.Bold, .Underlined}},

	info               = {fg = LIGHT_ACCENT},
	success            = {fg = style.Rgb{0x1a, 0x7f, 0x37}},
	warning            = {fg = style.Rgb{0x9a, 0x67, 0x00}, add = {.Bold}},
	error              = {fg = style.Rgb{0xcf, 0x22, 0x2e}, add = {.Bold}},
}

// Bright white and yellow on black, from the 16 named colors only, so it
// is the same in any color depth (named colors are never downsampled).
// Focus and selection don't rely on color alone: they are also bold.
HIGH_CONTRAST_THEME :: Theme {
	background         = {fg = .Bright_White, bg = .Black},
	text               = {fg = .Bright_White},
	muted              = {fg = .White},
	accent             = {fg = .Bright_Yellow},

	border_kind        = .Plain,
	border             = {fg = .White},
	border_focused     = {fg = .Bright_Yellow, add = {.Bold}},
	title              = {fg = .Bright_White, add = {.Bold}},

	selected           = {fg = .Black, bg = .Bright_Yellow, add = {.Bold}},
	selected_unfocused = {fg = .Black, bg = .White},
	header             = {fg = .Bright_Yellow, add = {.Bold, .Underlined}},

	gauge_filled       = {fg = .Bright_Yellow},
	gauge_empty        = {bg = .Bright_Black},

	tab                = {fg = .White},
	tab_selected       = {fg = .Bright_Yellow, add = {.Bold, .Underlined}},

	input              = {fg = .Bright_White, add = {.Underlined}},
	check              = {fg = .Bright_Yellow, add = {.Bold}},
	button             = {fg = .Bright_White, bg = .Bright_Black},
	button_focused     = {fg = .Black, bg = .Bright_Yellow, add = {.Bold}},
	button_pressed     = {fg = .Black, bg = .Bright_White, add = {.Bold}},
	modal              = {fg = .Bright_White, bg = .Black},
	scrollbar_track    = {fg = .White},
	scrollbar_thumb    = {fg = .Bright_Yellow},
	key                = {fg = .Bright_Yellow, add = {.Bold}},
	match              = {fg = .Bright_Yellow, add = {.Bold, .Underlined}},

	info               = {fg = .Bright_Cyan},
	success            = {fg = .Bright_Green},
	warning            = {fg = .Bright_Yellow, add = {.Bold}},
	error              = {fg = .Bright_Red, add = {.Bold}},
}

@(private) ODLAR_BG     :: style.Rgb{0x14, 0x09, 0x06}
@(private) ODLAR_TRACK  :: style.Rgb{0x3a, 0x1d, 0x14}
@(private) ODLAR_FRAME  :: style.Rgb{0x6b, 0x30, 0x20}
@(private) ODLAR_DIM    :: style.Rgb{0x9a, 0x6a, 0x55}
@(private) ODLAR_TEXT   :: style.Rgb{0xf6, 0xe3, 0xd4}
@(private) ODLAR_ACCENT :: style.Rgb{0xff, 0x8c, 0x42}

@(private) XEZER_BG     :: style.Rgb{0x06, 0x14, 0x1f}
@(private) XEZER_TRACK  :: style.Rgb{0x12, 0x30, 0x3f}
@(private) XEZER_FRAME  :: style.Rgb{0x1f, 0x51, 0x68}
@(private) XEZER_DIM    :: style.Rgb{0x5f, 0x8a, 0xa0}
@(private) XEZER_TEXT   :: style.Rgb{0xdf, 0xf3, 0xfb}
@(private) XEZER_ACCENT :: style.Rgb{0x4c, 0xc9, 0xf0}

@(private) LIGHT_BG     :: style.Rgb{0xfa, 0xfa, 0xf7}
@(private) LIGHT_TRACK  :: style.Rgb{0xe6, 0xe8, 0xeb}
@(private) LIGHT_FRAME  :: style.Rgb{0xc4, 0xc9, 0xd0}
@(private) LIGHT_DIM    :: style.Rgb{0x6a, 0x73, 0x7d}
@(private) LIGHT_TEXT   :: style.Rgb{0x1f, 0x23, 0x28}
@(private) LIGHT_ACCENT :: style.Rgb{0x0a, 0x5f, 0xc2}
