# Install

## Requirements

| Need | Why |
| --- | --- |
| macOS 14 or later | AppKit, ScreenCaptureKit |
| Swift 6 toolchain (Xcode or the Command Line Tools) | to build; **Xcode 26** to build Apple's own glass (`NSGlassEffectView`) in |
| [skyland](https://github.com/waxdred/skyland) or AeroSpace (optional) | workspaces, window title and their events |
| A Nerd Font (optional) | icons written as Nerd Font glyphs (`brew install --cask font-hack-nerd-font`) |
| SF Pro and SF Symbols (optional) | the Liquid Glass theme's text and icons (`brew install --cask font-sf-pro sf-symbols`) |

Without SF Pro installed as a font, `SF Pro` falls back to the system font (the same face), but SF
Symbols glyphs (private-use characters such as `􀊩`) show as `?`: install `font-sf-pro`.

## Build

```sh
git clone https://github.com/waxdred/skylandBar
cd skylandBar
swift build -c release
swift test                         # optional: the core's tests
```

The binary is `.build/release/skylandbar`. Put it on your `PATH` if you want to type `skylandbar`:

```sh
ln -sf "$PWD/.build/release/skylandbar" /opt/homebrew/bin/skylandbar   # or ~/.local/bin
```

## A first config

```sh
mkdir -p ~/.config/skylandbar/themes
cp themes/liquid-glass.toml ~/.config/skylandbar/themes/
cp examples/liquid-glass.toml ~/.config/skylandbar/skylandbar.toml   # Liquid Glass bar
# or: cp examples/skylandbar.toml ~/.config/skylandbar/skylandbar.toml  (a plain bar)
skylandbar --check
```

`--check` loads the file on a bar of its own (nothing on screen) and prints `ok, N items` or each
problem with its place (`item 'clock': [!] ...`). Exit status 0 when it loads.

## Run

```sh
skylandbar                          # ~/.config/skylandbar/skylandbar.toml, else ~/.config/skylandbar/skylandbarrc
skylandbar --config path/to/file    # another config (.toml, or a script of skylandbar commands)
```

Only one bar runs at a time: a second `skylandbar` says `already running` and leaves. Talk to the
running bar with `skylandbar --set ...`, `--query ...`, `--reload`, `--exit` (see
[reference.md](reference.md)).

## Start at login

```sh
skylandbar --service install     # a launch agent: starts now and at login, again if it crashes
skylandbar --service uninstall
```

The agent is `~/Library/LaunchAgents/com.waxdred.skylandbar.plist`; the bar's output goes to
`~/Library/Logs/skylandbar.log`. `skylandbar --exit` quits it until the next login (it is not
restarted after a clean exit). Restart it: `launchctl kickstart -k gui/$(id -u)/com.waxdred.skylandbar`.

## Permissions

| Permission (System Settings > Privacy & Security) | For | Without it |
| --- | --- | --- |
| Screen Recording | the `metal` glass engine (refraction), aliases (copies of menu bar items) | glass falls back to `backdrop` (a blur, no refraction); aliases are empty |
| Accessibility | clicks forwarded to an alias's real menu bar item, `menubar` items | the click does nothing |
| Location Services | the Wi-Fi network name in `wifi_change` | `INFO` is empty |

macOS gives a permission to the **process that is responsible**. Started from a terminal, the bar
uses the terminal's permissions; started by the launch agent, it needs its own: add the binary
itself (`.build/arm64-apple-macosx/release/skylandbar`, ⌘⇧G in the file picker), then restart the
bar. The binary is signed ad hoc: after a rebuild macOS asks again. Signed with a certificate of
your own, the permissions stay across rebuilds; then give it its icon (signing refuses a file
that has one, so after):

```sh
xattr -c .build/arm64-apple-macosx/release/skylandbar   # the icon of the last build, if any
codesign -f -s "<your identity>" --identifier com.waxdred.skylandbar .build/arm64-apple-macosx/release/skylandbar
resources/icon/make-icns .build/arm64-apple-macosx/release/skylandbar
```

The bar says at start which glass it draws (`skylandbar: glass: metal`, or `backdrop` and why), on
stderr or in the log.

## SketchyBar on the same Mac

skylandbar answers to SketchyBar's names (see [migrating-from-sketchybar.md](migrating-from-sketchybar.md)).
Stop SketchyBar before starting skylandbar, or uninstall it:

```sh
brew services stop sketchybar
brew uninstall sketchybar          # once your config no longer needs ~/.config/sketchybar
```

## Uninstall

```sh
skylandbar --service uninstall
skylandbar --exit
rm -rf ~/.config/skylandbar ~/.cache/skylandbar     # your config, the script shim
rm -rf path/to/skylandBar                           # the repository and its build
```
