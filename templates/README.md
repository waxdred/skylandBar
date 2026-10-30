# Templates

Ready-made items to include in `skylandbar.toml`, each one file:

| Template | Item | A click opens |
| --- | --- | --- |
| `wifi.toml` | `wifi`: on / off symbol | Apple's Wi-Fi menu: the switch, the networks |
| `battery.toml` | `battery`: level, charging, percent | Apple's battery menu: energy use, Low Power Mode |
| `control-center.toml` | `controlcenter` | Apple's Control Center |
| `github.toml` | `github`: the notch's GitHub tab, open PRs / issues (gh) | the PR or issue on GitHub |

```toml
include = ["themes/liquid-glass.toml", "templates/control-center.toml", "templates/battery.toml", "templates/wifi.toml"]
```

Paths are relative to the config's folder: copy (or link) this folder next to it
(`ln -s ~/code/hyperland/skylandBar/templates ~/.config/skylandbar/templates`). Included items
come before the file's own: on the right, the first one included is the rightmost. Group them
in glass with a bracket in your file (`members = ["controlcenter", "battery", "wifi"]`).

The click is the item's `menu_extra` (see docs/reference.md): it presses the real menu bar
item through Accessibility, so its menu is Apple's own, with everything it does. Any other
menu bar item works the same: `menu_extra = "bluetooth"`, `"sound"`, `"focus"`, or a word of
a third-party item's name.

A new template: one `[[item]]` (more if it needs them) with its look, script and `menu_extra`;
vars with a default (`${hover:-0x24ffffff}`) so it works without the theme.
