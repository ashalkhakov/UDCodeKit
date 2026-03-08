/*---------------------------------------------------------------------------------------------
 *  UDDocument.h — NSDocument subclass that represents an editor workspace.
 *
 *  A workspace is the top-level container managed by one window, analogous to
 *  a VS Code workspace or an Xcode workspace:
 *
 *    • Opened from a .udworkspace file  → restores the previously-open tab set.
 *    • Opened from a plain file (e.g. .json) → single-tab workspace (backwards-compat).
 *    • File > New                        → blank workspace with one empty editor tab.
 *
 *  The class is intentionally thin.  All per-window editor setup — tabs, syntax
 *  highlighting, diagnostics, LSP — lives in UDDocumentWindowController.
 *
 *  File I/O is the only responsibility of this class:
 *    • writeToURL: for .udworkspace  → JSON snapshot of the currently-open file list.
 *    • writeToURL: for a plain file  → the primary tab's text content (single-file mode).
 *--------------------------------------------------------------------------------------------*/

#import <Cocoa/Cocoa.h>
#import "UDTextModelTextStorage.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDWorkspace : NSDocument

/// Ordered list of file URLs the window controller should open as tabs when
/// the workspace loads.  Populated by -readFromURL:ofType:error: before
/// -windowDidLoad is called.  nil or empty → open one blank editor tab.
@property (nonatomic, copy, nullable) NSArray<NSURL *> *initialTabURLs;

/// Text storage of the workspace's primary tab.  Set by
/// UDDocumentWindowController in -windowDidLoad.  Used by
/// -writeToURL:ofType:error: when saving a plain (non-workspace) document.
@property (nonatomic, readwrite, nullable) UDTextModelTextStorage *primaryTextStorage;

@end

NS_ASSUME_NONNULL_END
