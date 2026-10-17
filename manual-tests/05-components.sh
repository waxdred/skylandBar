#!/usr/bin/env bash
# Brackets, graphes, sliders
source "$(dirname "$0")/lib.sh"

"$B" --add item t.x right --set t.x label="x" --add item t.y right --set t.y label="y" \
     --add bracket t.group '/^t\.[xy]$/' --set t.group background.color=0x40f5c2e7 background.corner_radius=8 background.height=24
step "Bracket" "un fond rose commun derrière x et y"

"$B" --add graph t.cpu right 60 --set t.cpu graph.color=0xffa6e3a1 graph.line_width=1 label="cpu" background.height=20
for _ in $(seq 1 50); do "$B" --push t.cpu "0.$((RANDOM % 100))"; sleep 0.1; done
step "Graphe" "une courbe verte remplie qui défile de droite à gauche" "le remplissage est la couleur plus claire"

"$B" --add slider t.vol right 100 --set t.vol slider.background.height=4 slider.background.color=0x40ffffff slider.background.corner_radius=2 \
        slider.highlight_color=0xffffffff slider.knob=● slider.percentage=50 icon=󰕾 \
        script='sketchybar --set $NAME label="$PERCENTAGE%"' --subscribe t.vol mouse.clicked
step "Slider" "à 50 %, glisse-le à la souris" "le label affiche le pourcentage pendant et après le glissé"

"$B" --animate sin 30 --set t.vol slider.percentage=90
step "Slider animé" "le curseur glisse à 90 %"
