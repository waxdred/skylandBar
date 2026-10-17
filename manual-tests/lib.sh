# Shared by the manual tests: sourced, not run.
# The bar must already run (with your config); each test adds items named t.*, says what
# to check, waits for Enter, and removes its items at the end (or on q / Ctrl-C).

B="${SKYLANDBAR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.build/release/skylandbar}"

cleanup() { "$B" --remove '/^t\./' >/dev/null 2>&1; true; }
trap cleanup EXIT

if ! "$B" --query bar >/dev/null 2>&1; then
    echo "La barre ne tourne pas. Lance-la d'abord :"
    echo "  $B --config ~/.config/sketchybar/sketchybarrc &"
    exit 1
fi

# step "titre" "à vérifier 1" "à vérifier 2"...
step() {
    printf '\n\033[1m▶ %s\033[0m\n' "$1"
    shift
    for check in "$@"; do printf '  [ ] %s\n' "$check"; done
    read -r -p "  Entrée : suite, q : arrêter " answer
    if [ "$answer" = q ]; then exit 0; fi
}

# a script that writes what it received into the item's label
SHOW='sketchybar --set "$NAME" label="$SENDER ${INFO:0:60}"'
