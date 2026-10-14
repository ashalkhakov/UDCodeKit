# TreeSitterMarkdown Grammar Bundle

Standalone macOS loadable bundle that provides tree-sitter-based syntax
highlighting for **Markdown** files.

## Directory layout

```
tree-sitter-markdown/
├── TreeSitterMarkdown.xcodeproj/  # standalone Xcode project (open this to edit/build)
├── Sources/
│   ├── TreeSitterMarkdownPlugin.h  # principal class header
│   └── TreeSitterMarkdownPlugin.m  # principal class implementation
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
- `src/scanner.cc` — external scanner
│   └── tree_sitter_markdown.h  # C header declaring the factory function
├── queries/                 # tree-sitter query files (source of truth for Resources/)
├── UPSTREAM                 # upstream URL + fetched commit SHA  ← fetched
├── fetch-deps.sh            # fetches all C dependencies  ← in git
└── README.md                # this file
```

## Upstream grammar

| Field  | Value |
|--------|-------|
| URL    | https://github.com/ikatyang/tree-sitter-markdown.git |
| Commit | `8b8b77af0493e26d378135a3e7f5ae25b555b375` |

## Fetching dependencies

Before building, fetch the tree-sitter runtime and grammar sources by running
`fetch-deps.sh` from the repository root or from within this directory:

```sh
# From the repository root
bash tree-sitter-markdown/fetch-deps.sh

# From within this directory
bash fetch-deps.sh
```

The script:
1. Shallow-clones the tree-sitter runtime into `tree-sitter-markdown/tree-sitter/`.
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
- `tree-sitter-markdown/src/tree_sitter/parser.h` contains the `REDUCE` macro
  variant that matches LANGUAGE_VERSION in `src/parser.c`.
- The bundle builds cleanly in Xcode (open `TreeSitterMarkdown.xcodeproj`).

## Building standalone

Open `tree-sitter-markdown/TreeSitterMarkdown.xcodeproj` in Xcode and press ⌘B.
The bundle product (`TreeSitterMarkdown.bundle`) lands in the Xcode-derived-data
build directory.

To use the bundle in UDCode, build via the top-level workspace
(`UDPieceTable.xcworkspace`) or `UDCode.xcodeproj` directly — it embeds all
bundles via its **Embed PlugIns** build phase.

## Principal class and lifecycle

The bundle's `NSPrincipalClass` is `TreeSitterMarkdownPlugin`.  When `UDLanguageModeRegistry`
loads the bundle it calls `-pluginDidLoad:`.  If the bundle is ever unloaded
`-pluginWillUnload:` is called first.

Language metadata (identifier, display name, file extensions, LSP language ID,
and query file names) is stored in `Resources/LanguageInfo.plist` and is read
by the host app *before* the bundle code runs, so no code executes prematurely.
