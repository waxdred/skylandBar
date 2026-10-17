# Tests manuels

Des scripts qui ajoutent des items de test (`t.*`), disent quoi vérifier, attendent
Entrée, puis retirent leurs items (aussi avec `q` ou Ctrl-C).

```sh
swift build -c release
.build/release/skylandbar &          # ta config ~/.config/skylandbar/skylandbar.toml
bash manual-tests/01-core.sh        # puis 02, 03...
```

Ils marchent depuis fish : ils tournent avec `bash`. Pour un autre binaire :
`SKYLANDBAR=/chemin/skylandbar bash manual-tests/01-core.sh`.

| Script | Ce qu'il teste |
| --- | --- |
| `01-core.sh` | add, set (regex), move, query, default, max_chars |
| `02-animations.sh` | `--animate` : les 6 courbes, item et barre, animation interrompue |
| `03-glass-clip.sh` | Liquid Glass (barre, `clear`, fond d'item), `background.clip` |
| `04-popups.sh` | popups verticale / horizontale, align, popup dans une popup, `mouse.exited.global` |
| `05-components.sh` | brackets, graphes (`--push`), sliders (glissé, `PERCENTAGE`, animé) |
| `06-aliases-images.sh` | `default_menu_items`, alias, teinte, images `app.*`, `media.artwork` |
| `07-events.sh` | événements système, souris, événement custom |
| `08-skyland.sh` | événements skyland natifs, workspaces poussés par skyland |
| `09-displays.sh` | `display=active` (fenêtre focus), `display=2`, `hidden=current` (2 écrans) |
| `10-texts-scripts.sh` | `scroll_texts`, `update_freq`, `when_shown`, `--reload`, `--exit` |
| `11-mach-lua.sh` | compatibilité : le CLI `sketchybar` et SbarLua par Mach, `--service install` |
| `12-workspaces.sh` | composants natifs : workspaces (états, clic, molette, animation) et titre |
| `13-perf.sh` | CPU et mémoire : repos, pluie de `--set`, animation continue |
| `14-notch.sh` | l'encoche façon boringNotch : survol, animation, contenu, script, `fake` |
| `15-toml.sh` | `skylandbar.toml` : `--export`, `--check`, chargement, hotload |
| `16-liquid-glass.sh` | le thème Liquid Glass : capsules, survol, popup, clair / sombre, accessibilité |
| `17-glass-engines.sh` | moteurs de verre : `metal` (réfraction), `backdrop`, `system`, réglages, fusion |
| `18-lens-motion.sh` | la sélection qui glisse : ressort, dépassement, étirement, apparition, Réduire les animations |

Note ce qui ne va pas (le numéro du script et la case) et envoie-le avec une capture.
