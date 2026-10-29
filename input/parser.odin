package input

import "core:mem"
import "core:strings"
import "core:unicode/utf8"

// Turns the raw byte stream from the terminal into Events. It is
// incremental: a sequence split across two reads is kept until the rest
// arrives.
//
// One ambiguity cannot be resolved from the bytes alone: ESC is both the Esc
// key and the first byte of every escape sequence. `feed` leaves a trailing
// lone ESC (or an unfinished ESC [ / ESC O) buffered; the caller waits a
// short time for more bytes and calls `flush` if none come, which reports
// what is buffered literally (Esc, Alt+[, ...).
//
// References:
//   https://invisible-island.net/xterm/ctlseqs/ctlseqs.html (PC-style function keys,
//     SGR mouse mode 1006, bracketed paste 2004)
//   https://sw.kovidgoyal.net/kitty/keyboard-protocol/ (CSI u)
Parser :: struct {
	pending:  [dynamic]u8, // bytes of an incomplete sequence
	paste:    [dynamic]u8,
	in_paste: bool,
}

parser_init :: proc(p: ^Parser, allocator := context.allocator) {
	p.pending = make([dynamic]u8, 0, 64, allocator)
	p.paste = make([dynamic]u8, 0, 0, allocator)
	p.in_paste = false
}

parser_destroy :: proc(p: ^Parser) {
	delete(p.pending)
	delete(p.paste)
	p^ = {}
}

// True when bytes are buffered that may still become part of a sequence:
// the caller should wait for more input (or time out and `flush`).
has_pending :: proc(p: ^Parser) -> bool {
	return len(p.pending) > 0 && !p.in_paste
}

// Parses `data` (after anything already buffered) and appends complete
// events to `events`. Paste text is allocated with `allocator`.
feed :: proc(p: ^Parser, data: []u8, events: ^[dynamic]Event, allocator := context.temp_allocator) {
	append(&p.pending, ..data)
	run(p, events, false, allocator)
}

// No more bytes are coming for now: interpret whatever is buffered.
flush :: proc(p: ^Parser, events: ^[dynamic]Event, allocator := context.temp_allocator) {
	run(p, events, true, allocator)
}

@(private)
PASTE_START :: "\x1b[200~"
@(private)
PASTE_END :: "\x1b[201~"

@(private)
run :: proc(p: ^Parser, events: ^[dynamic]Event, final: bool, allocator: mem.Allocator) {
	b := p.pending[:]
	i := 0
	for i < len(b) {
		if p.in_paste {
			// Everything up to the end marker is literal text, escape
			// sequences included.
			rest := string(b[i:])
			if end := strings.index(rest, PASTE_END); end >= 0 {
				append(&p.paste, rest[:end])
				append(events, Paste{strings.clone(string(p.paste[:]), allocator)})
				clear(&p.paste)
				p.in_paste = false
				i += end + len(PASTE_END)
				continue
			}
			// Keep a tail that could be the start of a split end marker.
			keep := min(len(rest), len(PASTE_END) - 1)
			for keep > 0 && !strings.has_prefix(PASTE_END, rest[len(rest) - keep:]) {
				keep -= 1
			}
			append(&p.paste, rest[:len(rest) - keep])
			i = len(b) - keep
			break
		}

		ev, n, st := parse_one(b[i:], final)
		if st == .Incomplete {
			break
		}
		i += n
		switch st {
		case .Event:      append(events, ev)
		case .Paste_Start: p.in_paste = true
		case .Skip, .Incomplete:
		}
	}
	remove_range(&p.pending, 0, i)
}

@(private)
Status :: enum u8 {
	Event,
	Skip,        // consumed, nothing to report (unknown or ignored sequence)
	Incomplete,  // need more bytes
	Paste_Start,
}

// Decodes the first event in `b` (len >= 1). `final` means no more bytes
// will follow, so a prefix must be interpreted as-is.
@(private)
parse_one :: proc(b: []u8, final: bool) -> (Event, int, Status) {
	if b[0] != 0x1b {
		return parse_plain(b, final)
	}
	if len(b) == 1 {
		if final { return Key{code = .Esc}, 1, .Event }
		return nil, 0, .Incomplete
	}
	switch b[1] {
	case '[':
		ev, n, st := parse_csi(b)
		if st == .Incomplete && final {
			return Key{code = .Char, char = '[', mods = {.Alt}}, 2, .Event
		}
		return ev, n, st
	case 'O':
		if len(b) < 3 {
			if final { return Key{code = .Char, char = 'O', mods = {.Alt}}, 2, .Event }
			return nil, 0, .Incomplete
		}
		return parse_ss3(b)
	case 0x1b:
		// ESC ESC: Esc pressed twice, or a slow Alt+Esc. Report the first.
		return Key{code = .Esc}, 1, .Event
	}
	// ESC + key = Alt+key (the "meta sends escape" convention).
	ev, n, st := parse_plain(b[1:], final)
	if st == .Incomplete {
		return nil, 0, .Incomplete
	}
	if k, ok := ev.(Key); ok {
		k.mods += {.Alt}
		return k, n + 1, .Event
	}
	return ev, n + 1, st
}

// A byte that does not start an escape sequence: a control key or UTF-8 text.
@(private)
parse_plain :: proc(b: []u8, final: bool) -> (Event, int, Status) {
	c := b[0]
	switch c {
	case 0x0d:        return Key{code = .Enter}, 1, .Event
	case 0x09:        return Key{code = .Tab}, 1, .Event
	case 0x7f, 0x08:  return Key{code = .Backspace}, 1, .Event // 0x08: Ctrl+H / Ctrl+Backspace on some terminals
	case 0x1b:        return Key{code = .Esc}, 1, .Event
	case 0x00:        return Key{code = .Char, char = ' ', mods = {.Ctrl}}, 1, .Event
	case 0x01 ..= 0x1a:
		// Ctrl+A .. Ctrl+Z (0x0a, Enter's \n, is Ctrl+J in raw mode).
		return Key{code = .Char, char = rune('a' + c - 1), mods = {.Ctrl}}, 1, .Event
	case 0x1c ..= 0x1f:
		// Ctrl+\ Ctrl+] Ctrl+^ Ctrl+_ (Ctrl+/ usually sends 0x1f too)
		return Key{code = .Char, char = rune(c + 0x40), mods = {.Ctrl}}, 1, .Event // 0x1c + 0x40 = '\\'
	}

	if c < 0x80 {
		return Key{code = .Char, char = rune(c)}, 1, .Event
	}
	want := utf8_len(c)
	if want == 0 {
		return nil, 1, .Skip // stray continuation byte or invalid lead
	}
	if len(b) < want {
		if final { return nil, len(b), .Skip }
		return nil, 0, .Incomplete
	}
	r, n := utf8.decode_rune(b[:want])
	if r == utf8.RUNE_ERROR {
		return nil, 1, .Skip
	}
	return Key{code = .Char, char = r}, n, .Event
}

@(private)
utf8_len :: proc(lead: u8) -> int {
	switch {
	case lead & 0xe0 == 0xc0: return 2
	case lead & 0xf0 == 0xe0: return 3
	case lead & 0xf8 == 0xf0: return 4
	}
	return 0
}

// SS3 (ESC O x): arrows/Home/End in application cursor mode, F1-F4.
@(private)
parse_ss3 :: proc(b: []u8) -> (Event, int, Status) {
	code: Key_Code
	switch b[2] {
	case 'A': code = .Up
	case 'B': code = .Down
	case 'C': code = .Right
	case 'D': code = .Left
	case 'H': code = .Home
	case 'F': code = .End
	case 'M': code = .Enter // keypad Enter
	case 'P': code = .F1
	case 'Q': code = .F2
	case 'R': code = .F3
	case 'S': code = .F4
	case:     return nil, 3, .Skip
	}
	return Key{code = code}, 3, .Event
}

// Longest CSI we accept; anything longer is garbage and gets dropped.
@(private)
MAX_CSI :: 64

@(private)
MAX_PARAMS :: 8

// CSI: ESC [ <private?> <params 0x30-0x3f> <intermediates 0x20-0x2f> <final 0x40-0x7e>
@(private)
parse_csi :: proc(b: []u8) -> (Event, int, Status) {
	end := -1
	for i in 2 ..< min(len(b), MAX_CSI) {
		if b[i] >= 0x40 && b[i] <= 0x7e {
			end = i
			break
		}
		if b[i] < 0x20 || b[i] > 0x3f {
			return nil, i, .Skip // not a valid CSI byte: drop what we have
		}
	}
	if end < 0 {
		if len(b) >= MAX_CSI { return nil, MAX_CSI, .Skip }
		return nil, 0, .Incomplete
	}
	n := end + 1
	final := b[end]
	body := b[2:end]

	private: u8
	if len(body) > 0 && body[0] >= '<' && body[0] <= '?' {
		private = body[0]
		body = body[1:]
	}

	params: [MAX_PARAMS]int
	nparams := parse_params(body, &params)

	if private == '<' {
		if final == 'M' || final == 'm' {
			return parse_sgr_mouse(params[:nparams], final == 'm'), n, .Event
		}
		return nil, n, .Skip
	}
	if private != 0 {
		return nil, n, .Skip // e.g. replies to queries we never sent
	}

	mods := decode_modifiers(params[1] if nparams > 1 else 1)
	code: Key_Code
	switch final {
	case 'A': code = .Up
	case 'B': code = .Down
	case 'C': code = .Right
	case 'D': code = .Left
	case 'H': code = .Home
	case 'F': code = .End
	case 'P': code = .F1
	case 'Q': code = .F2
	case 'R': code = .F3
	case 'S': code = .F4
	case 'Z': return Key{code = .Back_Tab, mods = mods + {.Shift}}, n, .Event
	case '~':
		if nparams == 0 { return nil, n, .Skip }
		switch params[0] {
		case 200:    return nil, n, .Paste_Start
		case 201:    return nil, n, .Skip // stray end marker
		case 1, 7:   code = .Home
		case 2:      code = .Insert
		case 3:      code = .Delete
		case 4, 8:   code = .End
		case 5:      code = .Page_Up
		case 6:      code = .Page_Down
		case 11:     code = .F1
		case 12:     code = .F2
		case 13:     code = .F3
		case 14:     code = .F4
		case 15:     code = .F5
		case 17:     code = .F6
		case 18:     code = .F7
		case 19:     code = .F8
		case 20:     code = .F9
		case 21:     code = .F10
		case 23:     code = .F11
		case 24:     code = .F12
		case:        return nil, n, .Skip
		}
	case 'u':
		// CSI codepoint ; modifiers u (fixterms / kitty, used by some
		// terminals for keys like Ctrl+Enter even without the protocol).
		if nparams == 0 { return nil, n, .Skip }
		return csi_u_key(params[0], mods), n, .Event
	case:
		return nil, n, .Skip // focus in/out, cursor reports, ...
	}
	return Key{code = code, mods = mods}, n, .Event
}

// Semicolon-separated decimal params; empty params are 0, ':' sub-params
// are skipped. Returns how many were present.
@(private)
parse_params :: proc(body: []u8, out: ^[MAX_PARAMS]int) -> int {
	if len(body) == 0 {
		return 0
	}
	n := 0
	cur := 0
	sub := false
	for c in body {
		switch c {
		case '0' ..= '9':
			if !sub { cur = min(cur * 10 + int(c - '0'), 1 << 20) }
		case ';':
			if n < MAX_PARAMS { out[n] = cur }
			n += 1
			cur = 0
			sub = false
		case ':':
			sub = true
		}
	}
	if n < MAX_PARAMS { out[n] = cur }
	return min(n + 1, MAX_PARAMS)
}

// xterm encodes modifiers as 1 + bits (1 Shift, 2 Alt, 4 Ctrl, 8 Meta/Super),
// which lines up with Key_Modifier's bit positions.
@(private)
decode_modifiers :: proc(param: int) -> Key_Modifiers {
	if param <= 1 {
		return {}
	}
	return transmute(Key_Modifiers)u8((param - 1) & 0xf)
}

@(private)
csi_u_key :: proc(cp: int, mods: Key_Modifiers) -> Key {
	switch cp {
	case 13:  return {code = .Enter, mods = mods}
	case 9:   return {code = .Tab, mods = mods}
	case 27:  return {code = .Esc, mods = mods}
	case 127: return {code = .Backspace, mods = mods}
	}
	return {code = .Char, char = rune(cp), mods = mods}
}

// SGR (1006) mouse: CSI < b ; x ; y M  (press/motion)  or  ... m  (release).
//   b & 3: 0 left, 1 middle, 2 right, 3 none   b & 4 Shift, 8 Alt, 16 Ctrl
//   b & 32: motion   b & 64: wheel (b & 3: 0 up, 1 down, 2 left, 3 right)
@(private)
parse_sgr_mouse :: proc(params: []int, release: bool) -> Mouse {
	if len(params) < 3 {
		return {}
	}
	b := params[0]
	m := Mouse{x = max(params[1] - 1, 0), y = max(params[2] - 1, 0)}
	if b & 4 != 0 { m.mods += {.Shift} }
	if b & 8 != 0 { m.mods += {.Alt} }
	if b & 16 != 0 { m.mods += {.Ctrl} }

	low := b & 3
	switch {
	case b & 64 != 0:
		m.kind = .Scroll
		m.button = Mouse_Button(int(Mouse_Button.Wheel_Up) + low)
	case b & 32 != 0:
		if low == 3 {
			m.kind = .Move
		} else {
			m.kind = .Drag
			m.button = Mouse_Button(int(Mouse_Button.Left) + low)
		}
	case:
		m.kind = .Release if release else .Press
		if low != 3 {
			m.button = Mouse_Button(int(Mouse_Button.Left) + low)
		}
	}
	return m
}
