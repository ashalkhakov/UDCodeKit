# TreeSitterSql Grammar Bundle

Standalone macOS loadable bundle that provides tree-sitter-based syntax
highlighting for **SQL** files.

## Directory layout

```
tree-sitter-sql/
├── TreeSitterSql.xcodeproj/   # standalone Xcode project (open this to edit/build)
├── Sources/
│   ├── TreeSitterSqlPlugin.h  # principal class header
│   └── TreeSitterSqlPlugin.m  # principal class implementation
├── Resources/
│   ├── Info.plist           # bundle metadata (NSPrincipalClass etc.)
│   ├── LanguageInfo.plist   # language metadata read by UDLanguageModeRegistry
│   ├── highlights.scm       # tree-sitter highlights query (fetched by fetch-deps.sh)
│   └── indents.scm          # tree-sitter indents query (fetched by fetch-deps.sh)
├── tree-sitter/             # tree-sitter runtime for this bundle (fetched by fetch-deps.sh)
│   ├── include/             # public API headers
│   └── src/                 # runtime C sources (compiled via lib.c)
├── src/                     # grammar sources (fetched by fetch-deps.sh)
│   ├── parser.c             # generated parser (DO NOT EDIT — re-fetch to update)
│   └── tree_sitter_sql.h   # C header declaring the factory function
├── queries/                 # tree-sitter query files (fetched by fetch-deps.sh)
├── UPSTREAM                 # upstream git URL + fetched commit SHA
├── fetch-deps.sh            # script that fetches all dependencies
└── README.md                # this file
```

## Upstream grammar

| Field | Value |
|-------|-------|
| URL   | https://github.com/DerekStride/tree-sitter-sql |

## Fetching dependencies

Before building, fetch the tree-sitter runtime and grammar sources by running
`fetch-deps.sh` from the repository root or from within this directory:

```sh
# From the repository root
bash tree-sitter-sql/fetch-deps.sh

# From within this directory
bash fetch-deps.sh
```

The script:
1. Shallow-clones the tree-sitter runtime into `tree-sitter-sql/tree-sitter/`.
2. Shallow-clones the upstream grammar repository.
3. Copies `src/parser.c` and query files.
4. Writes `src/tree_sitter_sql.h` (factory function declaration).
5. Syncs query files into `Resources/`.
6. Writes `UPSTREAM` with the fetched commit SHA.

**After running the script**, build the bundle in Xcode:

```sh
open tree-sitter-sql/TreeSitterSql.xcodeproj
```

Or build via the top-level workspace (`UDPieceTable.xcworkspace`) which
embeds all bundles via its **Embed PlugIns** build phase.

## Building standalone

Open `tree-sitter-sql/TreeSitterSql.xcodeproj` in Xcode and press ⌘B.
The bundle product (`TreeSitterSql.bundle`) lands in the Xcode-derived-data
build directory.

## Principal class and lifecycle

The bundle's `NSPrincipalClass` is `TreeSitterSqlPlugin`.  When
`UDLanguageModeRegistry` loads the bundle it calls `-extensionDidLoad:`.  If
the bundle is ever unloaded `-extensionWillUnload:` is called first.

Language metadata (identifier, display name, file extensions, LSP language ID,
and query file names) is stored in `Resources/LanguageInfo.plist` and is read
by the host app *before* the bundle code runs, so no code executes prematurely.
