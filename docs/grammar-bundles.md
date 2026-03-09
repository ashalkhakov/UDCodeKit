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

## Build system: per-language macOS bundles

Each grammar is compiled as a standalone **macOS loadable bundle**
(`*.bundle`) rather than being compiled directly into the main app.  The
bundle contains both the tree-sitter runtime (`lib.c`) and the grammar
sources (`parser.c`, `scanner.c`/`scanner.cc`), making it completely
self-contained.

### Why bundles?

Bundling each grammar separately solves two problems that arise when all
grammars share a single compilation unit:

1. **Header shadowing** — different grammar versions ship different copies of
   `src/tree_sitter/parser.h`.  When all grammar `src/` directories are
   listed in a shared `HEADER_SEARCH_PATHS`, the first matching copy wins
   for every file.  Per-bundle compilation gives each grammar an isolated
   search path.
2. **ABI versioning** — grammars generated with tree-sitter ≥ 0.25 use a
   new `TSLanguage` ABI (version 15) that differs from earlier grammars.
   Because each bundle links its own copy of the runtime, the runtime and
   grammar always match.

### Bundle products

| Bundle name               | Grammar    | Exported symbol        |
|---------------------------|------------|------------------------|
| `TreeSitterBash.bundle`   | bash       | `tree_sitter_bash`     |
| `TreeSitterC.bundle`      | c          | `tree_sitter_c`        |
| `TreeSitterHtml.bundle`   | html       | `tree_sitter_html`     |
| `TreeSitterJson.bundle`   | json       | `tree_sitter_json`     |
| `TreeSitterMake.bundle`   | make       | `tree_sitter_make`     |
| `TreeSitterMarkdown.bundle`| markdown  | `tree_sitter_markdown` |
| `TreeSitterObjc.bundle`   | objc       | `tree_sitter_objc`     |
| `TreeSitterXml.bundle`    | xml        | `tree_sitter_xml`      |
| `TreeSitterYaml.bundle`   | yaml       | `tree_sitter_yaml`     |

At build time Xcode copies all bundles into `TestApp.app/Contents/PlugIns/`
via an **Embed PlugIns** copy-files phase on the TestApp target.

### Xcode targets per bundle

Each bundle target in `TestApp.xcodeproj` has:

| Setting                 | Value                                                     |
|-------------------------|-----------------------------------------------------------|
| Product type            | `com.apple.product-type.bundle`                           |
| Source files            | `tree-sitter/src/lib.c`, `tree-sitter-<lang>/src/parser.c`, (optional scanner) |
| `HEADER_SEARCH_PATHS`   | `$(SRCROOT)/tree-sitter/include`, `$(SRCROOT)/tree-sitter/src`, `$(SRCROOT)/tree-sitter-<lang>/src` |
| `PRODUCT_BUNDLE_IDENTIFIER` | `org.underivable.treesitter.<lang>`                  |
| `WRAPPER_EXTENSION`     | `bundle`                                                  |

### Runtime loading

`UDLanguageModeRegistry` loads each bundle from the app's `PlugIns` directory
at startup using `NSBundle` + `dlsym`:

```objc
NSString *plugInsPath = [[NSBundle mainBundle] builtInPlugInsPath];
NSBundle *bundle = [NSBundle bundleWithPath:
    [plugInsPath stringByAppendingPathComponent:@"TreeSitterBash.bundle"]];
[bundle load];
// resolve the C factory function
LanguageFunc f = (LanguageFunc)(uintptr_t)dlsym(
    dlopen(bundle.executablePath.fileSystemRepresentation, RTLD_NOW|RTLD_GLOBAL),
    "tree_sitter_bash");
```

If a bundle is missing at runtime the mode still registers but with
`languageFunc == NULL` (plain-text fallback).

## Adding a new grammar bundle

1. **Add an entry** to the `GRAMMARS` associative array in
   `scripts/update-grammars.sh` and run it to vendor the files:

   ```bash
   ["<id>"]="<git-url>|<src-subdir>|<queries-subdir>|<c-function-name>"
   ```

   Then run:

   ```sh
   bash scripts/update-grammars.sh <id>
   ```

2. **Add a bundle target** to `TestApp.xcodeproj`:
   - New `PBXNativeTarget` with product type `com.apple.product-type.bundle`
   - Sources build phase: `tree-sitter/src/lib.c` + grammar source files
   - `HEADER_SEARCH_PATHS`: `tree-sitter/include`, `tree-sitter/src`,
     `tree-sitter-<lang>/src`
   - `PRODUCT_NAME`: `TreeSitter<Lang>` (PascalCase)
   - Add as a dependency of TestApp and add to the Embed PlugIns copy-files phase

3. **Register the mode** in `Sources/Model/UDLanguageModeRegistry.m`:

   ```objc
   UDLanguageMode *myLang = [[UDLanguageMode alloc]
       initWithIdentifier:@"<id>"
              displayName:@"My Language"
           fileExtensions:@[@"ext"]
             languageFunc:[self _langFuncNamed:"tree_sitter_<id>"
                                   bundleName:@"TreeSitter<Lang>.bundle"]
          highlightsQuery:kMyLangHighlightsQuery
             indentsQuery:nil
            lspLanguageID:nil
   defaultNewDocumentText:@""];
   [self _registerModeUnsafe:myLang];
   ```

4. **Add tests** in `Tests/UDLanguageModeTests.m`.


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
