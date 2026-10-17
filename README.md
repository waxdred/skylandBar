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
| Items | `position` left/right/center/q/e/`popup.<item>`, `drawing`, `width` (dynamic or fixed), `y_offset`, `display` (active: the focused window's display, or a list), `space` (Mission Control spaces), `ignore_association`, `updates` (on/off/when_shown), `update_freq`, `script`, `click_script`, `scroll_texts`, `background.*` |
| Text | `icon` and `label`: string, `font` (`Family:Style:Size`), `color` (+ `.alpha`), `highlight`, `highlight_color`, `padding_left/right`, `y_offset`, `width`, `align`, `max_chars`, `scroll_duration`, `drawing`, `background.*`, `shadow.*` |
| Backgrounds | `color`, `border_color/width`, `height`, `corner_radius`, `padding_left/right`, `x_offset`, `y_offset`, `clip`, `shadow.*`, `image` (a file, `app.<bundle id or name>`, `media.artwork`) with `image.scale/corner_radius/border_*/padding_*/y_offset/shadow`. Like sketchybar, setting a color, a border or an image draws the background |
| Popups | `popup.drawing` (+ toggle), `horizontal`, `align`, `height`, `y_offset`, `topmost`, `blur_radius`, `background.*`; popups of popup items |
| Components | brackets (`--add bracket <name> <member or /regex/>...`), graphs (`--push`, `graph.color/fill_color/line_width`), sliders (`slider.percentage/width/highlight_color/background.*/knob.*`, dragging sends `mouse.clicked` with `PERCENTAGE`), aliases (`alias.color/scale/update_freq`, clicks go to the real menu bar item), spaces (`SELECTED`, `SID`, `DID`) |
| Animations | `--animate <curve> <frames>` then `--set`/`--bar`: numbers and colors move along linear, quadratic, tanh, sin, exp or circ at 60 frames a second |
| Scripts | `NAME`, `SENDER`, `INFO`, `BUTTON`, `MODIFIER`, `SCROLL_DELTA`, `PERCENTAGE`, `SELECTED`, `SID`, `DID`, `CONFIG_DIR`, `BAR_NAME`, plus the variables given to `--trigger`. They stop when the bar quits |
| Events | `front_app_switched`, `space_change`, `space_windows_change`, `display_change`, `system_woke`, `system_will_sleep`, `power_source_change`, `volume_change`, `brightness_change`, `wifi_change`, `media_change`, `mouse.entered/exited(.global)`, `mouse.clicked`, `mouse.scrolled(.global)`, `routine`, `forced`, custom events (with an optional distributed notification) |
| Query | JSON close to SketchyBar's, with `bounding_rects` per display |

## skylandbar extras

- **skyland and AeroSpace events, built in**: skylandbar subscribes to skyland's socket (or
  AeroSpace's) and sends these events as they happen, with nothing in the window manager's config:

  | Event | Variables |
  | --- | --- |
  | `skyland_workspace_change`, `aerospace_workspace_change` | `FOCUSED_WORKSPACE`, `PREV_WORKSPACE` |
  | `skyland_focus_change` | `FOCUSED_WORKSPACE`, `WINDOW_ID` |
  | `skyland_monitor_change` | `FOCUSED_WORKSPACE`, `MONITOR` |
  | `skyland_mode_change`, `aerospace_mode_change` | `MODE` |
  | `skyland_window_detected` | `WINDOW_ID`, `WORKSPACE`, `APP_NAME`, `APP_BUNDLE_ID` |
  | `skyland_binding` | `MODE`, `BINDING` |

  `INFO` is the event's JSON. Configs written for AeroSpace and sketchybar that use
  `aerospace_workspace_change` work as they are. If the window manager's config also
  triggers it (`exec-on-workspace-change`), remove that line.
- skyland pushes its workspaces and window title to skylandbar while it runs, and to
  sketchybar otherwise.

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
- **space_change**: Mission Control spaces. Workspaces from skyland or AeroSpace come through the
  skyland events above.
- **sketchybar's Mach name**: only one bar can hold `git.felix.sketchybar`. With sketchybar
  running, the sketchybar CLI and SbarLua talk to sketchybar (skylandbar says so when it starts).

## Manual tests

`manual-tests/` holds one script per area, with what to check: see its README.

## SbarLua and the sketchybar CLI

skylandbar answers on sketchybar's Mach names (`git.felix.sketchybar` and
`git.felix.skylandbar`), the way sketchybar's own CLI and [SbarLua](https://github.com/FelixKratz/SbarLua)
reach the bar. Lua configs run as they are: their events go to the item's `mach_helper` (SbarLua's
event loop). Calls to `/opt/homebrew/bin/sketchybar` from skyland, AeroSpace or a shell reach
skylandbar while sketchybar itself is stopped (`brew services stop sketchybar`).

A config that keeps running (SbarLua's event loop) gets its `forced` update 2 seconds after it
starts. `--reload` stops it before running it again.

## Start at login

```sh
.build/release/skylandbar --service install     # a launch agent, logs in ~/Library/Logs/skylandbar.log
.build/release/skylandbar --service uninstall
```

## Layout

```
Sources/SkylandBarCore   Foundation only and tested: values, properties, command parser, layout, model
Sources/skylandbar       AppKit: windows and drawing, socket server and client, system events, scripts
Tests                    XCTest for the core
```
