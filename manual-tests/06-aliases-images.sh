#!/usr/bin/env bash
# Alias de la barre de menus, images de fond
source "$(dirname "$0")/lib.sh"

echo "Éléments de la barre de menus :"
"$B" --query default_menu_items | head -20
step "default_menu_items" "une liste « App,Nom » s'affiche (demande l'Enregistrement de l'écran)"

first=$("$B" --query default_menu_items | grep -o '"[^"]*,[^"]*"' | grep -v '^"Window Server' | head -1 | tr -d '"')
if [ -n "$first" ]; then
    "$B" --add alias "$first" right --set "$first" alias.update_freq=1
    step "Alias « $first »" "l'icône apparaît dans la barre" "un clic dessus ouvre le vrai menu (Accessibilité)"
    "$B" --set "$first" alias.color=0xfff38ba8
    step "alias.color" "l'icône est teintée en rose"
    "$B" --remove "$first"
fi

"$B" --add item t.finder right --set t.finder background.image=app.com.apple.finder background.image.scale=0.6 label="finder" label.padding_left=24
step "Image d'app (bundle id)" "l'icône du Finder derrière l'item"
"$B" --set t.finder background.image=app.Safari background.image.corner_radius=6
step "Image d'app (nom)" "l'icône de Safari, coins arrondis"
"$B" --add item t.art right --set t.art background.image=media.artwork background.image.scale=0.1 label="pochette"
step "media.artwork" "la pochette du morceau en cours (avant macOS 15.4 seulement)"
