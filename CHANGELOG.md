# Changelog

Each `## vX.Y.Z` section is also the text of its GitHub release.

## v0.12.1

- builds with an SDK older than macOS 26 (Homebrew's Command Line Tools with Swift 6.2):
  Apple's glass views are looked up at run time, and still used on macOS 26

## v0.12.0

The first release: a status bar for macOS 14 to 26 in Liquid Glass, the bar of
[skyland](https://github.com/waxdred/skyland), and a drop-in for SketchyBar configs.

**Liquid Glass**
- three engines: Apple's `NSGlassEffectView` on macOS 26, skylandbar's Metal shader before it
  (refraction at the edges, a little color split, blur, saturation, rim light; shapes close to
  each other melt together), Core Animation's blur without Screen Recording
- a selection lens (`background.glass = "lens"`) that flows to its new item like a drop,
  stretching on its way and leaving a drop behind; hover drops (`background.glass = "hover"`);
  what is under a drop is drawn magnified and lit through it
- the Liquid Glass theme (`themes/liquid-glass.toml`), which takes skyland's accent

**skyland and AeroSpace**
- built-in workspaces (with their apps' icons) and window title, no scripts
- skyland's and AeroSpace's events from their socket (`skyland_workspace_change`,
  `aerospace_workspace_change`, focus, monitor, mode, window detected, binding)
- the workspaces' lens follows skyland's three-finger swipe (`skyland_workspace_swipe`)
- the bar tells skyland its height: tiled windows stay below it

**The bar**
- one TOML file (`~/.config/skylandbar/skylandbar.toml`), hot reloaded, with vars, includes,
  themes and light / dark variants; or `skylandbar --add/--set ...` commands, as SketchyBar does
- items, popups, brackets, graphs, sliders, aliases, spaces, animations, the notch (boringNotch
  style, of glass)
- a settings window (`skylandbar --settings`) that writes back to the file, comments kept
- SketchyBar compatible: scripts reach it as `sketchybar`, it holds SketchyBar's Mach names,
  SbarLua configs run as they are
- one bar per user (a lock), a launch agent (`skylandbar --service install`)

**Fixes**
- memory: threads that never go back to a run loop drain an autorelease pool per message (the
  bar grew with its scripts' `--set` calls)
- quitting while skyland restarts no longer hangs
