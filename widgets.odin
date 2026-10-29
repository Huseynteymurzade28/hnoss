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

list :: widgets.list
List_State :: widgets.List_State
List_Options :: widgets.List_Options
table :: widgets.table
Table_State :: widgets.Table_State
Table_Options :: widgets.Table_Options
Column :: widgets.Column
gauge :: widgets.gauge
sparkline :: widgets.sparkline
tabs :: widgets.tabs
input :: widgets.input
Input_State :: widgets.Input_State
Input_Options :: widgets.Input_Options
input_text :: widgets.input_text
input_set :: widgets.input_set
input_destroy :: widgets.input_destroy
graph :: widgets.graph
Graph_Options :: widgets.Graph_Options
