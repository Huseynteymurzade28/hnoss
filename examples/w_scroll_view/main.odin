// Widget example: scroll views. The left one holds more checkboxes than fit,
// the right one text wider and taller than its box. Tab moves focus between
// them; ↑↓←→ PgUp PgDn Home End scroll the focused one; the wheel scrolls the
// one under the mouse (Shift+wheel sideways); click a checkbox to tick it.
//   q / Esc  quit
package main

import "core:fmt"
import "core:os"
import hnoss "../.."
import "../../backend"

REGIONS :: [?]string{
	"Abşeron", "Ağdam", "Ağdaş", "Ağstafa", "Ağsu", "Astara", "Balakən", "Bərdə",
	"Beyləqan", "Biləsuvar", "Cəbrayıl", "Cəlilabad", "Daşkəsən", "Füzuli",
	"Gədəbəy", "Goranboy", "Göyçay", "Göygöl", "Hacıqabul", "İmişli", "İsmayıllı",
	"Kəlbəcər", "Kürdəmir", "Laçın", "Lerik", "Masallı", "Neftçala", "Oğuz",
	"Qax", "Qazax", "Qəbələ", "Quba", "Qusar", "Saatlı", "Sabirabad", "Şamaxı",
	"Şəmkir", "Siyəzən", "Şuşa", "Tərtər", "Tovuz", "Ucar", "Xaçmaz", "Xızı",
	"Yardımlı", "Yevlax", "Zaqatala", "Zəngilan", "Zərdab",
}

WIDE :: `[b]Azərbaycan Respublikasının Dövlət Himni[/] [dim]· Əhməd Cavad, 1919[/]

Azərbaycan! Azərbaycan! Ey qəhrəman övladın şanlı Vətəni!
Səndən ötrü can verməyə cümlə hazırız!
Səndən ötrü qan tökməyə cümlə qadiriz!
Üçrəngli bayrağınla məsud yaşa! Üçrəngli bayrağınla məsud yaşa!

Minlərcə can qurban oldu, Sinən hərbə meydan oldu!
Hüququndan keçən əsgər, Hərə bir qəhrəman oldu!

Sən olasan gülüstan, Sənə hər an can qurban!
Sənə min bir məhəbbət Sinəmdə tutmuş məkan!

Namusunu hifz etməyə, Bayrağını yüksəltməyə
Cümlə gənclər müştaqdır! Şanlı Vətən! Şanlı Vətən!
Azərbaycan! Azərbaycan! Azərbaycan! Azərbaycan!

[dim]← → or Shift+wheel to read the long lines; ↑ ↓ for the rest.[/]`

main :: proc() {
	context.assertion_failure_proc = backend.assertion_failure_proc

	term, err := hnoss.init(hnoss.DEFAULT_OPTIONS + {.Mouse_Capture})
	if err != .None {
		fmt.eprintfln("hnoss: init failed: %v", err)
		os.exit(1)
	}
	defer hnoss.deinit(&term)

	regions := REGIONS
	picked: [len(REGIONS)]bool
	picked[37] = true // Şuşa
	left, right: hnoss.View_State
	wide_lines, wide_width := hnoss.measure(WIDE, max(int), .Clip)
	events: []hnoss.Event
	loop: for {
		f := hnoss.begin_frame(&term)
		ui := hnoss.ui(f, events)
		area := hnoss.inset(f.area, 1)
		footer := hnoss.cut_bottom(&area, 1)
		hnoss.label(ui, footer, "[dim]Tab focus · ↑↓←→ PgUp PgDn scroll · wheel · click · q quit[/]")
		hnoss.focus_order(ui, {&left, &right})

		cols := hnoss.split(area, .Horizontal, {24, hnoss.fill()}, gap = 1)
		// The box goes on last so its title counts this frame's clicks.
		content := hnoss.scroll_view(ui, hnoss.inset(cols[0], 1), &left, 0, len(regions))
		n := 0
		for name, i in regions {
			hnoss.checkbox(ui, {content.x, content.y + i, content.width, 1}, name, &picked[i])
			n += 1 if picked[i] else 0
		}
		hnoss.scroll_view_end(ui, &left)
		hnoss.box(ui, cols[0], fmt.tprintf("[b]Regions[/] [dim]%d[/]", n), {focused = hnoss.focused(ui, &left)})

		inner := hnoss.box(ui, cols[1], "[b]Himn[/]", {focused = hnoss.focused(ui, &right)})
		content = hnoss.scroll_view(ui, inner, &right, wide_width, wide_lines)
		hnoss.label(ui, content, WIDE, wrap = .Clip)
		hnoss.scroll_view_end(ui, &right)

		for ev in hnoss.unhandled(ui) {
			if hnoss.is_char(ev, 'q') || hnoss.is_key(ev, .Esc) || hnoss.is_char(ev, 'c', {.Ctrl}) {
				break loop
			}
		}
		hnoss.end_frame(&term)
		free_all(context.temp_allocator)
		events = hnoss.poll_events(&term, -1)
		if term.error != .None {
			break
		}
	}
}
