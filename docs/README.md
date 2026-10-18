# skylandbar documentation

skylandbar is a status bar for macOS 14 to 26, the bar of [skyland](https://github.com/waxdred/skyland).
It is described by one TOML file (`~/.config/skylandbar/skylandbar.toml`) and driven at run time by
`skylandbar --set ...` commands, from a shell or from the scripts of its items.

| Page | For |
| --- | --- |
| [install.md](install.md) | Build, first run, start at login, permissions, uninstall |
| [configuration.md](configuration.md) | The `skylandbar.toml` file: sections, items, vars, themes, includes, checking, the settings window |
| [reference.md](reference.md) | Every command, property, event and script variable |
| [components.md](components.md) | Built-in components: workspaces, window title, notch, brackets, graphs, sliders, aliases, popups |
| [liquid-glass.md](liquid-glass.md) | The Liquid Glass theme, glass engines, lenses, skyland's theme colors |
| [skyland.md](skyland.md) | What skylandbar does with skyland (and AeroSpace): events, workspaces, bar height, theme |
| [migrating-from-sketchybar.md](migrating-from-sketchybar.md) | Turning a `sketchybarrc` and its plugins into a skylandbar config; compatibility |
| [recipes.md](recipes.md) | Ready-to-paste items: clock, battery, volume, CPU, memory, Wi-Fi, keyboard layout, media |
| [troubleshooting.md](troubleshooting.md) | Symptoms, causes, fixes |
| [ai-setup.md](ai-setup.md) | **For an AI assistant** setting skylandbar up for a user: the procedure, the rules, the checks |

## Thirty seconds

```sh
git clone https://github.com/waxdred/skylandBar && cd skylandBar
swift build -c release
mkdir -p ~/.config/skylandbar/themes
cp themes/liquid-glass.toml ~/.config/skylandbar/themes/
cp examples/liquid-glass.toml ~/.config/skylandbar/skylandbar.toml
.build/release/skylandbar --check            # "ok, N items"
.build/release/skylandbar --service install  # starts now and at every login
```

Then edit `~/.config/skylandbar/skylandbar.toml`: the bar reloads when it is saved (`hotload = true`),
or open `skylandbar --settings` for sliders and pickers.

## Words used in these pages

| Word | Meaning |
| --- | --- |
| item | One thing on the bar: an icon and/or a label, a background, optional script |
| component | A built-in item kind that does its own work: `workspaces`, `title`, `notch`, `bracket`, `graph`, `slider`, `alias`, `space` |
| property | A `key=value` of the bar or of an item (`label.color=0xffffffff`) |
| script | A shell command run by the bar for an item (`script`, `click_script`), with `NAME`, `SENDER`, `INFO`... |
| event | Something that runs the scripts subscribed to it (`volume_change`, `mouse.clicked`, a custom one) |
| glass | A Liquid Glass background (`background.glass = "regular"`), drawn by one of the glass engines |
| notch | The camera housing of a MacBook display, and the `notch` component that opens from it |
