#!/usr/bin/env bash
# L'encoche, façon boringNotch : survol, animation, contenu, ouverture par script
source "$(dirname "$0")/lib.sh"

"$B" --add notch t.island --set t.island notch.width=320 notch.corner_radius=22 notch.animation=tanh notch.animation_frames=18 \
     --add item t.island.a popup.t.island --set t.island.a icon=󰝚 label="Première ligne" \
     --add slider t.island.vol popup.t.island 240 --set t.island.vol icon=󰕾 slider.percentage=40 slider.background.height=5 \
          slider.background.corner_radius=3 slider.background.color=0xff3c3c3c slider.highlight_color=0xffffffff \
          script='sketchybar --set t.island.a label="volume $PERCENTAGE%"' --subscribe t.island.vol mouse.clicked
step "Survol" "rien ne se voit au repos (noir sur l'encoche)" "souris sur l'encoche : le panneau noir s'agrandit en douceur" \
    "coins du haut évasés, coins du bas arrondis" "les 2 lignes apparaissent une fois ouvert" "la souris sort : il se referme après un court délai"
step "Contenu" "glisser le slider : la 1re ligne affiche le volume" "le panneau reste ouvert tant que la souris est dessus"

"$B" --set t.island notch.open=on; sleep 2; "$B" --set t.island notch.open=off
step "Par script" "il s'est ouvert 2 s puis refermé sans la souris"

"$B" --set t.island notch.horizontal=on notch.color=0xff1e1e2e
step "horizontal + couleur" "survol : les items côte à côte, fond bleu nuit"

echo "Sans encoche (écran externe seul) :"
"$B" --set t.island notch.fake=on
step "notch.fake=on" "un faux notch en haut au milieu de l'écran principal, même comportement"
