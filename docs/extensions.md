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
- **Update** installs the selected extension's update, and **Check for
  Updates** reads every installed extension's feed now (see Updates below).

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

## Updates

An installed extension can name a feed of its own (`"updates"` in its
package.json), and UDCode keeps it up to date from there. This is how VS Code
keeps extensions up to date from the Marketplace, with each extension's
releases taking the Marketplace's place. The feed is JSON, usually a
release's asset reached by GitHub's `releases/latest/download/` URL, and
lists the extension's versions:

```json
{
  "name": "ashalkhakov.udquaketools",
  "versions": [
    { "version": "1.2.0", "engines": { "udcode": "^0.22.0" },
      "packages": {
        "linux-x64": { "url": "https://github.com/…/udquaketools-1.2.0-linux-x64.udcx",
                       "sha256": "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08" },
        "win32-x64": { "url": "…", "sha256": "…" } } } ]
}
```

- **Which version:** the newest one that is newer than the installed one,
  whose `engines.udcode` takes this UDCode, and which has a package for this
  platform (or for `universal`).
- **When:** UDCode reads the feeds when it starts, at most once a day, and
  again from **UDCode > Check for Updates…** and the Extensions window's
  **Check for Updates**. Check for Updates… also checks UDCode itself, where
  UDCode has an updater of its own.
- **Installing:** the package is downloaded, and installed only if its
  SHA-256 is the one the feed names (on macOS, its signature is also checked
  when it loads, as for any extension). It goes in beside the version that is
  running, which it replaces when UDCode starts again.
- **Without asking:** updates are installed as soon as they're found,
  unless **Install updates automatically** is turned off in the Extensions
  window (VS Code's `extensions.autoUpdate`). When it's off, the window shows
  that an update is available, and **Update** installs it.

A kit writes its feed with each release (gnustep-release-actions'
`udcode-extension.sh`), beside the packages it lists.

**Shipped with UDCode.** A package of UDCode can carry extensions to install:
the `.udcx` files in the app's `Resources/Extensions`. UDCode installs each
one the first time it starts, before it loads any extension. From then on,
the extension updates from its own feed and UDCode from its own. A package
installed this way is never installed again, so an extension the user
uninstalls stays uninstalled. This is how UDQuakeTools ships: UDCode with its
extension.

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

- **`updates`**, optional, is the URL of its feed (see Updates).

UDCode reads `name`, `publisher`, `version`, `displayName`, `description`,
`license`, `engines`, `main` and `updates`, and ignores everything else.

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
| Windows | `ORMKit.bundle/`, beside its DLL | while UDCode loads an installed extension, its DLL's folder is a DLL search folder (`SetDllDirectoryW`) |

On macOS, sign the bundle and notarize it as you would an app's plug-in. The
released UDCode runs under the hardened runtime with library validation on,
so it loads only code signed by its own team: an extension must be signed
with the same Developer ID as UDCode's release, as the kits' releases are.
A UDCode you build yourself (version 0.0.0) loads extensions signed with
the identity you built it with.
Extensions signed by other developers can't be loaded unless UDCode turns
library validation off (`com.apple.security.cs.disable-library-validation`),
and it doesn't.

## File packages

A folder can be one document to the user, as a NeXT file package is:
`-mainFileOfPackageAtURL:` (`UDExtension.h`) says which file in it the folder
stands for, or nil for any other folder. Choosing the package, in File >
Open, the file navigator or on the command line, opens that file: it is what
is edited, saved and put under source control, and the tab has the package's
name. The navigator shows the package as one file; a package with packages in
it (Core Data's `.xcdatamodeld`, with a `.xcdatamodel` for each version)
expands to them, and choosing it opens the one it stands for. File > Open
Folder still opens any folder as a project, a package too.

## An editor of its own, and its panes

An extension can open its mode's documents in an editor of its own instead
of as text (`-workbench:editorForDocument:` in `UDExtension.h`), as VS
Code's custom editors do. The document stays the model: the editor makes
its changes as edits of the document's text, so undo, saving and the tab's
dot are the document's, and a tab of the text (`-showDocumentAsText:`)
shows the same document. The SQL extension's query by example works this
way, and so does ORMKit's ORM2.

As in Xcode, the editor needn't hold everything in its tab. Its view
controller can adopt `UDEditorPanes` (`UDEditorPanes.h`). Every method is
optional, and the window asks again each time the editor's tab comes to
the front:

- **`-inspectorViewControllers`**: inspectors of its own, shown as tabs of
  the inspector pane after File, like Interface Builder's Attributes and
  Size. The tab chosen stays chosen while the editor is in front.
- **`-bottomAreaViewControllers`**: panes in the bottom area, each a
  segment after the debugger's, the terminal's and the extensions' own,
  with `-imageForBottomAreaViewController:` as its image. When another tab
  comes to the front they go away, and the debugger is shown in their
  place. The workbench's `-showEditorBottomPane:` brings one
  to the front.
- **`-libraryViewController`**: what can be put in its document, shown in
  a popover by **View > Show Library** (⇧⌘L), as Xcode's Library. The
  workbench's `-closeLibrary` closes it once something is chosen.
- **`-revealDiagnostic:`**: an issue of its document chosen in the Issues
  navigator. The editor shows it, for example by selecting the element the
  issue is about, instead of the window going to a line of text. The issues
  themselves are the document's diagnostics (`diagnosticStore`), which the
  Issues navigator lists with every other document's.

## A model of its own: custom documents

Some documents' model isn't text: an archive whose entries are added and
removed, a game's decl edited as Core Data objects over its decl manager.
VS Code gives these a `CustomEditorProvider`, whose `CustomDocument` is the
extension's own object, and so does UDCode. The extension opens the model
(`-workbench:openCustomDocumentAtURL:fileSystemProvider:error:` in
`UDExtension.h`), asked before the file, or its provider's URL, is read as
text; it returns nil for what isn't its. The model adopts `UDCustomDocument`
(`UDCustomDocument.h`), and the window's `UDCodeDocument` of it has it as its
`customDocument`:

| VS Code | UDCode |
|---|---|
| `openCustomDocument` | `-workbench:openCustomDocumentAtURL:fileSystemProvider:error:` |
| `resolveCustomEditor` | `-workbench:editorForDocument:` (the document's `customDocument`) |
| `onDidChangeCustomDocument`, its edits' `undo`/`redo` | `UDCustomDocumentDidChangeNotification`, the model's `undoManager` |
| `saveCustomDocument`, `saveCustomDocumentAs` | `-saveCustomDocument:`, `-saveCustomDocumentAsURL:error:` |
| `revertCustomDocument` | `-revertCustomDocument:` |
| `CustomDocument.dispose` | `-closeCustomDocument` |

- **Undo** is the model's `undoManager` while its editor is in front (the
  window's `-windowWillReturnUndoManager:`), and the document's tab has a dot
  while the model `-isEdited`.
- **Save** and Save All save the model, and so does Save As when it has
  `-saveCustomDocumentAsURL:error:`. When its file changes on disk, or its
  provider says so, a model with no changes of its own is reverted.
- **Its text.** A model with a text (`-textOfDocument`: a decl's) can be
  shown with Open as Text, kept as the model changes. What is typed there is
  given back to the model (`-applyText:error:`) as one edit, undone with the
  typing. Text the model can't take stays as typed, and the document stays
  edited, until it is text the model takes or the model changes in its
  editor. A model with no text (an archive's) isn't shown as text.

Only the document's model is the extension's. It still has tabs, the dot,
closing with changes asked about, and a URL that is a file's or a provider's.

## Running a document

**Editor > Run** (⌘↩) and **Run All** (⇧⌘↩) are UDCode's, and run the
document in front, as text or in an extension's own editor, whichever
extension's it is: the SQL mode's statements, the OData Workbench's requests
and queries. An extension that runs its
mode's documents answers two methods of `UDExtension`:

- **`-workbench:canRunDocument:`**: whether it runs this document now. The
  first extension that says yes runs it, and the items are enabled.
- **`-workbench:runDocument:selection:all:`**: run the statement or request
  at the selection (or the caret; `{NSNotFound, 0}` when the document is in
  an editor of the extension's own), or with `all`, every one in order.

An extension's own items in the Editor menu (`-editorMenuItemsForWorkbench:`)
come after UDCode's, and shouldn't take ⌘↩ or ⇧⌘↩: in a menu, the first
item with a key equivalent takes the key, even while it is disabled, so two
extensions' ⌘↩ items would leave one of them unreachable from the keyboard.

An app that embeds UDCodeKit can register an extension it makes itself,
with no bundle, using `-[UDLanguageModeRegistry registerExtension:]`.

## Project systems

UDCode's file navigator shows a project as its folder's files. A project
system shows the same project another way: a game's decls by type and name
(UDQuakeTools' Quarry), or a solution's projects and their items, as VS Code's
C# Dev Kit shows a `.sln` in its Solution Explorer. VS Code has no single
project system API, and neither has UDCode. An extension builds one from the
parts VS Code's extensions use, and the window keeps the file navigator
beside it:

| VS Code | UDCode |
|---|---|
| `activationEvents: ["workspaceContains:**/*.sln"]` | `activationEvents` in the bundle's LanguageInfo.plist |
| a view container and `createTreeView` | `-navigatorViewControllerForWorkbench:` returning a `UDTreeViewController` |
| `TreeDataProvider`, `TreeItem` | `UDTreeDataProvider`, `UDTreeItem` (`UDTreeView.h`) |
| `TreeItem.command`, `vscode.open` | `UDTreeItem`'s `target` and `action`, `-openResource:` |
| `registerFileSystemProvider("quarry", …)` | `-workbench:fileSystemProviderForScheme:` returning a `UDFileSystemProvider` |
| `menus` → `view/item/context` | `-treeView:menuForElements:`, a menu from the extension's XIB |
| task, debug and test providers | `-buildSystemClasses`, `-debuggerClasses`, `-testRunnersForProject:` |
| custom editors | `-workbench:editorForDocument:`, and custom documents (above) |

**Activation.** An extension whose LanguageInfo.plist has an
`activationEvents` array is asked for what it brings a window (its
navigator, its menus, its providers, its editors) only in the windows where
one of the events holds:

- `"*"`: every window.
- `"workspaceContains:<glob>"`: the window's folder has a file or folder
  matching the glob, relative to the folder. `*` and `?` match within a
  name, and `**` matches any number of folders: `*.qworkspace` is at the
  folder's top, `**/*.sln` anywhere in it. The search doesn't look in hidden
  folders, and stops after 10000 entries.

Other events (VS Code's `onLanguage:`, say) are ignored. An extension with no
`activationEvents` is active in every window, as before. The window looks
when it opens, so a marker made later takes effect when the folder is opened
again.

**The tree.** `UDTreeViewController` shows the provider's elements, any
objects. It asks for an element's children when the element is first
expanded, never for the whole tree, and shows each element as the
`UDTreeItem` the provider makes of it: a label, an image, a dimmer detail at
the right, a tool tip, and whether it has children and starts open. As in VS
Code, choosing an element (a click, Return) runs its item's command, and
nothing else: the item's `action`, sent to its `target` with the tree view as
the sender, whose `chosenElement` is the element meanwhile. With no target
the action goes to the tree view itself, whose `-openResource:` opens the
item's `resourceURL` in the window, as VS Code's `vscode.open` does. An item
with no command opens nothing; a double click opens or closes it. `-refresh` and `-refreshElement:` ask again, keeping what was open
and selected (by the item's `identifier`, or else its label under its
parent's). `-revealElement:` opens what an element is under and selects it,
and needs `-treeView:parentOfElement:`. A provider that implements
`-treeView:filterDidChange:` gets a filter field under the tree, as Xcode's
navigators have.

**Documents that are not files.** A provider of a URL scheme reads and writes
what is at its URLs: `quarry:/material/textures/foo`, a decl in a game's
paks. A document of such a URL is a text document like a file's. It has
tabs, undo and the extension's own editor, Open as Text works, and Save
writes it back through the provider (`-writeContents:toURL:error:`), which
decides where it goes: Quarry writes into the mod's folder and leaves the
paks alone. The provider can name the document's language mode and its tab
(`-languageModeOfURL:`, `-displayNameOfURL:`), and posts
`UDFileSystemProviderDidChangeFilesNotification` when something changes
other than by a save, so that open documents without changes of their own
are read again. Such a document's `URL` is its provider's and its `fileURL`
is nil, so what only a file has (a language server, source control,
breakpoints, the file watcher) leaves it alone. Each window asks for its own
provider, so two windows can have the same scheme for different projects.

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
