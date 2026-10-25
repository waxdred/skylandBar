# Reference

## Command line

### Start and manage

| Command | Does |
| --- | --- |
| `skylandbar` | start the bar with the default config (see [configuration.md](configuration.md)) |
| `skylandbar --config <file>` / `-c <file>` | start the bar with that config |
| `skylandbar --check [<file>]` | load a TOML config on an invisible bar, print `ok, N items` or its problems; exit 1 on errors |
| `skylandbar --export` | print the running bar as `skylandbar.toml` |
| `skylandbar --settings` | open (or close) the settings window |
| `skylandbar --service install` / `uninstall` | start at login with a launch agent / stop doing so |
| `skylandbar --version`, `--help` | |

### Talk to the running bar

Several commands can follow each other in one call:
`skylandbar --add item a left --set a label=x --subscribe a volume_change`.

| Command | Arguments | Does |
| --- | --- | --- |
| `--bar` | `<property=value>...` | set bar properties |
| `--add` | `item\|space\|alias\|graph\|slider\|workspaces\|title <name> <position>` | add an item (graph and slider: then their width; alias: name is `App,Item`) |
| `--add` | `bracket <name> <member or /regex/>...` | a background around those items |
| `--add` | `notch <name>` | the notch component |
| `--add` | `event <name> [<distributed notification>]` | a custom event |
| `--set` | `<name or /regex/> <property=value>...` | set item properties |
| `--default` | `<property=value>...` | properties every item added afterwards starts with |
| `--subscribe` | `<name> <event>...` | run the item's script on these events |
| `--trigger` | `<event> [VAR=value...]` | send an event (the variables reach the scripts) |
| `--remove` | `<name or /regex/>` | remove items |
| `--move` | `<name> before\|after <reference>` | reorder |
| `--reorder` | `<name>...` | put these items in this order |
| `--rename` | `<name> <new>` | |
| `--clone` | `<new> <parent> [before\|after]` | copy an item |
| `--push` | `<graph> <value>...` | add values (0...1) to a graph |
| `--animate` | `linear\|quadratic\|tanh\|sin\|exp\|circ <frames>` | the following `--set` / `--bar` changes animate (60 frames a second) |
| `--query` | `bar\|defaults\|events\|displays\|default_menu_items\|config\|<name>` | print JSON |
| `--update` | | run every script once (`SENDER=forced`) |
| `--reload` | `[<file>]` | load the config again (or another one) |
| `--hotload` | `on\|off` | reload when the config file changes |
| `--exit` | | quit the bar |

Exit status: 0, or 1 when a line of the answer starts with `[!]` (an error). `[?]` lines are
warnings: a `/regex/` that matches nothing, `--add` of an item that is already there.

## Values

| Kind | Written |
| --- | --- |
| color | `0xAARRGGBB` (also `0xRRGGBB`, `#RRGGBB`, `#AARRGGBB`); `color.alpha=0.5` changes only the opacity |
| font | `"Family:Style:Size"`, e.g. `"SF Pro:Semibold:14"`, `"Hack Nerd Font:Bold:16.0"`; `font.size=12`, `font.style=Bold`, `font.family=...` change one part |
| boolean | `on`/`off`, `true`/`false`, `yes`/`no`; `toggle` where it says so |
| number | points (pt), seconds where it says so |

## Bar properties (`--bar`, `[bar]`)

| Property | Default | Values |
| --- | --- | --- |
| `position` | `top` | `top`, `bottom` |
| `height` | 25 | points |
| `notch_display_height` | 0 | height on a notched display (0: `height`) |
| `margin` | 0 | room left and right of the bar |
| `y_offset` | 0 | room between the screen's edge and the bar |
| `color` | `0x44000000` | background |
| `border_color`, `border_width` | | |
| `corner_radius` | 0 | |
| `blur_radius` | 0 | blur of what is behind (not with glass) |
| `padding_left`, `padding_right` | 0 | room inside the bar's ends |
| `notch_width`, `notch_offset` | 200, 0 | the notch's room for `q` / `e` items |
| `display` | `all` | `all`, `main`, or display numbers `1,2` |
| `hidden` | `off` | `on`, `off`, `current` (not on the focused display), `toggle` |
| `topmost` | `off` | `on` (over the menu bar), `window` (over windows), `off` |
| `sticky` | on | on every Space |
| `shadow` | off | the window's shadow |
| `font_smoothing` | off | |
| `glass` | `off` | `regular`, `clear`, `off`: the whole bar as glass |
| `glass_engine` | `auto` | `auto`, `system`, `metal`, `backdrop`: see [liquid-glass.md](liquid-glass.md); `flat`: no glass, opaque panels (themes/glyph.toml) |
| `glass_refraction` | 14 | points the edges bend what is behind (`metal`; at most a shape's half height / 2.2) |
| `glass_blur` | 2 | points (`metal`) |
| `glass_saturation` | 1.5 | (`metal`) |
| `glass_spacing` | 0 | glass shapes closer than this melt into one |
| `glass_lens_response`, `glass_lens_bounce`, `glass_lens_stretch` | 0.35, 0.3, 1 | how a selection lens flows to its new place |
| `motion` | `auto` | `auto` (follows Reduce Motion), `full`, `reduced`: every animation of the bar |

## Item properties (`--set`, `[[item]]`)

| Property | Default | Values |
| --- | --- | --- |
| `position` | | see [configuration.md](configuration.md#items) |
| `drawing` | on | shown |
| `width` | dynamic | a number: fixed width (its background paddings inside it) |
| `y_offset` | 0 | up |
| `display` | `all` | `all`, `active` (the focused window's display), or `1,2` |
| `space` | all | Mission Control spaces it shows on |
| `ignore_association` | off | |
| `updates` | `when_shown` | `on`, `off`, `when_shown`: when `update_freq` runs the script |
| `update_freq` | 0 | seconds between script runs (`SENDER=routine`) |
| `script` | | shell command run on events it subscribes to and on `update_freq` |
| `click_script` | | shell command run on a click |
| `menubar` | off | a left click shows the frontmost app's menus (needs Accessibility), in place of `click_script`: the item's bubble drops a row and a row of glass runs right from it with the menus' titles (the item's `label` font and color; as far as the bracket named here reaches, if any), each dropping its menu; on a bottom bar, one native menu with the status extras |
| `menubar_opacity` | 0 | the menu bar's glass: 0 the bracket's tint, up to 1 opaque (black, white in light mode) |
| `menu_extra` | | a menu bar item's name (`wifi`, `battery`, `controlcenter`, `bluetooth`, `sound`, or a word of a third-party one's): a left click opens its own menu (needs Accessibility), in place of `click_script`; see [templates](../templates/) |
| `scroll_texts` | off | long texts (`max_chars`) scroll |
| `icon.*`, `label.*` | | text properties below |
| `background.*` | | background properties below |
| `popup.*` | | popup properties below |
| `hover.<property>` | | the item's look while the mouse is on it (animated) |
| `graph.*`, `slider.*`, `alias.*` | | see [components.md](components.md) |
| `mach_helper` | | a Mach service that gets the item's events (SbarLua) |

### Text (`icon.*`, `label.*`)

| Property | Values |
| --- | --- |
| `icon` / `label` (or `.string`) | the text |
| `drawing` | on/off |
| `font` | `"Family:Style:Size"` |
| `color`, `highlight`, `highlight_color` | `highlight=on` draws in `highlight_color` |
| `padding_left`, `padding_right`, `y_offset` | points |
| `width` | fixed width; `align` = `left`, `center`, `right` in it |
| `max_chars` | cut (or scroll with `scroll_texts`) after that many characters |
| `scroll_duration` | |
| `background.*`, `shadow.*` | a background / shadow of the text alone |

### Background (`background.*`, also `icon.background.*`, `popup.background.*`, `slider.background.*`)

| Property | Values |
| --- | --- |
| `drawing` | on/off (setting a color, a border or an image turns it on) |
| `color`, `border_color`, `border_width` | |
| `height` | 0: the bar's |
| `corner_radius` | points, or `"concentric"` (its container's radius less the gap); `0` on glass is a capsule |
| `padding_left`, `padding_right` | room around it (an item's: also between items) |
| `x_offset`, `y_offset` | |
| `clip` | 0...1: cut the bar out behind it |
| `glass` | `regular`, `clear`, `lens` (a selection inside other glass), `off` |
| `image` (or `.string`) | a file path, `app.<bundle id or app name>`, `media.artwork` |
| `image.scale`, `.corner_radius`, `.border_width`, `.border_color`, `.padding_left/right`, `.y_offset`, `.drawing`, `.shadow.*` | |
| `shadow.drawing`, `.color`, `.angle`, `.distance` | |

### Popup (`popup.*`)

| Property | Values |
| --- | --- |
| `drawing` | on, off, `toggle` |
| `horizontal` | items side by side |
| `align` | `left`, `center`, `right` |
| `height` | a row's height |
| `y_offset`, `topmost`, `blur_radius` | |
| `background.*` | the popup's background (glass works) |

Items placed `popup.<item>` are its content.

## Events

| Event | When | `INFO` / variables |
| --- | --- | --- |
| `forced` | `--update`, after the config loads | |
| `routine` | `update_freq` | |
| `front_app_switched` | another app is active | the app's name |
| `space_change` | Mission Control space changed | `{"display-1": N}` |
| `space_windows_change` | windows of a space changed | JSON: the space and its apps |
| `display_change` | a display was added, removed, rearranged | |
| `system_will_sleep`, `system_woke` | | |
| `power_source_change` | | `AC` or `BATTERY` |
| `volume_change` | | 0...100 |
| `brightness_change` | | 0...100 |
| `wifi_change` | | network name (needs Location Services) |
| `media_change` | Music / Spotify | JSON: `state`, `title`, `artist`, `album`, `app` |
| `mouse.entered`, `mouse.exited` | the mouse over the item | |
| `mouse.entered.global`, `mouse.exited.global` | the mouse into / out of the bar or popup | |
| `mouse.clicked` | | `BUTTON` (left/right/other), `MODIFIER` |
| `mouse.scrolled`, `mouse.scrolled.global` | | `SCROLL_DELTA` |
| `appearance_change` | dark / light | `dark` or `light` |
| `notch_open`, `notch_close` | the notch component | |
| skyland and AeroSpace events | see [skyland.md](skyland.md) | |
| custom | `--add event <name> [<notification>]`, then `--trigger <name>` or that distributed notification | the `--trigger` variables |

## Script variables

| Variable | Value |
| --- | --- |
| `NAME` | the item's name |
| `SENDER` | the event (`forced`, `routine`, `mouse.clicked`...) |
| `INFO` | the event's data |
| `BUTTON`, `MODIFIER` | clicks: `left`/`right`/`other`; `shift`, `ctrl`, `alt`, `cmd` or `none` |
| `SCROLL_DELTA` | scrolls |
| `PERCENTAGE` | sliders |
| `SELECTED`, `SID`, `DID` | space items |
| `CONFIG_DIR` | the config's folder |
| `BAR_NAME` | `skylandbar` (or `sketchybar` while skylandbar holds that name) |
| `APPEARANCE` | `dark` or `light` |
| skyland variables | `FOCUSED_WORKSPACE`, `PREV_WORKSPACE`, `MODE`... (see [skyland.md](skyland.md)) |
| `--trigger` variables | as given |

Scripts run with bash, in the config's folder, with `skylandbar` (and `sketchybar`) first on
`PATH`. They are stopped when the bar quits.

## Query

`--query bar`, `--query <item>`, `--query defaults`, `--query events`, `--query displays`,
`--query default_menu_items` (what aliases can copy), `--query config` (the bar as TOML, as
`--export`). Items have `bounding_rects`: where they are, per display (`display-1`...).
