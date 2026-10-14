# TreeSitterJson Grammar Bundle

Standalone macOS loadable bundle that provides tree-sitter-based syntax
highlighting for **JSON** files.

## Directory layout

```
tree-sitter-json/
├── TreeSitterJson.xcodeproj/  # standalone Xcode project (open this to edit/build)
├── Sources/
│   ├── TreeSitterJsonPlugin.h  # principal class header
│   └── TreeSitterJsonPlugin.m  # principal class implementation
├── Resources/
│   ├── Info.plist           # bundle metadata (NSPrincipalClass etc.)
│   ├── LanguageInfo.plist   # language metadata read by UDLanguageModeRegistry
│   ├── highlights.scm       # tree-sitter highlights query (if present)
│   └── indents.scm          # tree-sitter indents query (if present)
├── tree-sitter/             # tree-sitter runtime for this bundle  ← fetched by fetch-deps.sh
│   ├── include/             # public API headers
│   └── src/                 # runtime C sources (compiled via lib.c)
├── src/                     # grammar C sources  ← fetched by fetch-deps.sh
│   ├── parser.c             # generated parser (DO NOT EDIT — re-fetch to update)
│   └── tree_sitter_json.h  # C header declaring the factory function
├── queries/                 # tree-sitter query files (source of truth for Resources/)
├── UPSTREAM                 # upstream URL + fetched commit SHA  ← fetched
├── fetch-deps.sh            # fetches all C dependencies  ← in git
└── README.md                # this file
```

## Upstream grammar

| Field  | Value |
|--------|-------|
| URL    | https://github.com/tree-sitter/tree-sitter-json.git |
| Commit | `001c28d7a29832b06b0e831ec77845553c89b56d` |

## Fetching dependencies

Before building, fetch the tree-sitter runtime and grammar sources by running
`fetch-deps.sh` from the repository root or from within this directory:

```sh
# From the repository root
bash tree-sitter-json/fetch-deps.sh

# From within this directory
bash fetch-deps.sh
```

The script:
1. Shallow-clones the tree-sitter runtime into `tree-sitter-json/tree-sitter/`.
2. Shallow-clones the upstream grammar repository.
3. Copies `src/parser.c`, `src/scanner.c`/`.cc` (if present), and query files.
4. Copies `src/tree_sitter/` headers (grammar-specific runtime headers).
5. Writes `UPSTREAM` with the fetched commit SHA.
6. Syncs query files into `Resources/`.

To update all grammars at once:

```sh
bash scripts/update-grammars.sh
```

**After fetching**, verify:
- `tree-sitter-json/src/tree_sitter/parser.h` contains the `REDUCE` macro
  variant that matches LANGUAGE_VERSION in `src/parser.c`.
- The bundle builds cleanly in Xcode (open `TreeSitterJson.xcodeproj`).

## Building standalone

Open `tree-sitter-json/TreeSitterJson.xcodeproj` in Xcode and press ⌘B.
The bundle product (`TreeSitterJson.bundle`) lands in the Xcode-derived-data
build directory.

To use the bundle in UDCode, build via the top-level workspace
(`UDPieceTable.xcworkspace`) or `UDCode.xcodeproj` directly — it embeds all
bundles via its **Embed PlugIns** build phase.

## Principal class and lifecycle

The bundle's `NSPrincipalClass` is `TreeSitterJsonPlugin`.  When `UDLanguageModeRegistry`
loads the bundle it calls `-pluginDidLoad:`.  If the bundle is ever unloaded
`-pluginWillUnload:` is called first.

Language metadata (identifier, display name, file extensions, LSP language ID,
and query file names) is stored in `Resources/LanguageInfo.plist` and is read
by the host app *before* the bundle code runs, so no code executes prematurely.
