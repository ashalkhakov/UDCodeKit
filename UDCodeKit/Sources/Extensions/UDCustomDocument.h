/*---------------------------------------------------------------------------------------------
 *  UDCustomDocument.h
 *
 *  A document whose model is an extension's own, not its text, as VS Code's
 *  CustomDocument is a CustomEditorProvider's (a hex editor's, an image's):
 *  an archive whose entries are edited, a decl edited as Core Data objects
 *  over a game's decl manager. The extension opens it (-[UDExtension
 *  workbench:openCustomDocumentAtURL:fileSystemProvider:error:]), and its
 *  editor (-workbench:editorForDocument:) edits it; the window's
 *  UDCodeDocument of it (its customDocument) is what has the tabs: its dot
 *  is the model's -isEdited, Save and Save All its -saveCustomDocument:, undo and
 *  redo its undoManager's while its editor is in front.
 *
 *  Its text, when it has one (-textOfDocument: a decl's), is what View >
 *  Open as Text shows, kept as the model is; typing there gives the text
 *  back to the model (-applyText:error:), its undo the model's. A model with
 *  no text (an archive) is not shown as text.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/* UDCodeKit's own: exported where it is built for Windows (its GNUmakefile),
   imported everywhere else, as FOUNDATION_EXPORT. */
#ifndef UDCODEKIT_EXPORT
#define UDCODEKIT_EXPORT FOUNDATION_EXPORT
#endif

/// Posted by a custom document when its model changed (an edit, its undo or
/// redo, a save, a revert: VS Code's onDidChangeCustomDocument);
/// object = the custom document.
UDCODEKIT_EXPORT NSNotificationName const UDCustomDocumentDidChangeNotification;

@protocol UDCustomDocument <NSObject>

/// What its edits are registered with: undo and redo while its editor, or its
/// text, is in front.
@property (nonatomic, readonly) NSUndoManager *undoManager;

/// Whether it has changes not saved (its tabs' dot; asked before its last tab
/// closes).
@property (nonatomic, readonly, getter=isEdited) BOOL edited;

/// Its changes written where it is from (VS Code's saveCustomDocument).
- (BOOL)saveCustomDocument:(NSError *__autoreleasing *)outError;

/// What it is from read again, its changes dropped (revertCustomDocument):
/// asked when that changed (another program wrote the file) and it has no
/// changes of its own.
- (BOOL)revertCustomDocument:(NSError *__autoreleasing *)outError;

@optional

/// Its model as text, now (unsaved changes and all); nil, or not
/// implemented: it has none, and is not shown as text.
- (nullable NSString *)textOfDocument;

/// @a text, typed in its text's tab, made its model: one edit of it, on its
/// undoManager. NO (with *outError) when the text is not one it can take
/// (does not parse): the text stays as typed, its document edited, until it
/// is one, or the model changes. Not implemented: its text is not edited.
- (BOOL)applyText:(NSString *)text error:(NSError *__autoreleasing *)outError;

/// It written to @a url, a file, which it is of from then on
/// (saveCustomDocumentAs). Not implemented: it has no Save As.
- (BOOL)saveCustomDocumentAsURL:(NSURL *)url error:(NSError *__autoreleasing *)outError;

/// Its last tab closed: what it holds let go (VS Code's dispose).
- (void)closeCustomDocument;

@end

NS_ASSUME_NONNULL_END
