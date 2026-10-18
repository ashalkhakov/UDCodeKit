/*---------------------------------------------------------------------------------------------
 *  UDDocumentWindowController.h
 *
 *  NSWindowController for a UDWorkspace.  Loaded from
 *  UDDocumentWindowController.xib (bare window only).
 *  All content is built programmatically in -windowDidLoad:
 *
 *    NSSplitViewController
 *      ├── UDErrorsViewController   — diagnostic list (left, fixed width)
 *      └── NSTabViewController      — one or more editor tabs (right, resizable)
 *              └── UDCodeEditorViewController ×N
 *
 *  Each tab is backed by a UDEditorTabContext (defined privately in the .m).
 *  A context owns the text storage, diagnostics pipeline, and LSP coordinator
 *  for ONE document.  Multiple tabs may share a single context to provide
 *  multiple simultaneous views of the same file.
 *--------------------------------------------------------------------------------------------*/

#import <Cocoa/Cocoa.h>

@class UDDebugSession, UDBreakpointStore;

NS_ASSUME_NONNULL_BEGIN

@interface UDDocumentWindowController : NSWindowController

// MARK: - Workspace / save notifications (called by UDWorkspace)

/// Called by UDWorkspace just before the workspace file is written.
- (void)documentWillSave;

/// Called by UDWorkspace after the write attempt, whether or not it succeeded.
- (void)documentDidSave:(BOOL)success;

// MARK: - Tab management

/// Open a new blank editor tab backed by an empty JSON document.
/// Can be wired from a menu item or toolbar button.
- (IBAction)addEditorTab:(nullable id)sender;

/// Present an NSOpenPanel and open each selected file in a new tab.
- (IBAction)openFileInNewTab:(nullable id)sender;

/// Open a specific URL in a new tab.
///
/// • If the URL is already open in another tab, a second *view* of the same
///   document context is created — both tabs share one UDTextModelTextStorage,
///   so edits in either are immediately visible in both.
/// • If the URL has not been opened yet, a new independent context is created.
/// • If the file cannot be read, logs an error and returns without adding a tab.
- (void)openURLInNewTab:(NSURL *)url;

// MARK: - Debugging

/// The window's breakpoints, which its editors show and set.
@property (nonatomic, strong, readonly) UDBreakpointStore *breakpoints;

/// The session Debug > Run started last (kept when it ends, for its console).
@property (nonatomic, strong, readonly, nullable) UDDebugSession *debugSession;

/// The adapter Debug > Run starts for a language whose grammar bundle has
/// none: UDCode itself, as the demo adapter (UDCode --debug-adapter).
@property (nonatomic, copy) NSArray<NSString *> *debugAdapterCommand;

/// Debug > Run: a session for the selected file (saved: the adapter reads
/// it), with the adapter its language's bundle gives, or the demo's.
- (IBAction)startDebugging:(nullable id)sender;
- (IBAction)stopDebugging:(nullable id)sender;
- (IBAction)toggleDebugArea:(nullable id)sender;
- (IBAction)showDebugNavigator:(nullable id)sender;

// MARK: - Workspace state (used by UDWorkspace for workspace file serialisation)

/// Returns the ordered, de-duplicated list of file URLs currently open as tabs.
/// Tabs backed by unsaved (fileURL-less) contexts are omitted.
- (NSArray<NSURL *> *)currentOpenFileURLs;

@end

NS_ASSUME_NONNULL_END
