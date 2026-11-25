package widgets

import "../anim"

// Where a value heading for `target` is this frame. The first call puts it
// there at once; after that, whenever `target` changes it moves over
// `duration`, also when it was still on its way. While it does,
// `hnoss.timeout` asks for frames at 60 fps.
//
//	hnoss.gauge(ui, area, hnoss.tween(ui, &shown, progress))
//
// For something that should move from the start, begin with
// `hnoss.tween_set(&shown, 0)`.
tween :: proc(ui: ^Ui, state: ^anim.Tween, target: f64, duration := anim.DEFAULT_DURATION, ease := anim.Ease.Out_Cubic) -> f64 {
	anim.tween_to(state, target, ui.now, duration, ease)
	if anim.tween_running(state, ui.now) { ui.mem.animating = true }
	return anim.tween_value(state, ui.now)
}

// Milliseconds to wait for input: a frame at 60 fps while something moves.
@(private)
tween_timeout :: proc(mem: ^Memory, wait_ms: int) -> int {
	if !mem.animating { return wait_ms }
	return 16 if wait_ms < 0 else min(16, wait_ms)
}
