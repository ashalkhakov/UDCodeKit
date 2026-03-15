/*---------------------------------------------------------------------------------------------
 *  UDRNGValidator.h
 *
 *  Wraps libxml2's RELAX NG validation API.  Loads a compiled schema from a
 *  file URL and validates an xmlDoc, returning UDDiagnosticItem instances for
 *  each validation error.
 *
 *  Thread safety:
 *    All methods must be called on the same serial background queue (owned by
 *    UDXMLRNGHighlighter).
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import <libxml/relaxng.h>
#import "UDDiagnosticItem.h"

NS_ASSUME_NONNULL_BEGIN

/// Wraps libxml2's RELAX NG validation API.
///
/// Usage:
///   UDRNGValidator *v = [[UDRNGValidator alloc] init];
///   NSError *err;
///   if ([v setSchemaURL:schemaURL error:&err]) {
///       [v validateDoc:mirrorDoc.xmlDoc
///            lineIndex:lineIndex
///            lineCount:lineCount
///           completion:^(NSArray<UDDiagnosticItem *> *items) { … }];
///   }
@interface UDRNGValidator : NSObject

/// Load and compile a RELAX NG schema from @p url.
///
/// Only @c file:// URLs pointing to @c .rng (XML syntax) files are supported
/// in this release.  Returns @c YES on success; populates @p error on failure.
/// Replaces any previously loaded schema.
- (BOOL)setSchemaURL:(NSURL *)url error:(NSError *__autoreleasing _Nullable *)error;

/// Unload the current schema.  Subsequent calls to -validateDoc:… are no-ops.
- (void)clearSchema;

/// Validate @p doc against the loaded schema.
///
/// @param doc         The xmlDoc to validate (produced by UDXMLMirrorDoc).
/// @param lineIndex   C array of NSUInteger values: @c lineIndex[i] is the
///                    0-based UTF-16 character offset of the start of
///                    line @c i (0-based line index).  @c lineIndex[0] == 0.
/// @param lineCount   Number of elements in @p lineIndex.
/// @param completion  Called synchronously before this method returns, on
///                    the same queue.  Receives an array of UDDiagnosticItem
///                    objects (may be empty).
- (void)validateDoc:(xmlDocPtr)doc
          lineIndex:(const NSUInteger *)lineIndex
          lineCount:(NSUInteger)lineCount
         completion:(void (^)(NSArray<UDDiagnosticItem *> *diagnostics))completion;

@end

NS_ASSUME_NONNULL_END
