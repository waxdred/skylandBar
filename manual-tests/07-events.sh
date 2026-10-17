#!/usr/bin/env bash
# Événements système : chaque item affiche le dernier SENDER et INFO reçus
source "$(dirname "$0")/lib.sh"

n=0
for event in front_app_switched volume_change brightness_change power_source_change wifi_change media_change space_change space_windows_change; do
    n=$((n + 1))
    "$B" --add item t.ev$n center --set t.ev$n label="$event ?" label.font.size=11 script="$SHOW" --subscribe t.ev$n $event
done
step "Événements" \
    "front_app_switched : change d'app → nom de l'app" \
    "volume_change : touches de volume → 0-100" \
    "brightness_change : luminosité → 0-100" \
    "power_source_change : brancher / débrancher → AC / BATTERY" \
    "wifi_change : changer de réseau → nom (vide sans Localisation)" \
    "media_change : lecture Music / Spotify → JSON" \
    "space_change : changer d'espace Mission Control → {\"display-1\":N}" \
    "space_windows_change : ouvrir / fermer une fenêtre → {\"apps\":…}"
"$B" --remove '/^t\.ev/'

"$B" --add item t.mouse center --set t.mouse label="souris ?" script="$SHOW" --subscribe t.mouse mouse.entered mouse.exited mouse.clicked mouse.scrolled
step "Souris" "survol → mouse.entered / mouse.exited" "clic gauche / droit → mouse.clicked (BUTTON)" "molette → mouse.scrolled"

"$B" --add event t_custom --add item t.custom center --set t.custom script='skylandbar --set $NAME label="custom $FOO"' --subscribe t.custom t_custom
"$B" --trigger t_custom FOO=ok
step "Événement custom" "le label affiche « custom ok »"
