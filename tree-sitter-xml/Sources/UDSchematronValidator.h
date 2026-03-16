/*---------------------------------------------------------------------------------------------
 *  UDSchematronValidator.h
 *
 *  Wraps libxml2's Schematron validation API.  Loads a compiled schema from a
 *  file URL and validates an xmlDoc, returning UDDiagnosticItem instances for
 *  each assertion failure.
 *
 *  Schematron validation is always full-document (there is no subtree API in
 *  libxml2's implementation).  Run it after RELAX NG validation completes.
 *
 *  Thread safety:
 *    All methods must be called on the same serial background queue (owned by
 *    UDXMLRNGHighlighter).
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import <libxml/tree.h>
#import "UDDiagnosticItem.h"

NS_ASSUME_NONNULL_BEGIN

/// Diagnostic source tag for Schematron errors.
extern UDDiagnosticSource const UDDiagnosticSourceSchematron;

/// Wraps libxml2's Schematron validation API.
///
/// Usage:
///   UDSchematronValidator *v = [[UDSchematronValidator alloc] init];
///   NSError *err;
///   if ([v setSchemaURL:schemaURL error:&err]) {
///       [v validateDoc:doc
///            lineIndex:lineIndex
///            lineCount:lineCount
///           completion:^(NSArray<UDDiagnosticItem *> *items) { … }];
///   }
@interface UDSchematronValidator : NSObject

/// Load and compile a Schematron schema from @p url.
///
/// Only @c file:// URLs pointing to @c .sch or @c .schematron files are
/// supported.  Returns @c YES on success; populates @p error on failure.
/// Replaces any previously loaded schema.
- (BOOL)setSchemaURL:(NSURL *)url error:(NSError *__autoreleasing _Nullable *)error;

/// Unload the current schema.  Subsequent calls to -validateDoc:… are no-ops.
- (void)clearSchema;

/// Validate @p doc against the loaded schema.
///
/// Schematron validation is always full-document.
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
