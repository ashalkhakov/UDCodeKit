/*---------------------------------------------------------------------------------------------
 *  UDDocumentService.h  —  Unified per-document lifecycle protocol.
 *
 *  Both LSP coordinators and tree-based validators (e.g. RELAX NG) follow the same
 *  per-tab lifecycle: they are created when a tab opens, receive change events while
 *  the tab is live, and are torn down when it closes.  UDDocumentService expresses
 *  that lifecycle with a single mandatory method (-closeDocument) and a set of
 *  @optional event methods that implementors subscribe to as needed.
 *
 *  The host keeps one NSArray<id<UDDocumentService>> per tab and fans out every
 *  event to all services that respond to it.  Services that publish diagnostics
 *  receive the UDDiagnosticStore at factory time (via UDExtension's
 *  -documentServiceForDocumentURL:store:) and write to it directly.
 *
 *  Event ordering per edit:
 *    1. -textWillChangeInRange:replacementString:   (before the edit is applied)
 *    2. NSTextStorageDidProcessEditingNotification fires; tree-sitter re-parses
 *    3. -treeDidUpdateWithNewTree:changedRanges:textModel:  (after re-parse)
 *
 *  Thread safety:
 *    All calls are made on the main thread.  Services are responsible for
 *    dispatching heavy work to their own background queues.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import <UDPieceTable/UDPieceTable.h>

NS_ASSUME_NONNULL_BEGIN

@protocol UDDocumentService <NSObject>

// ---------------------------------------------------------------------------
// MARK: - Mandatory
// ---------------------------------------------------------------------------

/// Called when the document tab closes.  Always on the main thread.
///
/// Services must clear their diagnostic partition from the store and release
/// all resources.  The host releases its strong reference after this call.
- (void)closeDocument;

// ---------------------------------------------------------------------------
// MARK: - Optional — text-change lifecycle (used by LSP and similar services)
// ---------------------------------------------------------------------------
@optional

/// Called once when the tab first activates, with the document's full text.
///
/// LSP implementations: use this to send @c textDocument/didOpen.
/// The content string is already materialised (it was needed to open the
/// document), so passing it here costs nothing extra.
- (void)documentDidOpenWithContent:(NSString *)content;

/// Called just before each text edit, before the tree-sitter re-parse.
///
/// LSP implementations: use this to send @c textDocument/didChange.
- (void)textWillChangeInRange:(NSRange)range
            replacementString:(NSString *)replacement;

/// Called before and after each save operation.
- (void)documentWillSave;
- (void)documentDidSave;

// ---------------------------------------------------------------------------
// MARK: - Optional — tree-change lifecycle (used by tree-based validators)
// ---------------------------------------------------------------------------

/// Called after each tree-sitter re-parse completes.  Always on the main thread.
/// Implementations must not block; dispatch expensive work to a background queue.
///
/// @param newTree        Newly parsed TSTree * (opaque @c const void *).
///                       Valid only for the duration of this call.
///                       Call @c ts_tree_copy() to keep it past the return.
///                       Do @b not call @c ts_tree_delete() on the passed pointer.
/// @param changedRanges  @c NSValue-wrapped @c NSRange character regions that changed
///                       structurally between the previous and new parse trees.
///                       @c nil for a full re-parse (initial load, undo/redo, etc.).
/// @param textModel      The document text model.  Do @b not call @c -getValue on
///                       the main thread; capture this reference and call @c -getValue
///                       from a background queue when the text is actually needed.
- (void)treeDidUpdateWithNewTree:(const void *)newTree
                   changedRanges:(nullable NSArray<NSValue *> *)changedRanges
                       textModel:(UDTextModel *)textModel;

@end

NS_ASSUME_NONNULL_END
