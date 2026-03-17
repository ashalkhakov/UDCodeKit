# TreeSitterXml Grammar Bundle

Standalone macOS loadable bundle that provides tree-sitter-based syntax
highlighting for **XML** files.

## Directory layout

```
tree-sitter-xml/
├── TreeSitterXml.xcodeproj/  # standalone Xcode project (open this to edit/build)
├── Sources/
│   ├── TreeSitterXmlPlugin.h  # principal class header
│   └── TreeSitterXmlPlugin.m  # principal class implementation
├── Resources/
│   ├── Info.plist           # bundle metadata (NSPrincipalClass etc.)
│   ├── LanguageInfo.plist   # language metadata read by UDLanguageModeRegistry
│   ├── highlights.scm       # tree-sitter highlights query (if present)
│   ├── indents.scm          # tree-sitter indents query (if present)
│   └── schemas/             # built-in RELAX NG schemas  ← in git
│       ├── xslt.rng         # XSLT 1.0 (James Clark, relaxng.org)
│       ├── svg.rng          # SVG 1.1 structural schema
│       └── xhtml/
│           ├── xhtml.rng    # XHTML (from jing-trang, relaxng.org)
│           └── modules/     # XHTML module schemas (28 files)
├── tree-sitter/             # tree-sitter runtime for this bundle  ← fetched by fetch-deps.sh
│   ├── include/             # public API headers
│   └── src/                 # runtime C sources (compiled via lib.c)
├── src/                     # grammar C sources  ← fetched by fetch-deps.sh
│   ├── parser.c             # generated parser (DO NOT EDIT — re-fetch to update)
- `src/scanner.c` — external scanner
│   └── tree_sitter_xml.h  # C header declaring the factory function
├── queries/                 # tree-sitter query files (source of truth for Resources/)
├── UPSTREAM                 # upstream URL + fetched commit SHA  ← fetched
├── fetch-deps.sh            # fetches all C dependencies  ← in git
└── README.md                # this file
```

## Upstream grammar

| Field  | Value |
|--------|-------|
| URL    | https://github.com/tree-sitter-grammars/tree-sitter-xml.git |
| Commit | `5000ae8f22d11fbe93939b05c1e37cf21117162d` |

## Fetching dependencies

Before building, fetch the tree-sitter runtime and grammar sources by running
`fetch-deps.sh` from the repository root or from within this directory:

```sh
# From the repository root
bash tree-sitter-xml/fetch-deps.sh

# From within this directory
bash fetch-deps.sh
```

The script:
1. Shallow-clones the tree-sitter runtime into `tree-sitter-xml/tree-sitter/`.
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
- `tree-sitter-xml/src/tree_sitter/parser.h` contains the `REDUCE` macro
  variant that matches LANGUAGE_VERSION in `src/parser.c`.
- The bundle builds cleanly in Xcode (open `TreeSitterXml.xcodeproj`).

## Building standalone

Open `tree-sitter-xml/TreeSitterXml.xcodeproj` in Xcode and press ⌘B.
The bundle product (`TreeSitterXml.bundle`) lands in the Xcode-derived-data
build directory.

To use the bundle in the TestApp, build via the top-level workspace
(`UDPieceTable.xcworkspace`) or `TestApp.xcodeproj` directly — it embeds all
bundles via its **Embed PlugIns** build phase.

## Principal class and lifecycle

The bundle's `NSPrincipalClass` is `TreeSitterXmlPlugin`.  When `UDLanguageModeRegistry`
loads the bundle it calls `-pluginDidLoad:`.  If the bundle is ever unloaded
`-pluginWillUnload:` is called first.

Language metadata (identifier, display name, file extensions, LSP language ID,
and query file names) is stored in `Resources/LanguageInfo.plist` and is read
by the host app *before* the bundle code runs, so no code executes prematurely.

## Built-in RELAX NG schemas

The bundle ships three well-known RELAX NG schemas under `Resources/schemas/`.
They are selected automatically — no `<?xml-model?>` processing instruction
is needed in the document.

### Schema selection

`TreeSitterXmlPlugin` inspects the first 2 KB of each opened document and
picks a schema according to the following rules (checked in priority order):

| Dialect  | Trigger (file extension **or** namespace URI in header) | Schema resource |
|----------|---------------------------------------------------------|-----------------|
| XSLT 1.0 | `.xsl`, `.xslt`, or `http://www.w3.org/1999/XSL/Transform` | `schemas/xslt.rng` |
| SVG 1.1  | `.svg`, or `http://www.w3.org/2000/svg` | `schemas/svg.rng` |
| XHTML    | `.xhtml`, or `http://www.w3.org/1999/xhtml` | `schemas/xhtml/xhtml.rng` |

An explicit `<?xml-model href="...">` processing instruction in the document
always takes precedence over the built-in selection.

### Schema sources

| Schema | Source |
|--------|--------|
| `schemas/xslt.rng` | James Clark's XSLT 1.0 RELAX NG grammar — originally published at `https://relaxng.org/jclark/xslt.rng` |
| `schemas/svg.rng` | Structural SVG 1.1 schema based on the W3C SVG 1.1 Second Edition Recommendation (`https://www.w3.org/TR/SVG11/`). Validates the root element, namespace, and common elements; uses an open content model for filter primitives and animation details. |
| `schemas/xhtml/xhtml.rng` | XHTML schema from the [jing-trang](https://github.com/relaxng/jing-trang) project, covering the union of XHTML Transitional and Frameset. Requires the 28 module files in `schemas/xhtml/modules/`. |
