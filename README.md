# skylandbar

A status bar for macOS that speaks [SketchyBar](https://github.com/FelixKratz/SketchyBar)'s
language, written in Swift for macOS 14 to 26, and meant to grow into the bar of
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

## What works

| Area | Supported |
| --- | --- |
| Commands | `--bar`, `--add item/event/bracket/graph/slider/alias/space`, `--set` (name or `/regex/`), `--default`, `--subscribe`, `--trigger` (with `VAR=value`), `--remove`, `--move before/after`, `--reorder`, `--rename`, `--clone`, `--push`, `--animate`, `--query bar/defaults/events/displays/default_menu_items/<item>`, `--update`, `--reload [file]`, `--hotload on/off`, `--exit` |
| Bar | `position` top/bottom, `height`, `notch_display_height`, `margin`, `y_offset`, `color`, `border_color/width`, `corner_radius`, `blur_radius`, `padding_left/right`, `notch_width`, `notch_offset`, `display` (all/main/list), `hidden` (on/off/current/toggle), `topmost` (on/window/off), `sticky`, `shadow`, `font_smoothing` |
| Items | `position` left/right/center/q/e/`popup.<item>`, `drawing`, `width` (dynamic or fixed), `y_offset`, `display` (active/list), `space` (Mission Control spaces), `ignore_association`, `updates` (on/off/when_shown), `update_freq`, `script`, `click_script`, `scroll_texts`, `background.*` |
| Text | `icon` and `label`: string, `font` (`Family:Style:Size`), `color` (+ `.alpha`), `highlight`, `highlight_color`, `padding_left/right`, `y_offset`, `width`, `align`, `max_chars`, `scroll_duration`, `drawing`, `background.*`, `shadow.*` |
| Backgrounds | `color`, `border_color/width`, `height`, `corner_radius`, `padding_left/right`, `x_offset`, `y_offset`, `shadow.*`, `image` (a file, `app.<bundle id or name>`, `media.artwork`) with `image.scale/corner_radius/border_*/padding_*/y_offset/shadow`. Like sketchybar, setting a color, a border or an image draws the background |
| Popups | `popup.drawing` (+ toggle), `horizontal`, `align`, `height`, `y_offset`, `topmost`, `blur_radius`, `background.*`; popups of popup items |
| Components | brackets (`--add bracket <name> <member or /regex/>...`), graphs (`--push`, `graph.color/fill_color/line_width`), sliders (`slider.percentage/width/highlight_color/background.*/knob.*`, dragging sends `mouse.clicked` with `PERCENTAGE`), aliases (`alias.color/scale/update_freq`, clicks go to the real menu bar item), spaces (`SELECTED`, `SID`, `DID`) |
| Animations | `--animate <curve> <frames>` then `--set`/`--bar`: numbers and colors move along linear, quadratic, tanh, sin, exp or circ at 60 frames a second |
| Scripts | `NAME`, `SENDER`, `INFO`, `BUTTON`, `MODIFIER`, `SCROLL_DELTA`, `PERCENTAGE`, `SELECTED`, `SID`, `DID`, `CONFIG_DIR`, `BAR_NAME`, plus the variables given to `--trigger`. They stop when the bar quits |
| Events | `front_app_switched`, `space_change`, `display_change`, `system_woke`, `system_will_sleep`, `power_source_change`, `volume_change`, `brightness_change`, `wifi_change`, `media_change`, `mouse.entered/exited(.global)`, `mouse.clicked`, `mouse.scrolled(.global)`, `routine`, `forced`, custom events (with an optional distributed notification) |
| Query | JSON close to SketchyBar's, with `bounding_rects` per display |

## skylandbar extras

- **Liquid Glass**: `--bar glass=on` (or `clear`), and `background.glass=on` on any background
  (items, icons, labels, brackets, `popup.background`, `slider.background`). The color becomes
  the glass tint. It uses `NSGlassEffectView` on macOS 26 when built with Xcode 26, and a blurred
  material before that.

## Permissions and limits

- **aliases**: Screen Recording, to copy menu bar items. A click forwarded to a real item also
  needs Accessibility.
- **wifi_change**: macOS gives the network name only to apps with Location Services, as it does for
  SketchyBar; otherwise `INFO` is empty.
- **media_change**: MediaRemote no longer answers apps from macOS 15.4. Music and Spotify still
  report through their notifications, but there is no artwork for them.
- **space_change**: Mission Control spaces. Workspaces from skyland or AeroSpace come through your
  own events (`--add event` + `--trigger`), as with SketchyBar.

## Next

- `space_windows_change`, `display=active` following the focused window rather than the mouse
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
