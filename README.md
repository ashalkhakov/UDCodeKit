# UDPieceTable

A code editor in Objective-C (ARC) on AppKit: VS Code's text model ported
(piece tree, decorations, undo, search, multiple cursors), tree-sitter for
syntax highlighting, folding, auto-indent and parse errors, and an LSP client
for diagnostics, completion and hover.

It is being restructured into **UDCodeKit**: an editor library other
applications embed, and a VS Code-like application built on it, on macOS and
on GNUstep (Linux).

## Layout

- `UDPieceTable/` — the text model, `UDPieceTable.framework` (Foundation
  only): `UDPieceTree`, `UDTextModel` (edits, undo, decorations, search),
  `UDIntervalTree`, `UDCursorsController`.
- `Sources/` — the editor and the test application: the `NSTextStorage` over
  the text model, the text view, gutters, folding, the highlighters, language
  modes and their registry, the LSP coordinator.
- `LSPKit/` — the Language Server Protocol client (`LSPKit.framework`), after
  Christopher Atlan's LSPKit.
- `tree-sitter-<lang>/` — grammar bundles (bash, c, html, json, make,
  markdown, objc, xml, yaml), loaded by the application as plug-ins; see
  [docs/grammar-bundles.md](docs/grammar-bundles.md). `tree-sitter-sql/` is
  unfinished and not built: no SQL grammar found yet is both complete enough
  and small enough to embed.

## Building

The grammars' C sources and the tree-sitter runtime are fetched, not kept in
git:

```bash
bash scripts/update-grammars.sh     # every grammar bundle, and the shared runtime
```

Then open `UDPieceTable.xcworkspace`: the `TestApp` scheme builds the
application with its grammar bundles.

## Tests

- `UDPieceTable` scheme — the text model (`UDPieceTable/Tests`), including
  `UDComplexityTests`, which keep every hot path proportional to the edit or
  the result rather than to the document, and `UDReferenceTests`, which check
  the decoration tree and the undo bookkeeping against plain reference
  implementations.
- `TestApp` scheme, `TestAppTests` — the editor (`Tests/`): text storage,
  incremental parsing, auto-indent, language modes, documents.

```bash
xcodebuild -workspace UDPieceTable.xcworkspace -scheme UDPieceTable -destination 'platform=macOS' test
xcodebuild -workspace UDPieceTable.xcworkspace -scheme TestApp -destination 'platform=macOS' test -only-testing:TestAppTests
```

## License

MIT (`LICENSE.md`): the ported VS Code code is Microsoft's, under MIT. LSPKit,
the tree-sitter runtime and the upstream grammars are MIT as well.
