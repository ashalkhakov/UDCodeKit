/*---------------------------------------------------------------------------------------------
 *  UDXMLRNGHighlighter.h
 *
 *  Implements UDDocumentService for RELAX NG schema validation of XML documents.
 *
 *  Text tracking — UDXMLGapBuffer:
 *    UDXMLRNGHighlighter maintains a UDXMLGapBuffer that mirrors the document text
 *    as a contiguous UTF-16 (unichar) array.  Edits are applied to the buffer in
 *    O(edit size) via -textWillChangeInRange:replacementString:, which fires before
 *    each tree-sitter re-parse.
 *
 *    On each -treeDidUpdateWithNewTree: call:
 *      1. The gap buffer is lazy-initialised from [textModel getValue] if not yet seeded
 *         (once per document open, not per keystroke).
 *      2. The gap buffer is captured by strong reference for the dispatch block —
 *         NO full-document snapshot is taken.  The gap buffer's
 *         -utf8DataFromByte:toByte:intoBuffer: method extracts only the text slices actually
 *         needed by UDXMLMirrorDoc, proportional to each individual node's size.
 *
 *  On each debounced validation (serial background queue):
 *    1. Builds a pre-computed line-start index from the TextModel's internal
 *       piece-tree: lineIndex[i] = UTF-16 char offset of line i (0-indexed).
 *       This is O(lineCount) piece-tree lookups; no character-by-character scan.
 *       The line index is used ONLY by the RELAX NG validator to map libxml2
 *       error line numbers back to document character offsets.
 *    2. Calls -applyTree:changedRanges:gapBuffer: on UDXMLMirrorDoc, passing the
 *       gap buffer directly.  UDXMLMirrorDoc calls -utf8DataFromByte:toByte:intoBuffer: on
 *       the buffer for each node it needs to encode — never the whole document.
 *    3. Runs RELAX NG validation.
 *    4. Publishes results to the UDDiagnosticStore on the main queue.
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
