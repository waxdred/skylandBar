#!/usr/bin/env bash
# Le CLI sketchybar et SbarLua parlent à skylandbar par Mach (sketchybar arrêté)
source "$(dirname "$0")/lib.sh"

SB=$(command -v /opt/homebrew/bin/sketchybar /usr/local/bin/sketchybar | head -1)
if [ -z "$SB" ]; then
    echo "Le CLI sketchybar n'est pas installé (brew install sketchybar) : tests Mach sautés."
    exit 0
fi
echo "sketchybar doit être arrêté : brew services stop sketchybar"

"$SB" --add item t.mach center --set t.mach label="via le CLI sketchybar"
step "CLI sketchybar → skylandbar" "l'item « via le CLI sketchybar » apparaît dans skylandbar"
"$SB" --query t.mach | head -5
step "--query par Mach" "un JSON s'affiche ci-dessus"
"$SB" --set t.mach nope=1; echo "code de sortie : $?"
step "Erreur par Mach" "un message [!] et un code de sortie 1"

echo "SbarLua (si installé) : mets une config Lua dans ~/.config/sketchybar puis :"
echo "  $B --reload"
step "Config Lua" "les items de la config Lua apparaissent" "leurs callbacks (subscribe) réagissent : changer d'app, cliquer..." \
    "un 2e --reload ne double pas les items ni les callbacks"

echo "Service :"
echo "  $B --exit; $B --service install   puis se déconnecter / reconnecter"
step "Au login" "la barre démarre seule" "kill -9 de la barre : elle redémarre" "--exit : elle reste fermée" "--service uninstall : plus au login"
