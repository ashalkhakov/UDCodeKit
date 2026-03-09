#!/usr/bin/env bash
# scripts/update-grammars.sh
#
# Fetches tree-sitter grammar source files from their canonical git repositories
# and vendors them into this repository.
#
# USAGE
#   bash scripts/update-grammars.sh [grammar ...]
#
#   With no arguments all grammars listed in GRAMMARS below are updated.
#   Pass one or more grammar names to update only specific ones, e.g.:
#
#       bash scripts/update-grammars.sh html xml yaml
#
# WHAT THIS SCRIPT DOES
#   For each grammar it:
#     1. Shallow-clones the upstream repository into a temporary directory.
#     2. Copies src/parser.c (required) into tree-sitter-<lang>/src/.
#     3. Copies src/scanner.c or src/scanner.cc (optional) into the same place.
#     4. Copies queries/highlights.scm and queries/indents.scm (optional)
#        into tree-sitter-<lang>/queries/.
#     5. Writes a tree-sitter-<lang>/src/tree_sitter_<lang>.h header that
#        declares the tree_sitter_<lang>() factory function so that the
#        Objective-C layer can call it without pulling in the full C API.
#     6. Writes tree-sitter-<lang>/UPSTREAM containing the repository URL
#        and the commit SHA that was vendored, for future reference.
#     7. Copies the shared tree-sitter/ runtime into
#        tree-sitter-<lang>/tree-sitter/ so each bundle is self-contained.
#     8. Syncs query files into tree-sitter-<lang>/Resources/ (the copies
#        that are compiled into the bundle as resources).
#
# ADDING A NEW GRAMMAR
#   Add a line to the GRAMMARS associative array below following the format:
#
#     ["<id>"]="<git-url>|<src-subdir>|<queries-subdir>|<c-function-name>"
#
#   Then run this script to vendor the grammar.  After that you will need to:
#     - Add src/parser.c (and scanner.c/cc if present) to the Xcode project.
#     - Add the grammar's src/ directory to HEADER_SEARCH_PATHS.
#     - Register the new UDLanguageMode in UDLanguageModeRegistry.m.
#
# REQUIREMENTS
#   git  (any recent version)
#
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# ─── Grammar registry ────────────────────────────────────────────────────────
#
# Format: ["id"]="url|src_subdir|queries_subdir|c_function_name"
#
# src_subdir     – path inside the clone that contains parser.c / scanner.c
# queries_subdir – path inside the clone that contains *.scm files
# c_function_name – the C symbol name for the language factory function

declare -A GRAMMARS=(
    ["bash"]="https://github.com/tree-sitter/tree-sitter-bash.git|src|queries|tree_sitter_bash"
    ["c"]="https://github.com/tree-sitter/tree-sitter-c.git|src|queries|tree_sitter_c"
    ["html"]="https://github.com/tree-sitter/tree-sitter-html.git|src|queries|tree_sitter_html"
    ["json"]="https://github.com/tree-sitter/tree-sitter-json.git|src|queries|tree_sitter_json"
    ["make"]="https://github.com/alemuller/tree-sitter-make.git|src|queries|tree_sitter_make"
    ["markdown"]="https://github.com/ikatyang/tree-sitter-markdown.git|src|queries|tree_sitter_markdown"
    ["objc"]="https://github.com/tree-sitter-grammars/tree-sitter-objc.git|src|queries|tree_sitter_objc"
    ["xml"]="https://github.com/tree-sitter-grammars/tree-sitter-xml.git|xml/src|queries/xml|tree_sitter_xml"
    ["yaml"]="https://github.com/tree-sitter-grammars/tree-sitter-yaml.git|src|queries|tree_sitter_yaml"
)

# ─── Helpers ─────────────────────────────────────────────────────────────────

log()  { echo "  $*"; }
info() { echo "==> $1"; }
warn() { echo "  [warn] $*"; }

write_header() {
    local lang="$1"          # e.g. "html"
    local func="$2"          # e.g. "tree_sitter_html"
    local dest_dir="$3"      # e.g. .../tree-sitter-html/src

    # Construct include-guard and uppercase macro names
    local guard
    guard="TREE_SITTER_${lang^^}_H_"
    local upper_lang="${lang^^}"

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

vendor_grammar() {
    local id="$1"
    local spec="${GRAMMARS[$id]}"

    IFS='|' read -r url src_subdir queries_subdir c_func <<< "$spec"

    info "Updating $id  ($url)"

    local work_dir
    work_dir="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '$work_dir'" RETURN

    # ── Clone ─────────────────────────────────────────────────────────────
    log "cloning (shallow)..."
    git clone --depth=1 --quiet "$url" "$work_dir/repo"

    local commit_sha
    commit_sha="$(git -C "$work_dir/repo" rev-parse HEAD)"
    log "HEAD = $commit_sha"

    local src_in="$work_dir/repo/$src_subdir"
    local qry_in="$work_dir/repo/$queries_subdir"

    # ── Destination directories ────────────────────────────────────────────
    local dest="$REPO_ROOT/tree-sitter-${id}"
    rm -rf "$dest"
    mkdir -p "$dest/src" "$dest/queries"

    # ── parser.c (required) ───────────────────────────────────────────────
    if [[ -f "$src_in/parser.c" ]]; then
        cp "$src_in/parser.c" "$dest/src/parser.c"
        log "copied parser.c  ($(wc -l < "$dest/src/parser.c") lines)"
    else
        echo "ERROR: parser.c not found at $src_in/parser.c" >&2
        exit 1
    fi

    # ── External scanner (optional, C or C++) ─────────────────────────────
    local scanner_copied=false
    if [[ -f "$src_in/scanner.c" ]]; then
        cp "$src_in/scanner.c" "$dest/src/scanner.c"
        log "copied scanner.c"
        scanner_copied=true
    elif [[ -f "$src_in/scanner.cc" ]]; then
        cp "$src_in/scanner.cc" "$dest/src/scanner.cc"
        log "copied scanner.cc"
        scanner_copied=true
    fi

    # ── tree_sitter/ runtime headers (array.h, alloc.h, parser.h) ─────────
    # Modern grammars bundle these in src/tree_sitter/ so scanners can do
    # #include "tree_sitter/array.h" etc.  Always copy this subdirectory
    # when it exists in the upstream source.
    if [[ -d "$src_in/tree_sitter" ]]; then
        cp -r "$src_in/tree_sitter" "$dest/src/tree_sitter"
        log "copied src/tree_sitter/ ($(ls "$dest/src/tree_sitter/" | tr '\n' ' '))"
    fi

    # ── Extra sibling C/C++ source files included by the scanner ──────────
    # Some grammars include sibling .c/.cc files (e.g. YAML schema files) or
    # shared headers from a parallel directory (e.g. XML common/scanner.h).
    # Copy any remaining .c / .cc / .h files in src/ that weren't already
    # copied, so relative includes resolve correctly.
    if $scanner_copied; then
        for extra in "$src_in"/*.c "$src_in"/*.cc "$src_in"/*.h; do
            [[ -f "$extra" ]] || continue
            local bname
            bname="$(basename "$extra")"
            # Skip files we already handle explicitly
            [[ "$bname" == "parser.c" || "$bname" == "scanner.c" || "$bname" == "scanner.cc" ]] && continue
            cp "$extra" "$dest/src/$bname"
            log "copied sibling src/$bname"
        done

        # Copy any subdirectories in src/ other than tree_sitter/ (already
        # handled above), e.g. the XML grammar's inline subdirs.
        find "$src_in" -mindepth 1 -maxdepth 1 -type d | while read -r subdir; do
            local subname
            subname="$(basename "$subdir")"
            [[ "$subname" == "tree_sitter" ]] && continue  # handled above
            cp -r "$subdir" "$dest/src/$subname"
            log "copied src subdirectory $subname/"
        done

        # XML grammar: common/scanner.h is at the repo root level relative to
        # the xml/src/ source dir.  Copy it to <dest>/common/ and rewrite the
        # include path so it resolves from our flattened vendored tree.
        # Original: #include "../../common/scanner.h"  (xml/src → repo root)
        # Vendored: #include "../common/scanner.h"     (tree-sitter-xml/src → tree-sitter-xml/)
        local common_dir="$work_dir/repo/common"
        if [[ -d "$common_dir" && -f "$dest/src/scanner.c" ]]; then
            mkdir -p "$dest/common"
            cp "$common_dir"/*.h "$dest/common/"
            log "copied common/ headers: $(ls "$dest/common/")"
            # Rewrite relative path for our flattened layout
            sed -i 's|#include "../../common/|#include "../common/|g' "$dest/src/scanner.c"
            log "patched scanner.c: ../../common/ → ../common/"
        fi
    fi

    # ── Queries (optional) ────────────────────────────────────────────────
    local queries_copied=0
    for q in highlights.scm indents.scm locals.scm; do
        if [[ -f "$qry_in/$q" ]]; then
            cp "$qry_in/$q" "$dest/queries/$q"
            log "copied queries/$q"
            ((queries_copied++)) || true
        fi
    done
    [[ $queries_copied -eq 0 ]] && warn "no .scm query files found in $queries_subdir"

    # ── Header ────────────────────────────────────────────────────────────
    write_header "$id" "$c_func" "$dest/src"

    # ── Per-bundle tree-sitter runtime copy ───────────────────────────────
    # Each bundle ships its own copy of the tree-sitter runtime so that it
    # can be built and tracked independently.  Copy from the shared tree-sitter/
    # directory at the repo root.
    local ts_src="$REPO_ROOT/tree-sitter"
    local ts_dest="$dest/tree-sitter"
    if [[ -d "$ts_src" ]]; then
        rm -rf "$ts_dest"
        cp -r "$ts_src" "$ts_dest"
        log "copied tree-sitter runtime → tree-sitter-${id}/tree-sitter/"
    else
        warn "shared tree-sitter/ not found at $ts_src — skipping per-bundle copy"
    fi

    # ── Sync query files into Resources/ (bundle resource copies) ────────
    # Resources/ is the copy of queries that gets compiled into the .bundle.
    # Keep it in sync with queries/ after every vendor run.
    local res_dir="$dest/Resources"
    if [[ -d "$res_dir" ]]; then
        for q in highlights.scm indents.scm locals.scm; do
            if [[ -f "$dest/queries/$q" ]]; then
                cp "$dest/queries/$q" "$res_dir/$q"
                log "synced queries/$q → Resources/$q"
            fi
        done
    fi

    # ── UPSTREAM provenance file ───────────────────────────────────────────
    cat > "$dest/UPSTREAM" <<UPSTREAM
url:    $url
commit: $commit_sha
UPSTREAM
    log "wrote UPSTREAM"

    echo "  OK"
}

# ─── Main ─────────────────────────────────────────────────────────────────────

if [[ $# -eq 0 ]]; then
    targets=("${!GRAMMARS[@]}")
else
    targets=("$@")
fi

# Sort for deterministic output
IFS=$'\n' read -rd '' -a targets < <(printf '%s\n' "${targets[@]}" | sort) || true

echo "Updating ${#targets[@]} grammar(s): ${targets[*]}"
echo

for id in "${targets[@]}"; do
    if [[ -z "${GRAMMARS[$id]+x}" ]]; then
        echo "ERROR: unknown grammar '$id'. Known grammars: ${!GRAMMARS[*]}" >&2
        exit 1
    fi
    vendor_grammar "$id"
    echo
done

echo "Done. Vendored grammars are in tree-sitter-*/ at the repo root."
echo "Remember to:"
echo "  1. Add new source files to TestApp.xcodeproj/project.pbxproj."
echo "  2. Add grammar src/ directories to HEADER_SEARCH_PATHS."
echo "  3. Register the new UDLanguageMode in Sources/Model/UDLanguageModeRegistry.m."
