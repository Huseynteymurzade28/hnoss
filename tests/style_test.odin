package tests

import "core:testing"
import "../buffer"
import "../style"

@(test)
rgb_to_indexed_exact_and_nearest :: proc(t: ^testing.T) {
	testing.expect_value(t, style.rgb_to_indexed({0, 0, 0}), style.Indexed(16))
	testing.expect_value(t, style.rgb_to_indexed({255, 255, 255}), style.Indexed(231))
	testing.expect_value(t, style.rgb_to_indexed({255, 135, 0}), style.Indexed(208))
	testing.expect_value(t, style.rgb_to_indexed({250, 130, 10}), style.Indexed(208))
	// Grays land on the ramp when it is closer than the cube.
	testing.expect_value(t, style.rgb_to_indexed({128, 128, 128}), style.Indexed(244))
	testing.expect_value(t, style.rgb_to_indexed({8, 8, 8}), style.Indexed(232))
}

@(test)
indexed_round_trips_through_rgb :: proc(t: ^testing.T) {
	for i in 16 ..< 256 {
		idx := style.Indexed(i)
		testing.expectf(t, style.rgb_to_indexed(style.indexed_to_rgb(idx)) == idx, "index %d", i)
	}
}

@(test)
rgb_to_named_picks_nearest :: proc(t: ^testing.T) {
	testing.expect_value(t, style.rgb_to_named({250, 10, 10}), style.Named_Color.Bright_Red)
	testing.expect_value(t, style.rgb_to_named({190, 0, 0}), style.Named_Color.Red)
	testing.expect_value(t, style.rgb_to_named({5, 5, 5}), style.Named_Color.Black)
	testing.expect_value(t, style.rgb_to_named({120, 120, 130}), style.Named_Color.Bright_Black)
}

@(test)
downsample_by_depth :: proc(t: ^testing.T) {
	orange: style.Color = style.Rgb{255, 135, 0}
	testing.expect_value(t, style.downsample(orange, .Truecolor), orange)
	testing.expect_value(t, style.downsample(orange, .Ansi256), style.Color(style.Indexed(208)))
	testing.expect_value(t, style.downsample(orange, .No_Color), style.Color(nil))
	// Indexed 0-15 are the named colors themselves.
	testing.expect_value(t, style.downsample(style.Indexed(9), .Ansi16), style.Color(style.Named_Color.Bright_Red))
	testing.expect_value(t, style.downsample(style.Indexed(196), .Ansi16), style.Color(style.Named_Color.Bright_Red))
	// What the depth already covers is left alone.
	testing.expect_value(t, style.downsample(style.Indexed(196), .Ansi256), style.Color(style.Indexed(196)))
	testing.expect_value(t, style.downsample(style.Named_Color.Cyan, .Ansi16), style.Color(style.Named_Color.Cyan))
	testing.expect_value(t, style.downsample(nil, .Ansi16), style.Color(nil))
}

@(test)
detect_color_depth_from_env :: proc(t: ^testing.T) {
	d :: style.detect_color_depth
	testing.expect_value(t, d({no_color = "1", colorterm = "truecolor"}), style.Color_Depth.No_Color)
	testing.expect_value(t, d({no_color = "", colorterm = "truecolor"}), style.Color_Depth.Truecolor)
	testing.expect_value(t, d({colorterm = "24bit", term = "xterm"}), style.Color_Depth.Truecolor)
	testing.expect_value(t, d({term = "xterm-256color"}), style.Color_Depth.Ansi256)
	testing.expect_value(t, d({term = "tmux-256color"}), style.Color_Depth.Ansi256)
	testing.expect_value(t, d({term = "xterm-direct"}), style.Color_Depth.Truecolor)
	testing.expect_value(t, d({term = "xterm-kitty"}), style.Color_Depth.Truecolor)
	testing.expect_value(t, d({term = "foot"}), style.Color_Depth.Truecolor)
	testing.expect_value(t, d({term = "xterm-256color", term_program = "iTerm.app"}), style.Color_Depth.Truecolor)
	testing.expect_value(t, d({term = "xterm-256color", term_program = "Apple_Terminal"}), style.Color_Depth.Ansi256)
	testing.expect_value(t, d({term = "linux"}), style.Color_Depth.Ansi16)
	testing.expect_value(t, d({term = "xterm"}), style.Color_Depth.Ansi16)
	testing.expect_value(t, d({term = "dumb"}), style.Color_Depth.No_Color)
	testing.expect_value(t, d({}), style.Color_Depth.Ansi16)
}

@(private = "file")
diff_at :: proc(depth: style.Color_Depth) -> string {
	prev, next: buffer.Buffer
	buffer.init(&prev, {0, 0, 3, 1})
	buffer.init(&next, {0, 0, 3, 1})
	defer buffer.destroy(&prev)
	defer buffer.destroy(&next)
	buffer.set_string(&next, 0, 0, "a", {fg = style.rgb(255, 135, 0), add = {.Bold}})
	buffer.set_string(&next, 1, 0, "b", {fg = style.rgb(250, 130, 10), add = {.Bold}})
	buffer.set_string(&next, 2, 0, "c", {bg = style.Indexed(196)})
	out := make([dynamic]u8, context.temp_allocator)
	buffer.diff(&prev, &next, &out, depth)
	return string(out[:])
}

@(test)
diff_downsamples_colors :: proc(t: ^testing.T) {
	testing.expect_value(t, diff_at(.Truecolor),
		"\x1b[1;1H\x1b[1;38;2;255;135;0ma\x1b[38;2;250;130;10mb\x1b[22;39;48;5;196mc\x1b[0m")
	// Two RGB colors that map to the same index need no SGR in between.
	testing.expect_value(t, diff_at(.Ansi256),
		"\x1b[1;1H\x1b[1;38;5;208mab\x1b[22;39;48;5;196mc\x1b[0m")
	// Orange is nearest to (xterm) Yellow.
	testing.expect_value(t, diff_at(.Ansi16),
		"\x1b[1;1H\x1b[1;33mab\x1b[22;39;101mc\x1b[0m")
	// NO_COLOR keeps the bold; nothing is left on, so no reset at the end.
	testing.expect_value(t, diff_at(.No_Color), "\x1b[1;1H\x1b[1mab\x1b[22mc")
}
