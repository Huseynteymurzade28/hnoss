package input

import "core:time"

// How close together presses must be to count as one double/triple click.
DEFAULT_CLICK_INTERVAL :: 400 * time.Millisecond

// Counts repeated clicks: a press of the same button on the same cell
// within `interval` of the previous press adds one, up to 3.
Click_Tracker :: struct {
	interval: time.Duration, // 0 means DEFAULT_CLICK_INTERVAL
	button:   Mouse_Button,
	x, y:     int,
	at:       time.Tick,
	count:    u8,
}

// Fills in `m.clicks` for a Press (and the Release that follows it) that
// happened at `now`.
track_click :: proc(t: ^Click_Tracker, m: ^Mouse, now: time.Tick) {
	#partial switch m.kind {
	case .Press:
		if m.button < .Left || m.button > .Right {
			return
		}
		interval := t.interval if t.interval > 0 else DEFAULT_CLICK_INTERVAL
		same := t.count > 0 && m.button == t.button && m.x == t.x && m.y == t.y
		if same && time.tick_diff(t.at, now) <= interval && t.count < 3 {
			t.count += 1
		} else {
			t.count = 1
		}
		t.button, t.x, t.y, t.at = m.button, m.x, m.y, now
		m.clicks = t.count
	case .Release:
		if t.count > 0 && m.button == t.button {
			m.clicks = t.count
		}
	case .Drag:
		t.count = 0 // dragging between presses breaks the run
	}
}
