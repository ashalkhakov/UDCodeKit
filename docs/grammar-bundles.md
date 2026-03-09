# Grammar Bundles

This document explains how tree-sitter grammar bundles are structured,
vendored, and kept up to date.

---

## Overview

Each bundled grammar lives in a top-level directory named
`tree-sitter-<lang>/` beside the Xcode project root:

```
tree-sitter-<lang>/
├── UPSTREAM          # upstream git URL + vendored commit SHA
├── queries/
│   ├── highlights.scm   # syntax-highlighting captures (required)
│   └── indents.scm      # indentation rules (optional)
└── src/
    ├── parser.c          # generated C parser (required)
    ├── scanner.c         # external scanner in C (optional)
    ├── scanner.cc        # external scanner in C++ (optional)
    └── tree_sitter_<lang>.h   # header declaring the factory function
```

## Bundled grammars

| Language     | Identifier  | Extensions                         | Upstream repository                                         |
|--------------|-------------|------------------------------------|-------------------------------------------------------------|
| Bash         | `bash`      | `.sh` `.bash` `.zsh` `.ksh`        | https://github.com/tree-sitter/tree-sitter-bash             |
| C            | `c`         | `.c`                               | https://github.com/tree-sitter/tree-sitter-c                |
| HTML         | `html`      | `.html` `.htm` `.xhtml` `.shtml`   | https://github.com/tree-sitter/tree-sitter-html             |
| JSON         | `json`      | `.json` `.jsonc` `.geojson`        | https://github.com/tree-sitter/tree-sitter-json             |
| Makefile     | `make`      | `.mk`                              | https://github.com/alemuller/tree-sitter-make               |
| Markdown     | `markdown`  | `.md` `.markdown` `.mdown` `.mkd`  | https://github.com/ikatyang/tree-sitter-markdown            |
| Objective-C  | `objc`      | `.m` `.mm` `.h`                    | https://github.com/tree-sitter-grammars/tree-sitter-objc    |
| XML          | `xml`       | `.xml` `.xsl` `.svg` `.rss` `.plist` | https://github.com/tree-sitter-grammars/tree-sitter-xml   |
| YAML         | `yaml`      | `.yaml` `.yml`                     | https://github.com/tree-sitter-grammars/tree-sitter-yaml    |

## Updating a grammar bundle

Use the provided shell script to re-vendor one or more grammars from their
upstream repositories:

```sh
# Update all bundled grammars
bash scripts/update-grammars.sh

# Update specific grammars only
bash scripts/update-grammars.sh c objc bash make
```

The script:

1. Shallow-clones (depth 1) the upstream repository into a temporary directory.
2. Copies `src/parser.c` (required), `src/scanner.c` / `src/scanner.cc`
   (if present), and any `*.scm` query files into the local bundle directory.
3. Regenerates the `tree_sitter_<lang>.h` header declaring the factory function.
4. Writes an `UPSTREAM` file recording the URL and commit SHA that was vendored.

After the script finishes you need to:

1. **Review the diff** — pay particular attention to `src/parser.c` and the
   query files since those change with every grammar release.
2. **Rebuild** the Xcode project (`⌘B`) to recompile the updated C sources.
3. **Run the tests** to confirm nothing regressed.
4. **Commit** the updated `tree-sitter-<lang>/` directory together with any
   changes to `UDLanguageModeRegistry.m` (e.g., updated queries or new
   language modes).

## Adding a new grammar bundle

1. **Add an entry** to the `GRAMMARS` associative array in
   `scripts/update-grammars.sh`:

   ```bash
   ["<id>"]="<git-url>|<src-subdir>|<queries-subdir>|<c-function-name>"
   ```

2. **Run the script** to vendor the files:

   ```sh
   bash scripts/update-grammars.sh <id>
   ```

3. **Register the grammar** in the Xcode project:
   - Add `tree-sitter-<id>/src/parser.c` (and `scanner.c` / `scanner.cc` if
     present) to the `Sources` build phase of the **TestApp** target in
     `TestApp.xcodeproj/project.pbxproj`.
   - Add `"$(SRCROOT)/tree-sitter-<id>/src"` to `HEADER_SEARCH_PATHS` in
     both the Debug and Release build configurations of the TestApp target.

4. **Import the header** and **register the mode** in
   `Sources/Model/UDLanguageModeRegistry.m`:

   ```objc
   #import "tree_sitter_<id>.h"

   // inside _initWithBuiltins:
   UDLanguageMode *myLang = [[UDLanguageMode alloc]
       initWithIdentifier:@"<id>"
              displayName:@"My Language"
           fileExtensions:@[@"ext"]
             languageFunc:(LanguageFunc)tree_sitter_<id>
          highlightsQuery:kMyLangHighlightsQuery
             indentsQuery:nil
            lspLanguageID:nil
   defaultNewDocumentText:@""];
   [self _registerModeUnsafe:myLang];
   ```

5. **Add tests** in `Tests/UDLanguageModeTests.m` covering at minimum:
   - Mode registration (`modeForIdentifier:` returns the correct identifier)
   - `languageFunc != NULL`
   - Extension lookup (`modeForFileExtension:`)

## Notes on grammar size

Some grammars ship with very large generated `parser.c` files (100 k+ lines).
These are normal — tree-sitter generates C state-machine tables that are
deliberately large for performance.  They compile fine with any modern C
compiler; the only practical concern is incremental-build time.

Grammars whose upstream repository does **not** pre-commit `parser.c` must be
generated locally with the tree-sitter CLI before vendoring:

```sh
npm install -g tree-sitter-cli
cd /tmp/clone-of-grammar
tree-sitter generate
# then copy src/parser.c into the bundle directory manually
```

## Notes on scanner helper files

Modern tree-sitter grammars (generated with tree-sitter ≥ 0.20 or so) have
their scanners include `"tree_sitter/array.h"`, `"tree_sitter/alloc.h"`, and
`"tree_sitter/parser.h"` from a `src/tree_sitter/` subdirectory that each
upstream grammar ships alongside its source.  The update script automatically
copies this subdirectory when present.

Some grammars also include:

- **Sibling `.c`/`.h` files** (e.g. YAML includes `schema.core.c` etc.,
  HTML includes `tag.h`) — the script copies all such files in `src/`.
- **A shared `common/` directory** (e.g. XML shares `common/scanner.h`
  between its XML and DTD sub-parsers) — the script copies `common/` one
  level above `src/` and patches the include path from
  `"../../common/scanner.h"` to `"../common/scanner.h"` to match the
  flattened vendored layout.
