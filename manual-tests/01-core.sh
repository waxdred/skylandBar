#!/usr/bin/env bash
# Commandes de base : add, set, regex, move, query, default
source "$(dirname "$0")/lib.sh"

"$B" --add item t.a left --set t.a label="t.a" background.color=0xff45475a background.corner_radius=6 \
     --add item t.b left --set t.b label="t.b" icon=󰀵 icon.color=0xfff38ba8
step "Deux items à gauche" "t.a avec un fond arrondi gris" "t.b avec une icône rose"

"$B" --set '/^t\.[ab]$/' label.color=0xffa6e3a1
step "--set par regex" "les deux labels deviennent verts"

"$B" --move t.b before t.a
step "--move" "t.b est maintenant avant t.a"

"$B" --query t.a | head -20
step "--query t.a" "un JSON s'affiche ci-dessus, avec label.value = t.a et bounding_rects"

"$B" --default label.color=0xfff9e2af --add item t.c left --set t.c label="t.c défaut"
"$B" --default label.color=0xffffffff
step "--default" "t.c a un label jaune (défaut appliqué à la création)"

"$B" --set t.a label.max_chars=3 label="abcdefgh"
step "max_chars" "t.a affiche « abc »"
