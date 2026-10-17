#!/usr/bin/env bash
# Les moteurs de verre : metal (réfraction), backdrop, system ; sur macOS 15 comme sur 26
source "$(dirname "$0")/lib.sh"

ROOT=$(cd "$(dirname "$0")/.." && pwd)
"$B" --reload "$ROOT/examples/liquid-glass.toml"; sleep 2
echo "Le moteur choisi est écrit sur stderr de la barre : « skylandbar: glass: ... »"
step "auto" "macOS 15 sans Enregistrement de l'écran : glass: backdrop" "avec l'autorisation (puis barre relancée) : glass: metal"

"$B" --bar glass_engine=backdrop
step "backdrop" "capsules floues et saturées, bord lumineux en haut à gauche, légère ombre" "pas de déformation"

"$B" --bar glass_engine=metal
step "metal" "sur les bords des capsules, ce qui est derrière se courbe (lentille)" "léger arc-en-ciel sur les bords" \
    "déplace une fenêtre derrière la barre : le verre suit en direct" "pas de reflet de la barre elle-même dans son verre"
"$B" --bar glass_refraction=28 glass_blur=0
step "Réglages" "glass_refraction=28 : courbure bien plus forte ; glass_blur=0 : net"
"$B" --bar glass_spacing=40
step "Fusion" "glass_spacing=40 : les capsules proches se rejoignent en une seule forme fluide"
"$B" --bar glass_refraction=14 glass_blur=2 glass_spacing=8 glass_engine=auto

echo "CPU : bash manual-tests/13-perf.sh avec le moteur metal"
