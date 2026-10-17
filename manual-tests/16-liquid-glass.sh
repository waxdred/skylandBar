#!/usr/bin/env bash
# Le thème Liquid Glass (macOS 26 + Xcode 26 pour le vrai verre)
source "$(dirname "$0")/lib.sh"

ROOT=$(cd "$(dirname "$0")/.." && pwd)
"$B" --check "$ROOT/examples/liquid-glass.toml"
step "--check" "« ok, N items »"

"$B" --reload "$ROOT/examples/liquid-glass.toml"; sleep 2
step "Le thème" "pas de fond derrière la barre" "3 capsules de verre : workspaces, titre, statut" \
    "le workspace focus est le seul élément teinté (bleu)" "icônes SF Symbols, police SF Pro"
step "Survol" "chaque item s'éclaircit légèrement sous la souris, en douceur (0,15 s)"
step "Popup" "clic sur l'heure : un panneau de verre arrondi (16) sous elle ; sortir de la barre le ferme"
step "Fusion (glass_spacing)" "change de workspace : les capsules restent séparées ; rapproche deux groupes (ex. --bar padding) : elles fusionnent"
step "Clair / sombre" "Réglages > Apparence > Clair : la barre se recharge avec les couleurs claires (texte noir)" "retour en Sombre"
step "Accessibilité" "Réglages > Accessibilité > Affichage > Réduire la transparence : le verre devient plus opaque" \
    "Augmenter le contraste : bordure visible" "Réduire les animations : changer de workspace / survoler sans animation"
echo "Pour revenir à ta config : $B --reload"
