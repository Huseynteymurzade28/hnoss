package widgets

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
	scrollbar_track:    Style,
	scrollbar_thumb:    Style,
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
	scrollbar_track    = {fg = .Bright_Black},
	scrollbar_thumb    = {fg = .Cyan},
}
