package input

Event :: union {
	Key,
	Mouse,
	Paste,
	Resize,
}

Key_Code :: enum u8 {
	None,
	Char, // see Key.char
	Enter,
	Tab,
	Back_Tab, // Shift+Tab
	Backspace,
	Esc,
	Up, Down, Left, Right,
	Home, End,
	Page_Up, Page_Down,
	Insert, Delete,
	F1, F2, F3, F4, F5, F6, F7, F8, F9, F10, F11, F12,
}

// Bit positions match xterm's modifier encoding (param - 1), see decode_modifiers.
Key_Modifier :: enum u8 {
	Shift,
	Alt,
	Ctrl,
	Super,
}
Key_Modifiers :: bit_set[Key_Modifier; u8]

// For printable keys code is .Char and char holds the rune exactly as typed
// ('A' for Shift+a; Shift is not added for it). Ctrl+letter is reported as
// the lowercase letter with .Ctrl.
Key :: struct {
	code: Key_Code,
	char: rune,
	mods: Key_Modifiers,
}

Mouse_Kind :: enum u8 {
	Press,
	Release,
	Drag,   // motion with a button held
	Move,   // motion with no button (needs any-motion tracking)
	Scroll,
}

Mouse_Button :: enum u8 {
	None,
	Left,
	Middle,
	Right,
	Wheel_Up,
	Wheel_Down,
	Wheel_Left,
	Wheel_Right,
}

// x, y are 0-based cell coordinates.
Mouse :: struct {
	kind:   Mouse_Kind,
	button: Mouse_Button,
	x, y:   int,
	mods:   Key_Modifiers,
}

// Text from a bracketed paste, delivered as one event instead of a stream
// of keys. Allocated with the allocator given to the parser call.
Paste :: struct {
	text: string,
}

Resize :: struct {
	cols, rows: int,
}

// Convenience for the most common check: `if input.is_char(ev, 'q') {...}`.
is_char :: proc(ev: Event, r: rune, mods: Key_Modifiers = {}) -> bool {
	k, ok := ev.(Key)
	return ok && k.code == .Char && k.char == r && k.mods == mods
}

is_key :: proc(ev: Event, code: Key_Code, mods: Key_Modifiers = {}) -> bool {
	k, ok := ev.(Key)
	return ok && k.code == code && k.mods == mods
}
