/*---------------------------------------------------------------------------------------------
 *  UDDocumentValidator.h  —  Protocol for per-document incremental tree validators.
 *
 *  Extension bundles that need to react to tree-sitter parse results (e.g. for RELAX NG
 *  schema validation) return an object conforming to UDDocumentValidator from their
 *  -documentValidatorForDocumentURL:store: factory method (declared in UDExtension.h).
 *
 *  The host retains the validator for the lifetime of the editor tab and drives it by:
 *    1. Calling -treeDidUpdateWithNewTree:changedRanges:sourceText: after each parse.
 *    2. Calling -invalidate when the tab closes.
 *
 *  All calls are made on the main thread.  The validator is responsible for dispatching
 *  work to background queues as needed and for publishing results to the
 *  UDDiagnosticStore that was supplied at factory time.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol UDDocumentValidator <NSObject>

/// Called by the host after each tree-sitter re-parse completes.
///
/// Always called on the main thread.  The validator must not block.
///
/// @param newTree        The newly parsed TSTree * (opaque const void *).
///                       Valid only for the duration of this call.
///                       Call ts_tree_copy() if you need the tree beyond this call.
///                       Do NOT call ts_tree_delete() on the pointer passed here.
/// @param changedRanges  NSValue-wrapped NSRanges of the character regions that
///                       changed structurally between the previous and new parse trees.
///                       nil for a full re-parse (initial load, undo/redo, etc.).
/// @param sourceText     The complete UTF-16 document text after the edit.
- (void)treeDidUpdateWithNewTree:(const void *)newTree
                   changedRanges:(nullable NSArray<NSValue *> *)changedRanges
                      sourceText:(NSString *)sourceText;

/// Called when the document tab closes.
///
/// The validator must clear its diagnostics from the store and release all resources.
/// After this call the host releases its strong reference to the validator.
///
/// Always called on the main thread.
- (void)invalidate;

@end

NS_ASSUME_NONNULL_END
