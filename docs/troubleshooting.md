# Troubleshooting

First look at what the bar says: run it in a terminal (`skylandbar --exit; skylandbar`), or read
`~/Library/Logs/skylandbar.log` when it runs as a service. `skylandbar --check` explains a config
that does not load.

| Symptom | Cause | Fix |
| --- | --- | --- |
| No bar at all | not running, or the config did not load | `skylandbar --query bar`; `skylandbar --check`; the log |
| `already running` | a bar runs (maybe the launch agent) | `skylandbar --exit` first, or `--reload` |
| `the bar is not running` from `skylandbar --set` | the bar quit, or another one took its socket | start it; `pgrep -lf skylandbar` should show one |
| `git.felix.sketchybar is taken (sketchybar runs?)` at start | SketchyBar runs | `brew services stop sketchybar` (only one bar holds that name) |
| An item does not change | its script fails or does not run | run the script by hand: `NAME=clock SENDER=forced bash -c '<script>'`; is it subscribed? `update_freq`? `updates = "when_shown"` stops scripts of hidden items |
| `'image' already has a value` (or any key) | TOML: a key both as a value and as a table | `image = { string = "...", scale = 0.8 }` |
| `unknown property` / `unknown option` | a misspelled key | the line says which; see [reference.md](reference.md) |
| Glass looks like a flat grey blur | engine `backdrop` (no Screen Recording) or macOS before 26 without `metal` | the start line says which engine and why; allow Screen Recording for the binary that runs, restart |
| Glass was fine from a terminal, flat as a service | permissions belong to the responsible process: the terminal, or the binary under launchd | add `.build/arm64-apple-macosx/release/skylandbar` to Screen Recording, `launchctl kickstart -k gui/$(id -u)/com.waxdred.skylandbar` |
| Glass lost after `swift build` | an unsigned binary: macOS may ask again after a rebuild | allow it again |
| Two glass capsules overlap | brackets span past their items | a spacer item between the groups ([recipes.md](recipes.md#a-separator-between-glass-groups)) |
| Capsules melt into one shape | they are closer than `glass_spacing` | more room between them, or `glass_spacing = 0` |
| A selection touches the glass's edge | a bracket ends at its items | `padding_left = 4, padding_right = 4` on the bracket's background |
| Text or icons in the middle are hidden | `center` is under the camera's notch | `position = "q"`, `"e"`, `"center_left"` or `"center_right"` |
| SF Symbols show as `?` | SF Pro is not installed as a font | `brew install --cask font-sf-pro` and restart the bar |
| Nerd Font icons show as boxes | no Nerd Font, or the item's font is not one | `brew install --cask font-hack-nerd-font`; `icon = { font = "Hack Nerd Font:Bold:14" }` |
| Text in Helvetica | the font's family is not installed | install it, or use one Font Book lists |
| Workspaces `scratch`, `scratch-music` on the bar | skyland's hidden scratchpads are workspaces too | `workspaces = { max = 12 }` |
| No workspaces | skyland / AeroSpace not running, or its CLI not found | start skyland; the bar reconnects by itself |
| The settings window does not show | it opened behind, or on another Space | run `skylandbar --settings` again; it comes to the front |
| Save in the settings window says `Not saved: ...` | the edited config does not load | the message says why; nothing was written |
| `wifi_change` gives no name | Location Services | allow it for skylandbar |
| `media_change` without artwork | macOS 15.4+ closed MediaRemote; Music and Spotify still send their notifications | |
| The bar comes back after `--exit` | the launch agent with a crash, not an `--exit` | `--exit` is final until login; `skylandbar --service uninstall` to stop it for good |
