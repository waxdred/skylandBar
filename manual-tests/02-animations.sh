#!/usr/bin/env bash
# --animate : les 6 courbes, sur un item et sur la barre
source "$(dirname "$0")/lib.sh"

"$B" --add item t.anim center --set t.anim label="animation" background.color=0xff313244 background.corner_radius=8 background.height=22
for curve in linear quadratic tanh sin exp circ; do
    "$B" --animate $curve 40 --set t.anim y_offset=6 label.color=0xfff38ba8 background.color=0xff89b4fa
    sleep 0.9
    "$B" --animate $curve 40 --set t.anim y_offset=0 label.color=0xffffffff background.color=0xff313244
    sleep 0.9
done
step "Item animé (6 courbes, aller-retour)" "le texte monte et redescend en douceur" "les couleurs passent progressivement (pas d'un coup)"

"$B" --animate tanh 30 --bar y_offset=8 margin=12 corner_radius=10
sleep 1
step "Barre animée" "la barre descend de 8 points, se décolle des bords, coins arrondis"
"$B" --animate tanh 30 --bar y_offset=0 margin=0 corner_radius=0
sleep 1
step "Retour" "la barre revient à sa place en douceur"

"$B" --animate linear 120 --set t.anim y_offset=8 && "$B" --animate linear 30 --set t.anim y_offset=0
sleep 1
step "Animation interrompue" "une animation lancée pendant une autre repart de la position actuelle (pas de saut)"
