package tests

import "core:fmt"
import "core:math/rand"
import "core:mem"
import "core:strings"
import "core:testing"
import "core:unicode/utf8"
import "../input"

// Fixed, so a failure in CI happens again here. Every failure reports the
// bytes that caused it.
@(private = "file")
FUZZ_SEED :: 0x686e6f7373

@(private = "file")
FUZZ_RUNS :: 4000

// Longer than any sequence the parser waits for (MAX_DCS).
@(private = "file")
MAX_PENDING :: 256

// Whole sequences, the kind a terminal sends.
@(private = "file", rodata)
SEQUENCES := []string {
	"a", "Z", "ö", "世", "🎉", "\r", "\t", "\x7f", "\x00", "\x03", "\x1c",
	"\x1ba", "\x1bö", "\x1b\r",
	"\x1bOA", "\x1bOH", "\x1bOP", "\x1bOM",
	"\x1b[A", "\x1b[1;5C", "\x1b[H", "\x1b[Z", "\x1b[3~", "\x1b[15;2~", "\x1b[24~",
	"\x1b[I", "\x1b[O",
	"\x1b[97;5u", "\x1b[13;2u", "\x1b[57399u", "\x1b[97:65;2:1u", "\x1b[?1u",
	"\x1b[<0;10;20M", "\x1b[<0;10;20m", "\x1b[<35;1;1M", "\x1b[<64;5;5M", "\x1b[<128;3;3M",
	"\x1b[200~hello\x1b[201~", "\x1b[200~\x1b[A ö\x1b[20\x1b[201~", "\x1b[200~\x1b[201~",
	"\x1b[?62;4;22c", "\x1b[?2026;2$y", "\x1bP>|kitty(0.39.1)\x1b\\", "\x1bP1$r0;38:2::1:2:3m\x1b\\",
}

// Bytes that matter to the parser, picked more often than the others.
@(private = "file")
random_byte :: proc() -> u8 {
	INTERESTING :: "\x1b\x1b\x1b[[OP<?;:~$uMmcy\\0129\x00\r\x7f\xc3\xe4\xf0\x80\xff"
	if rand.int_max(3) == 0 {
		return u8(rand.int_max(256))
	}
	s := INTERESTING
	return s[rand.int_max(len(s))]
}

@(private = "file")
random_bytes :: proc(n: int) -> []u8 {
	out := make([]u8, n, context.temp_allocator)
	for &b in out { b = random_byte() }
	return out
}

// Whole sequences one after the other.
@(private = "file")
random_sequences :: proc(n: int) -> []u8 {
	sb := strings.builder_make(context.temp_allocator)
	for _ in 0 ..< n {
		strings.write_string(&sb, SEQUENCES[rand.int_max(len(SEQUENCES))])
	}
	return sb.buf[:]
}

// Feeds `bytes` in pieces of 1 to `max_piece` bytes (0: all at once), and
// flushes at the end.
@(private = "file")
feed_split :: proc(bytes: []u8, max_piece: int, replies: bool) -> (events: []input.Event, p: input.Parser) {
	input.parser_init(&p, context.temp_allocator)
	if replies { input.await_replies(&p) }
	out := make([dynamic]input.Event, context.temp_allocator)
	for rest := bytes; len(rest) > 0; {
		n := len(rest)
		if max_piece > 0 { n = min(n, 1 + rand.int_max(max_piece)) }
		input.feed(&p, rest[:n], &out)
		rest = rest[n:]
	}
	input.flush(&p, &out)
	return out[:], p
}

@(private = "file")
same_events :: proc(a, b: []input.Event) -> bool {
	if len(a) != len(b) { return false }
	for ev, i in a {
		if ev != b[i] { return false }
	}
	return true
}

@(private = "file")
expect_split_agrees :: proc(t: ^testing.T, bytes: []u8, max_piece: int, replies: bool) -> bool {
	whole, p := feed_split(bytes, 0, replies)
	split, q := feed_split(bytes, max_piece, replies)
	same := same_events(whole, split) && p.in_paste == q.in_paste && p.caps == q.caps && p.keyboard_flags == q.keyboard_flags
	return testing.expectf(t, same, "%q: split differently\nwhole %v\nsplit %v", string(bytes), whole, split)
}

// What no byte stream may produce.
@(private = "file")
expect_sane :: proc(t: ^testing.T, events: []input.Event, bytes: []u8) -> bool {
	for ev in events {
		ok := true
		#partial switch e in ev {
		case input.Key:
			ok = e.code != .None && (e.code == .Char) == (e.char != 0) && utf8.valid_rune(e.char)
		case input.Mouse:
			ok = e.x >= 0 && e.y >= 0 && e.clicks == 0
			if e.kind == .Press || e.kind == .Drag || e.kind == .Scroll {
				ok &&= e.button != .None
			}
		case input.Resize: ok = false
		}
		testing.expectf(t, ok, "%q: bad event %v", string(bytes), ev) or_return
	}
	return true
}

@(test)
fuzz_random_bytes :: proc(t: ^testing.T) {
	rand.reset(FUZZ_SEED)
	for run in 0 ..< FUZZ_RUNS {
		bytes := random_bytes(1 + rand.int_max(120))
		replies := run % 2 == 0

		p: input.Parser
		input.parser_init(&p, context.temp_allocator)
		if replies { input.await_replies(&p) }
		events := make([dynamic]input.Event, context.temp_allocator)
		for rest := bytes; len(rest) > 0; {
			n := min(len(rest), 1 + rand.int_max(16))
			input.feed(&p, rest[:n], &events)
			rest = rest[n:]
			if !testing.expectf(t, len(p.pending) <= MAX_PENDING, "%q: %d bytes pending", string(bytes), len(p.pending)) { return }
		}
		input.flush(&p, &events)
		if !testing.expectf(t, !input.has_pending(&p), "%q: stuck with %q", string(bytes), string(p.pending[:])) { return }
		if !expect_sane(t, events[:], bytes) { return }

		// Nothing it was fed may keep it from reading the next key. A paste
		// has to end first.
		if p.in_paste { input.feed(&p, transmute([]u8)string("\x1b[201~"), &events) }
		clear(&events)
		input.feed(&p, transmute([]u8)string("\x1b[A"), &events)
		if !testing.expectf(t, len(events) == 1 && input.is_key(events[0], .Up), "%q: then Up gives %v", string(bytes), events[:]) { return }
		free_all(context.temp_allocator)
	}
}

@(test)
fuzz_random_bytes_split_anywhere :: proc(t: ^testing.T) {
	rand.reset(FUZZ_SEED)
	for run in 0 ..< FUZZ_RUNS {
		if !expect_split_agrees(t, random_bytes(1 + rand.int_max(120)), 1 + rand.int_max(8), run % 2 == 0) { return }
		free_all(context.temp_allocator)
	}
}

@(test)
fuzz_sequences_split_anywhere :: proc(t: ^testing.T) {
	rand.reset(FUZZ_SEED)
	for run in 0 ..< FUZZ_RUNS {
		if !expect_split_agrees(t, random_sequences(1 + rand.int_max(12)), 1 + rand.int_max(8), run % 2 == 0) { return }
		free_all(context.temp_allocator)
	}
}

// Every sequence, split in two at every byte.
@(test)
fuzz_each_sequence_at_every_split :: proc(t: ^testing.T) {
	for s in SEQUENCES {
		bytes := transmute([]u8)s
		whole, _ := feed_split(bytes, 0, true)
		for at in 1 ..< len(bytes) {
			p: input.Parser
			input.parser_init(&p, context.temp_allocator)
			input.await_replies(&p)
			events := make([dynamic]input.Event, context.temp_allocator)
			input.feed(&p, bytes[:at], &events)
			input.feed(&p, bytes[at:], &events)
			input.flush(&p, &events)
			testing.expectf(t, same_events(events[:], whole), "%q split at %d: %v, want %v", s, at, events[:], whole)
		}
	}
}

// A sequence that never ends must not grow the parser's buffer with it.
@(test)
fuzz_endless_sequences_stay_bounded :: proc(t: ^testing.T) {
	for start in ([]string{"\x1b[", "\x1b[<", "\x1b[?", "\x1bP", "\x1bP>|"}) {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		defer mem.tracking_allocator_destroy(&track)

		p: input.Parser
		input.parser_init(&p, mem.tracking_allocator(&track))
		defer input.parser_destroy(&p)
		input.await_replies(&p)
		events := make([dynamic]input.Event, context.temp_allocator)
		input.feed(&p, transmute([]u8)start, &events)
		for _ in 0 ..< 10_000 {
			input.feed(&p, transmute([]u8)string("1;"), &events)
		}
		testing.expect(t, len(p.pending) <= MAX_PENDING, fmt.tprintf("%q: %d bytes pending", start, len(p.pending)))
		testing.expectf(t, track.peak_memory_allocated < 4096, "%q: %d bytes allocated", start, track.peak_memory_allocated)
	}
}
