package input

import "core:strings"
import "core:time"

// How long to wait for the next key of a chord.
DEFAULT_CHORD_TIMEOUT :: time.Second

// The most keys in one chord.
MAX_CHORD :: 4

// One row of a key table. `keys` is a key or, separated by spaces, the keys
// of a chord ("Ctrl+S", "g g", "Ctrl+K Ctrl+S"; see parse_key). `action` is
// the name your code gets back and `desc` what the help page says. An
// action may have several rows. A row with neither keys nor an action is a
// heading for the help page.
Binding :: struct {
	keys, action, desc: string,
}

Chord :: struct {
	keys: [MAX_CHORD]Key,
	len:  int,
}

// Which keys mean which action, and the chord being typed. The strings of
// the bindings are not copied, so they must outlive the keymap.
Keymap :: struct {
	actions: [dynamic]Keymap_Action, // and headings, in help page order
	bound:   [dynamic]Bound_Chord,
	pending: Chord, // typed so far, the beginning of some chord
	at:      time.Tick, // of its last key
	timeout: time.Duration, // 0: DEFAULT_CHORD_TIMEOUT, below 0: none
}

Keymap_Action :: struct {
	name, desc: string, // a heading has no name
}

Bound_Chord :: struct {
	chord:  Chord,
	action: int, // index in Keymap.actions
}

// Returns the index of the first binding whose keys could not be read, or
// -1. The others are bound.
keymap_init :: proc(km: ^Keymap, bindings: []Binding, allocator := context.allocator) -> (bad: int) {
	km.actions = make([dynamic]Keymap_Action, allocator)
	km.bound = make([dynamic]Bound_Chord, allocator)
	bad = -1
	for b, i in bindings {
		if b.keys == "" && b.action == "" {
			append(&km.actions, Keymap_Action{desc = b.desc})
		} else if !keymap_bind(km, b) && bad < 0 {
			bad = i
		}
	}
	return
}

keymap_destroy :: proc(km: ^Keymap) {
	delete(km.actions)
	delete(km.bound)
	km^ = {}
}

// Adds a binding, next to the ones its action has. Keys that were bound to
// another action move to this one. An action without keys is only listed,
// for `keymap_rebind` later. False if the keys can't be read.
keymap_bind :: proc(km: ^Keymap, b: Binding) -> bool {
	chord: Chord
	if b.keys != "" {
		chord = parse_chord(b.keys) or_return
	}
	if b.action == "" { return false }
	action := find_action(km, b.action)
	if action < 0 {
		action = len(km.actions)
		append(&km.actions, Keymap_Action{name = b.action})
	}
	if b.desc != "" { km.actions[action].desc = b.desc }
	if chord.len > 0 {
		unbind_chord(km, chord)
		append(&km.bound, Bound_Chord{chord, action})
	}
	km.pending = {}
	return true
}

// Takes `keys` away from whatever they are bound to. False if that is nothing.
keymap_unbind :: proc(km: ^Keymap, keys: string) -> bool {
	chord := parse_chord(keys) or_return
	km.pending = {}
	return unbind_chord(km, chord)
}

// Replaces every binding of `action` with `keys`. False, and nothing
// changes, if there is no such action or the keys can't be read.
keymap_rebind :: proc(km: ^Keymap, action, keys: string) -> bool {
	i := find_action(km, action)
	if i < 0 { return false }
	chord := parse_chord(keys) or_return
	for j := len(km.bound) - 1; j >= 0; j -= 1 {
		if km.bound[j].action == i { ordered_remove(&km.bound, j) }
	}
	unbind_chord(km, chord)
	append(&km.bound, Bound_Chord{chord, i})
	km.pending = {}
	return true
}

// The action `keys` are bound to, "" if none.
keymap_lookup :: proc(km: ^Keymap, keys: string) -> string {
	chord, ok := parse_chord(keys)
	if !ok { return "" }
	i, _ := match_chord(km, chord)
	return km.actions[i].name if i >= 0 else ""
}

// Every chord bound to `action`, joined by ", " ("Ctrl+S, F2").
keymap_keys :: proc(km: ^Keymap, action: string, allocator := context.temp_allocator) -> string {
	sb := strings.builder_make(allocator)
	i := find_action(km, action)
	for b in km.bound {
		if i < 0 || b.action != i { continue }
		if strings.builder_len(sb) > 0 { strings.write_string(&sb, ", ") }
		strings.write_string(&sb, chord_name(b.chord))
	}
	return strings.to_string(sb)
}

// Handles one key at `now` and appends the names of the actions it set off
// to `actions`. False if the key is not part of any binding.
//
// A key that begins a longer chord waits for the rest. When what follows
// doesn't fit, the keys so far count on their own if they are bound, and are
// dropped otherwise; then the new key is looked at afresh. Esc only gives up
// the chord.
keymap_feed :: proc(km: ^Keymap, key: Key, now: time.Tick, actions: ^[dynamic]string) -> bool {
	keymap_expire(km, now, actions)
	for {
		chord := km.pending
		chord.keys[chord.len] = normalize_key(key) // a pending chord always has room
		chord.len += 1
		action, longer := match_chord(km, chord)
		if longer {
			km.pending = chord
			km.at = now
			return true
		}
		waiting := km.pending.len > 0
		if action >= 0 {
			km.pending = {}
			append(actions, km.actions[action].name)
			return true
		}
		if !waiting {
			return false
		}
		give_up(km, actions)
		if key.code == .Esc && key.mods == {} {
			return true
		}
	}
}

// Ends a chord that has waited longer than the timeout: keys that are bound
// on their own ("g" next to "g g") set their action off now.
keymap_expire :: proc(km: ^Keymap, now: time.Tick, actions: ^[dynamic]string) {
	if left, waiting := keymap_waiting(km, now); waiting && left <= 0 {
		give_up(km, actions)
	}
}

// How long until the chord being typed times out; false when there is none
// or it never does.
keymap_waiting :: proc(km: ^Keymap, now: time.Tick) -> (left: time.Duration, ok: bool) {
	if km.pending.len == 0 || km.timeout < 0 { return 0, false }
	timeout := km.timeout if km.timeout > 0 else DEFAULT_CHORD_TIMEOUT
	return timeout - time.tick_diff(km.at, now), true
}

// The keys of the chord being typed, e.g. to show in a status bar; "" when none.
keymap_pending :: proc(km: ^Keymap, allocator := context.temp_allocator) -> string {
	return chord_name(km.pending, allocator)
}

// Keys separated by spaces: at least one, at most MAX_CHORD.
parse_chord :: proc(s: string) -> (c: Chord, ok: bool) {
	rest := s
	for word in strings.fields_iterator(&rest) {
		if c.len == MAX_CHORD { return {}, false }
		c.keys[c.len] = parse_key(word) or_return
		c.len += 1
	}
	return c, c.len > 0
}

chord_name :: proc(c: Chord, allocator := context.temp_allocator) -> string {
	c := c
	sb := strings.builder_make(allocator)
	for k, i in c.keys[:c.len] {
		if i > 0 { strings.write_byte(&sb, ' ') }
		strings.write_string(&sb, key_name(k))
	}
	return strings.to_string(sb)
}

@(private)
give_up :: proc(km: ^Keymap, actions: ^[dynamic]string) {
	if i, _ := match_chord(km, km.pending); i >= 0 {
		append(actions, km.actions[i].name)
	}
	km.pending = {}
}

// The action `c` is bound to (-1: none), and whether a longer chord starts
// with it.
@(private)
match_chord :: proc(km: ^Keymap, c: Chord) -> (action: int, longer: bool) {
	action = -1
	for b in km.bound {
		if b.chord == c {
			action = b.action
		} else if b.chord.len > c.len {
			head := b.chord
			for &k in head.keys[c.len:] { k = {} }
			longer ||= head.keys == c.keys
		}
	}
	return
}

@(private)
unbind_chord :: proc(km: ^Keymap, c: Chord) -> bool {
	for b, i in km.bound {
		if b.chord == c {
			ordered_remove(&km.bound, i)
			return true
		}
	}
	return false
}

@(private)
find_action :: proc(km: ^Keymap, name: string) -> int {
	if name == "" { return -1 }
	for a, i in km.actions {
		if a.name == name { return i }
	}
	return -1
}
