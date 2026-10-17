#!/usr/bin/env bash
# CPU de la barre : au repos, sous une pluie de --set, pendant une animation
source "$(dirname "$0")/lib.sh"

pid=$(pgrep -x skylandbar | head -1)
[ -n "$pid" ] || { echo "skylandbar introuvable (pgrep)"; exit 1; }
cpu() { ps -o %cpu= -p "$pid" | tr -d ' '; }
rss() { ps -o rss= -p "$pid" | awk '{printf "%.1f Mo", $1/1024}'; }
measure() { sleep 1; local total=0; for _ in 1 2 3 4 5; do total=$(echo "$total + $(cpu)" | bc); sleep 1; done; echo "scale=1; $total / 5" | bc; }

echo "Repos : $(measure) % CPU, $(rss)"

"$B" --add item t.spam right --set t.spam label=0
( for i in $(seq 1 500); do "$B" --set t.spam label="$((i % 7))"; done ) &
echo "500 --set (labels qui se répètent) : $(measure) % CPU"
wait

( for i in $(seq 1 300); do "$B" --set t.spam label="same"; done ) &
echo "300 --set au même label (rien à redessiner) : $(measure) % CPU"
wait

"$B" --add item t.anim center --set t.anim label="anim" background.color=0xff313244
( for _ in 1 2 3 4 5 6; do "$B" --animate sin 60 --set t.anim y_offset=6; sleep 1; "$B" --animate sin 60 --set t.anim y_offset=0; sleep 1; done ) &
echo "Animation continue : $(measure) % CPU"
wait
echo "Après : $(rss)"
step "Mesures" "note les 4 valeurs de CPU et la mémoire, et compare avec la version 0.5 si tu veux (git checkout a7ebf2f)"
