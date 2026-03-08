/*---------------------------------------------------------------------------------------------
 *  UDDocumentWindowController.h
 *
 *  NSWindowController subclass for UDDocument.  Loaded from
 *  UDDocumentWindowController.xib, which supplies only the bare window.
 *  The content is built entirely in -windowDidLoad:
 *
 *    • UDTextEditorViewController (from UDTextEditorViewController.xib) —
 *      text view, gutters, find field, folding, bracket-match, etc.
 *    • UDErrorsViewController (from UDErrorsView.xib) — diagnostic list.
 *
 *  These two view controllers are placed inside an NSSplitViewController
 *  that is set as the window's contentViewController, so no manual frame
 *  layout is required in this file.
 *
 *  Owns the diagnostic pipeline (missing-node / parse-error highlighters,
 *  parse-error collector, diagnostic store) and the LSP coordinator.
 *  UDDocument is kept intentionally thin — it only reads/writes the file.
 *--------------------------------------------------------------------------------------------*/

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface UDDocumentWindowController : NSWindowController

/// Called by UDDocument.writeSafelyToURL:… just before the file is written.
- (void)documentWillSave;

/// Called by UDDocument.writeSafelyToURL:… after the write attempt, whether or
/// not it succeeded.  The LSP server is informed either way.
- (void)documentDidSave:(BOOL)success;

/// Open a new blank editor tab (new empty JSON document).
/// Can be wired from a menu item or toolbar button.
- (IBAction)addEditorTab:(nullable id)sender;

/// Open a file in a new editor tab.
///
/// If the URL is already open in another tab a second *view* of the same
/// document is created (the two tabs share one UDTextModelTextStorage, so
/// edits in either are immediately visible in both).  If the URL has not been
/// opened yet a new independent document context is created.
///
/// If the file cannot be read the method logs an error and returns without
/// adding a tab.
- (void)openURLInNewTab:(NSURL *)url;

@end

NS_ASSUME_NONNULL_END
