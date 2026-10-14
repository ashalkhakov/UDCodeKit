#!/usr/bin/env bash
# scripts/fetch-pinned.sh <name> <url> <dir>
#
# Checks out <url> into <dir> (which must not exist) at <name>'s commit in
# scripts/grammars.lock. With UD_FETCH_LATEST=1 (update-grammars.sh
# --latest), or when the lock has no <name>, its default branch's head
# instead, and the lock records that commit.
set -euo pipefail

name=$1 url=$2 dir=$3
lock="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/grammars.lock"
pin=$(awk -v n="$name" '$1 == n { print $2 }' "$lock")

if [[ "${UD_FETCH_LATEST:-}" != 1 && -n "$pin" ]]; then
    git init -q "$dir"
    git -C "$dir" fetch -q --depth=1 "$url" "$pin"
    git -C "$dir" checkout -q FETCH_HEAD
    exit 0
fi

git clone --depth=1 --quiet "$url" "$dir"
sha=$(git -C "$dir" rev-parse HEAD)
[[ -n "$pin" ]] || echo "  [warn] $name has no pin in grammars.lock: its head, $sha, is recorded" >&2
tmp=$(mktemp)
awk -v n="$name" -v s="$sha" '
    $1 == n { printf "%-11s %s\n", n, s; done = 1; next }
    { print }
    END { if (!done) printf "%-11s %s\n", n, s }' "$lock" > "$tmp"
mv "$tmp" "$lock"
