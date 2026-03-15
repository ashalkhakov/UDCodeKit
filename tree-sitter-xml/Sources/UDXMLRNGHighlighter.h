/*---------------------------------------------------------------------------------------------
 *  UDXMLRNGHighlighter.h
 *
 *  Implements UDDocumentService for RELAX NG schema validation.
 *
 *  Text handling (no full-document getValue on keystrokes):
 *    • -documentDidOpenWithContent: seeds the mirror doc's text buffer once.
 *    • -textWillChangeInRange:replacementString: accumulates pending edits
 *      (each is just the small replacement NSString, not the whole document).
 *    • -treeDidUpdateWithNewTree:changedRanges:textModel: drains the pending
 *      edits and dispatches a debounced validation block:
 *        – Keystroke path (changedRanges != nil, pending edits present):
 *            Applies each edit to the mirror doc's NSMutableString buffer
 *            (O(edit-size) per edit, never O(document-size)).  Each
 *            replacement string is transcoded UTF-16 → UTF-8 on the fly when
 *            the mirror doc passes it to libxml2 — no full UTF-8 copy is kept.
 *        – Full-rebuild path (changedRanges == nil or no pending edits):
 *            Calls [textModel getValue] on the main thread (safe), then resets
 *            the mirror doc buffer and rebuilds the xmlDoc from scratch.
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
