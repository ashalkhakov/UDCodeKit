# TreeSitterC Grammar Bundle

Standalone macOS loadable bundle that provides tree-sitter-based syntax
highlighting for **C** files.

## Directory layout

```
tree-sitter-c/
├── TreeSitterC.xcodeproj/  # standalone Xcode project (open this to edit/build)
├── Sources/
│   ├── TreeSitterCPlugin.h  # principal class header
│   └── TreeSitterCPlugin.m  # principal class implementation
├── Resources/
│   ├── Info.plist           # bundle metadata (NSPrincipalClass etc.)
│   ├── LanguageInfo.plist   # language metadata read by UDLanguageModeRegistry
│   ├── highlights.scm       # tree-sitter highlights query (if present)
│   └── indents.scm          # tree-sitter indents query (if present)
├── tree-sitter/             # vendored tree-sitter runtime for this bundle
│   ├── include/             # public API headers
│   └── src/                 # runtime C sources (compiled via lib.c)
├── src/                     # vendored grammar sources
│   ├── parser.c             # generated parser (DO NOT EDIT)
│   └── tree_sitter_c.h  # C header declaring the factory function
├── queries/                 # tree-sitter query files (source of truth for Resources/)
├── UPSTREAM                 # upstream git URL + vendored commit SHA
└── README.md                # this file
```

## Upstream grammar

| Field  | Value |
|--------|-------|
| URL    | https://github.com/tree-sitter/tree-sitter-c.git |
| Commit | `ae19b676b13bdcc13b7665397e6d9b14975473dd` |

## Re-vendoring grammar sources

To update the grammar sources to the latest upstream commit, run the
top-level update script from the repository root:

```sh
# Update only this grammar
bash scripts/update-grammars.sh c

# Update all grammars
bash scripts/update-grammars.sh
```

The script will:
1. Shallow-clone the upstream repository.
2. Copy `src/parser.c`, `src/scanner.c`/`.cc` (if present), and query files.
3. Copy `src/tree_sitter/` headers (grammar-specific runtime headers).
4. Rewrite the `UPSTREAM` provenance file with the new commit SHA.
5. Copy the tree-sitter runtime into `tree-sitter-c/tree-sitter/` so this
   bundle is self-contained.

**After running the script**, verify:
- `tree-sitter-c/src/tree_sitter/parser.h` contains the `REDUCE` macro
  variant that matches LANGUAGE_VERSION in `src/parser.c`.
- The bundle builds cleanly in Xcode (open `TreeSitterC.xcodeproj`).

## Building standalone

Open `tree-sitter-c/TreeSitterC.xcodeproj` in Xcode and press ⌘B.
The bundle product (`TreeSitterC.bundle`) lands in the Xcode-derived-data
build directory.

To use the bundle in the TestApp, build via the top-level workspace
(`UDPieceTable.xcworkspace`) or `TestApp.xcodeproj` directly — it embeds all
bundles via its **Embed PlugIns** build phase.

## Principal class and lifecycle

The bundle's `NSPrincipalClass` is `TreeSitterCPlugin`.  When `UDLanguageModeRegistry`
loads the bundle it calls `-pluginDidLoad:`.  If the bundle is ever unloaded
`-pluginWillUnload:` is called first.

Language metadata (identifier, display name, file extensions, LSP language ID,
and query file names) is stored in `Resources/LanguageInfo.plist` and is read
by the host app *before* the bundle code runs, so no code executes prematurely.
