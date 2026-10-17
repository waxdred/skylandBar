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

## Configuration: skylandbar.toml

skylandbar reads, in this order: `~/.config/skylandbar/skylandbar.toml`, then
`~/.config/skylandbar/skylandbarrc`, then `~/.config/sketchybar/sketchybarrc` (or the file given to
`--config`). A `.toml` file is skylandbar's own; the others are run as sketchybar configs.

```toml
hotload = true                       # reload when the file is saved (keys before any [section])

[vars]                               # ${name} in any string, then the environment (${HOME})
accent = "0xffcba6f7"

[bar]
height = 34
corner_radius = 12
color = 0xcc1e1e2e                   # a hex integer for a *color key is a color

[defaults]
icon = { font = "Hack Nerd Font:Bold:15", padding_left = 6 }

[[event]]
name = "theme_changed"

[[item]]                             # in bar order
name = "clock"
position = "right"
update_freq = 10
script = 'sketchybar --set "$NAME" label="$(date +%H:%M)"'
subscribe = "system_woke"
background = { color = "${accent}", corner_radius = 8 }

[[item]]
type = "workspaces"                  # item (default), space, alias, graph, slider, bracket,
name = "ws"                          # workspaces, title, notch
position = "left"
focused = { icon.color = "${accent}" }
```

Each `[[item]]` becomes the `--add` / `--set` / `--subscribe` a sketchybarrc would send, so the keys
are sketchybar's property names, and tables give dotted keys. Graphs and sliders take their width
from `graph.width` / `slider.width`, and brackets take `members = [...]`. A multi-line script goes
in `'''...'''`. `exec = [...]` (before any section) runs commands once the file is loaded.
An inline table `{ ... }` stays on one line. `examples/skylandbar.toml` is a full bar
(workspaces, title, clock, battery, volume, notch).

```sh
skylandbar --export > ~/.config/skylandbar/skylandbar.toml   # the running bar (your sketchybarrc) as TOML
skylandbar --check                                           # check the file without touching the bar
```

`--export` writes what each item has that differs from the defaults, with the scripts as they are
and the labels as they are now.

## The Liquid Glass theme

`themes/liquid-glass.toml` follows Apple's Liquid Glass
([overview](https://developer.apple.com/documentation/technologyoverviews/liquid-glass),
[NSGlassEffectView](https://developer.apple.com/documentation/appkit/nsglasseffectview)) with the
numbers of the [Liquid Glass guide](https://github.com/giorgio-a11y/liquid-glass-guide).
`examples/liquid-glass.toml` is a bar made with it:

```sh
mkdir -p ~/.config/skylandbar/themes
cp themes/liquid-glass.toml ~/.config/skylandbar/themes/
cp examples/liquid-glass.toml ~/.config/skylandbar/skylandbar.toml
```

| Apple's rule | In skylandbar |
| --- | --- |
| Glass is the control layer over the content, used sparingly, never glass on glass | the bar has no background; each group of controls is one glass capsule (`background.glass` on a bracket) |
| Default shape: a capsule; corners concentric to their container | `corner_radius = 0` on glass is a capsule; `corner_radius = "concentric"` follows the bar's or the popup's radius |
| Group glass in a container: one render pass, nearby shapes merge | each window's glass views sit in an `NSGlassEffectContainerView`; `glass_spacing` on the bar is its spacing |
| Tint only for prominence; system colors with light and dark variants | one tinted element (the focused workspace); `[vars.dark]` / `[vars.light]`, reloaded when the appearance changes |
| Hover at primary 0.04, easeInOut 0.15 s; springs about 0.3 s | `hover.*`: an item's look under the mouse, animated in 9 frames; workspaces in 18 |
| SF Pro 11 pt or more, no Thin / Light; SF Symbols; 8 pt grid | the theme's fonts, icons and paddings |
| Reduce Transparency, Increase Contrast, Reduce Motion | the first two change the system's glass by themselves; Reduce Motion ends skylandbar's animations at once |

### Glass engines: Liquid Glass before macOS 26 too

Apple's `NSGlassEffectView` exists only on macOS 26. skylandbar draws its glass with one of three
engines (`--bar glass_engine=...`, `auto` by default, which takes the first this Mac can do):

| Engine | What it is | Needs |
| --- | --- | --- |
| `system` | Apple's NSGlassEffectView in an NSGlassEffectContainerView | macOS 26 |
| `metal` | skylandbar's shader over what is behind the bar (ScreenCaptureKit, without skylandbar's own windows): the edges bend it as a lens would (`glass_refraction`, points, at most a shape's half height / 2.2 so it magnifies and never mirrors), colors split a little there, a light blur (`glass_blur`) and saturation (`glass_saturation`), the glass's own light in dark and light mode, a rim lit from the top left, a sheen, a faint inner shadow; shapes closer than `glass_spacing` melt into one | Screen Recording |
| `backdrop` | Core Animation's backdrop layer (the window server's blur, saturated) under a tint, a sheen, a rim light and a soft shadow; no refraction | nothing |

The bar says on stderr (or in `~/Library/Logs/skylandbar.log` as a service) which one it took.
To get `metal`, allow skylandbar in System Settings > Privacy & Security > Screen Recording, then
restart it (`--bar glass_engine=metal` asks once). The capture only covers the bar and a margin
around it, and sends a frame only when what is behind changes.

A selection lens (`background.glass = "lens"`, the focused workspace in the theme) flows to its
new item like a drop, as Apple's tab bars do: its leading end leaves first and fast, its trailing
end follows and catches up, so it stretches on its way (thinner, as a drop keeps its volume, at
most 1.8 times as long) and settles with a little jelly; while it moves it is lifted (it
magnifies more, its rim and shade grow). `glass_lens_response` (seconds, 0.35; 0 jumps),
`glass_lens_bounce` (overshoot, 0 to 1, 0.3), `glass_lens_stretch` (how unlike its ends are; 0:
it slides in one piece). A lens that appears grows out of 70 %. Reduce Motion: no slide.

`motion` on the bar decides for all of skylandbar's animations (lenses, `--animate`, workspaces,
hover, the notch): `auto` (the default) follows macOS's Reduce Motion, `full` animates anyway,
`reduced` never does.

What makes this possible, for any config:

- `include = "themes/x.toml"` (before any section, relative to the config's folder): a theme's
  vars, bar, defaults and items first, then yours, which can change them.
- `[vars.dark]` and `[vars.light]`: vars after the appearance. The config loads again when it
  changes, and scripts get `appearance_change` (INFO dark or light) and `APPEARANCE`.
- `hover.<property>` on any item, a workspaces component too: its look while the mouse is on it.
- `corner_radius = "concentric"`, `glass_spacing`, and capsules for glass.
- A bracket spans its members with the first one's `background.padding_left` and the last
  one's `background.padding_right` (as in sketchybar), then its own `background.padding_left/right`
  outward: room at a group's ends only, so a selection keeps off the glass's edge.
- `vars_file = "~/.cache/skyland/theme.env"` (before any section): its `NAME=value` lines are vars
  over every `[vars]`; the config loads again when the file changes. The Liquid Glass theme
  takes skyland's `ACCENT` this way (skyland-theme writes it), for a light tint on the glass,
  the hover and the selection, systemBlue without skyland.
- `${name:-default}` (a default when there is no such var) and `${color@0.1}` (a `0xAARRGGBB`
  color at that opacity); a var's value can use other vars.

## What works

| Area | Supported |
| --- | --- |
| Commands | `--bar`, `--add item/event/bracket/graph/slider/alias/space/workspaces/title/notch`, `--set` (name or `/regex/`), `--default`, `--subscribe`, `--trigger` (with `VAR=value`), `--remove`, `--move before/after`, `--reorder`, `--rename`, `--clone`, `--push`, `--animate`, `--query bar/defaults/events/displays/default_menu_items/config/<item>`, `--update`, `--reload [file]`, `--hotload on/off`, `--exit` |
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
- **Windows below the bar**: skylandbar tells skyland the room it takes at the top
  (`height` + `y_offset`, the notch height when a notched display shows it; 0 at the
  bottom or hidden) when it starts, its config changes, or skyland restarts, with
  skyland's `bar-height` command. No `bar-height` to keep in sync in skyland's config;
  quitting the bar goes back to it.
- **Built-in workspaces and window title, no scripts**: skylandbar asks skyland (or AeroSpace)
  itself, on each of its events:

  ```sh
  skylandbar --add workspaces ws left \
             --set ws icon.font="SF Pro:Bold:13" icon.color=0xff6c7086 label="{apps}" label.font.size=11 \
                      background.color=0xff313244 background.corner_radius=6 background.height=22 \
                      icon.padding_left=8 label.padding_right=8 \
                      focused.icon.color=0xffcba6f7 focused.background.color=0xff45475a \
                      empty.label="" visible.background.border_width=1 visible.background.border_color=0xff585b70 \
                      workspaces.animation=tanh workspaces.animation_frames=12 \
             --add title title center --set title title.app_icon=on label.max_chars=50
  ```

  `--add workspaces <name> <position>` puts an item per workspace right after it, named
  `<name>.<workspace>`. Each item gets the component's properties, then those of its states:
  `empty.*` (no window), `visible.*` (shown on a display), `focused.*`, with the later ones
  winning. `workspace.<name>.*` gives one workspace its own look, under the states
  (`workspace.1.icon=󰇧`). `{name}`, `{apps}` (each app once) and `{count}` (windows) are filled in the icon
  and the label; an icon left empty shows `{name}`. Each item sits on its workspace's display
  (`workspaces.monitor=off`: on every bar). A click goes to that workspace, and scrolling over the
  items goes to the next or previous one (`workspaces.scroll=off` turns this off). With
  `workspaces.animation=<curve>` (and `workspaces.animation_frames`, 15), the items move to
  their new look. The items also take the component's script and subscriptions, with `NAME`
  set to the item.

  `--add title <name> <position>` shows the focused window: `title.format` is `app_title`
  ("App: title"), `title` or `app`; `title.empty` (Desktop) is shown when no window has the
  focus; `title.app_icon=on` draws the app's icon as the icon's background image.

  Pick a component name your config does not already use for items (skyland's own profile
  has `workspace.N` items).

- **The notch, boringNotch style**: hovering the camera notch opens a black panel that
  grows out of it, holding your own items:

  ```sh
  skylandbar --add notch island \
             --set island notch.width=340 notch.corner_radius=22 notch.animation=tanh notch.animation_frames=18 \
             --add item island.song popup.island \
             --set island.song icon=󰝚 label="Rien en lecture" label.max_chars=40 scroll_texts=on \
                   script='sketchybar --set $NAME label="$(echo "$INFO" | jq -r ".artist + \" — \" + .title")"' \
             --subscribe island.song media_change \
             --add slider island.volume popup.island 260 \
             --set island.volume icon=󰕾 slider.percentage=50 slider.background.height=5 slider.background.corner_radius=3 \
                   slider.background.color=0xff3c3c3c slider.highlight_color=0xffffffff \
                   script='osascript -e "set volume output volume $PERCENTAGE"' --subscribe island.volume mouse.clicked
  ```

  `--add notch <name>` makes it; the items placed `popup.<name>` are its content, one per
  row (`notch.horizontal=on`: side by side), and they show once it is open. It opens
  `notch.open_delay` (0.3 s) after the mouse comes over the notch and closes
  `notch.close_delay` (0.1 s) after the mouse leaves it, on boringNotch's springs
  (`notch.animation=spring`, the default: a little past open, closing without a bounce), or
  a curve over `notch.animation_frames` (20). Its size is what the items need, `notch.width` /
  `notch.height` at least, with `notch.padding` (12), `notch.row_height` (the notch's
  height), `notch.corner_radius` (24, the bottom corners), `notch.flare` (19, the top curves
  into the screen's edge) and `notch.color` (black). Closed: `notch.closed_width` /
  `notch.closed_height` (the camera's notch), `notch.closed_corner_radius` (14),
  `notch.closed_flare` (6). `notch.open=on|off|toggle`
  opens or closes it from a script (on media_change, for example), and items can subscribe to
  `notch_open` / `notch_close`. Without a notch nothing shows, unless `notch.fake=on`, which puts
  one at the top middle of the main display. `notch.glass=on` (or `clear`): the same shape on the same
  springs, of glass (the bar's glass engine, `notch.color` its tint); closed, it is the black
  notch. examples/liquid-glass.toml has one.

- **Liquid Glass**: `--bar glass=on` (or `clear`), and `background.glass=on` on any background
  (items, icons, labels, brackets, `popup.background`, `slider.background`). The color becomes
  the glass tint. It uses `NSGlassEffectView` on macOS 26 when built with Xcode 26, and a blurred
  material before that. `background.glass=lens` inside another glass shape is a selection, as in
  Apple's tab bars: a drop of thicker glass (what is behind a little magnified, lighter, its own
  rim light) that does not melt into the glass around it (metal engine; elsewhere, glass). A
  selected workspace keeps its background under the mouse.

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
