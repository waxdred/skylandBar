#!/usr/bin/env bash
# La sélection (lens) qui glisse : ressort, dépassement, étirement, apparition
source "$(dirname "$0")/lib.sh"

ROOT=$(cd "$(dirname "$0")/.." && pwd)
"$B" --reload "$ROOT/examples/liquid-glass.toml"; sleep 2
step "Glissement" "change de workspace (clavier) : la lentille bleue glisse vers le nouveau, ~0,4 s" \
    "elle dépasse un peu sa cible puis revient" "elle s'allonge pendant le trajet, plus quand c'est loin"
step "Enchaînement" "change vite 1 → 4 → 2 : elle repart de là où elle est, sans saut"

"$B" --bar glass_lens_bounce=0.6 glass_lens_stretch=2
step "Réglages forts" "bounce 0.6 : rebond marqué ; stretch 2 : goutte très étirée"
"$B" --bar glass_lens_bounce=0 glass_lens_stretch=0
step "Sans rebond ni étirement" "glisse et s'arrête net, sans se déformer"
"$B" --bar glass_lens_response=0
step "response 0" "la lentille saute d'un coup"
"$B" --bar glass_lens_response=0.35 glass_lens_bounce=0.3 glass_lens_stretch=1

step "Deux écrans" "focus sur l'autre écran : la lentille y apparaît en grandissant (70 % → 100 %)"
step "Réduire les animations" "Réglages > Accessibilité > Affichage > Réduire les animations : elle saute sans glisser"
