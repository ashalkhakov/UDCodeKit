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

@end

NS_ASSUME_NONNULL_END
