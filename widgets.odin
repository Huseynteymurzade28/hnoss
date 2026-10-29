package hnoss

import "widgets"

Ui :: widgets.Ui
Theme :: widgets.Theme
Border :: widgets.Border
DEFAULT_THEME :: widgets.DEFAULT_THEME

// Starts this frame's widgets. `events` are the ones poll_events returned.
//
//	events := hnoss.poll_events(&term, 16)
//	f := hnoss.begin_frame(&term)
//	ui := hnoss.ui(f, events)
ui :: proc(f: ^Frame, events: []Event, theme := DEFAULT_THEME) -> ^Ui {
	return widgets.begin(f.buffer, events, f.memory, &f.cursor, theme)
}

focus :: widgets.focus
focused :: widgets.focused
focus_order :: widgets.focus_order
unhandled :: widgets.unhandled

box :: widgets.box
Box_Options :: widgets.Box_Options
label :: widgets.label
paragraph :: widgets.paragraph
Paragraph_Options :: widgets.Paragraph_Options
Scroll_State :: widgets.Scroll_State
scrollbar :: widgets.scrollbar
