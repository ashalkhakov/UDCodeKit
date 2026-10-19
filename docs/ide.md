# UDCode as a C and Objective-C IDE

Open a folder, build it, run it, debug it, change it. UDCode uses the tools
that already exist for each of those, and adds no project format:

- **Building** is the project's own command: `make`, `make -f Makefile.apple`,
  `cmake`, `xcodebuild`.
- **The language** is clangd, the language server LLVM ships: completion,
  errors as you type, hover, definitions and references, rename, formatting,
  fixes, signatures, the symbol under the caret highlighted where it occurs.
- **Debugging** is the debugger's own Debug Adapter Protocol: `lldb-dap` (LLVM's,
  and Xcode's on macOS) or gdb's (`gdb -i dap`, gdb 14 and later).

## The window

Xcode's, so that whoever knows Xcode knows where everything is:

- **The toolbar**:
  - the Navigator's button;
  - Run (⌘R) and Stop (⌘.);
  - the scheme: launch.json's configurations, or the project;
  - the activity view, saying what goes on: "hello | Building hello…", "hello | Build Succeeded | 2 warnings", "hello | Running hello";
  - the Inspector's button.
- **The navigator**: on the left, its bar of icons (Files, Find, Issues, Debug, Breakpoints, Build log, ⌘1–⌘9).
- **The editors**: in the middle, in tabs.
- **The debug area**: below the editors (⇧⌘Y).
- **The inspector**: on the right.

On macOS the icons are SF Symbols. GNUstep has none, so it gets drawings of
our own under the same names, from `scripts/draw-gnustep-images.swift` into
`Images/GNUstep/`. A segment's image in a XIB needs the gnustep-patches stack
with `xib-segment-image`.

## On a Linux without build tools (Bazzite, SteamOS)

An immutable system has no compiler to install, by design; it has Distrobox
for that: a container that shares your home, display, GPU and sound, whose
programs run as any other. `scripts/udcode-box.sh` makes one to work in:

```sh
curl -fsSLO https://raw.githubusercontent.com/ashalkhakov/UDCodeKit/master/scripts/udcode-box.sh
bash udcode-box.sh
```

It is Ubuntu 22.04, what UDCode's AppImage and the GNUstep stack's archives
are built on, with:

- the patched GNUstep stack and FreeCoreData, their latest releases, in
  `/opt/gnustep`, and the packages building on them needs;
- LLVM 18's clangd and lldb-dap, gdb, make, cmake, ninja and ripgrep;
- what the Quake and Doom 3 engines build with: SDL2, OpenAL, Vorbis, Opus;
- UDCode, its latest release, in the application menu (or
  `distrobox enter udcode -- udcode`).

Run it again to bring the box up to date. `--appimage FILE` installs UDCode
from an AppImage of your own (in your home); `--stack VERSION` a release of
the stack other than the latest.

The debugger in the box is lldb-dap (Ubuntu 22.04's gdb is older than its
DAP); the box is privileged, as Distrobox makes them, so lldb launches there.

## Opening a project

File › Open Folder… (⌥⌘O) opens a folder as a project. Its files are in the
navigator's Files tab, folders first, hidden files left out; a click opens one.
⌘S saves the tab's file, and Build saves every edited one first.

UDCode guesses how the project is built from what is in the folder, for the
system it runs on:

| The folder has | On | Build | Run |
|---|---|---|---|
| `GNUmakefile` | GNUstep | `make`, in GNUstep's environment | its `APP_NAME`'s `.app`, or `TOOL_NAME`'s `obj/` tool |
| `Makefile.apple` | macOS | `make -f Makefile.apple` | asked |
| an `.xcodeproj` | macOS | `xcodebuild -configuration Debug build` (Debug, as Xcode's Run) | its first application or tool, where the Debug build puts it (`xcodebuild -showBuildSettings`) |
| `Makefile` | both | `make` | asked |
| `CMakeLists.txt` | both | `cmake -S . -B build -DCMAKE_EXPORT_COMPILE_COMMANDS=ON && cmake --build build` (`-G Ninja` where there is no make) | asked |

"Asked": the first Run opens Debug › Project Settings…, where the program is
named once.

A folder with both a Makefile and a CMakeLists.txt is built with the one this
machine has the tool for: make where there is make, else CMake (a Steam Deck
has CMake and Ninja, not make). A `"macos"` or `"gnustep"` section in the
settings can say otherwise.

## Building, running, debugging

| | | |
|---|---|---|
| Debug › Build | ⌘B | the build command; its log in the navigator's Build tab, its errors and warnings in Issues (and in the open file's editor) |
| Debug › Clean | ⇧⌘K | the clean command |
| Debug › Run | ⌘R | builds, then runs the program under the debugger: breakpoints, stepping, threads, variables, the console |
| Debug › Run Without Debugging | ⌃⌘R | builds, then runs it, its output in the console |
| Debug › Stop | ⌘. | stops the build, or the program |

The debugger is lldb-dap on macOS and gdb on Linux, each falling back on the
other. lldb can't launch a program where address randomization can't be
turned off, a container among them.

## A project set up for VS Code

A folder with `.vscode/tasks.json` and `.vscode/launch.json` works as it is,
read as VS Code reads them (comments and trailing commas included):

- **Build** runs the default build task (`"group": { "kind": "build",
  "isDefault": true }`), what it `dependsOn` first; Debug › Run Task runs any.
- **Run** uses the launch configuration chosen in Debug › Launch
  Configuration (launch.json's first until one is chosen): its
  `preLaunchTask`, then its `program`, `args`, `cwd` and `env` (or the C/C++
  extension's `environment`). `"lldb"`, `"lldb-dap"` and `"cppdbg"` with
  `"MIMode": "lldb"` run under lldb-dap; `"cppdbg"` with `"MIMode": "gdb"`
  and `"gdb"` under gdb (`miDebuggerPath` too). An `"attach"` attaches to
  its `processId`.
- `"osx"` and `"linux"` properties override the rest on that system.
- VS Code's variables: `${workspaceFolder}`, `${workspaceFolderBasename}`,
  `${file}`, `${fileBasename}`, `${fileBasenameNoExtension}`, `${fileDirname}`,
  `${fileExtname}`, `${relativeFile}`, `${cwd}`, `${userHome}`, `${env:NAME}`.

Without them, what follows is used.

## Finding and changing code

As in Xcode, with the language server doing the work:

| | | |
|---|---|---|
| Navigate › Open Quickly… | ⇧⌘O | a file by the letters of its name (ripgrep's list, so `.gitignore`'s files are left out), or a symbol (`workspace/symbol`) |
| Navigate › Jump to Definition | ⌃⌘J | where the symbol at the caret is defined |
| Navigate › Find References | ⇧⌃⌘F | everywhere it is used, in the Find navigator |
| Edit › Find › Find in Workspace… | ⇧⌘F | the folder's files searched (ripgrep, else grep), the matches by file in the Find navigator (⌘3) |
| Editor › Rename Symbol | ⌃⌘E | edited where it stands, as in Xcode: every place it is in the file changes as you type; Return, and the other files change too (open ones through their editors, the others on disk); Escape puts it back |
| Editor › Format Document | ⌃⇧I | the server's formatting (clangd follows the project's `.clang-format`) |
| Editor › Fix Issue at Cursor | ⌃⌥⌘F | the caret's issue and the server's fixes for it (then its refactorings), in a Fix-its panel at the issue, as Xcode's: Return or a click applies one, the arrows choose, Escape puts it away |

What only the compiler knows is coloured too: clangd's semantic tokens, over
tree-sitter's colours. A macro, a parameter, a field, a type behind a typedef
each get their own colour, and code an `#if` leaves out is greyed as a
comment. They come again whenever the typing pauses.

Typing `(` or `,` in a call shows the function's signature, the parameter
there in bold. Resting the caret on a symbol highlights it wherever it occurs
in the file, the places it is assigned to in a warmer colour.

## The terminal

View › Terminal (⌃`) opens a shell in the bottom area: the switch at the
right of its bar goes between the debugger's variables and console, and the
terminal. The shell is your login shell (`$SHELL`), in the project's folder;
on GNUstep it gets the build's environment (GNUstep.sh's), so `make` there
works as Build does. It is xterm's terminal, as libvterm reads it (Neovim's
terminal library, compiled in, fetched at the commit `scripts/grammars.lock`
names): colours, a full-screen program's own screen (vim, less, top), the
lines that scroll off kept above. A drag selects, ⌘C copies, ⌘V pastes (in
brackets, when the shell asks). When the shell ends, the screen says so, and
⌃` starts another.

## Changes made elsewhere

The folder is watched (FSEvents on macOS, inotify on Linux): the navigator
lists what a build or git makes, an open file with no edits of its own takes
what another program wrote (one with edits keeps them), and the language
servers are told.

## Settings

What can't be guessed is set in Debug › Project Settings…, or in the folder's
`.udcode/settings.json`, which goes with the project. One file serves both
systems: a `"macos"` or `"gnustep"` section overrides the rest on that system,
as VS Code's `launch.json` has `"osx"` and `"linux"`. Project Settings writes
this system's section only.

```json
{
  "build": "make",
  "clean": "make clean",
  "run": {
    "program": "obj/hello",
    "arguments": "--verbose \"two words\"",
    "directory": ".",
    "environment": { "NSZombieEnabled": "YES" }
  },
  "debugger": "lldb",
  "languageServers": { "c": ["clangd", "--background-index"] },
  "macos":   { "build": "make -f Makefile.apple", "run": { "program": "build/Hello.app" } },
  "gnustep": { "run": { "program": "Hello.app" } }
}
```

- `debugger`: `"lldb"`, `"gdb"`, or any debug adapter's command, as an array.
- `languageServers`: a language mode's server, in place of its bundle's.
- Paths are relative to the folder. An application's path runs its executable.

## clangd

The C and Objective-C bundles name clangd, found on PATH, in Xcode, or under a
distribution's versioned names (`clangd-18`). A project's files share one
clangd, rooted at its folder, which finds the project's `compile_commands.json`
itself (CMake's, or Bear's for make). For a file it has none for, it is told
how to compile it: GNUstep's flags (`gnustep-config --objc-flags`) on GNUstep,
the SDK on macOS, and the folder's headers.

## The pieces

| Piece | Where | What |
|---|---|---|
| `UDProject` | UDCodeKit `Project/` | a folder's settings, what is guessed, the build's environment, clangd's fallback flags |
| `UDToolLocator` | UDCodeKit `Project/` | where clangd, lldb-dap and gdb are, and how each debugger is asked to launch |
| `UDFileNavigatorViewController` | UDCodeKit `Project/`, `UDFileNavigator.xib` | the folder's files |
| `UDBuildRunner` | UDCodeKit `Project/` | the build command, its output, its diagnostics by file |
| `UDBuildLogViewController` | UDCodeKit `Project/`, `UDBuildLog.xib` | the build's log and how it went |
| `UDProjectSettingsController` | UDCodeKit `Project/`, `UDProjectSettings.xib` | the settings sheet |
| `UDTasks` | UDCodeKit `Project/` | `.vscode/tasks.json` and `launch.json`, as VS Code reads them |
| `UDFileWatcher` | UDCodeKit `Project/` | the folder watched: FSEvents, inotify |
| `UDSearchResultsViewController` | UDCodeKit `Project/`, `UDSearchResults.xib` | the Find navigator: workspace search, references |
| `UDOpenQuicklyController` | UDCodeKit `Project/`, `UDOpenQuickly.xib` | Open Quickly |
| `UDWorkspaceEdit` | UDCodeKit `LSP/` | a server's WorkspaceEdit or TextEdits, applied |
| `UDOccurrencesHighlighter` | UDCodeKit `Highlighters/` | the caret's symbol, where it occurs |
| `UDSemanticTokensHighlighter` | UDCodeKit `Highlighters/` | a server's semantic tokens, named as tree-sitter's captures |
| `UDLinkedEditing` | UDCodeKit `Highlighters/` | places edited together (Rename Symbol's) |
| `UDIssuePopupController` | UDCodeKit `Workbench/`, `UDIssuePopup.xib` | an issue's Fix-its |
| `UDTerminalViewController` | UDCodeKit `Terminal/`, `UDTerminal.xib` | a shell in a terminal |
| `UDTerminalView` | UDCodeKit `Terminal/` | libvterm's screen, drawn; keys, selection, paste |
| `UDPseudoTerminal` | UDCodeKit `Terminal/` | a program on a pseudo-terminal of its own (forkpty) |
| `UDDocumentWindowController` | UDCode | the project window: navigator, tabs, the menus' actions |

How this compares with VS Code: [architecture.md](architecture.md).
