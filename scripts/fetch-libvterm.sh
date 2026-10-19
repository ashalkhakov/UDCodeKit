#!/usr/bin/env bash
# scripts/fetch-libvterm.sh
#
# Fetches libvterm (Paul Evans', MIT; the terminal emulation Neovim uses) into
# the repo-root libvterm/ directory, at its commit in scripts/grammars.lock.
# It is compiled into UDCodeKit for the terminal (Sources/Terminal): its
# sources, its headers, and its encoding tables, generated as its own
# Makefile generates them (perl).
#
# USAGE
#   bash scripts/fetch-libvterm.sh
#
# REQUIREMENTS
#   git, perl
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# Upstream is Launchpad's bzr; Neovim keeps it mirrored in git, on "mirror".
LIBVTERM_URL="https://github.com/neovim/libvterm.git"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$REPO_ROOT/libvterm"

echo "==> Fetching libvterm → libvterm/"

work_dir="$(mktemp -d)"
trap "rm -rf '$work_dir'" EXIT

"$REPO_ROOT/scripts/fetch-pinned.sh" libvterm "$LIBVTERM_URL" "$work_dir/libvterm"
src="$work_dir/libvterm"
echo "  commit = $(git -C "$src" rev-parse HEAD)"

for table in "$src"/src/encoding/*.tbl; do
    perl -CSD "$src/tbl2inc_c.pl" "$table" > "${table%.tbl}.inc"
done

rm -rf "$DEST"
mkdir -p "$DEST/src/encoding"
cp -r "$src/include" "$DEST/include"
cp "$src"/src/*.c "$src"/src/*.h "$src"/src/*.inc "$DEST/src/"
cp "$src"/src/encoding/*.inc "$DEST/src/encoding/"
cp "$src/LICENSE" "$DEST/LICENSE"

echo "  OK — libvterm written to libvterm/"
