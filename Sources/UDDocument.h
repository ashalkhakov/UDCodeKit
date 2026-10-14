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
 *    • writeToURL: for .udworkspace  → delegates to workspaceModel.serializeToData:
 *    • writeToURL: for a plain file  → the primary tab's text content (single-file mode).
 *--------------------------------------------------------------------------------------------*/

#import <Cocoa/Cocoa.h>
#import <UDCodeKit/UDCodeKit.h>
#import "UDWorkspaceModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDWorkspace : NSDocument

/// Ordered list of file URLs the window controller should open as tabs when
/// the workspace loads.  Set by -readFromURL:ofType:error: for plain-file
/// workspaces (the workspace model path does not use this).
/// nil or empty → open one blank editor tab.
@property (nonatomic, copy, nullable) NSArray<NSURL *> *initialTabURLs;

/// Pre-loaded workspace model for .udworkspace files.  Set by
/// -readFromURL:ofType:error: before -windowDidLoad is called.  nil for
/// plain-file workspaces (window controller builds the model on demand).
@property (nonatomic, strong, nullable) UDWorkspaceModel *workspaceModel;

/// Text storage of the workspace's primary tab.  Set by
/// UDDocumentWindowController in -windowDidLoad.  Used by
/// -writeToURL:ofType:error: when saving a plain (non-workspace) document.
@property (nonatomic, readwrite, nullable) UDTextModelTextStorage *primaryTextStorage;

@end

NS_ASSUME_NONNULL_END
