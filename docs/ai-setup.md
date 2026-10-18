# Setting skylandbar up for a user: guide for an AI assistant

This page is written for an AI assistant (Claude Code, a chat with shell access...) that installs
and configures skylandbar for a user. It is the procedure, the rules that keep a config working,
and the checks to run before saying it is done. The other pages are the reference:
[configuration.md](configuration.md), [reference.md](reference.md), [components.md](components.md),
[liquid-glass.md](liquid-glass.md), [recipes.md](recipes.md), [troubleshooting.md](troubleshooting.md).

## What you are working with

- One binary, `skylandbar`: it is the bar when started without commands, and the client of the
  running bar otherwise (`skylandbar --set ...`).
- One config file, `~/.config/skylandbar/skylandbar.toml`, outside any repository. Themes go in
  `~/.config/skylandbar/themes/`, scripts the user wants to keep in `~/.config/skylandbar/plugins/`.
- The repository holds `themes/liquid-glass.toml`, `examples/liquid-glass.toml` (a glass bar),
  `examples/skylandbar.toml` (a plain bar).
- Tools you can rely on to verify your work: `skylandbar --check`, `skylandbar --query <item>`,
  `skylandbar --query bar`, the start line (`skylandbar: glass: ...`), and a screenshot
  (`screencapture -x -R0,0,<width>,50 /tmp/bar.png`, then look at it).

## Procedure

### 1. Learn the machine (read only)

```sh
sw_vers -productVersion                       # macOS version: 26+ has Apple's glass
xcode-select -p; swift --version              # toolchain
pgrep -lf 'sketchybar|skylandbar|skyland|AeroSpace'
ls ~/.config/skylandbar ~/.config/sketchybar 2>/dev/null
system_profiler SPDisplaysDataType | grep -E 'Resolution|Main'
brew list --cask | grep -iE 'font-sf-pro|sf-symbols|nerd'
```

From this decide, and tell the user:

- a notched display (MacBook 14"/16" since 2021) means nothing useful can go at `center`;
- skyland or AeroSpace present means the `workspaces` and `title` components work;
- an existing `~/.config/sketchybar/sketchybarrc` means a migration
  ([migrating-from-sketchybar.md](migrating-from-sketchybar.md));
- an existing `~/.config/skylandbar/skylandbar.toml` must be backed up before any change
  (`cp skylandbar.toml skylandbar.toml.bak`).

### 2. Ask only what you cannot decide

Useful questions, with a default you can take if the user does not care:

| Question | Default |
| --- | --- |
| Glass (Liquid Glass theme) or an opaque bar? | glass |
| Which items? (clock, battery, volume, CPU, memory, Wi-Fi, keyboard, media, workspaces, window title) | workspaces left; clock, battery, volume right |
| Keep the notch panel? | yes on a notched display |
| Colors from skyland's theme? | yes when skyland runs |

### 3. Build and install

```sh
cd path/to/skylandBar
swift build -c release
mkdir -p ~/.config/skylandbar/themes
cp themes/liquid-glass.toml ~/.config/skylandbar/themes/     # for a glass bar
```

Fonts the config will use, if missing (ask before installing):
`brew install --cask font-sf-pro sf-symbols font-hack-nerd-font`.

### 4. Write the config

Start from `examples/liquid-glass.toml` (glass) or `examples/skylandbar.toml` (plain), or from
the user's translated sketchybarrc. Add items from [recipes.md](recipes.md). Keep the user's own
values (sizes they edited, their scripts) when you change a file: edit lines, do not regenerate
the whole file without need.

### 5. Check before touching the running bar

```sh
skylandbar --check                                   # must print: ok, N items
```

Fix every `[!]` line. Never install a config that does not pass `--check`.

### 6. Run it and look at it

```sh
skylandbar --exit 2>/dev/null; brew services stop sketchybar 2>/dev/null
skylandbar --service install                         # or: skylandbar &  for a try
sleep 3; tail -3 ~/Library/Logs/skylandbar.log       # the glass engine line, errors
skylandbar --query bar | head -40                    # items, in order
screencapture -x -R0,0,1728,50 /tmp/bar-left.png    # then view the image
```

For each item, check that its label has a value: `skylandbar --query clock` (`label.value`).
An empty label means its script failed: run it by hand
(`NAME=clock SENDER=forced bash -c '<script>'`).

### 7. Tell the user what to do by hand

- Screen Recording for the `metal` glass: System Settings > Privacy & Security > Screen Recording,
  add `.build/arm64-apple-macosx/release/skylandbar`, then
  `launchctl kickstart -k gui/$(id -u)/com.waxdred.skylandbar`.
- Where the config is, that it reloads on save, and `skylandbar --settings` for sliders.

## Rules that keep a config working

1. **Top-level keys first.** `include`, `vars_file`, `hotload`, `exec` go before the first
   `[section]`; after a header, a key belongs to that section.
2. **Inline tables on one line.** `icon = { font = "...", color = "..." }` cannot span lines.
3. **A key is a value or a table, not both.** Not `image = "x"` with `image.scale = 1`:
   `image = { string = "x", scale = 1 }`. Same for `icon` / `label`: use `icon = { string = "..." }`
   when the icon also has other keys, or `icon = "..."` alone.
4. **Scripts in literal strings.** One line: `script = '...'` (single quotes, so `$NAME` and `"`
   stay as they are). Several lines: `script = '''...'''`. Avoid escaped quotes inside; when the
   script needs both kinds of quotes, use a multi-line literal and plain shell.
5. **Scripts call `skylandbar --set "$NAME" ...`.** `$NAME` is the item; quote values with spaces.
6. **`right` items are listed from the right edge**: the first `right` item in the file is the
   rightmost.
7. **Nothing at `center` on a notched display**: use `q` / `e` (against the notch, with the bar's
   `notch_width`) or `center_left` / `center_right` (centered between the side items and the notch).
8. **Glass groups need room between them.** A bracket spans its items plus their outer paddings
   plus its own: two adjacent groups overlap. Put a spacer item (`width = 20`, nothing drawn)
   between them in file order. Shapes closer than `glass_spacing` (8 in the theme) melt.
9. **Brackets take `members`**, names or `"/regex/"` (the workspaces items: `"/^ws\\./"` for a
   component named `ws`).
10. **Component options live in their table**: `workspaces = { max = 12 }`, `title = { format = "app" }`,
    `notch = { width = 600 }`; per-workspace looks in `workspace = { "1" = { icon = "..." } }`.
11. **skyland's scratchpads are workspaces**: `workspaces = { max = 12 }` (or the user's count).
12. **Colors are `0xAARRGGBB`** (alpha first). `"${accent@0.3}"` is a var at 30 %.
13. **SF Symbols need SF Pro installed**; Nerd Font glyphs need the item's font to be a Nerd Font.
14. **Back up before overwriting** the user's config, and keep their edits.
15. **Do not edit `~/.config/sketchybar`**: copy what you need into `~/.config/skylandbar/`.

## A complete config to start from (glass, notched MacBook, skyland)

```toml
include = "themes/liquid-glass.toml"
hotload = true

[bar]
topmost = "on"
notch_width = 200

[[item]]
type = "workspaces"
name = "ws"
position = "left"
icon = { color = "${secondary}", padding_left = 10, padding_right = 10 }
label = { drawing = false }
background = { drawing = true, color = "0x00000000", height = 28, corner_radius = "concentric" }
focused = { icon.color = "${accent}", background.glass = "lens", background.color = "${accent_soft}" }
hover = { background.color = "${hover}" }
workspaces = { max = 12 }

[[item]]
type = "bracket"
name = "ws.glass"
members = ["/^ws\\./"]
background = { glass = "regular", color = "${glass_tint}", height = 36, corner_radius = 0, drawing = true, padding_left = 4, padding_right = 4 }

[[item]]
name = "clock"
position = "center_right"
update_freq = 10
icon = "􀐫"
script = 'skylandbar --set "$NAME" label="$(date "+%a %d %b  %H:%M")"'
background = { glass = "regular", color = "${glass_tint}", height = 36, corner_radius = 0, drawing = true }

[[item]]
name = "battery"
position = "right"
update_freq = 120
script = '''
percent=$(pmset -g batt | grep -Eo "[0-9]+%" | tr -d %)
skylandbar --set "$NAME" label="$percent%"
'''
icon = "􀛨"
subscribe = ["power_source_change", "system_woke"]
background = { drawing = true, color = "0x00000000", height = 28, corner_radius = "concentric" }

[[item]]
name = "volume"
position = "right"
icon = "􀊩"
script = '''
[ "$SENDER" = volume_change ] || INFO=$(osascript -e "output volume of (get volume settings)")
skylandbar --set "$NAME" label="$INFO%"
'''
subscribe = "volume_change"
background = { drawing = true, color = "0x00000000", height = 28, corner_radius = "concentric" }

[[item]]
type = "bracket"
name = "status.glass"
members = ["battery", "volume"]
background = { glass = "regular", color = "${glass_tint}", height = 36, corner_radius = 0, drawing = true, padding_left = 4, padding_right = 4 }

[[item]]
type = "notch"
name = "island"
notch = { glass = "regular", color = "${glass_tint}", width = 600, height = 190, padding = 16, bottom_right = "island.settings" }

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
label = { drawing = false }
click_script = "skylandbar --settings"
```

## Done means

- [ ] `skylandbar --check` prints `ok`
- [ ] the bar runs (`skylandbar --query bar` answers) and starts at login (`launchctl list | grep skylandbar`)
- [ ] every item with a script has a label value (`--query <item>`)
- [ ] a screenshot shows nothing hidden by the notch and no overlapping capsules
- [ ] the start line names the expected glass engine, or the user knows the permission step
- [ ] the user's previous config is backed up, and you said where everything is
