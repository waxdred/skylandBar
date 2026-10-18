# Migrating from SketchyBar

skylandbar uses SketchyBar's command and property names, so a `sketchybarrc` and its plugins
translate line for line. This page is the procedure; [ai-setup.md](ai-setup.md) has it as steps
for an assistant.

## Compatibility

Tools that talk to a bar by SketchyBar's names reach skylandbar:

- scripts started by skylandbar find it as `sketchybar` too, first on their `PATH`: plugins that
  call `sketchybar --set ...` work unchanged;
- skylandbar holds the Mach names `git.felix.skylandbar` and `git.felix.sketchybar`, used by the
  `sketchybar` CLI (`/opt/homebrew/bin/sketchybar`) and [SbarLua](https://github.com/FelixKratz/SbarLua).
  Only one bar can hold the second: while SketchyBar itself runs, they reach SketchyBar, and
  skylandbar says so when it starts;
- Lua configs (SbarLua) run as they are (`skylandbar --config init.lua`): their events go to the
  item's `mach_helper`.

skylandbar never reads `~/.config/sketchybar`: point it at a file, or translate the config.

## Translate a sketchybarrc

1. **Copy the plugins** you use into `~/.config/skylandbar/plugins/`, and in them replace
   `sketchybar --` with `skylandbar --`, and `~/.config/sketchybar/` paths with the new ones.
   (`sketchybar --` keeps working inside skylandbar's scripts; the copy lets you uninstall
   SketchyBar and its folder.)
2. **Translate the rc** to `~/.config/skylandbar/skylandbar.toml`, one part at a time:

| sketchybarrc | skylandbar.toml |
| --- | --- |
| `export ACCENT=0xffc6a0f6` | `[vars]` `ACCENT = "0xffc6a0f6"`, used as `"${ACCENT}"` |
| `sketchybar --bar height=32 color=$BASE` | `[bar]` `height = 32`, `color = "${BASE}"` |
| `sketchybar --default icon.font="..." label.color=$X` | `[defaults]` `icon = { font = "..." }`, `label = { color = "${X}" }` |
| `sketchybar --add item clock right --set clock update_freq=30 script="$PLUGIN_DIR/clock.sh"` | `[[item]]` `name = "clock"`, `position = "right"`, `update_freq = 30`, `script = "$HOME/.config/skylandbar/plugins/clock.sh"` |
| `--subscribe clock system_woke` | `subscribe = "system_woke"` (or a list) |
| `--add bracket status volume battery --set status background.color=...` | `[[item]]` `type = "bracket"`, `members = ["volume", "battery"]`, `background = { color = "..." }` |
| `--add event theme_changed` | `[[event]]` `name = "theme_changed"` |
| a `for` loop making `space.1`...`space.N` with `yabai` / `aerospace` scripts | one `type = "workspaces"` item (built in, no script): see [components.md](components.md) |
| a window title plugin (`yabai -m query`, `aerospace list-windows`) | one `type = "title"` item |
| `sketchybar --update` at the end | nothing (the bar runs every script once after loading) |

Or let skylandbar translate: run the old rc with skylandbar, then export.

```sh
skylandbar --config ~/.config/sketchybar/sketchybarrc   # the old config, run by skylandbar
skylandbar --export > ~/.config/skylandbar/skylandbar.toml
```

The export has every item with what differs from the defaults (literal values, not your vars):
a starting point to clean up.

3. **Check, then run**:

```sh
skylandbar --check
brew services stop sketchybar
skylandbar --service install
```

4. **Uninstall SketchyBar** once the bar is right: `brew uninstall sketchybar`.

## Differences to know

| Topic | SketchyBar | skylandbar |
| --- | --- | --- |
| config | `~/.config/sketchybar/sketchybarrc` (a script) | `~/.config/skylandbar/skylandbar.toml` (or `skylandbarrc`, a script) |
| workspaces of a window manager | your scripts | built-in `workspaces` component (skyland, AeroSpace) |
| text fonts | a missing font falls back to Helvetica | same, except `SF Pro` which falls back to the system font |
| `center` on a notched display | under the camera | the same: use `q` / `e` / `center_left` / `center_right` |
| extras | | `vars`, themes and includes, Liquid Glass, the notch component, `hover.*`, a settings window |
