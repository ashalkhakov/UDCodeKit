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
├── tree-sitter/             # vendored tree-sitter runtime for this bundle
│   ├── include/             # public API headers
│   └── src/                 # runtime C sources (compiled via lib.c)
├── src/                     # vendored grammar sources
│   ├── parser.c             # generated parser (DO NOT EDIT)
- `src/scanner.cc` — external scanner
│   └── tree_sitter_markdown.h  # C header declaring the factory function
├── queries/                 # tree-sitter query files (source of truth for Resources/)
├── UPSTREAM                 # upstream git URL + vendored commit SHA
└── README.md                # this file
```

## Upstream grammar

| Field  | Value |
|--------|-------|
| URL    | https://github.com/ikatyang/tree-sitter-markdown.git |
| Commit | `8b8b77af0493e26d378135a3e7f5ae25b555b375` |

## Re-vendoring grammar sources

To update the grammar sources to the latest upstream commit, run the
top-level update script from the repository root:

```sh
# Update only this grammar
bash scripts/update-grammars.sh markdown

# Update all grammars
bash scripts/update-grammars.sh
```

The script will:
1. Shallow-clone the upstream repository.
2. Copy `src/parser.c`, `src/scanner.c`/`.cc` (if present), and query files.
3. Copy `src/tree_sitter/` headers (grammar-specific runtime headers).
4. Rewrite the `UPSTREAM` provenance file with the new commit SHA.
5. Copy the tree-sitter runtime into `tree-sitter-markdown/tree-sitter/` so this
   bundle is self-contained.

**After running the script**, verify:
- `tree-sitter-markdown/src/tree_sitter/parser.h` contains the `REDUCE` macro
  variant that matches LANGUAGE_VERSION in `src/parser.c`.
- The bundle builds cleanly in Xcode (open `TreeSitterMarkdown.xcodeproj`).

## Building standalone

Open `tree-sitter-markdown/TreeSitterMarkdown.xcodeproj` in Xcode and press ⌘B.
The bundle product (`TreeSitterMarkdown.bundle`) lands in the Xcode-derived-data
build directory.

To use the bundle in the TestApp, build via the top-level workspace
(`UDPieceTable.xcworkspace`) or `TestApp.xcodeproj` directly — it embeds all
bundles via its **Embed PlugIns** build phase.

## Principal class and lifecycle

The bundle's `NSPrincipalClass` is `TreeSitterMarkdownPlugin`.  When `UDLanguageModeRegistry`
loads the bundle it calls `-pluginDidLoad:`.  If the bundle is ever unloaded
`-pluginWillUnload:` is called first.

Language metadata (identifier, display name, file extensions, LSP language ID,
and query file names) is stored in `Resources/LanguageInfo.plist` and is read
by the host app *before* the bundle code runs, so no code executes prematurely.
