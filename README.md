# skylandbar

A status bar for macOS that speaks [SketchyBar](https://github.com/FelixKratz/SketchyBar)'s
language, written in Swift for macOS 15 and macOS 26, and meant to grow into the bar of
[skyland](https://github.com/waxdred/skyland).

Configs and plugins written for SketchyBar run unchanged: scripts are started with a `PATH`
whose first directory holds a `sketchybar` that is this binary.

## Build and run

```sh
swift build -c release
swift test
.build/release/skylandbar                    # runs ~/.config/skylandbar/skylandbarrc,
                                             # else ~/.config/sketchybar/sketchybarrc
.build/release/skylandbar --config ~/.config/sketchybar/sketchybarrc
```

Quit SketchyBar first (`brew services stop sketchybar`). Both bars can run at once,
but each one draws its own bar.

From a shell, or from your scripts:

```sh
skylandbar --set clock label="$(date '+%H:%M')"
skylandbar --query bar
```

## Milestone 1: the core (this version)

| Area | Supported |
| --- | --- |
| Commands | `--bar`, `--add item/event/bracket/graph/slider/alias/space`, `--set` (name or `/regex/`), `--default`, `--subscribe`, `--trigger` (with `VAR=value`), `--remove`, `--move before/after`, `--reorder`, `--rename`, `--clone`, `--query bar/defaults/events/displays/<item>`, `--update`, `--reload [file]`, `--hotload on/off`, `--exit` |
| Bar | `position` top/bottom, `height`, `margin`, `y_offset`, `color`, `border_color/width`, `corner_radius`, `blur_radius`, `padding_left/right`, `notch_width`, `notch_offset`, `display` (all/main/list), `hidden` (on/off/current/toggle), `topmost` (on/window/off), `sticky`, `shadow`, `font_smoothing` |
| Items | `position` left/right/center/q/e, `drawing`, `width` (dynamic or fixed), `y_offset`, `display` (active/list), `ignore_association`, `associated_display`, `associated_space`, `updates` (on/off/when_shown), `update_freq`, `script`, `click_script`, `background.*` |
| Text | `icon` and `label`: string, `font` (`Family:Style:Size`), `color` (+ `.alpha`), `highlight`, `highlight_color`, `padding_left/right`, `y_offset`, `width`, `align`, `max_chars`, `drawing`, `background.*`, `shadow.*` |
| Scripts | `NAME`, `SENDER`, `INFO`, `BUTTON`, `MODIFIER`, `SCROLL_DELTA`, `CONFIG_DIR`, `BAR_NAME`, plus the variables given to `--trigger` |
| Events | `front_app_switched`, `space_change`, `display_change`, `system_woke`, `system_will_sleep`, `power_source_change`, `volume_change`, `mouse.entered/exited(.global)`, `mouse.clicked`, `mouse.scrolled(.global)`, `routine`, `forced`, custom events (with an optional distributed notification) |
| Query | JSON close to SketchyBar's, with `bounding_rects` per display |

Popups, graphs, sliders, aliases and `--animate` are parsed, and their properties are
stored and shown by `--query`. They are not drawn yet; see milestone 2.

## Milestone 2: next

- popups (`popup.*`), brackets drawn around their members, graphs (`--push`), sliders, aliases (menu bar items)
- `--animate` with SketchyBar's curves, images (`background.image`, `icon.image` app icons)
- the `wifi_change`, `brightness_change` and `media_change` events
- Liquid Glass on macOS 26 (`NSGlassEffectView`), and blur everywhere else
- skyland integration: workspaces and focus pushed by skyland instead of `aerospace` calls in scripts

## Not supported

- SbarLua and other configs that talk to SketchyBar through its Mach port (the `mach_helper`
  property is stored and ignored). Shell configs work.

## Layout

```
Sources/SkylandBarCore   Foundation only and tested: values, properties, command parser, layout, model
Sources/skylandbar       AppKit: windows and drawing, socket server and client, system events, scripts
Tests                    XCTest for the core
```
