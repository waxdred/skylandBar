# Components

Built-in item kinds. In TOML: `type = "<kind>"` in an `[[item]]`. On the command line:
`skylandbar --add <kind> <name> <position>`.

## workspaces: skyland's (or AeroSpace's) workspaces

One item per workspace, made and updated by the bar itself (it asks skyland on each of its
events: no script needed). The items are named `<component name>.<workspace>` and sit right after
the component.

```toml
[[item]]
type = "workspaces"
name = "ws"
position = "left"
icon = { font = "SF Pro:Bold:13", color = "0xff6c7086", padding_left = 10, padding_right = 4 }
label = { string = "{apps}", font = "SF Pro:Medium:11", padding_right = 10 }
background = { drawing = true, color = "0x00000000", height = 28, corner_radius = 8 }
focused = { icon.color = "0xffcba6f7", background.color = "0x40cba6f7" }
visible = { background.border_width = 1, background.border_color = "0xff585b70" }
empty = { label.string = "" }
hover = { background.color = "0x1affffff" }
workspaces = { max = 12, animation = "tanh", animation_frames = 15 }
workspace = { "1" = { icon = "󰇧" }, "2" = { icon = "󰭻" } }
```

| Key | Meaning |
| --- | --- |
| any property | every workspace item starts with it |
| `empty.*` | a workspace with no window |
| `visible.*` | a workspace shown on a display |
| `focused.*` | the focused workspace (later states win: empty, visible, focused) |
| `workspace.<name>.*` | one workspace's own look, applied before the states (its icon, mostly) |
| `hover.*` | under the mouse (a focused lens keeps its background) |
| `workspaces.max` | the first N workspaces only, in skyland's order; 0 (default) all. skyland lists its scratchpads (`scratch`, `scratch-music`) after 1-12: `max = 12` leaves them out |
| `workspaces.monitor` | `off`: every workspace on every bar (default: each on its display's bar) |
| `workspaces.scroll` | `off`: no workspace switching with the scroll wheel |
| `workspaces.animation`, `.animation_frames` | a curve (`linear`, `quadratic`, `tanh`, `sin`, `exp`, `circ`) and frames (15) to move to a new look |

In texts: `{name}` (the workspace's name; an empty icon shows it), `{apps}` (its apps, once
each), `{count}` (its windows). A click goes to that workspace; scrolling goes to the next or
previous one. The items also get the component's script and subscriptions, with `NAME` set to
the item. Name the component something your config does not use for other items.

A capsule of glass around them: a bracket with `members = ["/^ws\\./"]` (see below).

## title: the focused window

```toml
[[item]]
type = "title"
name = "window"
position = "left"
title = { format = "app_title", app_icon = "on", empty = "Desktop" }
label = { max_chars = 48 }
```

| Key | Values |
| --- | --- |
| `title.format` | `app_title` ("App: title"), `title`, `app` |
| `title.empty` | shown with no focused window (`Desktop`) |
| `title.app_icon` | `on`: the app's icon as the icon's background image |

## notch: a panel that opens from the camera's notch

Hovering the notch opens it on a spring (boringNotch's shape and timing); the items placed
`popup.<notch name>` are its content, shown once it is open.

```toml
[[item]]
type = "notch"
name = "island"
notch = { glass = "regular", color = "0x14ffffff", width = 600, height = 190, padding = 16, closed_width = 205, closed_height = 42, bottom_right = "island.settings" }

[[item]]
name = "island.date"
position = "popup.island"
icon = "􀉉"
script = 'skylandbar --set "$NAME" label="$(date "+%A %d %B  %H:%M")"'
subscribe = "notch_open"

[[item]]
name = "island.settings"
position = "popup.island"
icon = "􀍟"
click_script = "skylandbar --settings"
```

| Option (`notch.*`) | Default | Meaning |
| --- | --- | --- |
| `width`, `height` | the items' | open size at least (`width` without the top curves; `height` from the screen's top) |
| `padding` | 12 | room around the items |
| `row_height` | the notch's height | a row of items |
| `horizontal` | off | items side by side |
| `corner_radius` | 24 | open: bottom corners |
| `flare` | 19 | open: the curves where it meets the screen's top edge |
| `closed_width`, `closed_height` | the camera's notch | closed size: larger shows around the camera |
| `closed_corner_radius`, `closed_flare` | 14, 6 | closed corners and curves |
| `color` | black | its color; with glass, the glass's tint |
| `glass` | off | `regular` / `clear`: the same shape and springs in glass, closed too |
| `open_delay`, `close_delay` | 0.3, 0.1 | seconds after the mouse comes / leaves |
| `animation` | `spring` | boringNotch's springs (a little past open, no bounce closing), or a curve with `animation_frames` (20) |
| `bottom_right` | | an item of the notch put in its bottom right corner, out of the rows |
| `open` | | `on`, `off`, `toggle`: from a script |
| `fake` | off | `on`: a notch at the top middle of the main display when it has none (to try it on an external display) |

Items can subscribe to `notch_open` / `notch_close`. Without a notched display (and without
`fake`), nothing shows. While open, the notch's window takes the clicks under it.

## bracket: one background around several items

```toml
[[item]]
type = "bracket"
name = "status.glass"
members = ["volume", "battery", "clock"]      # names or "/regex/"
background = { glass = "regular", height = 36, corner_radius = 0, drawing = true, padding_left = 4, padding_right = 4 }
```

It spans its members, plus the first member's `background.padding_left` and the last one's
`background.padding_right`, plus its **own** `background.padding_left/right` outward. Two brackets
next to each other therefore overlap unless something is between them: put a spacer item
(`width = 20`, nothing drawn) between the groups. Glass brackets closer than the bar's
`glass_spacing` melt into one shape.

## graph

```toml
[[item]]
type = "graph"
name = "cpu.graph"
position = "right"
graph = { width = 60, color = "0xffa6e3a1", fill_color = "0x40a6e3a1", line_width = 1 }
```

`skylandbar --push cpu.graph 0.42` adds a value (0...1); they scroll right to left.

## slider

```toml
[[item]]
type = "slider"
name = "volume.slider"
position = "right"
slider = { width = 100, percentage = 50, highlight_color = "0xffffffff", knob = "●", background = { height = 4, color = "0x40ffffff", corner_radius = 2 } }
script = 'osascript -e "set volume output volume $PERCENTAGE"'
subscribe = "mouse.clicked"
```

Dragging sends `mouse.clicked` with `PERCENTAGE`. `slider.knob.*` styles the knob as a text.

## alias: a copy of a menu bar item

```sh
skylandbar --query default_menu_items      # the names it can copy: "App,Item"
```

```toml
[[item]]
type = "alias"
name = "Control Center,Battery"
position = "right"
alias = { color = "0xffffffff", scale = 1, update_freq = 1 }
```

Needs Screen Recording; a click goes to the real item (needs Accessibility).

## space: a Mission Control space

`type = "space"` items get `SELECTED`, `SID`, `DID` in their scripts and `space_change`. For
skyland or AeroSpace workspaces use `workspaces` instead.

## popups

Any item has a popup: items placed `popup.<item>` are its rows. Open it with
`popup.drawing=toggle` (in a `click_script`), close it on `mouse.exited.global`:

```toml
[[item]]
name = "clock"
position = "right"
click_script = 'skylandbar --set "$NAME" popup.drawing=toggle'
script = '[ "$SENDER" = mouse.exited.global ] && skylandbar --set "$NAME" popup.drawing=off'
subscribe = "mouse.exited.global"
popup = { align = "center", background = { glass = "regular", corner_radius = 16, drawing = true } }

[[item]]
name = "clock.date"
position = "popup.clock"
script = 'skylandbar --set "$NAME" label="$(date "+%A %d %B")"'
```
