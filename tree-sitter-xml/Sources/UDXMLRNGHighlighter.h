/*---------------------------------------------------------------------------------------------
 *  UDXMLRNGHighlighter.h
 *
 *  Implements UDDocumentService for RELAX NG schema validation of XML documents.
 *
 *  On each -treeDidUpdateWithNewTree:changedRanges:textModel: call (main thread):
 *    1. Captures a text snapshot via [textModel getValue] (main-thread safe).
 *    2. Builds a pre-computed line-start index from the TextModel's internal
 *       piece-tree: lineIndex[i] = UTF-16 char offset of line i (0-indexed).
 *       This is O(lineCount) piece-tree lookups; no character-by-character scan.
 *       The line index is used ONLY by the RELAX NG validator to map libxml2
 *       error line numbers back to document character offsets.
 *    3. Copies the TSTree via ts_tree_copy().
 *    4. Debounces 150 ms, then on the private serial validation queue:
 *       a. Calls -applyTree:changedRanges:textSource: on UDXMLMirrorDoc,
 *          passing the text snapshot directly.  The mirror doc uses
 *          ts_node_start_point().row for O(1) line numbers and extracts
 *          text slices from the snapshot on the fly — no persistent copy.
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
