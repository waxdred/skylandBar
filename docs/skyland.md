# skylandbar and skyland

skylandbar is skyland's bar: it talks to skyland directly, with nothing to add to skyland's
config. With AeroSpace instead of skyland, the same works through AeroSpace's socket.

## Events

skylandbar subscribes to skyland's socket and sends these events to the items subscribed to them:

| Event | Variables (`INFO` is the event's JSON) |
| --- | --- |
| `skyland_workspace_change`, `aerospace_workspace_change` | `FOCUSED_WORKSPACE`, `PREV_WORKSPACE` |
| `skyland_focus_change` | `FOCUSED_WORKSPACE`, `WINDOW_ID` |
| `skyland_monitor_change` | `FOCUSED_WORKSPACE`, `MONITOR` |
| `skyland_mode_change`, `aerospace_mode_change` | `MODE` |
| `skyland_window_detected` | `WINDOW_ID`, `WORKSPACE`, `APP_NAME`, `APP_BUNDLE_ID` |
| `skyland_binding` | `MODE`, `BINDING` |
| `skyland_workspace_swipe` | `FOCUSED_WORKSPACE`, `TARGET_WORKSPACE` (empty once the fingers lift), `PROGRESS` (0 to 1): a trackpad swipe in progress; the workspaces' lens follows it by itself |

If skyland quits and comes back, skylandbar reconnects by itself. Configs written for AeroSpace
that use `aerospace_workspace_change` work as they are; remove `exec-on-workspace-change` from the
window manager's config if it also triggers it.

```toml
[[item]]
name = "mode"
position = "left"
label = { string = "" }
script = 'skylandbar --set "$NAME" label="$MODE" drawing=$([ "$MODE" = main ] && echo off || echo on)'
subscribe = "skyland_mode_change"
```

## Workspaces and window title

The `workspaces` and `title` components ask skyland themselves (`list-workspaces`,
`list-windows`) on each event: see [components.md](components.md). skyland names its hidden
scratchpad workspaces `scratch`, `scratch-music`...; `workspaces = { max = 12 }` keeps them off
the bar.

## Windows below the bar

skylandbar tells skyland how much room it takes at the top (`height` + `y_offset`, or the notch
height on a notched display; 0 at the bottom) when it starts, when its config changes,
and when skyland restarts, with skyland's `bar-height` command. skyland tiles windows below it;
nothing to keep in sync in skyland's config. A hidden bar keeps its room (skyland hides it while the
macOS menu bar slides in, and the windows keep their size); quitting the bar gives the room back.

## Theme

skyland's `skyland-theme` writes its colors to `~/.cache/skyland/theme.env`.
`vars_file = "~/.cache/skyland/theme.env"` in the config makes them vars and reloads the bar when
they change: see [liquid-glass.md](liquid-glass.md#skylands-theme-colors).

## skyland's sketchybar calls

Parts of skyland still call the `sketchybar` command (`skyland bar`, `skyland-env` at login,
`skyland-theme apply`). skylandbar answers to that name (see
[migrating-from-sketchybar.md](migrating-from-sketchybar.md#compatibility)), so these calls reach
it: `skyland-theme apply` sets every item's colors and `skyland bar` adds `workspace.N` items.
skylandbar's own components do this work already. With SketchyBar uninstalled
(`brew uninstall sketchybar`), the `sketchybar` command is gone and these calls do nothing.
