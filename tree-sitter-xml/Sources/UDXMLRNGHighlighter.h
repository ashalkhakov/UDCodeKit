/*---------------------------------------------------------------------------------------------
 *  UDXMLRNGHighlighter.h
 *
 *  Implements UDDocumentService for RELAX NG schema validation.
 *
 *  On each -treeDidUpdateWithNewTree:changedRanges:textModel: call (main thread):
 *    1. Copies the TSTree via ts_tree_copy().
 *    2. Retains the UDTextModel reference.
 *    3. Debounces 150 ms, then on a private serial queue:
 *       a. Reads the document text via [textModel getValue].
 *       b. Rebuilds the libxml2 mirror doc.
 *       c. Runs RELAX NG validation.
 *       d. Publishes results to the UDDiagnosticStore on the main queue.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import "UDDocumentService.h"
#import "UDDiagnosticStore.h"

NS_ASSUME_NONNULL_BEGIN

/// Implements UDDocumentService for RELAX NG schema validation of XML documents.
///
/// Responds to -treeDidUpdateWithNewTree:changedRanges:textModel: (tree lifecycle).
/// Debounces 150 ms, then on a private serial queue:
///   1. Reads the document text via [textModel getValue] (lazy — avoids main-thread stall).
///   2. Rebuilds the libxml2 mirror doc from the tree.
///   3. Runs RELAX NG validation.
///   4. Publishes results to the UDDiagnosticStore on the main queue.
@interface UDXMLRNGHighlighter : NSObject <UDDocumentService>

- (instancetype)initWithSchemaURL:(NSURL *)schemaURL
                            store:(UDDiagnosticStore *)store NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
