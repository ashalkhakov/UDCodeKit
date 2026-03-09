# Grammar Bundles

This document explains how tree-sitter grammar bundles are structured,
vendored, and kept up to date.

---

## Overview

Each grammar is a **self-contained subdirectory** at the repo root named
`tree-sitter-<lang>/`.  Every subdirectory contains:

- A standalone `TreeSitter<Lang>.xcodeproj` (editable and buildable in Xcode independently)
- A `Sources/` directory with an Objective-C **principal class** (`TreeSitter<Lang>Plugin`)
- A `Resources/` directory with language metadata (`LanguageInfo.plist`) and query files
- A per-bundle `tree-sitter/` runtime copy (split vendoring — tracked independently)
- The vendored grammar C sources in `src/`
- A `README.md` describing the directory layout and how to re-vendor

```
tree-sitter-<lang>/
├── TreeSitter<Lang>.xcodeproj/   # standalone Xcode project
├── Sources/
│   ├── TreeSitter<Lang>Plugin.h  # principal class header
│   └── TreeSitter<Lang>Plugin.m  # principal class implementation
├── Resources/
│   ├── Info.plist           # bundle metadata (NSPrincipalClass, bundle ID, …)
│   ├── LanguageInfo.plist   # language metadata (read without loading bundle code)
│   ├── highlights.scm       # tree-sitter highlights query (if present)
│   └── indents.scm          # tree-sitter indents query (if present)
├── tree-sitter/             # vendored tree-sitter runtime for this bundle
│   ├── include/             # public API headers
│   └── src/                 # runtime C sources (compiled via lib.c)
├── src/                     # vendored grammar sources
│   ├── parser.c             # generated C parser (DO NOT EDIT)
│   ├── scanner.c            # external scanner in C (optional)
│   ├── scanner.cc           # external scanner in C++ (optional)
│   ├── tree_sitter/         # grammar-specific runtime helper headers
│   └── tree_sitter_<lang>.h # header declaring the factory function
├── queries/                 # source of truth for .scm query files
├── UPSTREAM                 # upstream git URL + vendored commit SHA
└── README.md                # this bundle's documentation
```

## Bundled grammars

| Language     | Identifier  | Extensions                             | Upstream repository                                         |
|--------------|-------------|----------------------------------------|-------------------------------------------------------------|
| Bash         | `bash`      | `.sh` `.bash` `.zsh` `.ksh`            | https://github.com/tree-sitter/tree-sitter-bash             |
| C            | `c`         | `.c`                                   | https://github.com/tree-sitter/tree-sitter-c                |
| HTML         | `html`      | `.html` `.htm` `.xhtml` `.shtml`       | https://github.com/tree-sitter/tree-sitter-html             |
| JSON         | `json`      | `.json` `.jsonc` `.geojson`            | https://github.com/tree-sitter/tree-sitter-json             |
| Makefile     | `make`      | `.mk`                                  | https://github.com/alemuller/tree-sitter-make               |
| Markdown     | `markdown`  | `.md` `.markdown` `.mdown` `.mkd`      | https://github.com/ikatyang/tree-sitter-markdown            |
| Objective-C  | `objc`      | `.m` `.mm` `.h`                        | https://github.com/tree-sitter-grammars/tree-sitter-objc    |
| XML          | `xml`       | `.xml` `.xsl` `.svg` `.rss` `.plist`   | https://github.com/tree-sitter-grammars/tree-sitter-xml     |
| YAML         | `yaml`      | `.yaml` `.yml`                         | https://github.com/tree-sitter-grammars/tree-sitter-yaml    |

## Language metadata and the LanguageInfo.plist

`Resources/LanguageInfo.plist` carries all language metadata that
`UDLanguageModeRegistry` needs to create a `UDLanguageMode` object:

| Key                  | Type   | Description                                        |
|----------------------|--------|----------------------------------------------------|
| `identifier`         | String | Unique lowercase mode ID, e.g. `"bash"`            |
| `displayName`        | String | Human-readable name, e.g. `"Bash"`                 |
| `fileExtensions`     | Array  | Lowercase extensions without dot, e.g. `["sh"]`   |
| `lspLanguageID`      | String | Optional LSP `languageId`, e.g. `"shellscript"`    |
| `treeSitterSymbol`   | String | C symbol name, e.g. `"tree_sitter_bash"`           |
| `highlightsQueryFile`| String | Optional resource filename, e.g. `"highlights.scm"`|
| `indentsQueryFile`   | String | Optional resource filename, e.g. `"indents.scm"`   |

The host app reads this plist **before** loading the bundle's executable,
so no grammar code runs until the tree-sitter C symbol is actually needed.

## Principal class and lifecycle

Each bundle's `NSPrincipalClass` (set via `Resources/Info.plist`) is
`TreeSitter<Lang>Plugin`.  It exposes:

```objc
+ (instancetype)sharedPlugin;            // singleton accessor
- (void)pluginDidLoad:(NSBundle *)bundle;    // called by host after load
- (void)pluginWillUnload:(NSBundle *)bundle; // called before unload
```

`+load` is also implemented, so any image-level initialisation runs
automatically when the bundle is mapped into the process.

## Per-bundle tree-sitter runtime (split vendoring)

Each bundle directory contains its own copy of the tree-sitter runtime in
`tree-sitter-<lang>/tree-sitter/`.  This allows each bundle to track its own
runtime version independently while remaining ABI-compatible with the host.

The update script (`scripts/update-grammars.sh`) automatically copies the
shared `tree-sitter/` directory at the repo root into each bundle's
`tree-sitter/` after vendoring grammar sources.

## Updating a grammar bundle

Use the top-level update script to re-vendor one or more grammars:

```sh
# Update all bundled grammars
bash scripts/update-grammars.sh

# Update specific grammars only
bash scripts/update-grammars.sh c objc bash make
```

The script:

1. Shallow-clones (depth 1) the upstream repository.
2. Copies `src/parser.c`, `src/scanner.c` / `src/scanner.cc` (if present),
   and `src/tree_sitter/` headers.
3. Copies query `.scm` files into `tree-sitter-<lang>/queries/`.
4. Regenerates the `tree_sitter_<lang>.h` factory header.
5. Copies the shared `tree-sitter/` runtime into `tree-sitter-<lang>/tree-sitter/`.
6. Syncs query files into `tree-sitter-<lang>/Resources/` (bundle resources).
7. Writes `UPSTREAM` with the new commit SHA.

**After updating**, verify:
- The `REDUCE` macro variant in `src/tree_sitter/parser.h` matches the
  grammar's `LANGUAGE_VERSION`:
  - Version 13 → variadic `REDUCE(sym, children, ...)` (e.g. from markdown)
  - Version 14+ → fixed 4-arg `REDUCE(sym, children, precedence, prod_id)` (e.g. from html)
- The bundle builds in Xcode (open `TreeSitter<Lang>.xcodeproj`).
- Run the tests to confirm nothing regressed.

## Build system: per-language macOS bundles

### Standalone subprojects

Open any `tree-sitter-<lang>/TreeSitter<Lang>.xcodeproj` in Xcode to build
a single grammar bundle in isolation.  This is the recommended workflow for
iterating on a grammar's scanner or query files.

Each standalone project compiles:
- `tree-sitter/src/lib.c` — the tree-sitter runtime (per-bundle copy)
- `src/parser.c` — the generated grammar parser
- `src/scanner.c` or `src/scanner.cc` — the external scanner (when present)
- `Sources/TreeSitter<Lang>Plugin.m` — the principal class

### TestApp workspace

The full app build uses `UDPieceTable.xcworkspace`, which includes all 9
grammar subprojects in a "Grammar Bundles" group alongside the main
`TestApp.xcodeproj`.

`TestApp.xcodeproj` contains inline bundle targets that build each grammar
using the same per-bundle `tree-sitter-<lang>/` source tree.  At build time
Xcode copies all bundles into `TestApp.app/Contents/PlugIns/`.

### Bundle products

| Bundle name                | Grammar   | Exported symbol        |
|----------------------------|-----------|------------------------|
| `TreeSitterBash.bundle`    | bash      | `tree_sitter_bash`     |
| `TreeSitterC.bundle`       | c         | `tree_sitter_c`        |
| `TreeSitterHtml.bundle`    | html      | `tree_sitter_html`     |
| `TreeSitterJson.bundle`    | json      | `tree_sitter_json`     |
| `TreeSitterMake.bundle`    | make      | `tree_sitter_make`     |
| `TreeSitterMarkdown.bundle`| markdown  | `tree_sitter_markdown` |
| `TreeSitterObjc.bundle`    | objc      | `tree_sitter_objc`     |
| `TreeSitterXml.bundle`     | xml       | `tree_sitter_xml`      |
| `TreeSitterYaml.bundle`    | yaml      | `tree_sitter_yaml`     |

### Runtime loading

`UDLanguageModeRegistry` loads bundles at startup:

1. **Metadata phase** (no bundle code runs): reads `LanguageInfo.plist` and
   `.scm` query files using `NSBundle` resource-lookup APIs.
2. **Load phase**: calls `[bundle loadAndReturnError:]` then `dlsym` to
   resolve the tree-sitter C symbol.
3. **Lifecycle phase**: calls `[principalClass sharedPlugin]` then
   `-pluginDidLoad:` on the returned object.

If a bundle is missing at runtime the mode is silently omitted (no crash;
the plaintext fallback handles those file extensions).

## Adding a new grammar bundle

1. Add an entry to `GRAMMARS` in `scripts/update-grammars.sh` and run it:

   ```bash
   ["<id>"]="<git-url>|<src-subdir>|<queries-subdir>|<c-function-name>"
   bash scripts/update-grammars.sh <id>
   ```

2. The script creates `tree-sitter-<id>/` with all needed files.  Manually
   create the files not generated by the script:
   - `Sources/TreeSitter<Id>Plugin.{h,m}` — copy from an existing bundle and adapt
   - `Resources/Info.plist` — copy from an existing bundle and update identifiers
   - `TreeSitter<Id>.xcodeproj/` — copy from an existing bundle xcodeproj and update

3. Add a **bundle target** to `TestApp.xcodeproj` following the pattern of
   the other `CC0N…` targets (sources, resources, HEADER_SEARCH_PATHS,
   INFOPLIST_FILE, PRODUCT_BUNDLE_IDENTIFIER).

4. Add the bundle name to the `bundleNames` array in
   `Sources/Model/UDLanguageModeRegistry.m` and add a default
   new-document text entry to `sDefaultTexts()` if desired.

5. Add the new `tree-sitter-<id>/TreeSitter<Id>.xcodeproj` to the
   "Grammar Bundles" group in `UDPieceTable.xcworkspace`.

6. Add tests in `Tests/UDLanguageModeTests.m`.

## Notes on grammar versions and the REDUCE macro

Grammar parsers carry a `LANGUAGE_VERSION` constant.  The tree-sitter
runtime is generally backwards-compatible, but the `src/tree_sitter/parser.h`
shipped *by the grammar* must match the version used to generate `parser.c`:

| LANGUAGE_VERSION | REDUCE macro signature                          | Example grammar |
|------------------|-------------------------------------------------|-----------------|
| 13               | `REDUCE(sym, children, ...)` (variadic)         | make, markdown  |
| 14               | `REDUCE(sym, children, precedence, prod_id)`    | html, json, xml |
| 15               | `REDUCE(sym, children, precedence, prod_id)`    | bash, c, yaml   |

When the update script vendors a grammar and the upstream does not ship
`src/tree_sitter/parser.h`, you must manually supply the correct version.
Copy the appropriate file from an existing grammar's `src/tree_sitter/`
directory.
