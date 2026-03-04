/*---------------------------------------------------------------------------------------------
 *  UDDocument.h
 *
 *  NSDocument subclass for the TestApp.
 *
 *  Owns the complete editor stack:
 *    - UDTextModelTextStorage (piece-table storage + tree-sitter syntax)
 *    - All editor accessories: line numbers, find, folding, bracket match,
 *      missing-node highlights, structured navigation, auto-indent
 *    - UDErrorsViewController (tree-sitter parse errors — unchanged)
 *    - UDLSPCoordinator (additive LSP layer; diagnostics appear on top)
 *    - UDDiagnosticTextView (inline LSP diagnostic labels)
 *--------------------------------------------------------------------------------------------*/

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface UDDocument : NSDocument

@end

NS_ASSUME_NONNULL_END
