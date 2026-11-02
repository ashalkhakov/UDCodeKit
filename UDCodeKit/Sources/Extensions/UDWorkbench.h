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

/* UDCodeKit's own: exported where it is built for Windows (its GNUmakefile),
   imported everywhere else, as FOUNDATION_EXPORT. */
#ifndef UDCODEKIT_EXPORT
#define UDCODEKIT_EXPORT FOUNDATION_EXPORT
#endif

/// Posted when the window's selected tab changes (another document, or
/// none); object = the workbench.
UDCODEKIT_EXPORT NSNotificationName const UDWorkbenchSelectionDidChangeNotification;

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
/// The same, named @a name until it is saved (its tab's title; Save's
/// file name): a table's rows browsed, by its table's.
- (void)openUntitledDocumentWithText:(NSString *)text languageMode:(NSString *)identifier name:(nullable NSString *)name;
/// @a document's tab selected (its first); NO when no tab shows it.
- (BOOL)showDocument:(UDCodeDocument *)document;
/// @a viewController in an editor tab of its own (an extension's view: a
/// database's diagram), titled @a title; its tab selected when it has one.
- (void)showViewController:(NSViewController *)viewController title:(NSString *)title;
/// @a document as text, in a tab (the one showing it so, else a new one),
/// though an extension edits it another way (a query by example's), as VS
/// Code's Reopen Editor With… Text Editor.
- (void)showDocumentAsText:(UDCodeDocument *)document;
/// The navigator @a extension contributed, shown.
- (void)showNavigatorOfExtension:(id<UDExtension>)extension;
/// @a viewController in the bottom area (beside the debugger and the
/// terminal: a query's results), under @a extension's segment of its
/// switch (added the first time: its bottomAreaImage, @a title its tip),
/// in place of what it showed before; that segment chosen, the area shown.
- (void)showBottomAreaViewController:(NSViewController *)viewController title:(NSString *)title
                           extension:(id<UDExtension>)extension;
/// What @a extension's segment shows (nil: nothing yet), and whether it is
/// in front (its segment chosen, the area shown).
- (nullable NSViewController *)bottomAreaViewControllerOfExtension:(id<UDExtension>)extension;
- (BOOL)isBottomAreaShowingExtension:(id<UDExtension>)extension;
/// The editors of @a document (its tabs').
- (NSArray<UDCodeEditorViewController *> *)editorsOfDocument:(UDCodeDocument *)document;
/// The Library's popover (View > Show Library, UDEditorPanes'
/// -libraryViewController) closed: what was chosen in it taken.
- (void)closeLibrary;

@end

NS_ASSUME_NONNULL_END
