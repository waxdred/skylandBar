#!/usr/bin/env bash
# skylandbar.toml : export de la barre actuelle, vérification, chargement, hotload
source "$(dirname "$0")/lib.sh"

DIR=$(mktemp -d)
"$B" --export > "$DIR/exported.toml"
echo "Export : $DIR/exported.toml ($(wc -l < "$DIR/exported.toml") lignes)"
head -30 "$DIR/exported.toml"
step "--export" "le TOML ci-dessus décrit ta barre actuelle ([bar], [defaults], [[item]]...)"

"$B" --check "$DIR/exported.toml"
step "--check de l'export" "« ok, N items » sans erreur"

EXAMPLE="$(dirname "$0")/../examples/skylandbar.toml"
"$B" --check "$EXAMPLE"
printf 'height = \n' > "$DIR/broken.toml"; "$B" --check "$DIR/broken.toml"
step "--check" "l'exemple : ok" "le fichier cassé : « line 1: expected a value », code de sortie 1"

"$B" --reload "$DIR/exported.toml"; sleep 2
step "Rechargement de l'export" "la barre est identique à ta config sketchybar (mêmes items, couleurs, scripts)"

"$B" --reload "$(cd "$(dirname "$EXAMPLE")" && pwd)/skylandbar.toml"; sleep 2
step "L'exemple" "barre Catppuccin flottante : workspaces à gauche, titre au centre, heure / batterie / volume à droite" \
    "survol de l'encoche : morceau en cours et volume"

cp "$EXAMPLE" "$DIR/live.toml"; "$B" --reload "$DIR/live.toml"; sleep 2
sed -i '' 's/^height = 34/height = 44/' "$DIR/live.toml"; sleep 2
step "hotload" "en modifiant le fichier (height 34 → 44), la barre s'est rechargée toute seule"

echo "Pour revenir à ta config : $B --reload"
