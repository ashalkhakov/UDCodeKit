/*---------------------------------------------------------------------------------------------
 *  UDDocumentWindowController.h
 *
 *  NSWindowController subclass for UDDocument.  Loaded from
 *  UDDocumentWindowController.xib, which supplies the window, the main scroll
 *  view with the text view, and the find search field.  The line-number gutter,
 *  find-results gutter, and errors panel are added programmatically in
 *  -windowDidLoad because their frames depend on the window size at run time.
 *
 *  Owns the LSP coordinator and all editor-feature controllers (folding,
 *  bracket-match, missing-node highlights, structured navigation, auto-indent).
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
