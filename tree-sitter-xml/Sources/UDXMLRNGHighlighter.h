/*---------------------------------------------------------------------------------------------
 *  UDXMLRNGHighlighter.h
 *
 *  Implements UDDocumentService for RELAX NG schema validation of XML documents.
 *
 *  Text tracking — UDXMLGapBuffer:
 *    UDXMLRNGHighlighter maintains a UDXMLGapBuffer that mirrors the document text
 *    as a contiguous UTF-16 (unichar) array.  Edits are applied to the buffer in
 *    O(edit size) via -textWillChangeInRange:replacementString:, which fires before
 *    each tree-sitter re-parse.  This avoids calling [UDTextModel getValue] (which
 *    materialises the whole piece-tree into a new NSString) on every keystroke.
 *
 *    The buffer is seeded lazily on the first -treeDidUpdateWithNewTree: call.
 *    [textModel getValue] is called exactly once per document open — not per edit.
 *
 *  On each -treeDidUpdateWithNewTree:changedRanges:textModel: call (main thread):
 *    1. Lazy-initialises the gap buffer from [textModel getValue] if not yet seeded.
 *    2. Snapshots the gap buffer via -snapshotString (O(n), but not per keystroke —
 *       edits to the buffer are incremental O(edit size) via textWillChangeInRange:).
 *    3. Builds a pre-computed line-start index from the TextModel's internal
 *       piece-tree: lineIndex[i] = UTF-16 char offset of line i (0-indexed).
 *       This is O(lineCount) piece-tree lookups; no character-by-character scan.
 *       The line index is used ONLY by the RELAX NG validator to map libxml2
 *       error line numbers back to document character offsets.
 *    4. Copies the TSTree via ts_tree_copy().
 *    5. Debounces 150 ms, then on the private serial validation queue:
 *       a. Calls -applyTree:changedRanges:textSource: on UDXMLMirrorDoc,
 *          passing the snapshot.  The mirror doc uses ts_node_start_point().row
 *          for O(1) line numbers and extracts text slices on the fly.
 *       b. Runs RELAX NG validation.
 *       c. Publishes results to the UDDiagnosticStore on the main queue.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import "UDDocumentService.h"
#import "UDDiagnosticStore.h"

NS_ASSUME_NONNULL_BEGIN

/// Implements UDDocumentService for RELAX NG schema validation of XML documents.
@interface UDXMLRNGHighlighter : NSObject <UDDocumentService>

- (instancetype)initWithSchemaURL:(NSURL *)schemaURL
                            store:(UDDiagnosticStore *)store NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
