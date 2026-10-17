#!/usr/bin/env bash
# Popups : verticale, horizontale, alignement, popup dans une popup, mouse.exited.global
source "$(dirname "$0")/lib.sh"

"$B" --add item t.menu left --set t.menu icon=󰍜 label="menu" click_script='sketchybar --set $NAME popup.drawing=toggle' \
        popup.background.color=0xf01e1e2e popup.background.corner_radius=8 popup.background.border_width=1 popup.background.border_color=0xff585b70 popup.y_offset=4 \
     --add item t.menu.a popup.t.menu --set t.menu.a label="Première ligne" \
     --add item t.menu.b popup.t.menu --set t.menu.b label="Deuxième, plus longue" \
     --add item t.menu.c popup.t.menu --set t.menu.c label="Clic : ferme" click_script='sketchybar --set t.menu popup.drawing=off'
step "Popup verticale" "clic sur « menu » : la popup s'ouvre sous l'item" "3 lignes, largeur = la plus longue" "« Clic : ferme » ferme la popup" "re-clic sur menu : toggle"

"$B" --set t.menu popup.drawing=on popup.horizontal=on
step "Popup horizontale" "les 3 items côte à côte"
"$B" --set t.menu popup.horizontal=off popup.align=center
step "popup.align=center" "la popup est centrée sur l'item"

"$B" --set t.menu.b popup.background.color=0xf0313244 click_script='sketchybar --set $NAME popup.drawing=toggle' \
     --add item t.menu.b.x popup.t.menu.b --set t.menu.b.x label="sous-menu"
step "Popup dans une popup" "clic sur « Deuxième… » : une popup s'ouvre sous elle"

"$B" --set t.menu popup.drawing=off --subscribe t.menu mouse.exited.global --set t.menu script='[ "$SENDER" = mouse.exited.global ] && sketchybar --set $NAME popup.drawing=off'
step "Fermeture en sortant" "ouvre la popup, passe la souris de la barre à la popup : elle reste ouverte" "sors de la barre et de la popup : elle se ferme"
