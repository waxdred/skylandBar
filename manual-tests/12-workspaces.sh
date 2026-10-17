#!/usr/bin/env bash
# Composants skyland natifs : workspaces et titre, sans script
source "$(dirname "$0")/lib.sh"

echo "skyland (ou AeroSpace) doit tourner."
"$B" --add workspaces t.ws left \
     --set t.ws icon.color=0xff6c7086 label="{apps}" label.font.size=11 background.color=0xff313244 background.corner_radius=6 \
          background.height=22 icon.padding_left=8 icon.padding_right=4 label.padding_right=8 \
          focused.icon.color=0xffcba6f7 focused.background.color=0xff45475a empty.label="" \
     --add title t.title center --set t.title title.app_icon=on label.max_chars=50
step "Workspaces" "un item par workspace, son nom en icône, ses apps en label" "le workspace focus est violet sur fond plus clair" \
    "chaque workspace est sur la barre de son écran" "change de workspace (clavier) : la barre suit tout de suite"
step "Clic et molette" "clic sur un workspace : skyland y va" "molette sur les workspaces : suivant / précédent (en boucle)"
step "Titre" "« App: titre » de la fenêtre focus, avec l'icône de l'app" "workspace vide : « Desktop »"

"$B" --set t.ws workspaces.animation=tanh workspaces.animation_frames=12 focused.y_offset=2 focused.background.border_width=1 \
          focused.background.border_color=0xffcba6f7
step "Animation" "en changeant de workspace, l'ancien redescend et le nouveau monte en douceur, la couleur glisse"

"$B" --set t.ws workspaces.monitor=off
step "workspaces.monitor=off" "tous les workspaces sur chaque barre"
"$B" --set t.title title.format=title title.empty="—"
step "title.format=title" "le titre seul ; « — » sans fenêtre"

"$B" --query t.ws | head -30
step "--query" "le JSON montre options et states"
