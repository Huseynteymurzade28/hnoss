package hnoss

import "core:time"
import "widgets"

Ui :: widgets.Ui
Theme :: widgets.Theme
Border :: widgets.Border
DEFAULT_THEME :: widgets.DEFAULT_THEME
LIGHT_THEME :: widgets.LIGHT_THEME
HIGH_CONTRAST_THEME :: widgets.HIGH_CONTRAST_THEME
ODLAR_YURDU_THEME :: widgets.ODLAR_YURDU_THEME
XEZER_THEME :: widgets.XEZER_THEME
Cursor :: widgets.Cursor
Cursor_Shape :: widgets.Cursor_Shape

// Starts this frame's widgets. `events` are the ones poll_events returned.
//
//	events := hnoss.poll_events(&term, 16)
//	f := hnoss.begin_frame(&term)
//	ui := hnoss.ui(f, events)
ui :: proc(f: ^Frame, events: []Event, theme := DEFAULT_THEME) -> ^Ui {
	f.ui = widgets.begin(f.buffer, events, f.memory, &f.cursor, theme)
	return f.ui
}

focus :: widgets.focus
focused :: widgets.focused
hover :: widgets.hover
hovered :: widgets.hovered
focus_order :: widgets.focus_order
unhandled :: widgets.unhandled

box :: widgets.box
key_hints :: widgets.key_hints
status_bar :: widgets.status_bar
Status_Bar :: widgets.Status_Bar
key_help :: widgets.key_help
Key_Hint :: widgets.Key_Hint
Box_Options :: widgets.Box_Options
label :: widgets.label
paragraph :: widgets.paragraph
Paragraph_Options :: widgets.Paragraph_Options
Scroll_State :: widgets.Scroll_State
scrollbar :: widgets.scrollbar
hscrollbar :: widgets.hscrollbar
scroll_view :: widgets.scroll_view
scroll_view_end :: widgets.scroll_view_end
View_State :: widgets.View_State
log_view :: widgets.log_view
Log_State :: widgets.Log_State
Log_Options :: widgets.Log_Options
log_append :: widgets.log_append
log_appendf :: widgets.log_appendf
log_len :: widgets.log_len
log_line :: widgets.log_line
log_clear :: widgets.log_clear
log_destroy :: widgets.log_destroy

list :: widgets.list
List_State :: widgets.List_State
List_Options :: widgets.List_Options
list_query :: widgets.list_query
list_set_query :: widgets.list_set_query
table :: widgets.table
Table_State :: widgets.Table_State
Table_Options :: widgets.Table_Options
Column :: widgets.Column
tree :: widgets.tree
Tree_Item :: widgets.Tree_Item
Tree_State :: widgets.Tree_State
Tree_Options :: widgets.Tree_Options
gauge :: widgets.gauge
spinner :: widgets.spinner
Spinner_Kind :: widgets.Spinner_Kind
Spinner_Options :: widgets.Spinner_Options
sparkline :: widgets.sparkline
bar_chart :: widgets.bar_chart
heatmap :: widgets.heatmap
Heatmap_Options :: widgets.Heatmap_Options
Bar :: widgets.Bar
Bar_Chart_Options :: widgets.Bar_Chart_Options
tabs :: widgets.tabs
input :: widgets.input
Input_State :: widgets.Input_State
Input_Options :: widgets.Input_Options
input_text :: widgets.input_text
input_set :: widgets.input_set
input_destroy :: widgets.input_destroy
text_area :: widgets.text_area
Text_Area_Options :: widgets.Text_Area_Options
graph :: widgets.graph
Canvas :: widgets.Canvas
canvas :: widgets.canvas
canvas_set :: widgets.canvas_set
canvas_unset :: widgets.canvas_unset
canvas_get :: widgets.canvas_get
canvas_line :: widgets.canvas_line
canvas_rect :: widgets.canvas_rect
canvas_circle :: widgets.canvas_circle
canvas_polygon :: widgets.canvas_polygon
canvas_draw :: widgets.canvas_draw
checkbox :: widgets.checkbox
toggle :: widgets.toggle
radio :: widgets.radio
button :: widgets.button
select :: widgets.select
slider :: widgets.slider
Slider_Options :: widgets.Slider_Options
number_input :: widgets.number_input
Number_State :: widgets.Number_State
Number_Options :: widgets.Number_Options
Select_State :: widgets.Select_State
Select_Options :: widgets.Select_Options
Button_State :: widgets.Button_State
modal :: widgets.modal
tooltip :: widgets.tooltip
TOOLTIP_DELAY :: widgets.TOOLTIP_DELAY
toast :: widgets.toast
Toast_Kind :: widgets.Toast_Kind

// How long to wait for input so toasts on screen still slide and expire
// on time: `wait_ms` when there are none, otherwise at most that (-1: no
// limit of your own).
//
//	events = hnoss.poll_events(&term, hnoss.toast_timeout(&term, -1))
toast_timeout :: proc(t: ^Terminal, wait_ms: int) -> int {
	return widgets.toast_timeout(&t.widget_memory, time.tick_now(), wait_ms)
}

// How long to wait for input so that what happens by itself still gets its
// frame on time: toasts sliding and expiring, a tooltip opening. `wait_ms`
// when nothing is pending, otherwise at most that (-1: no limit of your own).
//
//	events = hnoss.poll_events(&term, hnoss.timeout(&term, -1))
timeout :: proc(t: ^Terminal, wait_ms: int) -> int {
	return widgets.timeout(&t.widget_memory, time.tick_now(), wait_ms)
}
Graph_Options :: widgets.Graph_Options
