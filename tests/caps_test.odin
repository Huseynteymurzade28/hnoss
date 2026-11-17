package tests

import "core:testing"
import hnoss ".."
import "../input"
import "../style"

// A parser awaiting replies to CAPS_QUERY, fed `chunks` one after another.
@(private = "file")
replies :: proc(chunks: ..string) -> (p: input.Parser, events: [dynamic]input.Event) {
	input.parser_init(&p, context.temp_allocator)
	input.await_replies(&p)
	events = make([dynamic]input.Event, context.temp_allocator)
	for c in chunks {
		input.feed(&p, transmute([]u8)c, &events)
	}
	return
}

KITTY_REPLIES :: "\x1bP>|kitty(0.39.1)\x1b\\" + "\x1b[?2026;2$y" + "\x1b[?2027;0$y" + "\x1bP1$r0;38:2:1:2:3m\x1b\\" + "\x1b[?62;4;22c"

@(test)
caps_replies_are_recorded_and_not_events :: proc(t: ^testing.T) {
	p, events := replies(KITTY_REPLIES)
	testing.expect_value(t, len(events), 0)
	c := &p.caps
	testing.expect(t, c.answered)
	testing.expect_value(t, input.caps_version(c), "kitty(0.39.1)")
	testing.expect_value(t, c.sync_output, input.Mode_State.Reset)
	testing.expect(t, input.mode_supported(c.sync_output))
	testing.expect_value(t, c.grapheme_clustering, input.Mode_State.Unsupported)
	testing.expect(t, !input.mode_supported(c.grapheme_clustering))
	testing.expect(t, c.truecolor)
	testing.expect(t, c.sixel)
	testing.expect_value(t, c.da1_len, 3)
	testing.expect_value(t, c.da1[0], 62)
	// DA1 ends it: ESC P is Alt+Shift+P again.
	testing.expect(t, !p.awaiting_replies)
	input.feed(&p, transmute([]u8)string("\x1bPx"), &events)
	testing.expect_value(t, len(events), 2)
	testing.expect_value(t, events[0], input.Event(input.Key{code = .Char, char = 'P', mods = {.Alt}}))
}

@(test)
caps_replies_split_and_mixed_with_keys :: proc(t: ^testing.T) {
	// Split anywhere, with a key press between replies.
	p, events := replies("\x1bP>|foo", "t(1.20)\x1b", "\\a\x1b[?2026;", "1$y\x1b[?6", "4;1c")
	testing.expect_value(t, len(events), 1)
	testing.expect_value(t, events[0], input.Event(input.Key{code = .Char, char = 'a'}))
	testing.expect_value(t, input.caps_version(&p.caps), "foot(1.20)")
	testing.expect_value(t, p.caps.sync_output, input.Mode_State.Set)
	testing.expect(t, p.caps.answered)
	testing.expect(t, !p.caps.sixel)
	testing.expect(t, !p.caps.truecolor)
}

@(test)
caps_truecolor_read_back :: proc(t: ^testing.T) {
	check :: proc(t: ^testing.T, reply: string, want: bool, loc := #caller_location) {
		p, _ := replies(reply, "\x1b[?1c")
		testing.expect_value(t, p.caps.truecolor, want, loc = loc)
	}
	check(t, "\x1bP1$r0;38:2::1:2:3m\x1b\\", true)
	check(t, "\x1bP1$r38;2;1;2;3m\x1b\\", true)
	check(t, "\x1bP1$r0;38;5;16m\x1b\\", false) // mapped to the palette
	check(t, "\x1bP0$r\x1b\\", false)              // DECRQSS not understood
	check(t, "\x1bP1$r0m\x1b\\", false)
}

@(test)
caps_dcs_only_while_awaiting :: proc(t: ^testing.T) {
	plain :: proc(bytes: string) -> []input.Event {
		p: input.Parser
		input.parser_init(&p, context.temp_allocator)
		events := make([dynamic]input.Event, context.temp_allocator)
		input.feed(&p, transmute([]u8)bytes, &events)
		input.flush(&p, &events)
		return events[:]
	}
	// Without await_replies, ESC P is Alt+Shift+P as before.
	got := plain("\x1bP")
	testing.expect_value(t, len(got), 1)
	testing.expect_value(t, got[0], input.Event(input.Key{code = .Char, char = 'P', mods = {.Alt}}))
	// A DCS cut off at a flush falls back to keys too.
	p, events := replies("\x1bP")
	input.flush(&p, &events)
	testing.expect_value(t, len(events), 1)
	testing.expect_value(t, events[0], input.Event(input.Key{code = .Char, char = 'P', mods = {.Alt}}))
	// A DECRPM / DA1 reply never becomes a key, awaited or not.
	testing.expect_value(t, len(plain("\x1b[?2026;1$y\x1b[?62c")), 0)
}

@(test)
caps_upgrade_depth_and_features :: proc(t: ^testing.T) {
	p, _ := replies(KITTY_REPLIES)
	d, f := hnoss.upgrade_from_caps(&p.caps, .Ansi256, {.Hyperlinks})
	testing.expect_value(t, d, style.Color_Depth.Truecolor)
	testing.expect_value(t, f, hnoss.Output_Features{.Hyperlinks, .Styled_Underlines})
	// NO_COLOR is never upgraded; Truecolor stays.
	d, _ = hnoss.upgrade_from_caps(&p.caps, .No_Color, {})
	testing.expect_value(t, d, style.Color_Depth.No_Color)
	// A terminal that only answered DA1 changes nothing.
	q, _ := replies("\x1b[?1;2c")
	d, f = hnoss.upgrade_from_caps(&q.caps, .Ansi16, {.Hyperlinks})
	testing.expect_value(t, d, style.Color_Depth.Ansi16)
	testing.expect_value(t, f, hnoss.Output_Features{.Hyperlinks})

	testing.expect(t, style.detect_styled_underlines({xtversion = "WezTerm 20240203-110809-5046fc22"}))
	testing.expect(t, style.detect_styled_underlines({xtversion = "ghostty 1.1.0"}))
	testing.expect(t, !style.detect_styled_underlines({xtversion = "XTerm(390)"}))
	testing.expect(t, !style.detect_styled_underlines({xtversion = "tmux 3.4"}))
}
