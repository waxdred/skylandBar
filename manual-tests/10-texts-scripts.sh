#!/usr/bin/env bash
# Texte qui défile, update_freq, updates=when_shown, reload, scripts arrêtés à la sortie
source "$(dirname "$0")/lib.sh"

"$B" --add item t.scroll center --set t.scroll label="Un titre beaucoup trop long pour la barre" label.max_chars=15 scroll_texts=on
step "scroll_texts" "le texte défile dans une fenêtre de 15 caractères"

"$B" --add item t.clock center --set t.clock update_freq=1 script='skylandbar --set $NAME label="$(date +%S)"'
step "update_freq=1" "les secondes avancent"
"$B" --set t.clock drawing=off; sleep 2; "$B" --set t.clock drawing=on
step "updates=when_shown" "masqué 2 s puis réaffiché : les secondes reprennent"

"$B" --reload
sleep 2
step "--reload" "la barre recharge ta config (les items t.* ont disparu)"

echo "Pour finir, à la main :"
echo "  $B --exit   → la barre se ferme, aucun message « the bar is not running » des scripts"
