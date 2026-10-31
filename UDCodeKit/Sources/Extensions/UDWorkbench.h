/*---------------------------------------------------------------------------------------------
 *  UDWorkbench.h
 *
 *  The window an extension's views and commands work in (UDCode's workspace
 *  window), as VS Code's workbench is its extensions': its project, the
 *  document and editor in front, files opened in tabs, the navigator an
 *  extension contributed shown. See UDExtension's -navigatorViewController…
 *  and -editorMenuItems… for what an extension contributes to it.
 *--------------------------------------------------------------------------------------------*/

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@class UDProject, UDCodeDocument, UDCodeEditorViewController;
@protocol UDExtension;

@protocol UDWorkbench <NSObject>

@property (nonatomic, readonly, nullable) NSWindow *window;
/// The project (its folder's settings: an extension's own keys too); nil:
/// the window has none.
@property (nonatomic, readonly, nullable) UDProject *project;

/// The selected tab's text document and its editor; nil when the tab shows
/// none (a history, a diff's other side).
@property (nonatomic, readonly, nullable) UDCodeDocument *selectedDocument;
@property (nonatomic, readonly, nullable) UDCodeEditorViewController *selectedEditor;

/// @a url in a tab: the one showing it, else a new one.
- (void)showURL:(NSURL *)url;
/// A new, untitled document of the mode @a identifier ("sql"), with @a text,
/// in a tab of its own.
- (void)openUntitledDocumentWithText:(NSString *)text languageMode:(NSString *)identifier;
/// The navigator @a extension contributed, shown.
- (void)showNavigatorOfExtension:(id<UDExtension>)extension;
/// The editors of @a document (its tabs').
- (NSArray<UDCodeEditorViewController *> *)editorsOfDocument:(UDCodeDocument *)document;

@end

NS_ASSUME_NONNULL_END
