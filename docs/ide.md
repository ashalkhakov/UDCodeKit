# UDCode as a C and Objective-C IDE

Open a folder, build it, run it, debug it, change it. UDCode uses the tools
that already exist for each of those, and adds no project format:

- **Building** is the project's own command: `make`, `make -f Makefile.apple`,
  `cmake`, `xcodebuild`.
- **The language** is clangd, the language server LLVM ships: completion,
  errors as you type, hover, go to definition.
- **Debugging** is the debugger's own Debug Adapter Protocol: `lldb-dap` (LLVM's,
  and Xcode's on macOS) or gdb's (`gdb -i dap`, gdb 14 and later).

## Opening a project

File › Open Folder… (⇧⌘O) opens a folder as a project. Its files are in the
navigator's Files tab, folders first, hidden files left out; a click opens one.
⌘S saves the tab's file, and Build saves every edited one first.

UDCode guesses how the project is built from what is in the folder, for the
system it runs on:

| The folder has | On | Build | Run |
|---|---|---|---|
| `GNUmakefile` | GNUstep | `make`, in GNUstep's environment | its `APP_NAME`'s `.app`, or `TOOL_NAME`'s `obj/` tool |
| `Makefile.apple` | macOS | `make -f Makefile.apple` | asked |
| an `.xcodeproj` | macOS | `xcodebuild build` | asked |
| `Makefile` | both | `make` | asked |
| `CMakeLists.txt` | both | `cmake -S . -B build && cmake --build build` | asked |

"Asked": the first Run opens Debug › Project Settings…, where the program is
named once.

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
| `UDDocumentWindowController` | UDCode | the project window: navigator, tabs, the menus' actions |

How this compares with VS Code: [architecture.md](architecture.md).
