<p align="center">
  <img src="docs/assets/logo.svg" width="150" alt="hnoss logo">
</p>

<h1 align="center">hnoss</h1>

<p align="center">
  An immediate-mode TUI library for <a href="https://odin-lang.org">Odin</a>. Pure Odin, no C, batteries included.<br>
  <a href="https://huseynteymurzade28.github.io/hnoss/"><b>Documentation</b></a> ·
  <a href="https://huseynteymurzade28.github.io/hnoss/guide.html">Guide</a> ·
  <a href="https://huseynteymurzade28.github.io/hnoss/widgets.html">Widgets</a> ·
  <a href="examples/">Examples</a><br><br>
  <a href="https://github.com/Huseynteymurzade28/hnoss/actions/workflows/ci.yml"><img src="https://github.com/Huseynteymurzade28/hnoss/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
</p>

![hnoss demo](docs/demo.gif)

<p align="center"><sub><code>examples/demo</code>: plasma, a shaded 3D torus on a braille canvas, live graphs and scripted input, at 60 fps in ~2 ms a frame.</sub></p>

![hnoss monitor](docs/monitor-odlar-yurdu.svg)

<p align="center"><sub><code>examples/monitor</code>: a live system monitor reading <code>/proc</code>, in the <b>Odlar Yurdu</b> theme.</sub></p>

## Gallery

| | | |
|:-:|:-:|:-:|
| ![showcase](docs/gallery/showcase.svg)<br>**Widgets**<br><sub>tabs, lists, braille graph, table, gauges, input</sub> | ![plasma](docs/gallery/plasma.svg)<br>**Truecolor at 60 fps**<br><sub>double-buffered diff, one write per frame</sub> | ![text](docs/gallery/text.svg)<br>**Text & markup**<br><sub>wrapping by grapheme, `[b red]markup[/]`</sub> |
| ![layout](docs/gallery/layout.svg)<br>**Layout**<br><sub>cuts, split, grid, center</sub> | ![list](docs/gallery/list.svg)<br>**Stateful widgets**<br><sub>keyboard, mouse, focus</sub> | ![events](docs/gallery/events.svg)<br>**Input**<br><sub>keys, modifiers, mouse, paste</sub> |

## Install

hnoss is a plain Odin package; there is no package manager, so add the repository to your project:

```sh
git submodule add https://github.com/Huseynteymurzade28/hnoss libs/hnoss   # inside a git repo (git init first)
# or, without git in your project:
git clone https://github.com/Huseynteymurzade28/hnoss libs/hnoss
```

Then import it by path, relative to the file that imports it (`import hnoss "libs/hnoss"`), or register a collection once and import it from anywhere in your project:

```sh
odin run . -collection:libs=libs      # import hnoss "libs:hnoss"
```

## Quick start

```odin
package main

import hnoss "libs/hnoss"

main :: proc() {
    term, _ := hnoss.init(hnoss.DEFAULT_OPTIONS + {.Mouse_Capture})
    defer hnoss.deinit(&term)           // the terminal is always restored, even on panic or Ctrl+C

    cities := []string{"Bakı", "Gəncə", "Şəki", "Lənkəran"}
    list: hnoss.List_State
    events: []hnoss.Event
    for {
        f := hnoss.begin_frame(&term)
        ui := hnoss.ui(f, events)
        inner := hnoss.box(ui, hnoss.inset(f.area, 1), "🇦🇿 [b]Cities[/]")
        hnoss.focus(ui, &list)
        hnoss.list(ui, inner, cities, &list)          // ↑↓, click, wheel

        for ev in hnoss.unhandled(ui) {
            if hnoss.is_char(ev, 'q') { return }
        }
        hnoss.end_frame(&term)                        // diff, one write
        free_all(context.temp_allocator)
        events = hnoss.poll_events(&term, -1)
    }
}
```

## Why hnoss

- **Pure Odin.** Only `core:` and `base:`; raw syscalls on Linux, no ncurses, no libc bindings.
- **Immediate mode.** Calling a widget draws it, handles its input and returns what happened.
- **Fast.** Only changed cells are written; a full 200×60 truecolor frame diffs in ~2 ms.
- **Correct text.** Unicode 16 widths and grapheme clusters: `世界`, `é`, `👩‍💻`, `🇦🇿`.
- **Safe.** Raw mode, alt screen and cursor are restored on exit, panic and signals.

## Build

```sh
./build.sh                 # check + tests + all examples into bin/
./build.sh run demo        # or: showcase, monitor, plasma, text, layout, event_inspector, w_<widget>
```

Linux today; the platform layer is one small file so macOS/Windows can follow.

## License

MIT
