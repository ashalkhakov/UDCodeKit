#!/usr/bin/env bash
# fetch-deps.sh — fetches tree-sitter runtime and grammar sources for TreeSitterYaml
#
# Run from the repository root:
#   bash tree-sitter-yaml/fetch-deps.sh
#
# Or run from within this directory:
#   cd tree-sitter-yaml && bash fetch-deps.sh
#
# WHAT THIS SCRIPT DOES
#   1. Shallow-clones the tree-sitter runtime into tree-sitter-yaml/tree-sitter/.
#   2. Shallow-clones the upstream grammar repository.
#   3. Copies src/parser.c (required) into tree-sitter-yaml/src/.
#   4. Copies src/scanner.c or src/scanner.cc (optional) into the same place.
#   5. Copies src/tree_sitter/ headers (grammar-specific runtime helper headers).
#   6. Copies any sibling C/C++/header files needed by the scanner.
#   7. Copies queries/highlights.scm and queries/indents.scm (optional) into
#      tree-sitter-yaml/queries/ and syncs them to Resources/.
#   8. Writes tree-sitter-yaml/src/tree_sitter_yaml.h (factory function
#      declaration).
#   9. Writes tree-sitter-yaml/UPSTREAM with the upstream URL and commit SHA.
#
# REQUIREMENTS
#   git  (any recent version)
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── Grammar-specific parameters ───────────────────────────────────────────────
GRAMMAR_ID="yaml"
GRAMMAR_URL="https://github.com/tree-sitter-grammars/tree-sitter-yaml.git"
GRAMMAR_SRC_SUBDIR="src"
GRAMMAR_QUERIES_SUBDIR="queries"
GRAMMAR_C_FUNC="tree_sitter_yaml"
TREE_SITTER_URL="https://github.com/tree-sitter/tree-sitter.git"
# ─────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="$SCRIPT_DIR"

log()  { echo "  $*"; }
info() { echo "==> $1"; }
warn() { echo "  [warn] $*"; }

write_header() {
    local lang="$1"
    local func="$2"
    local dest_dir="$3"
    local guard
    guard="TREE_SITTER_${lang^^}_H_"
    cat > "$dest_dir/tree_sitter_${lang}.h" <<HEADER
#ifndef ${guard}
#define ${guard}

#ifdef __cplusplus
extern "C" {
#endif

typedef struct TSLanguage TSLanguage;

const TSLanguage *${func}(void);

#ifdef __cplusplus
}
#endif

#endif  /* ${guard} */
HEADER
    log "wrote tree_sitter_${lang}.h"
}

# ── Fetch tree-sitter runtime ─────────────────────────────────────────────────
info "Fetching tree-sitter runtime → tree-sitter-${GRAMMAR_ID}/tree-sitter/"

work_dir="$(mktemp -d)"
ts_work="$work_dir/tree-sitter"
grammar_work="$work_dir/repo"

cleanup() { rm -rf "$work_dir"; }
trap cleanup EXIT

log "cloning tree-sitter (shallow)..."
git clone --depth=1 --quiet "$TREE_SITTER_URL" "$ts_work"
log "tree-sitter HEAD = $(git -C "$ts_work" rev-parse HEAD)"

rm -rf "$DEST/tree-sitter"
mkdir -p "$DEST/tree-sitter"
cp -r "$ts_work/include" "$DEST/tree-sitter/include"
cp -r "$ts_work/lib/src"  "$DEST/tree-sitter/src"
log "OK"

# ── Fetch grammar sources ──────────────────────────────────────────────────────
info "Fetching grammar ${GRAMMAR_ID}  ($GRAMMAR_URL)"

log "cloning grammar (shallow)..."
git clone --depth=1 --quiet "$GRAMMAR_URL" "$grammar_work"
commit_sha="$(git -C "$grammar_work" rev-parse HEAD)"
log "HEAD = $commit_sha"

src_in="$grammar_work/$GRAMMAR_SRC_SUBDIR"
qry_in="$grammar_work/$GRAMMAR_QUERIES_SUBDIR"

rm -rf "$DEST/src" "$DEST/queries"
mkdir -p "$DEST/src" "$DEST/queries"

# ── parser.c (required) ───────────────────────────────────────────────────────
if [[ -f "$src_in/parser.c" ]]; then
    cp "$src_in/parser.c" "$DEST/src/parser.c"
    log "copied parser.c  ($(wc -l < "$DEST/src/parser.c") lines)"
else
    echo "ERROR: parser.c not found at $src_in/parser.c" >&2
    exit 1
fi

# ── External scanner (optional) ───────────────────────────────────────────────
scanner_copied=false
if [[ -f "$src_in/scanner.c" ]]; then
    cp "$src_in/scanner.c" "$DEST/src/scanner.c"
    log "copied scanner.c"
    scanner_copied=true
elif [[ -f "$src_in/scanner.cc" ]]; then
    cp "$src_in/scanner.cc" "$DEST/src/scanner.cc"
    log "copied scanner.cc"
    scanner_copied=true
fi

# ── tree_sitter/ runtime headers ──────────────────────────────────────────────
if [[ -d "$src_in/tree_sitter" ]]; then
    cp -r "$src_in/tree_sitter" "$DEST/src/tree_sitter"
    log "copied src/tree_sitter/ ($(ls "$DEST/src/tree_sitter/" | tr '\n' ' '))"
fi

# ── Extra sibling C/C++/header files ──────────────────────────────────────────
if $scanner_copied; then
    for extra in "$src_in"/*.c "$src_in"/*.cc "$src_in"/*.h; do
        [[ -f "$extra" ]] || continue
        bname="$(basename "$extra")"
        [[ "$bname" == "parser.c" || "$bname" == "scanner.c" || "$bname" == "scanner.cc" ]] && continue
        cp "$extra" "$DEST/src/$bname"
        log "copied sibling src/$bname"
    done
    find "$src_in" -mindepth 1 -maxdepth 1 -type d | while read -r subdir; do
        subname="$(basename "$subdir")"
        [[ "$subname" == "tree_sitter" ]] && continue
        cp -r "$subdir" "$DEST/src/$subname"
        log "copied src subdirectory $subname/"
    done
    # XML special case: common/scanner.h lives outside the src subdir
    common_dir="$grammar_work/common"
    if [[ -d "$common_dir" && -f "$DEST/src/scanner.c" ]]; then
        mkdir -p "$DEST/common"
        cp "$common_dir"/*.h "$DEST/common/"
        log "copied common/ headers: $(ls "$DEST/common/")"
        sed -i 's|#include "../../common/|#include "../common/|g' "$DEST/src/scanner.c"
        log "patched scanner.c: ../../common/ → ../common/"
    fi
fi

# ── Query files ───────────────────────────────────────────────────────────────
queries_copied=0
for q in highlights.scm indents.scm locals.scm; do
    if [[ -f "$qry_in/$q" ]]; then
        cp "$qry_in/$q" "$DEST/queries/$q"
        log "copied queries/$q"
        ((queries_copied++)) || true
    fi
done
[[ $queries_copied -eq 0 ]] && warn "no .scm query files found in $GRAMMAR_QUERIES_SUBDIR"

# ── Sync query files into Resources/ ─────────────────────────────────────────
res_dir="$DEST/Resources"
if [[ -d "$res_dir" ]]; then
    for q in highlights.scm indents.scm locals.scm; do
        if [[ -f "$DEST/queries/$q" ]]; then
            cp "$DEST/queries/$q" "$res_dir/$q"
            log "synced queries/$q → Resources/$q"
        fi
    done
fi

# ── Factory function header ───────────────────────────────────────────────────
# Use the GRAMMAR_ID with hyphens replaced by underscores for the file/symbol name
lang_safe="${GRAMMAR_ID//-/_}"
write_header "$lang_safe" "$GRAMMAR_C_FUNC" "$DEST/src"

# ── UPSTREAM provenance ───────────────────────────────────────────────────────
cat > "$DEST/UPSTREAM" <<UPSTREAM
url:    $GRAMMAR_URL
commit: $commit_sha
UPSTREAM
log "wrote UPSTREAM"

echo "  OK"
