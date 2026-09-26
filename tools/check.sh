#!/usr/bin/env bash
#
# Everything a change to this game should pass before it is pushed.
#
#   tools/check.sh            import, parse every script, run every suite, test the rename
#   tools/check.sh --quick    the same without the rename test
#
# 1. IMPORT. Registers the addons' class names; without it every Dot* type in every script
#    fails to resolve and it reads like a hundred unrelated errors.
# 2. PARSE every script on its own. A scene whose script does not parse does not fail, it
#    HANGS, silently -- so this runs before anything is run.
# 3. THE SUITES, every examples/headless_*.tscn, each capped with a timeout. One of them,
#    headless_pack, is what refuses the two things a delivered game may not have: a
#    `class_name`, and a bare "res://<your folder>/..." string that is not wrapped in
#    TplPaths.rebase(). It proves its own scanners can see before it trusts them.
# 4. THE RENAME. tools/rename.sh on a scratch copy, which must come out with no trace of the
#    old prefix and pass the suites again. A rename script nobody runs is one that breaks the
#    first time somebody who is not us needs it.
#
# CI (.github/workflows/ci.yml) runs steps 1-3 on every push; step 4 is local.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

GODOT="${GODOT:-godot}"
RED=$'\033[31m'; GRN=$'\033[32m'; OFF=$'\033[0m'
fails=0

[ -e addons/dot_core ] || {
    printf 'addons/ is empty. Link the addons first:\n  ../dot-ci/scripts/resolve-deps.sh .    (or ./bootstrap.sh inside the family tree)\n' >&2
    exit 2
}

# Engine noise that is not a script problem. A suite's own output is still read in full.
NOISE='ObjectDB instances( were)? leaked|resources still in use|Pages in use exist at exit|at: (cleanup|clear|~PagedAllocator)'

run_checks() {    # <project dir>
    local dir="$1" f out status scene
    echo "importing"
    timeout 600 "$GODOT" --headless --path "$dir" --import >/dev/null 2>&1

    echo "parsing"
    while read -r f; do
        out="$(timeout 120 "$GODOT" --headless --path "$dir" --check-only --script "res://$f" 2>&1 \
            | grep -Ev '^(Godot Engine v|$)' | grep -Eiv "$NOISE")"
        if [ -n "$out" ]; then
            printf '  %sFAIL%s %s\n%s\n' "$RED" "$OFF" "$f" "$out"
            fails=$((fails + 1))
        fi
    done < <(cd "$dir" && find . -name '*.gd' -not -path './.godot/*' -not -path './addons/*' \
        -not -path './.deps/*' | sed 's|^\./||' | sort)

    for scene in "$dir"/examples/headless_*.tscn; do
        scene="examples/$(basename "$scene")"
        echo
        echo "running $scene"
        out="$(timeout 300 "$GODOT" --headless --path "$dir" "res://$scene" 2>&1)"
        status=$?
        # The suite's own lines; the server's INFO log is left out, its warnings are not.
        printf '%s\n' "$out" | grep -vE '^(inf|dbg|trc) |^Godot Engine|^$'
        if [ "$status" -ne 0 ] || printf '%s' "$out" | grep -qE 'SCRIPT ERROR|Parse Error'; then
            printf '  %sFAIL%s %s (exit %d)\n' "$RED" "$OFF" "$scene" "$status"
            fails=$((fails + 1))
        fi
    done
}

run_checks .

if [ "${1:-}" != "--quick" ]; then
    echo
    echo "the rename"
    scratch="$(mktemp -d)"
    trap 'rm -rf "$scratch"' EXIT
    copy="$scratch/crate-rush"
    mkdir -p "$copy/addons"
    git ls-files -co --exclude-standard | grep -v '^addons/' | while read -r f; do
        mkdir -p "$copy/$(dirname "$f")" && cp "$f" "$copy/$f"
    done
    git -C "$copy" init -q
    for link in addons/*; do ln -s "$(readlink -f "$link")" "$copy/$link"; done

    if ! "$copy/tools/rename.sh" cr crate-rush; then
        printf '  %sFAIL%s tools/rename.sh refused a good name\n' "$RED" "$OFF"
        fails=$((fails + 1))
    else
        left="$(cd "$copy" && grep -rlE '\btpl|\bTpl|dot-game-template' --exclude-dir=addons --exclude-dir=.git --exclude='*.md' . ; \
            find . -name 'tpl_*' -not -path './addons/*')"
        if [ -n "$left" ]; then
            printf '  %sFAIL%s the old names survived the rename in:\n%s\n' "$RED" "$OFF" "$left"
            fails=$((fails + 1))
        else
            printf '  %sok%s   no trace of tpl or dot-game-template is left\n' "$GRN" "$OFF"
        fi
        run_checks "$copy"
    fi

    if "$copy/tools/rename.sh" cr bad__name >/dev/null 2>&1; then
        printf '  %sFAIL%s tools/rename.sh accepted a name the site would refuse\n' "$RED" "$OFF"
        fails=$((fails + 1))
    else
        printf '  %sok%s   and a name the site would refuse is refused\n' "$GRN" "$OFF"
    fi
fi

echo
if [ "$fails" -eq 0 ]; then
    printf '%sall checks passed%s\n' "$GRN" "$OFF"
else
    printf '%s%d failed%s\n' "$RED" "$fails" "$OFF"
fi
exit $((fails > 0))
