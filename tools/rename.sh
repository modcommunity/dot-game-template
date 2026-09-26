#!/usr/bin/env bash
#
# Make this template yours: a new file prefix and your repository's name, in one pass.
#
#   tools/rename.sh <prefix> <repo-name>
#   tools/rename.sh cr crate-rush
#
# <prefix> replaces `tpl` everywhere: file names (game/tpl_game.gd -> game/cr_game.gd), the
# script constants (TplGame -> CrGame), the module and command names (tpl_status -> cr_status)
# and the log channels. Lowercase letters and digits, starting with a letter, twelve at most.
#
# <repo-name> replaces `dot-game-template`: project.godot's name, game.yml's placeholder
# content id, the docs. Use your repository's name exactly. The site publishes your game as
# <your site username>/<repo name> and refuses a name that is not lowercase a-z, 0-9, - and _
# (no leading, trailing or doubled _), so this refuses the same names now rather than then.
#
# WHY A PREFIX AT ALL: a game in this family has no `class_name` (a delivered pack cannot use
# one), so nothing stops two games' files colliding except their names. A prefix you choose
# once keeps yours apart from every other game a server or a developer has installed.
#
# Run it once, on a clean checkout, then re-import and run tools/check.sh. It deletes .godot/
# (the editor's cache), which still holds the old file names and would otherwise disagree.
set -euo pipefail

usage() { printf 'usage: tools/rename.sh <prefix> <repo-name>   e.g. tools/rename.sh cr crate-rush\n' >&2; exit 2; }

[ $# -eq 2 ] || usage
NEW="$1"
REPO="$2"

[[ "$NEW" =~ ^[a-z][a-z0-9]{0,11}$ ]] \
    || { printf 'prefix %s: lowercase letters and digits, starting with a letter, at most 12\n' "$NEW" >&2; exit 2; }
[ "$NEW" != "tpl" ] || { printf 'the prefix is already tpl\n' >&2; exit 2; }
[[ "$REPO" =~ ^[a-z0-9_-]{1,64}$ && "$REPO" != _* && "$REPO" != *_ && "$REPO" != *__* ]] \
    || { printf 'repo name %s: lowercase a-z, 0-9, - and _, no leading, trailing or doubled _\n' "$REPO" >&2; exit 2; }

cd "$(dirname "${BASH_SOURCE[0]}")/.."

CAP="${NEW^}"

# The files this repository owns: tracked, or new and not ignored. Never addons/ (links to
# other repositories) and never .godot/ (a cache).
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    mapfile -t FILES < <(git ls-files -co --exclude-standard | grep -v '^addons/')
else
    mapfile -t FILES < <(find . -type f -not -path './.godot/*' -not -path './addons/*' \
        -not -path './.git/*' -not -path './.deps/*' | sed 's|^\./||')
fi

[ "${#FILES[@]}" -gt 0 ] || { printf 'no files found; run this from a checkout of the template\n' >&2; exit 1; }

# Contents first, while every path is still the one git listed. `\btpl` matches tpl_game,
# "tpl" and tpl.net, and not the tpl inside another word; `\bTpl` matches TplGame.
changed=0
for f in "${FILES[@]}"; do
    [ -f "$f" ] || continue
    grep -Iq . "$f" 2>/dev/null || continue          # text files only
    if grep -qE '\btpl|\bTpl|dot-game-template' "$f"; then
        sed -i -E "s/\\btpl/${NEW}/g; s/\\bTpl/${CAP}/g; s/dot-game-template/${REPO}/g" "$f"
        changed=$((changed + 1))
    fi
done

# Then the names. Only the file name moves; no folder here carries the prefix.
moved=0
for f in "${FILES[@]}"; do
    base="$(basename "$f")"
    [[ "$base" == tpl_* ]] || continue
    target="$(dirname "$f")/${NEW}_${base#tpl_}"
    mv "$f" "$target"
    moved=$((moved + 1))
done

rm -rf .godot

printf 'renamed %d file(s) and rewrote %d: tpl -> %s, Tpl -> %s, dot-game-template -> %s\n' \
    "$moved" "$changed" "$NEW" "$CAP" "$REPO"
printf 'next: godot --headless --path . --import && tools/check.sh\n'
