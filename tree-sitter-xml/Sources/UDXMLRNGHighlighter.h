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
 *    3. Copies the TSTree via ts_tree_copy().
 *    4. Debounces 150 ms, then on the private serial validation queue:
 *       a. Forwards the text snapshot and line index to UDXMLMirrorDoc via
 *          -updateTextSnapshot:lineIndexData:.
 *       b. Calls -applyTree:changedRanges: which performs a diffing rebuild:
 *          the existing libxml2 tree and the new tree-sitter tree are traversed
 *          in lockstep; added, deleted, and modified nodes are patched in-place.
 *       c. Runs RELAX NG validation from dirtyRoot (or the full document).
 *       d. Publishes results to the UDDiagnosticStore on the main queue.
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
