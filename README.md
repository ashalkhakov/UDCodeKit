# UDPieceTable

A code editor in Objective-C (ARC) on AppKit: VS Code's text model ported
(piece tree, decorations, undo, search, multiple cursors), tree-sitter for
syntax highlighting, folding, auto-indent and parse errors, an LSP client
for diagnostics, completion and hover, and a debugger with Xcode's UI and VS
Code's features over any Debug Adapter Protocol adapter.

It is being restructured into **UDCodeKit**: an editor library other
applications embed, and a VS Code-like application built on it, on macOS and
on GNUstep (Linux).

## Layout

- `UDPieceTable/` — the text model, `UDPieceTable.framework` (Foundation
  only): `UDPieceTree`, `UDTextModel` (edits, undo, decorations, search),
  `UDIntervalTree`, `UDCursorsController`.
- `UDCodeKit/` — the editor, `UDCodeKit.framework`, for applications to
  embed: the `NSTextStorage` over the text model, the editor view controller
  with its text view, gutters and folding, the highlighters, language modes
  and their registry, the LSP coordinator, and `UDEditorSession`, which ties
  one document's services together. It compiles the tree-sitter runtime in;
  only the umbrella header `<UDCodeKit/UDCodeKit.h>` and the headers it
  names are public. It also has what an Xcode-like window is made of:
  `UDPaneSplitController` (navigator | editors | inspector, panes that keep
  their size, hide, and are remembered), `UDEditorTabsController` with
  `UDTabBarView` (editor tabs), and the find and replace bar. And the
  debugger (`Debug/`): `UDBreakpointStore`, `UDDebugSession`, the debug bar,
  the debug and breakpoint navigators, the debug area with its watch
  expressions, the breakpoint editor and the debug hover, as VS Code's
  debugging behaves; see [docs/debugging.md](docs/debugging.md). Every view
  is in a XIB.
- `Sources/` — the test application on top of it: documents, workspaces,
  tabs, the issues pane, the debugger, and a demo debug adapter (`UDCode
  --debug-adapter`, `Sources/Debug/`).
- `LSPKit/` — the Language Server Protocol client (`LSPKit.framework`), after
  Christopher Atlan's LSPKit; the Debug Adapter Protocol client
  (`DAPClient`); and the Content-Length transport both use (`LSPTransport`).
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

Then open `UDPieceTable.xcworkspace`: the `UDCodeKit` scheme builds the
framework, and the `UDCode` scheme builds the application with the
frameworks and grammar bundles embedded.

On GNUstep, with `GNUstep.sh` sourced, `make` at the root builds the same out
of the tree, under `build/gnustep/`: the three frameworks, the grammar
bundles and `UDCode.app` with the bundles in its `PlugIns` folder. It wants
the patched stack from
[gnustep-patches](https://github.com/ashalkhakov/gnustep-patches) (view-based
tables load their prototype cells from a XIB there).

## Tests

- `UDPieceTable` scheme — the text model (`UDPieceTable/Tests`), including
  `UDComplexityTests`, which keep every hot path proportional to the edit or
  the result rather than to the document, and `UDReferenceTests`, which check
  the decoration tree and the undo bookkeeping against plain reference
  implementations.
- `UDCode` scheme, `UDCodeTests` — the editor (`Tests/`): text storage,
  incremental parsing and highlighting, parse errors, folding, find and
  replace, auto-indent, language modes, documents; `UDEditorComplexityTests`
  for the editor's hot paths; the find bar and the workspace window driven
  in-process; and the debugger: the transport and `DAPClient`, the
  breakpoint store and the session against the demo adapter (in-process
  over pipes, and as a process), and its UI in the workspace window.

```bash
xcodebuild -workspace UDPieceTable.xcworkspace -scheme UDPieceTable -destination 'platform=macOS' test
xcodebuild -workspace UDPieceTable.xcworkspace -scheme UDCode -destination 'platform=macOS' test
make check      # GNUstep: both suites, under Xvfb when there is no display
```

On GNUstep the editor's tests run without a host application: the
`UDCodeTests` bundle compiles in UDCode's sources (all but `main.m`) and its
XIBs, and finds the grammars through `$UD_PLUGINS_PATH`, which `make check`
points at the `UDCode.app` it built.

## Releases

`.github/workflows/build.yml` builds every push with gnustep-release-actions,
the familiar way on each system (`make`, `make check`, `make install` on
GNUstep; `make -f Makefile.apple` and the same targets on macOS), on what
`.github/pins.env` names. It publishes UDCodeKit as a library (the installed
frameworks and grammar bundles for Linux; UDPieceTable, LSPKit and UDCodeKit
as XCFrameworks for Apple) and UDCode as an AppImage and a Mac app; a `v*`
tag releases them, the Mac app signed, notarized and updated by Sparkle.

## License

MIT (`LICENSE.md`): the ported VS Code code is Microsoft's, under MIT. LSPKit,
the tree-sitter runtime and the upstream grammars are MIT as well.
