package widgets

import "core:time"
import "../input"

// The names of the actions this frame's keys set off, in order; the keys
// are consumed. Only keys nobody has consumed yet count, so call it after
// the widgets and typing into a field sets nothing off. Called before them
// the keymap goes first, which suits chords whose keys a widget uses too
// ("g g" over a list).
//
//	for action in hnoss.actions(ui, &keymap) {
//		switch action {
//		case "save": save()
//		case "quit": return
//		}
//	}
//
// A chord being typed times out: wait with `keymap_timeout`.
actions :: proc(ui: ^Ui, km: ^input.Keymap) -> []string {
	out := make([dynamic]string, context.temp_allocator)
	input.keymap_expire(km, ui.now, &out)
	for ev, i in ui.events {
		if ui.handled[i] { continue }
		k, ok := ev.(input.Key)
		if ok && input.keymap_feed(km, k, ui.now, &out) {
			consume(ui, i)
		}
	}
	return out[:]
}

// The keymap as hints for `key_help`: headings and actions in the order
// they were bound, with the keys they have now. Actions without keys or a
// description are left out.
//
//	hnoss.key_help(ui, inner, hnoss.keymap_hints(&keymap))
keymap_hints :: proc(km: ^input.Keymap, allocator := context.temp_allocator) -> []Key_Hint {
	out := make([dynamic]Key_Hint, allocator)
	for a in km.actions {
		if a.name == "" {
			append(&out, Key_Hint{"", a.desc})
			continue
		}
		keys := input.keymap_keys(km, a.name, allocator)
		if keys == "" || a.desc == "" { continue }
		append(&out, Key_Hint{keys, a.desc})
	}
	return out[:]
}

// How long to wait for input so a chord being typed times out on time:
// `wait_ms` when there is none, otherwise at most that (-1: no limit of
// your own).
keymap_timeout :: proc(km: ^input.Keymap, now: time.Tick, wait_ms: int) -> int {
	left, waiting := input.keymap_waiting(km, now)
	if !waiting { return wait_ms }
	ms := max(int(time.duration_milliseconds(left)), 0) + 1
	return ms if wait_ms < 0 else min(ms, wait_ms)
}
