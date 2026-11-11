// Widget example: bar charts. Monthly rainfall in Lənkəran as vertical bars
// with a gradient, and July temperatures by city as horizontal ones; the
// values drift a little every frame so the eighth-block tips move.
//   Space  pause    q  quit
package main

import "core:fmt"
import "core:math"
import "core:os"
import "core:time"
import hnoss "../.."
import "../../backend"

MONTHS :: [12]string{"Yan", "Fev", "Mar", "Apr", "May", "İyn", "İyl", "Avq", "Sen", "Okt", "Noy", "Dek"}
RAIN :: [12]f64{110, 105, 95, 55, 40, 20, 15, 45, 150, 250, 210, 135} // mm, roughly
CITIES :: [?]string{"Bakı", "Gəncə", "Şəki", "Lənkəran", "Naxçıvan", "Şuşa"}
JULY :: [?]f64{32, 33, 29, 30, 36, 23} // °C, roughly

main :: proc() {
	context.assertion_failure_proc = backend.assertion_failure_proc

	term, err := hnoss.init()
	if err != .None {
		fmt.eprintfln("hnoss: init failed: %v", err)
		os.exit(1)
	}
	defer hnoss.deinit(&term)

	months, rain := MONTHS, RAIN
	cities, july := CITIES, JULY
	last := time.tick_now()
	paused := false
	t := 0.0 // seconds of animation, stopped while paused
	events: []hnoss.Event
	loop: for {
		now := time.tick_now()
		if !paused {
			t += time.duration_seconds(time.tick_diff(last, now))
		}
		last = now
		f := hnoss.begin_frame(&term)
		ui := hnoss.ui(f, events)
		area := hnoss.inset(f.area, 1)
		footer := hnoss.cut_bottom(&area, 1)
		hnoss.key_hints(ui, footer, {{"Space", "resume" if paused else "pause"}, {"q", "quit"}})

		rows := hnoss.split(area, .Vertical, {hnoss.fill(), len(cities) + 2}, gap = 1)

		monthly: [12]hnoss.Bar
		for &b, i in monthly {
			b = {months[i], math.round(rain[i] * (1 + 0.15 * math.sin(t * 1.3 + f64(i))))}
		}
		inner := hnoss.box(ui, rows[0], "[b]Lənkəran[/] [dim]· rainfall, mm[/]")
		hnoss.bar_chart(ui, inner, monthly[:], {
			gradient = {hnoss.hex(0x3a7bd5), hnoss.hex(0x00d2ff)},
		})

		temps: [len(CITIES)]hnoss.Bar
		for &b, i in temps {
			b = {cities[i], july[i] + 1.5 * math.sin(t * 0.9 + f64(i) * 2)}
		}
		hot := hnoss.Style{fg = hnoss.hex(0xff5f40)}
		inner = hnoss.box(ui, rows[1], "[b]July[/] [dim]· average high[/]")
		hnoss.bar_chart(ui, inner, temps[:], {
			horizontal = true,
			max_value  = 40,
			format     = "%.1f°C",
			gradient   = {hnoss.hex(0xf9d423), hnoss.hex(0xff4e50)},
			colors     = {{}, {}, {}, {}, hot}, // Naxçıvan stands out
		})

		for ev in hnoss.unhandled(ui) {
			switch {
			case hnoss.is_char(ev, 'q') || hnoss.is_key(ev, .Esc) || hnoss.is_char(ev, 'c', {.Ctrl}):
				break loop
			case hnoss.is_char(ev, ' '):
				paused = !paused
			}
		}
		hnoss.end_frame(&term)
		free_all(context.temp_allocator)
		events = hnoss.poll_events(&term, 33)
		if term.error != .None {
			break
		}
	}
}
