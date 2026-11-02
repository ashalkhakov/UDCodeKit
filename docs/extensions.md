# Extensions

UDCode's modes come in extensions: bundles whose principal class conforms to
`UDExtension` (UDCodeKit's `Extensions/UDExtension.h`). Some are built in,
in the app's `PlugIns` folder: the grammars, C and Objective-C, git, SQL.
Others come from the projects that own them: an ORM2 mode from ORMKit, XForms
from XFormsKit, and so on. Each of those projects builds, licenses and
releases its own extension, and you install it into your home folder. The
app stays as it was shipped, which matters for an AppImage, a signed Mac app
or an MSI, none of which can be changed afterwards.

This works the way VS Code's extensions do: the same folder layout, manifest,
package format and command line, with `udcode` in place of `vscode`.

## Installing

**UDCode > Extensions…** (⇧⌘X) lists every extension, built in and
installed, whether it is loaded, and if it isn't, why: for another UDCode
version, built for another platform, disabled, or its place taken by an
installed one. From there:

- **Install from Package…** installs a `.udcx`.
- **Uninstall** removes an installed extension. A built-in one can't be
  uninstalled.
- **Disable** and **Enable** work on any extension, built-in ones included.

Changes apply the next time UDCode starts. UDCode loads extensions once, at
start, and never unloads them.

The command line does the same without opening a window:

```
UDCode --install-extension ormkit-0.5.0-darwin-arm64.udcx
UDCode --uninstall-extension ashalkhakov.ormkit
UDCode --list-extensions --show-versions
```

On macOS, run `UDCode.app/Contents/MacOS/UDCode`. On Linux, run the AppImage
itself. On Windows, run `UDCode.exe` from a console; the output goes to that
console.

## Where they are

```
~/.udcode/extensions/                    (Windows: %USERPROFILE%\.udcode\extensions)
  extensions.json                        what is installed (VS Code's index)
  .obsolete                              what was uninstalled; removed at the next start
  ashalkhakov.ormkit-0.5.0-darwin-arm64/  publisher.name-version[-platform]
    package.json                         the manifest
    ORMKit.bundle/                       its main: the extension bundle
    LICENSE                              …and whatever else the package holds
```

When you uninstall an extension, or install another version over it, the old
folder is marked in `.obsolete` and removed the next time UDCode starts. It
is not removed straight away because UDCode may still have it loaded, and
Windows can't delete a DLL that is in use. If two versions of the same id are
installed, the newest is loaded. An installed extension whose id (or bundle
identifier) matches a built-in one replaces it, which is how a newer ORMKit
takes over from the one UDCode shipped with. `$UD_EXTENSIONS_PATH` names
another folder, which is what the tests use.

## The manifest: package.json

```json
{
  "name": "ormkit",
  "publisher": "ashalkhakov",
  "version": "0.5.0",
  "displayName": "ORM2",
  "description": "Object-role models: verbalised, validated, mapped to SQL",
  "license": "LGPL-2.1-only",
  "repository": "https://github.com/ashalkhakov/ORMKit",
  "engines": { "udcode": "^0.16.0" },
  "main": "./ORMKit.bundle"
}
```

- **`publisher`** and **`name`** together make the id, `publisher.name`,
  compared in lowercase.
- **`engines.udcode`** is required. It is a semver range: `^0.16.0`,
  `~0.16.1`, `>=0.15.0 <0.17.0`, `0.16.2` or `*`. With a 0.x major version,
  `^` stays within the minor version, so `^0.16.0` accepts 0.16.* only. The
  extension API is UDCodeKit's headers, which can change between minor
  versions until 1.0, so declare the minor version you built against. A
  development build of UDCode, whose version is 0.0.0, accepts any range.
- **`main`** is the bundle, relative to the package.json.

UDCode reads `name`, `publisher`, `version`, `displayName`, `description`,
`license`, `engines` and `main`, and ignores everything else.

## The package: .udcx

A `.udcx` is laid out as a `.vsix` is: a zip archive containing

```
extension/                 becomes the installed folder
  package.json
  ORMKit.bundle/
  LICENSE
extension.vsixmanifest     its Identity's TargetPlatform: darwin-arm64,
                           darwin-x64, linux-x64, linux-arm64, win32-x64,
                           win32-arm64; none means any platform
```

```xml
<?xml version="1.0" encoding="utf-8"?>
<PackageManifest Version="2.0.0">
  <Metadata>
    <Identity Id="ormkit" Version="0.5.0" Publisher="ashalkhakov" TargetPlatform="darwin-arm64"/>
    <DisplayName>ORM2</DisplayName>
  </Metadata>
</PackageManifest>
```

An extension has compiled code, so it needs a package per platform: one for
each of the targets UDCode is released for. A kit's release workflow builds
those packages next to its libraries (gnustep-release-actions builds each
platform already), and attaches them to the kit's GitHub release. UDCode
refuses a package built for another platform, or for UDCode versions its
`engines.udcode` doesn't include, and says why.

UDCode unpacks packages with the system's own tools: `ditto` on macOS,
`tar.exe` on Windows 10 and later, and `unzip`, `bsdtar` or `python3` on
Linux, whichever is installed.

## What goes in the bundle

The bundle is an extension bundle like the built-in ones
([grammar bundles](grammar-bundles.md)): `Info.plist` with
`NSPrincipalClass`, `LanguageInfo.plist` with its `languageModes`, and its
code. Build it against the UDCode release it is for. That release's UDCodeKit
(the `udcodekit-<version>-…` archives attached to each UDCode release)
provides the headers and the libraries to link against, the same way VS
Code's `@types/vscode` is pinned to an engine.

**The bundle contains its own libraries and nothing of UDCode's.**
UDCodeKit, LSPKit, UDPieceTable, the GNUstep libraries and AppKit all come
from the running UDCode. If an extension shipped its own copies, two of each
would be loaded into one process. Libraries of its own, such as the kit
itself (ORMKit's `libORMKit`) and anything that UDCode doesn't ship, go
inside the bundle:

| Platform | Where | How it is found |
|---|---|---|
| macOS | `ORMKit.bundle/Contents/Frameworks/` | the bundle's binary links with `@loader_path/../Frameworks` in its rpath |
| Linux | `ORMKit.bundle/` (beside its binary) or a `lib/` in it | the binary's `RUNPATH` is `$ORIGIN` (or `$ORIGIN/lib`) |
| Windows | `ORMKit.bundle/`, beside its DLL | UDCode loads an installed extension's DLL with `LOAD_WITH_ALTERED_SEARCH_PATH`, so Windows looks for its DLLs in that folder first |

On macOS, sign the bundle and notarize it as you would an app's plug-in. The
released UDCode runs under the hardened runtime with library validation on,
so it loads only code signed by its own team: an extension must be signed
with UDCode's Developer ID (team V2D8AKM5BB), as the kits' releases are.
Extensions signed by other developers can't be loaded unless UDCode turns
library validation off (`com.apple.security.cs.disable-library-validation`),
and it doesn't.

## Licences

UDCode is MIT, and so are UDCodeKit, LSPKit and UDPieceTable. An extension
is a separate work under its own licence, which its package.json names and
its package carries:

- **LGPL-2.1 kits** (XFormsKit, RDLKit, ODataKit, ORMKit, WorkflowKit): keep
  the kit a shared library inside the bundle, not linked statically into the
  bundle's binary, so that a user can replace it with one they have built
  (LGPL 2.1 §6). The package carries the licence's text and says where the
  source for that exact version is (§6(d)): the `repository` in
  package.json and a release tag matching the version.
- **GPL-3.0** (UDQuakeTools' modes): UDCode never ships a GPL extension
  built in. It is installed separately, as its own package, from its own
  releases.
- **MIT** (FreeCoreData, DiagramKit): no conditions beyond keeping the
  notice.

Libraries that a bundle carries for its own use are covered the same way: a
`Licenses/` folder in the package with each library's text, the way UDCode
carries the database client libraries' licences.
