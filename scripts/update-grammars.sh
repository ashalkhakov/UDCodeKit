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
        # Some scanners #include sibling .cc files — copy any extra includes
        if [[ -d "$src_in" ]]; then
            # Copy any subdirectories needed by the scanner
            find "$src_in" -mindepth 1 -maxdepth 1 -type d | while read -r subdir; do
                local subname
                subname="$(basename "$subdir")"
                cp -r "$subdir" "$dest/src/$subname"
                log "copied subdirectory $subname/"
            done
        fi
        log "copied scanner.cc"
        scanner_copied=true
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
