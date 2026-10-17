#!/usr/bin/env bash
# skyland : événements natifs (subscribe) et workspaces poussés par skyland
source "$(dirname "$0")/lib.sh"

"$B" --add item t.ws center --set t.ws label="workspace ?" script='sketchybar --set $NAME label="ws $FOCUSED_WORKSPACE (avant $PREV_WORKSPACE)"' \
     --subscribe t.ws skyland_workspace_change \
     --add item t.mode center --set t.mode label="mode ?" script='sketchybar --set $NAME label="mode $MODE"' --subscribe t.mode skyland_mode_change
step "Événements skyland (sans exec-on-workspace-change)" "change de workspace : « ws N (avant M) »" "change de mode (ex. resize) : « mode … »" "quitte et relance skyland : ça repart tout seul (3 s)"

step "Workspaces poussés par skyland (skyland avec bar.swift à jour)" "les items workspace.N de ta config suivent le focus" "le titre de fenêtre suit"
