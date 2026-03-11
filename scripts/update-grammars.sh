#!/usr/bin/env bash
# scripts/update-grammars.sh
#
# Convenience wrapper that runs each grammar bundle's fetch-deps.sh and then
# fetches the shared tree-sitter runtime used by TestApp.xcodeproj.
#
# USAGE
#   bash scripts/update-grammars.sh [grammar ...]
#
#   With no arguments all known grammars are updated.
#   Pass one or more grammar names to update only specific ones, e.g.:
#
#       bash scripts/update-grammars.sh html xml yaml
#
# HOW IT WORKS
#   Each grammar bundle (tree-sitter-<lang>/) contains a self-contained
#   fetch-deps.sh script that clones the upstream grammar repository and the
#   tree-sitter runtime, then writes all generated files into the bundle
#   directory.  This wrapper simply delegates to those per-bundle scripts.
#
#   The shared tree-sitter/ runtime at the repo root (used by TestApp) is
#   fetched separately via scripts/fetch-tree-sitter.sh.
#
# ADDING A NEW GRAMMAR
#   1. Create a tree-sitter-<lang>/ directory.
#   2. Copy fetch-deps.sh from an existing bundle and set the parameters at
#      the top of the file (GRAMMAR_ID, GRAMMAR_URL, GRAMMAR_SRC_SUBDIR,
#      GRAMMAR_QUERIES_SUBDIR, GRAMMAR_C_FUNC).
#   3. Add the new grammar name to the ALL_GRAMMARS array below.
#   4. Create Sources/TreeSitter<Lang>Plugin.{h,m}, Resources/Info.plist,
#      Resources/LanguageInfo.plist, TreeSitter<Lang>.xcodeproj, and README.md.
#      (See docs/grammar-bundles.md for full instructions.)
#   5. Register the new bundle in Sources/Model/UDLanguageModeRegistry.m.
#
# REQUIREMENTS
#   git  (any recent version)
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ALL_GRAMMARS=(bash c html json make markdown objc sql xml yaml)

# ─── Main ─────────────────────────────────────────────────────────────────────

if [[ $# -eq 0 ]]; then
    targets=("${ALL_GRAMMARS[@]}")
else
    targets=("$@")
fi

# Sort for deterministic output
IFS=$'\n' read -rd '' -a targets < <(printf '%s\n' "${targets[@]}" | sort) || true

echo "Updating ${#targets[@]} grammar(s): ${targets[*]}"
echo

for id in "${targets[@]}"; do
    script="$REPO_ROOT/tree-sitter-${id}/fetch-deps.sh"
    if [[ ! -f "$script" ]]; then
        echo "ERROR: fetch-deps.sh not found for grammar '$id' (expected at $script)" >&2
        exit 1
    fi
    bash "$script"
    echo
done

# Also refresh the shared tree-sitter runtime at the repo root
echo "==> Refreshing shared tree-sitter runtime → tree-sitter/"
bash "$REPO_ROOT/scripts/fetch-tree-sitter.sh"
echo

echo "Done."
echo "Remember to:"
echo "  1. Add new source files to TestApp.xcodeproj/project.pbxproj."
echo "  2. Add grammar src/ directories to HEADER_SEARCH_PATHS."
echo "  3. Register the new bundle name in Sources/Model/UDLanguageModeRegistry.m."
