/*
Package widgets: immediate-mode widgets. Calling a widget draws it, handles
the input meant for it and reports what happened:

	ui := hnoss.ui(f, events)
	inner := hnoss.box(ui, area, "Processes")
	if hnoss.list(ui, inner, names, &list_state) { ... }   // selection changed

Stateful widgets take a pointer to state you own; that pointer is also
the widget's identity for keyboard focus (hnoss.focus, hnoss.focus_order).
Events a widget uses are consumed; hnoss.unhandled(ui) gives the rest to
the app. Colors come from ui.theme.
*/
package widgets
