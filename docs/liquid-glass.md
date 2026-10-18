# Liquid Glass

skylandbar draws Apple's Liquid Glass on any background (`background.glass`), on the whole bar
(`--bar glass=on`), on popups and on the notch, and ships a theme that follows Apple's rules:
`themes/liquid-glass.toml`, used by `examples/liquid-glass.toml`.

## Using the theme

```sh
mkdir -p ~/.config/skylandbar/themes
cp themes/liquid-glass.toml ~/.config/skylandbar/themes/
cp examples/liquid-glass.toml ~/.config/skylandbar/skylandbar.toml
```

In your own config: `include = "themes/liquid-glass.toml"` before any section. It sets:

- no background under the bar (`color = 0x00000000`), height 40, margin 8, offset 4, corner 20;
- `[defaults]`: SF Pro, primary text, item backgrounds off, concentric corners;
- vars: `primary`, `secondary`, `tertiary`, `accent`, `accent_soft` (30 %), `glass_tint` (8 %),
  `hover` (14 %), `font`, `radius_large` / `_row` / `_small`, `spring`; dark and light variants;
- `accent` = skyland's `ACCENT` (from `~/.cache/skyland/theme.env`), else systemBlue;
- glass settings: `glass_engine = "auto"`, refraction 6, blur, saturation, spacing 8.

The pattern of a glassy bar:

| Element | How |
| --- | --- |
| a group of items | a `bracket` with `background = { glass = "regular", color = "${glass_tint}", height = 36, corner_radius = 0, drawing = true, padding_left = 4, padding_right = 4 }` |
| an item in a group | `background = { drawing = true, color = "0x00000000", height = 28, corner_radius = "concentric" }` and `hover = { background.color = "${hover}" }` |
| the selected one | `background.glass = "lens"` with `background.color = "${accent_soft}"` (the workspaces' `focused`) |
| a lone item | its own `background = { glass = "regular", ... }` |
| text | `${primary}` / `${secondary}`; color only for meaning (red: low battery) |

`corner_radius = 0` on glass is a capsule; `"concentric"` follows the container's radius less the
gap (a 28 pt item in a 36 pt capsule: a capsule too).

## Glass engines

| Engine | What | Needs |
| --- | --- | --- |
| `system` | Apple's `NSGlassEffectView` in an `NSGlassEffectContainerView` | macOS 26, and a build with Xcode 26 |
| `metal` | skylandbar's shader over what is behind (ScreenCaptureKit, without its own windows): lens refraction at the edges, a little color split, blur, saturation, rim light, sheen, inner shadow; shapes closer than `glass_spacing` melt | Screen Recording |
| `backdrop` | Core Animation's blur with a tint, sheen, rim light and shadow; no refraction | nothing |

`glass_engine = "auto"` (default) takes the first this Mac can do. The bar prints the one it took
at start (`skylandbar: glass: metal`; in `~/Library/Logs/skylandbar.log` as a service). To get
`metal`: allow skylandbar in System Settings > Privacy & Security > Screen Recording, then
restart it (see [install.md](install.md#permissions) about the launch agent).

Tuning (`[bar]`, or the settings window's Glass section):

| Property | Default (theme) | Effect |
| --- | --- | --- |
| `glass_refraction` | 6 | how far the edges bend what is behind, pt; at most half a shape's height / 2.2 (8 on a 36 pt capsule), so it magnifies and never mirrors |
| `glass_blur` | 2 | pt |
| `glass_saturation` | 1.6 | |
| `glass_spacing` | 8 | shapes closer than this melt into one (0: never) |
| `motion` | `auto` | `full` animates even with Reduce Motion, `reduced` never |

## Lenses: selections

`background.glass = "lens"` on a background inside another glass shape is a drop of thicker
glass: what is behind a little magnified, lighter, its own rim, tinted by its color. It does not
melt into the glass around it. When the selection moves (the focused workspace), the lens flows
to its new place like a drop, stretched on the way, and settles with a little jelly:
`glass_lens_response` (0.35 s), `glass_lens_bounce` (0.3), `glass_lens_stretch` (1; 0 slides in
one piece). Outside other glass, or with another engine, a lens is plain glass.

## skyland's theme colors

skyland's `skyland-theme` writes `~/.cache/skyland/theme.env`:

```
BAR_BG=0xff090f0f
TEXT=0xffdde4e3
TEXT_DIM=0xffbbc9c9
ITEM_BG=0xff161d1d
ITEM_BG_ACTIVE=0xff242b2b
BORDER=0xff3c4949
BORDER_ACTIVE=0xff47e3e4
ACCENT=0xff47e3e4
```

`vars_file = "~/.cache/skyland/theme.env"` makes them vars (`${ACCENT}`, `${TEXT}`...) over the
`[vars]`, and the config reloads when skyland changes theme. The Liquid Glass theme does this for
`ACCENT`. An opaque, skyland-colored bar can use all of them:

```toml
vars_file = "~/.cache/skyland/theme.env"
[vars]
BAR_BG = "0xff24273a"     # defaults when there is no theme.env
ITEM_BG = "0xff363a4f"
[bar]
color = "${BAR_BG}"
[defaults]
background = { color = "${ITEM_BG}", corner_radius = 6, height = 24 }
```

## The glass notch

`notch = { glass = "regular", color = "${glass_tint}", ... }`: the notch in glass, open and
closed; with `closed_width` / `closed_height` larger than the camera's notch, a rim of glass
around the camera. What is behind its open size is captured while it is closed, so it has glass
from its first frame. See [components.md](components.md#notch-a-panel-that-opens-from-the-cameras-notch).

## Apple's rules, and where they are

| Rule | In skylandbar |
| --- | --- |
| glass is the control layer, used sparingly; never glass on glass | no bar background; one capsule per group |
| capsules, concentric corners | `corner_radius = 0` on glass, `"concentric"` |
| group glass in a container, nearby shapes merge | `glass_spacing` |
| tint only for prominence | one tinted element: the focused workspace |
| hover: primary at low opacity, eased | `hover.*`, animated |
| SF Pro 11 pt or more, SF Symbols, 8 pt grid | the theme's fonts and paddings |
| Reduce Transparency, Increase Contrast, Reduce Motion | the system's glass follows the first two; `motion = "auto"` follows the third |
