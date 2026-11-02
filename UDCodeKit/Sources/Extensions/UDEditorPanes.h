/*---------------------------------------------------------------------------------------------
 *  UDEditorPanes.h
 *
 *  What a custom editor (an extension's -workbench:editorForDocument:) adds
 *  to the window while its tab is in front, as Xcode's editors do: its own
 *  inspectors beside the File inspector (Interface Builder's Attributes,
 *  Size…), panes in the bottom area beside the debugger and the terminal,
 *  a Library of what can be put in its document (⇧⌘L), and the issues of
 *  its document shown in it when chosen in the Issues navigator.
 *
 *  The editor's view controller adopts it; each method is optional. The
 *  window asks again whenever the editor's tab comes to the front, and
 *  takes them away when another tab does.
 *--------------------------------------------------------------------------------------------*/

#import <AppKit/AppKit.h>
#import "UDDiagnosticItem.h"

NS_ASSUME_NONNULL_BEGIN

@protocol UDEditorPanes <NSObject>
@optional

/// Its inspectors, each a tab of the inspector pane after File, named by
/// its view controller's title. The same ones each time it is asked: the
/// tab chosen stays chosen while the editor is in front.
- (NSArray<NSViewController *> *)inspectorViewControllers;

/// Its panes in the bottom area, each a segment of its switch after the
/// debugger's, the terminal's and the extensions' own, its title the
/// segment's tool tip.
- (NSArray<NSViewController *> *)bottomAreaViewControllers;
/// A bottom pane's segment's image (16 points square); nil: its title's
/// first letter.
- (nullable NSImage *)imageForBottomAreaViewController:(NSViewController *)viewController;

/// View > Show Library (⇧⌘L): what can be put in its document, shown in a
/// popover over the editor. nil: it has none (the item is dimmed).
- (nullable NSViewController *)libraryViewController;

/// An issue of its document chosen in the Issues navigator: shown (the
/// element it is about selected, say). A text editor's tab would have gone
/// to its line.
- (void)revealDiagnostic:(UDDiagnosticItem *)diagnostic;

@end

NS_ASSUME_NONNULL_END
