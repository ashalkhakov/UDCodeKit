# UDCodeKit and VS Code

UDCodeKit follows VS Code where VS Code set the standard (its protocols, its
editor's data structures, its debugging behaviour) and follows Xcode for the
look. It is a native AppKit library for macOS and GNUstep, small enough to be
embedded: UDCode is one app on it, Quarry (UDQuakeTools) another.

## Side by side

| | VS Code | UDCodeKit | |
|---|---|---|---|
| **UI** | Electron, a web page (the workbench) | AppKit on macOS, GNUstep's AppKit on Linux; every view from a XIB | different by design |
| **Layout** | activity bar, side bar, editor groups, panel | Xcode's: navigator, editors and tabs, inspector, debug area | different by design |
| **Text model** | piece tree (a piece table in a red-black tree) | `UDPieceTable`: the same, ported; every edit costs the edit, tested for it (`UDComplexityTests`) | same |
| **Highlighting** | TextMate grammars, then semantic tokens from the language server | tree-sitter grammars and queries (`highlights.scm`), incremental | different: tree-sitter is the newer way (Zed, Neovim, Helix) |
| **Language configuration** | `language-configuration.json`: comments, brackets, auto-closing, indentation | `LanguageInfo.plist`, the same keys | same |
| **Extensions** | npm packages with `package.json`, run in a separate extension-host process | grammar bundles: an `NSBundle` with `LanguageInfo.plist` and a principal class, loaded into the app | different: in-process (see below) |
| **Language features** | an extension starts a server with `vscode-languageclient` | the bundle names the server's command; the host starts it (`LSPKit`), one per project and command | same protocol (LSP) |
| **Debugging** | `contributes.debuggers` and a debug adapter per session | the bundle or the project names the adapter's command; `UDDebugSession` per session | same protocol (DAP) and behaviour; Xcode's views |
| **Launch configurations** | `launch.json`: named configurations, a dropdown | VS Code's `launch.json` as it is (Debug › Launch Configuration); without one, `run` in `.udcode/settings.json`, inferred where it can be | same, and less to write |
| **Build** | `tasks.json`, problem matchers (`$gcc`) | VS Code's `tasks.json` as it is (the default build task, Run Task); without one, the project's build command; gcc/clang diagnostics parsed (`UDBuildRunner`) | same, one matcher |
| **Settings** | `.vscode/settings.json`, `tasks.json`, `launch.json`, user settings | `tasks.json` and `launch.json` read; `.udcode/settings.json` for what they don't say, with `"macos"`/`"gnustep"` sections; the rest guessed from the folder | VS Code's files, and less to write |
| **Workspace** | a folder, or several (multi-root), and `.code-workspace` files | a folder (File › Open Folder…), or files in a window (`.udworkspace`) | no multi-root yet |
| **Files** | Explorer, file watching | the file navigator; the folder watched (FSEvents, inotify), open files read again | same |

## Where we follow VS Code, and why

- **LSP and DAP.** The protocols are where language and debugger support live
  today: clangd, lldb-dap, gdb, rust-analyzer, debugpy all speak them. Speaking
  them means using those tools as they come, and any language with a server
  or an adapter plugs in through its bundle or the project's settings.
- **The debugging behaviour.** Conditional breakpoints, hit counts, logpoints,
  exception filters, watch expressions, the debug hover, Run to Cursor and
  Jump to Cursor, noDebug runs: VS Code's semantics, so adapters behave as
  they were written to.
- **The text model.** VS Code's piece tree is the best known structure for a
  code editor's text; `UDPieceTable` is its port, with its asymptotics kept.

## Where we differ, and why

- **Native views, Xcode's layout.** One AppKit code base runs on macOS and
  GNUstep, and apps embed its views (Quarry's scripts and their debugging are
  UDCodeKit's). VS Code's workbench can't be embedded.
- **tree-sitter, not TextMate.** Incremental, exact parse trees, which also give
  folding, structure, indentation and parse errors without a server.
- **Bundles in-process.** VS Code isolates extensions in an extension host, so a
  faulty one can't hang the editor. Our bundles are small and native (a grammar,
  a few methods), and the heavy lifting, the language server and the debugger,
  already runs in processes of its own. Isolation becomes worth it only if
  bundles grow into full extensions.
- **Inferred settings.** VS Code asks for `tasks.json` and `launch.json`. We
  read them when a project has them, and otherwise guess from the folder
  (GNUmakefile, Makefile.apple, CMake, Xcode) and ask only for what can't be
  guessed, in one file that serves both systems.

## Where we are going

The direction is VS Code's capabilities through VS Code's protocols, in a
native, embeddable, Xcode-like shell, using existing tools and adding no
formats of our own. What VS Code has that we don't, roughly in the order it
would matter for the IDE:

1. **A terminal** in the bottom area.
2. **Source control**: GitX ported to GNUstep, rather than a git UI of our own.
3. **Semantic tokens**, the one part of LSP's editing support not yet used
   (tree-sitter colours the code meanwhile).
4. **Multi-root workspaces** and **remote development**, the last of these.

Done since this was first written: file watching; VS Code's `tasks.json`
and `launch.json` (several launch configurations, preLaunchTask, Run Task);
and the rest of LSP's editing support, in Xcode's menus: Open Quickly
(files and workspace symbols), Jump to Definition, Find References and Find
in Workspace in a Find navigator, Rename Symbol, Format Document, Fix Issue
(code actions, with the server's own edits through `workspace/applyEdit`),
signature help, and the caret's symbol highlighted where it occurs.

An extension host is not on the list: if bundles ever run third-party code
of size, it is the way to keep the app responsive, but not before.
