package tests

import "core:math"
import "core:testing"
import "core:time"
import "../anim"

@(private = "file")
near :: proc(a, b: f64, eps := 1e-9) -> bool { return abs(a - b) < eps }

@(test)
ease_ends_and_range :: proc(t: ^testing.T) {
	for e in anim.Ease {
		testing.expect_value(t, anim.ease(e, 0), 0)
		testing.expect_value(t, anim.ease(e, 1), 1)
		testing.expect_value(t, anim.ease(e, -3), 0)
		testing.expect_value(t, anim.ease(e, 7), 1)
		testing.expect_value(t, anim.ease(e, math.nan_f64()), 0)
		// No jump at either end or in the middle.
		prev := 0.0
		for i in 0 ..= 1000 {
			v := anim.ease(e, f64(i) / 1000)
			testing.expectf(t, abs(v - prev) < 0.03, "%v jumps at %d", e, i)
			testing.expectf(t, v > -0.5 && v < 1.5, "%v is %v at %d", e, v, i)
			prev = v
		}
	}
}

@(test)
ease_known_values :: proc(t: ^testing.T) {
	testing.expect(t, near(anim.ease(.Linear, 0.3), 0.3))
	testing.expect(t, near(anim.ease(.In_Quad, 0.5), 0.25))
	testing.expect(t, near(anim.ease(.Out_Quad, 0.5), 0.75))
	testing.expect(t, near(anim.ease(.In_Cubic, 0.5), 0.125))
	testing.expect(t, near(anim.ease(.Out_Cubic, 0.5), 0.875))
	for e in ([]anim.Ease{.In_Out_Quad, .In_Out_Cubic, .In_Out_Expo, .In_Out_Back, .In_Out_Elastic}) {
		testing.expectf(t, near(anim.ease(e, 0.5), 0.5), "%v", e)
	}
	// Back and Elastic go past the end.
	past := 0.0
	for i in 0 ..= 100 { past = max(past, anim.ease(.Out_Back, f64(i) / 100)) }
	testing.expect(t, near(past, 1.1, 0.001))
}

@(private = "file")
at :: proc(ms: int) -> time.Tick {
	return {1 + i64(ms) * i64(time.Millisecond)}
}

@(test)
tween_runs_on_time :: proc(t: ^testing.T) {
	tw: anim.Tween
	anim.tween_to(&tw, 10, at(0)) // the first value is just there
	testing.expect_value(t, anim.tween_value(&tw, at(0)), 10)
	testing.expect(t, !anim.tween_running(&tw, at(0)))

	for ms := 0; ms <= 100; ms += 20 { // however often it is called
		anim.tween_to(&tw, 20, at(ms), 100 * time.Millisecond, .Linear)
		testing.expectf(t, near(anim.tween_value(&tw, at(ms)), 10 + f64(ms) / 10), "at %d: %v", ms, anim.tween_value(&tw, at(ms)))
	}
	testing.expect(t, anim.tween_running(&tw, at(99)))
	testing.expect(t, !anim.tween_running(&tw, at(100)))
	testing.expect_value(t, anim.tween_value(&tw, at(5000)), 20)
}

@(test)
tween_turns_around_where_it_is :: proc(t: ^testing.T) {
	tw: anim.Tween
	anim.tween_set(&tw, 0)
	anim.tween_to(&tw, 10, at(0), 100 * time.Millisecond, .Linear)
	anim.tween_to(&tw, 0, at(50), 100 * time.Millisecond, .Linear)
	testing.expect(t, near(anim.tween_value(&tw, at(50)), 5))
	testing.expect(t, near(anim.tween_value(&tw, at(100)), 2.5))
	testing.expect_value(t, anim.tween_value(&tw, at(150)), 0)

	anim.tween_to(&tw, 8, at(200), 0) // no duration: at once
	testing.expect_value(t, anim.tween_value(&tw, at(200)), 8)
}
