#!/usr/bin/env bash
# Plusieurs écrans : display=active, hidden=current, display=2
source "$(dirname "$0")/lib.sh"

"$B" --add item t.active center --set t.active label="écran actif" display=active background.color=0xff45475a background.corner_radius=6
step "display=active" "l'item est sur l'écran de la fenêtre qui a le focus (pas celui de la souris)" "focus une fenêtre sur l'autre écran : l'item y passe"

"$B" --set t.active display=2 label="écran 2"
step "display=2" "l'item n'est que sur le 2e écran"

"$B" --bar hidden=current
step "hidden=current" "la barre disparaît de l'écran actif seulement"
"$B" --bar hidden=off
