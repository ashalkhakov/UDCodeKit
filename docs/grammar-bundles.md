# Grammar Bundles

This document explains how tree-sitter grammar bundles are structured,
vendored, and kept up to date.

---

## Overview

Each grammar is a **self-contained subdirectory** at the repo root named
`tree-sitter-<lang>/`.  Every subdirectory contains:

- A standalone `TreeSitter<Lang>.xcodeproj` (editable and buildable in Xcode independently)
- A `Sources/` directory with an Objective-C **principal class** (`TreeSitter<Lang>Plugin`)
  that conforms to the `UDExtension` protocol
- A `Resources/` directory with language metadata (`LanguageInfo.plist`) and query files
- A per-bundle `tree-sitter/` runtime copy (split vendoring — tracked independently)
- The vendored grammar C sources in `src/`
- A `README.md` describing the directory layout and how to re-vendor

```
tree-sitter-<lang>/
├── TreeSitter<Lang>.xcodeproj/   # standalone Xcode project
├── Sources/
│   ├── TreeSitter<Lang>Plugin.h  # principal class header (conforms to UDExtension)
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
| C            | `c`         | `.c` `.h`                              | https://github.com/tree-sitter/tree-sitter-c                |
| HTML         | `html`      | `.html` `.htm` `.xhtml` `.shtml`       | https://github.com/tree-sitter/tree-sitter-html             |
| JSON         | `json`      | `.json` `.jsonc` `.geojson`            | https://github.com/tree-sitter/tree-sitter-json             |
| Makefile     | `make`      | `.mk`                                  | https://github.com/alemuller/tree-sitter-make               |
| Markdown     | `markdown`  | `.md` `.markdown` `.mdown` `.mkd`      | https://github.com/ikatyang/tree-sitter-markdown            |
| Objective-C  | `objc`      | `.m` `.mm` `.h`                        | https://github.com/tree-sitter-grammars/tree-sitter-objc    |
| XML          | `xml`       | `.xml` `.xsl` `.svg` `.rss` `.plist`   | https://github.com/tree-sitter-grammars/tree-sitter-xml     |
| YAML         | `yaml`      | `.yaml` `.yml`                         | https://github.com/tree-sitter-grammars/tree-sitter-yaml    |

---

## The UDExtension protocol

Each bundle's `NSPrincipalClass` conforms to the `UDExtension` protocol
(defined in `Sources/Extensions/UDExtension.h`):

```objc
@protocol UDExtension <NSObject>
- (void)extensionDidLoad:(NSBundle *)bundle;
- (void)extensionWillUnload:(NSBundle *)bundle;
- (nullable const void *)languageFuncForIdentifier:(NSString *)identifier;
@end
```

### Multiple language modes per extension

An extension may declare **zero, one, or multiple** language modes in its
`LanguageInfo.plist` (via the `languageModes` array).  For each mode, the
registry calls `-languageFuncForIdentifier:` with the mode's `identifier`
string to obtain the tree-sitter C factory pointer.

Non-language extensions (e.g. future theme or snippet bundles) declare an
empty `languageModes` array and always return `NULL` from
`-languageFuncForIdentifier:`.

### Lifecycle hooks

| Call         | When                                                   |
|--------------|--------------------------------------------------------|
| `-extensionDidLoad:`    | After the bundle is loaded; perform initialisation |
| `-extensionWillUnload:` | Before the app terminates; release resources       |

**Non-deterministic teardown:** The host calls `-extensionWillUnload:` and
then releases its strong reference to the extension instance.  Because
Objective-C uses reference counting, other retain cycles or autorelease pools
may keep extension objects alive for an indeterminate time after the call
returns.  `NSBundle` does not unload the bundle's Mach-O image, so C code
compiled into the bundle remains mapped into memory indefinitely.
`-dealloc` implementations in extension classes may therefore run *after*
`-extensionWillUnload:` has returned — do not rely on any specific teardown
order.

---

## Language metadata: `LanguageInfo.plist`

Each bundle's `Resources/LanguageInfo.plist` contains a `languageModes` array.
Every element describes one language mode the extension provides:

```xml
<dict>
    <key>languageModes</key>
    <array>
        <dict>
            <!-- Required fields -->
            <key>identifier</key>        <string>bash</string>
            <key>displayName</key>       <string>Bash</string>
            <key>fileExtensions</key>    <array><string>sh</string></array>

            <!-- Optional fields -->
            <key>lspLanguageID</key>     <string>shellscript</string>
            <key>highlightsQueryFile</key><string>highlights.scm</string>
            <key>indentsQueryFile</key>  <string>indents.scm</string>

            <!-- Language configuration (see below) -->
            <key>comments</key>    <dict>…</dict>
            <key>brackets</key>    <array>…</array>
            <key>autoClosingPairs</key><array>…</array>
            <key>autoCloseBefore</key><string>…</string>
            <key>surroundingPairs</key><array>…</array>
            <key>folding</key>     <dict>…</dict>
        </dict>
    </array>
</dict>
```

> **Note:** The `treeSitterSymbol` key used in earlier versions has been
> removed.  The tree-sitter C factory is now obtained by calling
> `-languageFuncForIdentifier:` on the extension instance.

The host app reads the plist and loads query files **before** executing any
bundle code, so metadata is available without triggering any grammar initialisation.

### LanguageInfo.plist — required fields

| Key             | Type   | Description                                               |
|-----------------|--------|-----------------------------------------------------------|
| `identifier`    | String | Unique lowercase mode ID, e.g. `"bash"`                   |
| `displayName`   | String | Human-readable name, e.g. `"Bash"`                        |
| `fileExtensions`| Array  | Lowercase extensions without dot, e.g. `["sh"]`           |

### LanguageInfo.plist — optional grammar fields

| Key                   | Type   | Description                                              |
|-----------------------|--------|----------------------------------------------------------|
| `lspLanguageID`       | String | LSP `languageId` (e.g. `"shellscript"`)                  |
| `highlightsQueryFile` | String | Resource filename, e.g. `"highlights.scm"`               |
| `indentsQueryFile`    | String | Resource filename, e.g. `"indents.scm"`                  |

---

## Language configuration

The language configuration is embedded directly inside each mode entry in
`LanguageInfo.plist`.  It is loaded into a `UDLanguageConfiguration` object
and made available via `UDLanguageMode.languageConfiguration`.

### `comments`

```xml
<key>comments</key>
<dict>
    <key>lineComment</key>   <string>//</string>
    <key>blockComment</key>
    <array>
        <string>/*</string>
        <string>*/</string>
    </array>
</dict>
```

| Sub-key        | Type   | Description                          |
|----------------|--------|--------------------------------------|
| `lineComment`  | String | Single-line comment prefix (`//`, `#`) |
| `blockComment` | Array  | Two-element `[start, end]` pair       |

### `brackets`

```xml
<key>brackets</key>
<array>
    <array><string>{</string><string>}</string></array>
    <array><string>[</string><string>]</string></array>
    <array><string>(</string><string>)</string></array>
</array>
```

Each element is a two-element `[open, close]` array.  Used by the auto-indenter
for electric-pair indentation and by the bracket-match highlighter.

### `autoClosingPairs`

```xml
<key>autoClosingPairs</key>
<array>
    <dict>
        <key>open</key>  <string>{</string>
        <key>close</key> <string>}</string>
    </dict>
    <dict>
        <key>open</key>  <string>"</string>
        <key>close</key> <string>"</string>
        <key>notIn</key>
        <array><string>string</string></array>
    </dict>
</array>
```

| Key     | Type   | Description                                              |
|---------|--------|----------------------------------------------------------|
| `open`  | String | The character that triggers auto-closing                 |
| `close` | String | The character that is auto-inserted                      |
| `notIn` | Array  | Tree-sitter node-type contexts to suppress auto-close in |

### `autoCloseBefore`

```xml
<key>autoCloseBefore</key>
<string>;:.,=}])`"' &#x0A;&#x09;</string>
```

Characters to the right of the cursor that permit an auto-close to occur.

### `surroundingPairs`

```xml
<key>surroundingPairs</key>
<array>
    <array><string>{</string><string>}</string></array>
    <array><string>"</string><string>"</string></array>
</array>
```

Pairs of characters that can wrap a selected range.  Same format as `brackets`.

### `folding`

```xml
<key>folding</key>
<dict>
    <key>markers</key>
    <dict>
        <key>start</key> <string>^\s*//\s*#region\b</string>
        <key>end</key>   <string>^\s*//\s*#endregion\b</string>
    </dict>
</dict>
```

Regular-expression patterns marking the beginning and end of foldable regions
(for languages that use comment-based fold markers rather than structural folding).

---

## Principal class and lifecycle

Each bundle's `NSPrincipalClass` (set via `Resources/Info.plist`) is
`TreeSitter<Lang>Plugin`, which conforms to `UDExtension`:

```objc
// In TreeSitter<Lang>Plugin.m
- (void)extensionDidLoad:(NSBundle *)bundle { … }
- (void)extensionWillUnload:(NSBundle *)bundle { … }
- (nullable const void *)languageFuncForIdentifier:(NSString *)identifier {
    if ([identifier isEqualToString:@"<lang>"]) return tree_sitter_<lang>;
    return NULL;
}
```

The host calls `-extensionWillUnload:` for all loaded bundles in reverse load
order when `[UDLanguageModeRegistry sharedRegistry] unloadAllExtensions` is
called from `-applicationWillTerminate:`.

---

## Per-bundle tree-sitter runtime (split vendoring)

Each bundle directory contains its own copy of the tree-sitter runtime in
`tree-sitter-<lang>/tree-sitter/`.  This allows each bundle to track its own
runtime version independently while remaining ABI-compatible with the host.

The update script (`scripts/update-grammars.sh`) automatically copies the
shared `tree-sitter/` directory at the repo root into each bundle's
`tree-sitter/` after vendoring grammar sources.

---

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

---

## Build system: per-language macOS bundles

### Standalone subprojects

Open any `tree-sitter-<lang>/TreeSitter<Lang>.xcodeproj` in Xcode to build
a single grammar bundle in isolation.  This is the recommended workflow for
iterating on a grammar's scanner or query files.

Each standalone project compiles:
- `tree-sitter/src/lib.c` — the tree-sitter runtime (per-bundle copy)
- `src/parser.c` — the generated grammar parser
- `src/scanner.c` or `src/scanner.cc` — the external scanner (when present)
- `Sources/TreeSitter<Lang>Plugin.m` — the principal class (conforms to UDExtension)

### TestApp workspace

The full app build uses `UDPieceTable.xcworkspace`, which includes all 9
grammar subprojects in a "Grammar Bundles" group alongside the main
`TestApp.xcodeproj`.

### Runtime loading

`UDLanguageModeRegistry` loads bundles at startup:

1. **Metadata phase** (no bundle code runs): reads `LanguageInfo.plist` and
   `.scm` query files using `NSBundle` resource-lookup APIs.
2. **Load phase**: calls `[bundle loadAndReturnError:]` to map the bundle image.
3. **Lifecycle phase**: instantiates the principal class, calls
   `-extensionDidLoad:`, then calls `-languageFuncForIdentifier:` for each
   mode declared in the plist.
4. **Language configuration**: the `UDLanguageConfiguration` object is
   populated from the mode's dictionary in `LanguageInfo.plist` and stored
   on the `UDLanguageMode` object.

If a bundle is missing at runtime the mode is silently omitted (no crash;
the plaintext fallback handles those file extensions).

---

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
   - Add language configuration to `Resources/LanguageInfo.plist`

3. Add a **bundle target** to `TestApp.xcodeproj` following the pattern of
   the other `CC0N…` targets (sources, resources, HEADER_SEARCH_PATHS,
   INFOPLIST_FILE, PRODUCT_BUNDLE_IDENTIFIER).

4. Add the bundle name to the `bundleNames` array in
   `Sources/Model/UDLanguageModeRegistry.m` and add a default
   new-document text entry to `sDefaultTexts()` if desired.

5. Add the new `tree-sitter-<id>/TreeSitter<Id>.xcodeproj` to the
   "Grammar Bundles" group in `UDPieceTable.xcworkspace`.

---

## Notes on grammar versions and the REDUCE macro

Grammar parsers carry a `LANGUAGE_VERSION` constant.  The `src/tree_sitter/parser.h`
shipped *by the grammar* must match the version used to generate `parser.c`:

| LANGUAGE_VERSION | REDUCE macro signature                          | Example grammar |
|------------------|-------------------------------------------------|-----------------|
| 13               | `REDUCE(sym, children, ...)` (variadic)         | make, markdown  |
| 14               | `REDUCE(sym, children, precedence, prod_id)`    | html, json, xml |
| 15               | `REDUCE(sym, children, precedence, prod_id)`    | bash, c, yaml   |

When the update script vendors a grammar and the upstream does not ship
`src/tree_sitter/parser.h`, copy the appropriate version from an existing
grammar's `src/tree_sitter/` directory.
