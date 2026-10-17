#!/usr/bin/env bash
# Liquid Glass sur la barre et les fonds, background.clip
source "$(dirname "$0")/lib.sh"

before=$("$B" --query bar | grep -o '"color" : "[^"]*"' | head -1 | cut -d'"' -f4)
"$B" --bar glass=on color=0x30ffffff
step "Barre en verre" "macOS 26 + Xcode 26 : effet Liquid Glass" "sinon : flou (NSVisualEffectView)" "la teinte claire se voit"

"$B" --bar glass=clear
step "glass=clear" "verre plus transparent (macOS 26)"
"$B" --bar glass=off color="${before:-0x44000000}"

"$B" --add item t.pill right --set t.pill label="pill" background.glass=on background.color=0x40cba6f7 background.corner_radius=10 background.height=24 label.padding_left=8 label.padding_right=8
step "Pastille en verre sur un item" "un fond en verre arrondi derrière « pill », teinté violet"

"$B" --add item t.hole right --set t.hole label="trou" background.color=0x00000000 background.clip=1 background.corner_radius=6 background.height=20
step "background.clip=1" "la barre est découpée derrière « trou » (on voit le bureau)"
"$B" --set t.hole background.clip=0.5
step "background.clip=0.5" "découpe à moitié"
