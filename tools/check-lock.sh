#!/usr/bin/env bash
# Fails when a pin in addons.lock is older than the tag dot-server-deploy pins for the same addon.
#
#   tools/check-lock.sh [path/to/dot-server-deploy]    default: ../dot-server-deploy, else a shallow clone
#   tools/check-lock.sh --self-test                    runs the check against tools/fixtures
#
# A stale pin only shows on a fresh install, so it is caught here, not there.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

# compare <lock> <server lock>: prints each stale pin; exit 1 if any
compare() {
    local bad=0 repo have want
    while IFS=$'\t' read -r repo have; do
        case "$repo" in ''|'#'*) continue ;; esac
        want="$(awk -v r="$repo" '$1 == r { print $2; exit }' "$2")"
        [ -n "$want" ] && [ "$want" != "$have" ] || continue
        if [ "$(printf '%s\n%s\n' "$have" "$want" | sort -V | head -1)" = "$have" ]; then
            printf 'stale: %s is %s, dot-server-deploy pins %s\n' "$repo" "$have" "$want"
            bad=1
        fi
    done < "$1"
    return $bad
}

if [ "${1:-}" = "--self-test" ]; then
    f=tools/fixtures
    compare "$f/lock-stale.tsv" "$f/server.tsv" >/dev/null && { echo "self-test FAIL: stale pin not caught"; exit 1; }
    compare "$f/lock-ok.tsv" "$f/server.tsv" || { echo "self-test FAIL: good lock rejected"; exit 1; }
    echo "self-test ok"; exit 0
fi

server="${1:-../dot-server-deploy}/addons.lock"
if [ ! -f "$server" ]; then
    tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
    if timeout 60 git clone -q --depth 1 "https://github.com/modcommunity/dot-server-deploy" "$tmp" 2>/dev/null; then
        server="$tmp/addons.lock"
    else
        echo "check-lock: dot-server-deploy unreachable, skipped (not a failure)"; exit 0
    fi
fi

if compare addons.lock "$server"; then
    echo "addons.lock is current with dot-server-deploy"
else
    echo "fix: tools/sync-lock.sh ${1:-<path to dot-server-deploy>} && git commit -am 'Refresh addons.lock'"
    exit 1
fi
