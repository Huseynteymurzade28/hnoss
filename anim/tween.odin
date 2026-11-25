package anim

import "core:time"

DEFAULT_DURATION :: 250 * time.Millisecond

// A value on its way to another. The zero value has no value yet: the first
// `tween_to` puts it there at once.
Tween :: struct {
	from, to: f64,
	start:    time.Tick,
	duration: time.Duration, // 0: arrived
	ease:     Ease,
	set:      bool,
}

// Puts the value at `v`, with nothing left to do.
tween_set :: proc(tw: ^Tween, v: f64) {
	tw^ = {from = v, to = v, ease = tw.ease, set = true}
}

// Heads for `to`, from wherever the value is at `now`. Call it every frame:
// as long as `to` stays the same, it goes on as it was.
tween_to :: proc(tw: ^Tween, to: f64, now: time.Tick, duration := DEFAULT_DURATION, ease := Ease.Out_Cubic) {
	if !tw.set || duration <= 0 {
		tween_set(tw, to)
		return
	}
	if to == tw.to { return }
	from := tween_value(tw, now)
	tw^ = {from = from, to = to, start = now, duration = duration, ease = ease, set = true}
}

tween_value :: proc(tw: ^Tween, now: time.Tick) -> f64 {
	if !tween_running(tw, now) { return tw.to }
	t := f64(time.tick_diff(tw.start, now)) / f64(tw.duration)
	return tw.from + (tw.to - tw.from) * ease(tw.ease, t)
}

// Not there yet at `now`.
tween_running :: proc(tw: ^Tween, now: time.Tick) -> bool {
	return tw.duration > 0 && time.tick_diff(tw.start, now) < tw.duration
}
