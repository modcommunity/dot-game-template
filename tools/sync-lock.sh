#!/usr/bin/env bash
# Writes addons.lock: the release tag of each addon in .gitignore's /addons/ lines.
#
# A server (dot-server-deploy) installs the tags in ITS addons.lock, and a pack records the
# API level of the addons it was built against. Built against the newest main, a pack asked
# for levels that the tags a server installs did not have yet ("needs dot-net API level 12
# or newer; this server has level 11"). resolve-deps.sh reads this file and clones the same
# tags, so the template and the server agree by construction.
#
#   tools/sync-lock.sh [path/to/dot-server-deploy]    take the server's tag, else the newest release tag
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
DEPLOY="${1:-../dot-server-deploy}"
SERVER_LOCK="$DEPLOY/addons.lock"

{
    printf '# The addon release tags this game is built and checked against; written by tools/sync-lock.sh.\n'
    printf '# Same tags as dot-server-deploy'"'"'s addons.lock, so a pack and the server that mounts it agree.\n'
    grep -oE '^/addons/[a-z0-9_]+$' .gitignore | sed 's|^/addons/||' | sort -u | while read -r a; do
        repo="${a//_/-}"
        ref=""
        [ -f "$SERVER_LOCK" ] && ref="$(awk -v r="$repo" '$1 == r { print $2; exit }' "$SERVER_LOCK")"
        [ -n "$ref" ] || ref="$(git ls-remote --tags --refs "https://github.com/modcommunity/$repo" 2>/dev/null \
            | sed 's|.*refs/tags/||' | sort -V | tail -1)"
        [ -n "$ref" ] || { echo "no release tag for $repo yet: locked to main, cut one" >&2; ref=main; }
        printf '%s\t%s\n' "$repo" "$ref"
    done
} > addons.lock.new && mv addons.lock.new addons.lock
cat addons.lock
