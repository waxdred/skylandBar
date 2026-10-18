# Recipes

Items to paste into `~/.config/skylandbar/skylandbar.toml`. Icons are SF Symbols (need SF Pro
installed) or Nerd Font glyphs (need a Nerd Font, `icon = { font = "Hack Nerd Font:Bold:14" }`).
Scripts run with bash; `$NAME` is the item. In the Liquid Glass theme, add the glass item look
from [liquid-glass.md](liquid-glass.md) and put them in a bracket.

## Clock

```toml
[[item]]
name = "clock"
position = "right"
update_freq = 10
icon = "􀐫"
script = 'skylandbar --set "$NAME" label="$(date "+%a %d %b  %H:%M")"'
subscribe = "system_woke"
```

## Battery

```toml
[[item]]
name = "battery"
position = "right"
update_freq = 120
script = '''
percent=$(pmset -g batt | grep -Eo "[0-9]+%" | tr -d %)
case 1 in
  $(( percent > 75 ))) icon=􀛨 ;;
  $(( percent > 50 ))) icon=􀺸 ;;
  $(( percent > 25 ))) icon=􀺶 ;;
  *) icon=􀛩 ;;
esac
pmset -g batt | grep -q "AC Power" && icon=􀢋
skylandbar --set "$NAME" icon="$icon" label="$percent%"
'''
subscribe = ["power_source_change", "system_woke"]
```

## Volume

```toml
[[item]]
name = "volume"
position = "right"
icon = "􀊩"
script = '''
[ "$SENDER" = volume_change ] || INFO=$(osascript -e "output volume of (get volume settings)")
icon=􀊩; [ "$INFO" -lt 66 ] && icon=􀊥; [ "$INFO" -lt 33 ] && icon=􀊡; [ "$INFO" -eq 0 ] && icon=􀊣
skylandbar --set "$NAME" icon="$icon" label="$INFO%"
'''
subscribe = "volume_change"
click_script = "open x-apple.systempreferences:com.apple.Sound-Settings.extension"
```

## CPU

```toml
[[item]]
name = "cpu"
position = "right"
update_freq = 2
icon = "􀧓"
script = '''
cpu=$(ps -A -o %cpu | awk -v n="$(sysctl -n hw.ncpu)" '{s+=$1} END {printf "%.0f", s/n}')
skylandbar --set "$NAME" label="$cpu%"
'''
```

## Memory

```toml
[[item]]
name = "memory"
position = "right"
update_freq = 5
icon = "􀫦"
script = '''
used=$(memory_pressure | awk '/System-wide memory free percentage/ {print 100 - $5}')
skylandbar --set "$NAME" label="${used}%"
'''
```

## Wi-Fi

```toml
[[item]]
name = "wifi"
position = "right"
icon = "􀙇"
script = 'skylandbar --set "$NAME" label="${INFO:-off}"'
subscribe = ["wifi_change", "system_woke"]
```

The network name needs Location Services for skylandbar (else `INFO` is empty).

## Keyboard layout

```toml
[[item]]
name = "keyboard"
position = "right"
update_freq = 2
icon = "􀇳"
script = '''
id=$(defaults read ~/Library/Preferences/com.apple.HIToolbox.plist AppleSelectedInputSources | grep -m1 '"KeyboardLayout Name"' | sed -E 's/.*= "?([^";]*)"?;/\1/')
skylandbar --set "$NAME" label="$id"
'''
```

## Front app

```toml
[[item]]
name = "front_app"
position = "left"
icon = { drawing = false }
script = 'skylandbar --set "$NAME" label="$INFO"'
subscribe = "front_app_switched"
```

(The `title` component shows the app and the window title without a script.)

## Now playing (Music, Spotify)

```toml
[[item]]
name = "media"
position = "right"
icon = "􀑪"
label = { max_chars = 32 }
scroll_texts = true
script = '''
[ "$SENDER" = media_change ] || exit 0
state=$(echo "$INFO" | jq -r .state)
[ "$state" = playing ] || { skylandbar --set "$NAME" drawing=off; exit 0; }
skylandbar --set "$NAME" drawing=on label="$(echo "$INFO" | jq -r '.artist + " — " + .title')"
'''
subscribe = "media_change"
```

## A separator between glass groups

Two brackets next to each other overlap (each spans past its items): put this between them, in
bar order.

```toml
[[item]]
name = "groups.gap"
position = "right"
width = 20
icon = { drawing = false }
label = { drawing = false }
background = { drawing = false }
```

## Open the settings window from the bar

```toml
[[item]]
name = "settings"
position = "right"
icon = "􀍟"
label = { drawing = false }
click_script = "skylandbar --settings"
```
