/*---------------------------------------------------------------------------------------------
 *  UDXMLRNGHighlighter.h
 *
 *  Implements UDDocumentService for RELAX NG schema validation.
 *
 *  On each -treeDidUpdateWithNewTree:changedRanges:sourceText: call (main thread):
 *    1. Drains accumulated pending edits (captured from -textWillChangeInRange:).
 *    2. Copies the TSTree via ts_tree_copy().
 *    3. Debounces 150 ms, then on a private serial queue:
 *       a. Applies any pending edits to the mirror doc's internal text buffer.
 *       b. Rebuilds the libxml2 mirror doc from the tree + updated buffer.
 *       c. Runs RELAX NG validation.
 *       d. Publishes results to the UDDiagnosticStore on the main queue.
 *
 *  The sourceText parameter in step 3 is the string snapshot that tree-sitter
 *  used to produce the parse tree.  It is already in memory (computed by
 *  UDTreeSitterHighlighter during processEditing) and never causes an extra
 *  -getValue traversal of the piece table.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import "UDDocumentService.h"
#import "UDDiagnosticStore.h"

NS_ASSUME_NONNULL_BEGIN

/// Implements UDDocumentService for RELAX NG schema validation of XML documents.
///
/// Responds to -treeDidUpdateWithNewTree:changedRanges:sourceText: (tree lifecycle)
/// and -textWillChangeInRange:replacementString: (edit accumulation).
@interface UDXMLRNGHighlighter : NSObject <UDDocumentService>

- (instancetype)initWithSchemaURL:(NSURL *)schemaURL
                            store:(UDDiagnosticStore *)store NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
