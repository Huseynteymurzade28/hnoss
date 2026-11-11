// Widget example: log view. A made-up service writes a few lines a second;
// the view follows the tail until you scroll up, then holds still and
// counts what arrives meanwhile.
//   ↑↓ (k j) PgUp PgDn Home (g)  scroll    End (G)  follow the tail again
//   wheel  scroll                           click the "new lines" note  follow
//   w      wrap long lines on / off         Space  pause the service
//   c      clear                            q      quit
package main

import "core:fmt"
import "core:math/rand"
import "core:os"
import "core:time"
import hnoss "../.."
import "../../backend"

CITIES :: [?]string{"Bakı", "Gəncə", "Sumqayıt", "Mingəçevir", "Şəki", "Lənkəran", "Naxçıvan", "Şuşa"}

main :: proc() {
	context.assertion_failure_proc = backend.assertion_failure_proc

	term, err := hnoss.init(hnoss.DEFAULT_OPTIONS + {.Mouse_Capture})
	if err != .None {
		fmt.eprintfln("hnoss: init failed: %v", err)
		os.exit(1)
	}
	defer hnoss.deinit(&term)

	logs := hnoss.Log_State{max_lines = 2000}
	defer hnoss.log_destroy(&logs)
	hnoss.log_append(&logs, "[dim]-- weather service starting --[/]")

	wrap := true
	running := true
	start := time.now()
	next := start
	seq := 0
	events: []hnoss.Event
	loop: for {
		now := time.now()
		for running && time.diff(next, now) >= 0 {
			seq += 1
			write_line(&logs, seq, time.diff(start, now))
			next = time.time_add(next, time.Duration(rand.int_max(400) + 50) * time.Millisecond)
		}

		f := hnoss.begin_frame(&term)
		ui := hnoss.ui(f, events)
		area := hnoss.inset(f.area, 1)
		footer := hnoss.cut_bottom(&area, 1)
		hnoss.key_hints(ui, footer, {
			{"↑↓ PgUp Home", "scroll"}, {"End", "follow"}, {"w", "wrap"},
			{"Space", "pause" if running else "resume"}, {"c", "clear"}, {"q", "quit"},
		})
		hnoss.focus(ui, &logs)

		status := "[green]following[/]" if !logs.paused else "[yellow]scrolled back[/]"
		title := fmt.tprintf("[b]weather.log[/] [dim]%d lines ·[/] %s%s", hnoss.log_len(&logs), status,
			"" if running else " [dim]· service paused[/]")
		inner := hnoss.box(ui, area, title, {focused = true})
		hnoss.log_view(ui, inner, &logs, {wrap = .Word if wrap else .Ellipsis, markup = true, scrollbar = true})

		for ev in hnoss.unhandled(ui) {
			switch {
			case hnoss.is_char(ev, 'q') || hnoss.is_key(ev, .Esc) || hnoss.is_char(ev, 'c', {.Ctrl}):
				break loop
			case hnoss.is_char(ev, 'w'):
				wrap = !wrap
			case hnoss.is_char(ev, ' '):
				running = !running
				next = time.now()
			case hnoss.is_char(ev, 'c'):
				hnoss.log_clear(&logs)
			}
		}
		hnoss.end_frame(&term)
		free_all(context.temp_allocator)
		events = hnoss.poll_events(&term, 50)
		if term.error != .None {
			break
		}
	}
}

write_line :: proc(logs: ^hnoss.Log_State, seq: int, at: time.Duration) {
	cities := CITIES
	city := rand.choice(cities[:])
	secs := time.duration_seconds(at)
	stamp := fmt.tprintf("[dim]%02d:%06.3f[/]", int(secs) / 60, secs - f64(int(secs) / 60 * 60))
	switch r := rand.int_max(100); {
	case r < 70:
		hnoss.log_appendf(logs, "%s [green]INFO [/] #%d %s: %d°C, wind %d km/h", stamp, seq, city,
			rand.int_max(35) - 5, rand.int_max(60))
	case r < 85:
		hnoss.log_appendf(logs, "%s [cyan]DEBUG[/] #%d cache hit for \"%s\" (%d µs)", stamp, seq, city, rand.int_max(900) + 20)
	case r < 96:
		hnoss.log_appendf(logs, "%s [yellow]WARN [/] #%d %s station slow to answer (%d ms), retrying with a longer timeout and the backup endpoint", stamp, seq, city, rand.int_max(3000) + 500)
	case:
		hnoss.log_appendf(logs, "%s [b red]ERROR[/] #%d %s: connection reset by peer", stamp, seq, city)
	}
}
