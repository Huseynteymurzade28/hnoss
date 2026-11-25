package input

import "core:strings"

// The queries init sends to learn what the terminal can do, in order. The
// terminal answers them in the same order, and every terminal answers DA1,
// so its reply marks the end: whatever hasn't answered by then never will.
//
//   XTVERSION   CSI > 0 q           -> DCS > | name(version) ST
//   DECRQM      CSI ? 2026 $ p      -> CSI ? 2026 ; state $ y   synchronized output
//   DECRQM      CSI ? 2027 $ p      -> CSI ? 2027 ; state $ y   grapheme clustering
//   DECRQSS     (set an RGB color)  -> DCS 1 $ r 0;38:2::1:2:3m ST
//               DCS $ q m ST           read the SGR state back: a terminal
//                                      without truecolor reports the nearest
//                                      palette color instead
//   DA1         CSI c               -> CSI ? 62 ; 4 ; 22 c       (4: sixel)
//
// https://invisible-island.net/xterm/ctlseqs/ctlseqs.html
// https://gist.github.com/christianparpart/d8a62cc1ab659194337d73e399004036
CAPS_QUERY :: "\x1b[>0q" + "\x1b[?2026$p" + "\x1b[?2027$p" + "\x1b[38;2;1;2;3m" + "\x1bP$qm\x1b\\" + "\x1b[0m" + "\x1b[c"

// What the terminal said about a DEC private mode (DECRPM).
Mode_State :: enum u8 {
	Unknown,      // no answer (yet)
	Unsupported,  // the terminal doesn't know the mode
	Set,
	Reset,        // supported, currently off
	Always_Set,   // permanently on
	Always_Reset, // known but can't be turned on
}

// True when the mode can be used: the terminal knows it and it isn't
// stuck off.
mode_supported :: proc(m: Mode_State) -> bool {
	return m == .Set || m == .Reset || m == .Always_Set
}

// What the terminal reported in reply to CAPS_QUERY. Fields fill in as
// replies arrive; `answered` is set by the last one (DA1), after which
// nothing else changes.
Caps :: struct {
	answered:            bool,
	sync_output:         Mode_State, // ?2026
	grapheme_clustering: Mode_State, // ?2027
	truecolor:           bool,       // an RGB color read back unchanged
	sixel:               bool,       // DA1 attribute 4
	da1:                 [16]int,    // DA1 parameters: the conformance level, then attributes
	da1_len:             int,
	version_buf:         [64]u8,     // XTVERSION, e.g. "kitty(0.39.1)"; see caps_version
	version_len:         int,
}

// The terminal's name and version from XTVERSION, "" if it didn't say.
caps_version :: proc(c: ^Caps) -> string {
	return string(c.version_buf[:c.version_len])
}

// Puts the parser in the state for replies to CAPS_QUERY: DCS strings
// (ESC P … ESC \) are read as replies until DA1 answers or
// `stop_awaiting_replies`. Outside it ESC P is Alt+Shift+P, as before.
await_replies :: proc(p: ^Parser) {
	p.awaiting_replies = true
}

// Gives up on replies that never came (e.g. not a real terminal).
stop_awaiting_replies :: proc(p: ^Parser) {
	p.awaiting_replies = false
}

// Records one reply sequence (all of it, from ESC on).
@(private)
record_reply :: proc(p: ^Parser, seq: []u8) {
	c := &p.caps
	s := string(seq)
	if strings.has_prefix(s, "\x1bP") {
		body := strings.trim_suffix(s[2:], "\x1b\\")
		switch {
		case strings.has_prefix(body, ">|"):
			name := body[2:]
			n := copy(c.version_buf[:], name)
			for n > 0 && n < len(name) && name[n] & 0xc0 == 0x80 {
				n -= 1 // don't cut a UTF-8 sequence in half
			}
			c.version_len = n
		case strings.has_prefix(body, "1$r"):
			c.truecolor = reports_test_color(body[3:])
		}
		return
	}

	// CSI ? … $ y (DECRPM) or CSI ? … c (DA1).
	body := seq[3:len(seq) - 1]
	params: [MAX_PARAMS]int
	switch seq[len(seq) - 1] {
	case 'y':
		n := parse_params(body[:len(body) - 1], &params) // drop the '$'
		if n < 2 { return }
		state := Mode_State.Unknown
		switch params[1] {
		case 0: state = .Unsupported
		case 1: state = .Set
		case 2: state = .Reset
		case 3: state = .Always_Set
		case 4: state = .Always_Reset
		}
		switch params[0] {
		case 2026: c.sync_output = state
		case 2027: c.grapheme_clustering = state
		}
	case 'c':
		c.da1_len = 0
		cur, have := 0, false
		for b in body {
			switch b {
			case '0' ..= '9':
				cur = min(cur * 10 + int(b - '0'), 1 << 20)
				have = true
			case ';':
				push_da1(c, cur)
				cur, have = 0, false
			}
		}
		if have { push_da1(c, cur) }
		for v, i in c.da1[:c.da1_len] {
			if i > 0 && v == 4 { c.sixel = true }
		}
		c.answered = true
		p.awaiting_replies = false
	}
}

@(private)
push_da1 :: proc(c: ^Caps, v: int) {
	if c.da1_len < len(c.da1) {
		c.da1[c.da1_len] = v
		c.da1_len += 1
	}
}

// The SGR state DECRQSS reported ("0;38:2::1:2:3m", "38;2;1;2;3m", …)
// still holds the RGB color CAPS_QUERY set: 38, 2, then 1, 2, 3, with
// any empty color-space field skipped.
@(private)
reports_test_color :: proc(sgr: string) -> bool {
	nums: [32]int
	n := 0
	cur, have := 0, false
	for i in 0 ..= len(sgr) {
		b := sgr[i] if i < len(sgr) else ';'
		switch b {
		case '0' ..= '9':
			cur = min(cur * 10 + int(b - '0'), 1 << 20)
			have = true
		case:
			if have && n < len(nums) {
				nums[n] = cur
				n += 1
			}
			cur, have = 0, false
		}
	}
	want := [5]int{38, 2, 1, 2, 3}
	for i in 0 ..= n - len(want) {
		got: [5]int
		copy(got[:], nums[i:])
		if got == want {
			return true
		}
	}
	return false
}

// Longest DCS reply we wait for; anything longer is dropped.
@(private)
MAX_DCS :: 256

// DCS: ESC P … ESC \ (only while awaiting replies).
@(private)
parse_dcs :: proc(b: []u8) -> (int, Status) {
	for i in 2 ..< min(len(b), MAX_DCS) {
		if b[i] == 0x1b && i + 1 < min(len(b), MAX_DCS) && b[i + 1] == '\\' {
			return i + 2, .Reply
		}
	}
	if len(b) >= MAX_DCS {
		return MAX_DCS, .Skip
	}
	return 0, .Incomplete
}
