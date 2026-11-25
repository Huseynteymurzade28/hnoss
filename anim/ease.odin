package anim

import "core:math"

// How a value gets from start to end. In_ starts slowly, Out_ ends slowly,
// In_Out_ does both. Back and Elastic overshoot.
Ease :: enum u8 {
	Out_Cubic, // the default: quick to react, soft to arrive
	Linear,
	In_Quad, Out_Quad, In_Out_Quad,
	In_Cubic, In_Out_Cubic,
	In_Expo, Out_Expo, In_Out_Expo,
	In_Back, Out_Back, In_Out_Back,
	In_Elastic, Out_Elastic, In_Out_Elastic,
}

// The eased position at `t`, the part of the time gone by (clamped to 0..1).
// Exactly 0 at 0 and 1 at 1; Back and Elastic leave that range in between.
ease :: proc(e: Ease, t: f64) -> f64 {
	if !(t > 0) { return 0 } // NaN too
	if t >= 1 { return 1 }
	switch e {
	case .Linear:         return t
	case .In_Quad:        return quad(t)
	case .Out_Quad:       return 1 - quad(1 - t)
	case .In_Out_Quad:    return both(quad, t)
	case .In_Cubic:       return cubic(t)
	case .Out_Cubic:      return 1 - cubic(1 - t)
	case .In_Out_Cubic:   return both(cubic, t)
	case .In_Expo:        return expo(t)
	case .Out_Expo:       return 1 - expo(1 - t)
	case .In_Out_Expo:    return both(expo, t)
	case .In_Back:        return back(t)
	case .Out_Back:       return 1 - back(1 - t)
	case .In_Out_Back:    return both(back, t)
	case .In_Elastic:     return elastic(t)
	case .Out_Elastic:    return 1 - elastic(1 - t)
	case .In_Out_Elastic: return both(elastic, t)
	}
	return t
}

// The In curve up to the middle, its mirror image after it.
@(private)
both :: proc(f: proc(t: f64) -> f64, t: f64) -> f64 {
	return f(2 * t) / 2 if t < 0.5 else 1 - f(2 - 2 * t) / 2
}

@(private)
quad :: proc(t: f64) -> f64 { return t * t }

@(private)
cubic :: proc(t: f64) -> f64 { return t * t * t }

// Scaled so it starts at 0 and not at 2^-10.
@(private)
expo :: proc(t: f64) -> f64 {
	return (math.pow(2, 10 * t) - 1) / 1023
}

// Goes back by a tenth first.
@(private)
back :: proc(t: f64) -> f64 {
	S :: 1.70158
	return t * t * ((S + 1) * t - S)
}

@(private)
elastic :: proc(t: f64) -> f64 {
	if t <= 0 { return 0 }
	if t >= 1 { return 1 }
	return -math.pow(2, 10 * t - 10) * math.sin((t * 10 - 10.75) * math.TAU / 3)
}
