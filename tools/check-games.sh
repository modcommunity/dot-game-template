#!/usr/bin/env bash
#
# Fails when a game's game.sh has drifted from what tools/game.sh.in and the game's game.conf produce.
#
#   tools/check-games.sh [GAME_DIR...]      (default: every sibling directory with a game.conf)
#
# Run it after changing game.sh.in or gen-game-sh.py: the template must leave every converted game's
# --check passing, so a regenerated game.sh never regresses a game's SUITES, PACK, timeouts or defs.
# Fix the template or the game's game.conf, never a game's game.sh by hand.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
games=("$@")
if [ ${#games[@]} -eq 0 ]; then
    for d in "$HERE"/../../*/; do [ -f "$d/game.conf" ] && games+=("$d"); done
fi
bad=0
for g in "${games[@]}"; do
    if out="$(python3 -I "$HERE/gen-game-sh.py" --check "$g" 2>&1)"; then
        printf 'ok    %s\n' "$(basename "$(cd "$g" && pwd)")"
    else
        printf 'DRIFT %s: %s\n' "$(basename "$(cd "$g" && pwd)")" "$out"; bad=$((bad + 1))
    fi
done
[ "$bad" -eq 0 ] && echo "${#games[@]} games match the generator" || { echo "$bad of ${#games[@]} games drifted"; exit 1; }
