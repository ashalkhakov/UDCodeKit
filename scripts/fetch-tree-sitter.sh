#!/usr/bin/env bash
# scripts/fetch-tree-sitter.sh
#
# Fetches the tree-sitter runtime into the repo-root tree-sitter/ directory.
# This copy is referenced by TestApp.xcodeproj (HEADER_SEARCH_PATHS, lib.c).
#
# USAGE
#   bash scripts/fetch-tree-sitter.sh
#
# REQUIREMENTS
#   git  (any recent version)
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

TREE_SITTER_URL="https://github.com/tree-sitter/tree-sitter.git"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$REPO_ROOT/tree-sitter"

echo "==> Fetching tree-sitter runtime → tree-sitter/"

work_dir="$(mktemp -d)"
trap "rm -rf '$work_dir'" EXIT

echo "  cloning (shallow)..."
git clone --depth=1 --quiet "$TREE_SITTER_URL" "$work_dir/tree-sitter"

commit_sha="$(git -C "$work_dir/tree-sitter" rev-parse HEAD)"
echo "  HEAD = $commit_sha"

rm -rf "$DEST"
mkdir -p "$DEST"
cp -r "$work_dir/tree-sitter/lib/include" "$DEST/include"
cp -r "$work_dir/tree-sitter/lib/src" "$DEST/src"

echo "  OK — tree-sitter runtime written to tree-sitter/"
