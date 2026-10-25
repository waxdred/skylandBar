# Changelog

Each `## vX.Y.Z` section is also the text of its GitHub release.

## v0.14.0

**Glyph theme**
- `themes/glyph.toml`: black, white dots, one red (Nothing OS like, skyland's `ui-style = 'glyph'`;
  palette after glyph-rice). Same variable names as liquid-glass.toml: a Liquid Glass config takes
  it as it is. Colors from skyland's theme.env (`HIGHLIGHT`: the one red), else the dark palette.
- `glass_engine = "flat"`: no glass, each glass shape an opaque panel in its tint with a thin line
  and a faint dot grid; the selection lens a pill outlined in the tint's contrast color. Nothing
  captured, no permission; never taken by `auto`.
- Fonts next to the config (`fonts/`, `themes/fonts/`: .ttf / .otf) are registered for the bar
  only at each config load. `themes/fonts` ships Space Mono and Doto (SIL OFL).
- flat: touching panels drawn as one (the open menu bar's L: one outline, no inner lines),
  see-through tints made opaque, one dot grid for the bar, brighter dots (16%).
- The open menu bar no longer draws its trigger's hover tint as a square over the drop.

## v0.13.1

- The open menu bar's L: the row stands as far under the workspaces as the skyland icon
  stands off them (its `padding_right` sets both gaps), its inner corner is concentric to
  the workspaces' capsule and its outer corner to that one; the glass follows the round.

## v0.13.0

**Menu bar in the bar**
- The frontmost app's menus open from the skyland icon (`menubar = "<bracket>"`), a row of
  glass out of its bubble; Apple's status items show as templates.
- `menubar_opacity` works: on Apple's glass, group tints (`background.color`, the theme's
  `glass_tint`, `menubar_opacity`) did nothing, every tint came out the same light gray. Each
  group's tint now fills its shape under the rim.

**Lens**
- On Apple's glass a moving lens is a drop of water: a round head, a body thinning behind
  it, back to round as it lands, with cyan, magenta and yellow along its edge. No drop with
  a dark ring is left behind, and the item it leaves no longer keeps a fading grey disc.
- On a swipe it is pulled out of its item like a drop, follows the fingers, and springs back
  when they let go halfway.
- No frame of Apple's frosted look on fast switches; a double rim (lit top left, shade
  inside) over each glass shape.

**Full screen**
- The bar goes behind full screen apps and videos (the green button, a video's full
  screen), as the menu bar does, and comes back when they leave it.

**Performance**
- Animation frames at 60 Hz at most, only the items that changed are drawn again, glass
  values set once per filter, and a burst of focus events looks up the windows once: the
  main thread went from 44% to 34% while switching workspaces quickly.

**Fixes**
- A hidden bar keeps its room below skyland's windows.
- `glass_engine = auto` never takes the metal engine (its capture blacked protected videos);
  the metal glass takes snapshots instead of running a capture stream.
- A socket client that never ends its message no longer hangs the bar.
- MIT license.

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
