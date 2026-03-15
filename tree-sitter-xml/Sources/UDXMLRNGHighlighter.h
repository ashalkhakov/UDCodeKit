/*---------------------------------------------------------------------------------------------
 *  UDXMLRNGHighlighter.h
 *
 *  Implements UDDocumentValidator for RELAX NG schema validation.
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
#import "UDDocumentValidator.h"
#import "UDDiagnosticStore.h"

NS_ASSUME_NONNULL_BEGIN

/// Implements UDDocumentValidator for RELAX NG schema validation of XML documents.
@interface UDXMLRNGHighlighter : NSObject <UDDocumentValidator>

/// Designated initializer.
///
/// @param schemaURL  URL to the @c .rng (XML syntax) schema file.
/// @param store      Diagnostic store into which validation errors are published.
- (instancetype)initWithSchemaURL:(NSURL *)schemaURL
                            store:(UDDiagnosticStore *)store NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
