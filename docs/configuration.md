# Configuration: skylandbar.toml

skylandbar reads, in this order, the first that exists:

1. the file given to `--config`
2. `~/.config/skylandbar/skylandbar.toml`
3. `~/.config/skylandbar/skylandbarrc`: a shell script that sends `skylandbar` commands (run with bash)

This page is about the TOML file. Each part of it becomes the commands a script would send
(`--bar`, `--default`, `--add`, `--set`, `--subscribe`), so a property means the same in both:
see [reference.md](reference.md) for every property.

## The whole shape

```toml
# keys before any [section]
include = "themes/liquid-glass.toml"     # a theme first (or a list of files)
vars_file = "~/.cache/skyland/theme.env" # NAME=value lines as vars (or a list)
hotload = true                           # reload when this file is saved
exec = ["~/bin/start-helpers.sh"]        # shell commands run once the file is loaded

[vars]                                   # ${name} in any string below
accent = "0xffcba6f7"

[vars.dark]                              # after the appearance: dark...
text = "0xffffffff"
[vars.light]                             # ...or light; the file loads again when it changes
text = "0xff000000"

[bar]                                    # --bar
height = 32
color = 0xcc1e1e2e

[defaults]                               # --default: what every item added after starts with
icon = { font = "Hack Nerd Font:Bold:14", padding_left = 6 }

[[event]]                                # --add event <name> [<distributed notification>]
name = "theme_changed"

[[item]]                                 # --add <type> <name> <position> --set ... --subscribe ...
name = "clock"
position = "right"
update_freq = 10
script = 'skylandbar --set "$NAME" label="$(date +%H:%M)"'
subscribe = "system_woke"
background = { color = "${accent}", corner_radius = 8 }
```

The top-level keys (`include`, `vars_file`, `hotload`, `exec`) must come **before** the first
`[section]`: in TOML, a key after a header belongs to that section.

## Items

`[[item]]` tables, in bar order. Keys:

| Key | Meaning |
| --- | --- |
| `name` | Required, unique. Used by `--set`, scripts (`$NAME`), brackets, popups |
| `type` | `item` (default), `space`, `alias`, `graph`, `slider`, `bracket`, `workspaces`, `title`, `notch` |
| `position` | `left`, `right`, `center`, `q`, `e`, `center_left`, `center_right`, `popup.<item>`; not for `bracket` and `notch` |
| `members` | `bracket` only: item names or `/regex/` |
| `subscribe` | an event name or a list of them |
| any other key | a property: `update_freq = 10`, `icon = { ... }`, `label.color = "0xff..."` |

Positions:

| Position | Where |
| --- | --- |
| `left` | from the left edge, in file order |
| `right` | from the right edge, **the first `right` item is the rightmost** |
| `center` | centered on the bar (on a notched display: under the camera, hidden) |
| `q` / `e` | against the notch, left / right of it (`notch_width` on the bar is its width) |
| `center_left` / `center_right` | centered in the room between the left (right) items and the notch |
| `popup.<item>` | in that item's popup (or in the notch component's panel) |

Tables give dotted keys: `icon = { font = "SF Pro:Bold:14", color = "0xffffffff" }` is
`icon.font=... icon.color=...`, and `background = { image = { string = "app.Safari", scale = 0.5 } }`
is `background.image.string=... background.image.scale=...`.

Rules of TOML that matter here:

- An inline table `{ ... }` stays on **one line**.
- A key cannot be both a value and a table: `image = "x"` and `image.scale = 1` together are an
  error (`'image' already has a value`). Write `image = { string = "x", scale = 1 }`.
- A multi-line script goes in `'''...'''` (literal: no escapes, `$NAME` stays as is).
- Integers written in hex for `*color` keys are colors: `color = 0xff1e1e2e` works like `"0xff1e1e2e"`.
- `true` / `false` work for on/off properties.

Graphs and sliders take their width in the item: `graph.width = 60`, `slider.width = 120`.

## Vars

| Form | Value |
| --- | --- |
| `${name}` | a `[vars]` var (its own `${...}` filled too), else an environment variable (`${HOME}`), else left as written |
| `${name:-default}` | `default` when there is no such var |
| `${color@0.1}` | a `0xAARRGGBB` color at that opacity (`0x1a...` here) |

Order: the included files' `[vars]`, then the file's own (it wins), then `[vars.dark]` or
`[vars.light]` for the current appearance, then the `vars_file` lines over all of them.

`vars_file = "~/.cache/skyland/theme.env"` is how the Liquid Glass theme takes skyland's colors:
see [liquid-glass.md](liquid-glass.md). A missing file is no error (the defaults stay); the
config loads again when the file changes.

## Themes and includes

`include = "themes/x.toml"` (relative to the config's folder, `~` for home; a list for several)
loads that file's vars, bar, defaults and items **first**, then the file's own, which can change
them. An included file cannot include others.

## Appearance

With `[vars.dark]` / `[vars.light]` the config loads again when macOS switches between dark and
light; scripts get the `appearance_change` event (`INFO` = `dark` or `light`) and `$APPEARANCE`.

## Reloading

| How | When |
| --- | --- |
| `hotload = true` | when the file is saved |
| `skylandbar --reload` | now (`--reload other.toml` for another file) |
| the settings window's Save | after writing |
| `vars_file` changing | when skyland (or anything) writes it |

## Checking and exporting

```sh
skylandbar --check                  # ~/.config/skylandbar/skylandbar.toml
skylandbar --check path/to/file.toml
skylandbar --export > bar.toml      # the running bar as TOML: what each item has that differs from the defaults
```

`--check` prints `ok, N items`, or one line per problem with where it is, then exits 1. `[!]`
lines are errors; `[?]` lines are warnings (a `/regex/` matching nothing, an item added twice).

## The settings window

`skylandbar --settings` opens a window (skyland's style: its theme colors over a blur) with the
bar's settings as sliders and pickers, showing the running bar's values:

| Section | Written to |
| --- | --- |
| Bar: position, height, offset, margin, paddings, corner radius, above windows | `[bar]` of the config file |
| Glass: engine, refraction, blur, saturation, spacing, animations | `[bar]` |
| Workspaces: at most, animation | the workspaces component's `workspaces = { ... }` |
| Notch open / closed: material, sizes, corners, curves, delays | the notch component's `notch = { ... }` |

Changes wait for **Save** (⌘S): the config is checked first (nothing is written if it does not
load), each changed value is written on its own line (comments and order kept), and the bar
reloads. **Revert** drops unsaved changes. "Open config file" gives the file to its editor.
`--settings` again on the window closes it. Values that come from an included theme are written
into the config file, where they win over the theme.

The notch's `notch.bottom_right` can hold a gear item whose `click_script` is
`skylandbar --settings` (the Liquid Glass example does).

## Shell configs

A `skylandbarrc` (or any non-`.toml` file given to `--config`) is run with bash and sends commands:

```sh
#!/bin/bash
skylandbar --bar height=32 color=0xff1e1e2e \
           --default icon.font="SF Pro:Bold:14" \
           --add item clock right \
           --set clock update_freq=10 script='skylandbar --set $NAME label="$(date +%H:%M)"'
skylandbar --update                 # run every script once
```

`skylandbar --export` turns the running bar (from such a script) into TOML.
