package tests

import "core:testing"
import "../input"

// Feeds `bytes` in one go, then flushes, and returns the events.
@(private = "file")
parse :: proc(bytes: string, flush := true) -> []input.Event {
	p: input.Parser
	input.parser_init(&p, context.temp_allocator)
	events := make([dynamic]input.Event, context.temp_allocator)
	input.feed(&p, transmute([]u8)bytes, &events)
	if flush {
		input.flush(&p, &events)
	}
	return events[:]
}

@(private = "file")
expect_events :: proc(t: ^testing.T, bytes: string, want: ..input.Event, loc := #caller_location) {
	got := parse(bytes)
	if !testing.expectf(t, len(got) == len(want), "%q: got %d events %v, want %v", bytes, len(got), got, want, loc = loc) {
		return
	}
	for i in 0 ..< len(want) {
		testing.expectf(t, got[i] == want[i], "%q: event %d = %v, want %v", bytes, i, got[i], want[i], loc = loc)
	}
}

@(private = "file")
key :: proc(code: input.Key_Code, mods: input.Key_Modifiers = {}) -> input.Event {
	return input.Key{code = code, mods = mods}
}

@(private = "file")
ch :: proc(r: rune, mods: input.Key_Modifiers = {}) -> input.Event {
	return input.Key{code = .Char, char = r, mods = mods}
}

@(test)
input_plain_text_and_utf8 :: proc(t: ^testing.T) {
	expect_events(t, "aZ", ch('a'), ch('Z'))
	expect_events(t, "ö世🎉", ch('ö'), ch('世'), ch('🎉'))
}

@(test)
input_control_keys :: proc(t: ^testing.T) {
	expect_events(t, "\r", key(.Enter))
	expect_events(t, "\t", key(.Tab))
	expect_events(t, "\x7f", key(.Backspace))
	expect_events(t, "\x08", key(.Backspace))
	expect_events(t, "\x03", ch('c', {.Ctrl}))
	expect_events(t, "\n", ch('j', {.Ctrl}))
	expect_events(t, "\x00", ch(' ', {.Ctrl}))
	expect_events(t, "\x1c\x1f", ch('\\', {.Ctrl}), ch('_', {.Ctrl}))
}

@(test)
input_lone_esc_waits_for_flush :: proc(t: ^testing.T) {
	testing.expect_value(t, len(parse("\x1b", flush = false)), 0)
	expect_events(t, "\x1b", key(.Esc))
	expect_events(t, "\x1b\x1b", key(.Esc), key(.Esc))
}

@(test)
input_alt_keys :: proc(t: ^testing.T) {
	expect_events(t, "\x1ba", ch('a', {.Alt}))
	expect_events(t, "\x1b\x7f", key(.Backspace, {.Alt}))
	expect_events(t, "\x1b\x01", ch('a', {.Alt, .Ctrl}))
	expect_events(t, "\x1bö", ch('ö', {.Alt}))
	// An unfinished CSI / SS3 introducer at the end is Alt+[ / Alt+O.
	expect_events(t, "\x1b[", ch('[', {.Alt}))
	expect_events(t, "\x1bO", ch('O', {.Alt}))
}

@(test)
input_arrows_and_nav :: proc(t: ^testing.T) {
	expect_events(t, "\x1b[A\x1b[B\x1b[C\x1b[D", key(.Up), key(.Down), key(.Right), key(.Left))
	expect_events(t, "\x1bOA\x1bOH\x1bOF", key(.Up), key(.Home), key(.End)) // application mode
	expect_events(t, "\x1b[H\x1b[F\x1b[1~\x1b[4~", key(.Home), key(.End), key(.Home), key(.End))
	expect_events(t, "\x1b[2~\x1b[3~\x1b[5~\x1b[6~", key(.Insert), key(.Delete), key(.Page_Up), key(.Page_Down))
	expect_events(t, "\x1b[Z", key(.Back_Tab, {.Shift}))
}

@(test)
input_modifiers_via_csi :: proc(t: ^testing.T) {
	expect_events(t, "\x1b[1;2A", key(.Up, {.Shift}))
	expect_events(t, "\x1b[1;3D", key(.Left, {.Alt}))
	expect_events(t, "\x1b[1;5C", key(.Right, {.Ctrl}))
	expect_events(t, "\x1b[1;8H", key(.Home, {.Shift, .Alt, .Ctrl}))
	expect_events(t, "\x1b[3;5~", key(.Delete, {.Ctrl}))
	expect_events(t, "\x1b[1;9A", key(.Up, {.Super}))
}

@(test)
input_function_keys :: proc(t: ^testing.T) {
	expect_events(t, "\x1bOP\x1bOQ\x1bOR\x1bOS", key(.F1), key(.F2), key(.F3), key(.F4))
	expect_events(t, "\x1b[11~\x1b[15~\x1b[17~\x1b[21~\x1b[23~\x1b[24~",
		key(.F1), key(.F5), key(.F6), key(.F10), key(.F11), key(.F12))
	expect_events(t, "\x1b[1;2P", key(.F1, {.Shift}))
	expect_events(t, "\x1b[15;5~", key(.F5, {.Ctrl}))
}

@(test)
input_csi_u :: proc(t: ^testing.T) {
	expect_events(t, "\x1b[13;5u", key(.Enter, {.Ctrl}))
	expect_events(t, "\x1b[97;5u", ch('a', {.Ctrl}))
}

@(test)
input_sgr_mouse :: proc(t: ^testing.T) {
	expect_events(t, "\x1b[<0;10;5M", input.Mouse{kind = .Press, button = .Left, x = 9, y = 4})
	expect_events(t, "\x1b[<0;10;5m", input.Mouse{kind = .Release, button = .Left, x = 9, y = 4})
	expect_events(t, "\x1b[<2;1;1M", input.Mouse{kind = .Press, button = .Right})
	expect_events(t, "\x1b[<32;3;4M", input.Mouse{kind = .Drag, button = .Left, x = 2, y = 3})
	expect_events(t, "\x1b[<35;3;4M", input.Mouse{kind = .Move, x = 2, y = 3})
	expect_events(t, "\x1b[<64;1;1M\x1b[<65;1;1M", input.Mouse{kind = .Scroll, button = .Wheel_Up},
		input.Mouse{kind = .Scroll, button = .Wheel_Down})
	expect_events(t, "\x1b[<20;300;200M", input.Mouse{kind = .Press, button = .Left, x = 299, y = 199, mods = {.Shift, .Ctrl}})
}

@(test)
input_bracketed_paste :: proc(t: ^testing.T) {
	got := parse("x\x1b[200~hello\x1b[A\r\nworld\x1b[201~y")
	testing.expect_value(t, len(got), 3)
	testing.expect_value(t, got[0], ch('x'))
	p, ok := got[1].(input.Paste)
	testing.expect(t, ok)
	testing.expect_value(t, p.text, "hello\x1b[A\r\nworld") // escape sequences stay literal
	testing.expect_value(t, got[2], ch('y'))
}

@(test)
input_sequences_split_across_reads :: proc(t: ^testing.T) {
	p: input.Parser
	input.parser_init(&p, context.temp_allocator)
	events := make([dynamic]input.Event, context.temp_allocator)

	// CSI split in the middle, then a UTF-8 char split in the middle.
	input.feed(&p, transmute([]u8)string("\x1b[1;"), &events)
	testing.expect_value(t, len(events), 0)
	testing.expect(t, input.has_pending(&p))
	input.feed(&p, transmute([]u8)string("5A\xe4\xb8"), &events)
	input.feed(&p, transmute([]u8)string("\x96"), &events)
	testing.expect_value(t, len(events), 2)
	testing.expect_value(t, events[0], key(.Up, {.Ctrl}))
	testing.expect_value(t, events[1], ch('世'))
	testing.expect(t, !input.has_pending(&p))

	// Paste whose end marker arrives split.
	clear(&events)
	input.feed(&p, transmute([]u8)string("\x1b[200~ab"), &events)
	input.feed(&p, transmute([]u8)string("c\x1b[20"), &events)
	testing.expect_value(t, len(events), 0)
	input.feed(&p, transmute([]u8)string("1~"), &events)
	testing.expect_value(t, len(events), 1)
	testing.expect_value(t, events[0].(input.Paste).text, "abc")
}

@(test)
input_garbage_is_dropped :: proc(t: ^testing.T) {
	expect_events(t, "\x1b[?1;2c" + "a", ch('a'))       // DA reply
	expect_events(t, "\x1b[I\x1b[O" + "b", ch('b'))     // focus in/out
	expect_events(t, "\x80\xff" + "c", ch('c'))          // invalid UTF-8
	expect_events(t, "\x1b[99~" + "d", ch('d'))          // unknown ~ key
}

// Sequences kitty sends with the keyboard protocol's "disambiguate" flag.
@(test)
input_kitty_disambiguated_keys :: proc(t: ^testing.T) {
	expect_events(t, "\x1b[27u", key(.Esc))                       // Esc: no timeout needed
	expect_events(t, "\x1b[105;5u", ch('i', {.Ctrl}))            // Ctrl+I, not Tab
	expect_events(t, "\x1b[104;5u", ch('h', {.Ctrl}))            // Ctrl+H, not Backspace
	expect_events(t, "\x1b[109;5u", ch('m', {.Ctrl}))            // Ctrl+M, not Enter
	expect_events(t, "\x1b[13;2u", key(.Enter, {.Shift}))        // Shift+Enter
	expect_events(t, "\x1b[127;5u", key(.Backspace, {.Ctrl}))    // Ctrl+Backspace
	expect_events(t, "\x1b[9;2u", key(.Tab, {.Shift}))
	expect_events(t, "\x1b[120;3u", ch('x', {.Alt}))
	expect_events(t, "\x1b[97;6u", ch('a', {.Shift, .Ctrl}))
	expect_events(t, "\x1b[399;5u", ch('Ə', {.Ctrl}))             // non-ASCII codepoints too
	expect_events(t, "\x1b[99;69u", ch('c', {.Ctrl}))            // Caps Lock bit (64) is ignored
}

@(test)
input_kitty_keypad_and_unknown_keys :: proc(t: ^testing.T) {
	expect_events(t, "\x1b[57414u", key(.Enter))                 // KP_ENTER
	expect_events(t, "\x1b[57399u\x1b[57408u", ch('0'), ch('9')) // KP_0, KP_9
	expect_events(t, "\x1b[57413u", ch('+'))
	expect_events(t, "\x1b[57419u\x1b[57426u", key(.Up), key(.Delete))
	expect_events(t, "\x1b[57376u" + "a", ch('a'))               // F13: dropped
	expect_events(t, "\x1b[57441;2u" + "b", ch('b'))             // Left Shift on its own: dropped
}

@(test)
input_kitty_capability_reply :: proc(t: ^testing.T) {
	p: input.Parser
	input.parser_init(&p, context.temp_allocator)
	events := make([dynamic]input.Event, context.temp_allocator)
	testing.expect_value(t, p.keyboard_flags, -1)
	input.feed(&p, transmute([]u8)string("\x1b[?1u"), &events)
	testing.expect_value(t, p.keyboard_flags, 1)
	testing.expect_value(t, len(events), 0) // the reply is not an event
}
