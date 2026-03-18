/*---------------------------------------------------------------------------------------------
 *  UDTSRNGValidator.h
 *
 *  Clark's derivative-based RELAX NG validator operating directly on the
 *  Tree-sitter parse tree, with incremental caching.
 *
 *  Why not libxml2?
 *    libxml2's xmlRelaxNG* API has well-known deficiencies: interleave patterns,
 *    attribute ordering, and some datatype checks are handled incorrectly.  In
 *    practice this means XSLT, XHTML and SVG schemas either produce no errors at
 *    all or produce false positives.
 *
 *  This validator follows James Clark's derivative-based algorithm:
 *    - Patterns are immutable, hash-consed (interned) objects; two structurally
 *      equal patterns are the same pointer.
 *    - childDeriv / startTagOpenDeriv / attsDeriv / endTagDeriv / textDeriv are
 *      translated directly from Clark's Haskell reference implementation.
 *    - <ref> patterns are kept as opaque tokens in the compiled schema and
 *      resolved lazily during validation, which handles recursive grammars
 *      naturally without separate fixpoint passes.
 *
 *  Incremental validation:
 *    The caller supplies a persistent NSMutableDictionary `cache`.  For each
 *    element node whose ts_node_has_changes() returns NO, the validator looks up
 *    (nodeId, entryPattern) → exitPattern in the cache and skips re-processing
 *    the entire subtree.  On a typical single-keystroke edit this reduces
 *    revalidated element count from O(document) to O(depth × siblings).
 *
 *  Schema loading:
 *    .rng files are parsed once with libxml2 (the schema file is static; the
 *    document being validated is accessed through the Tree-sitter TSNode API).
 *
 *  Thread safety:
 *    All methods must be called on the same serial background queue.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import "UDDiagnosticItem.h"

@class UDXMLGapBuffer;

NS_ASSUME_NONNULL_BEGIN

extern UDDiagnosticSource const UDDiagnosticSourceRNG; // RNG rules

@interface UDTSRNGValidator : NSObject

/// Load and compile a RELAX NG schema from a .rng (XML syntax) file.
/// Returns YES on success; populates outError on failure.
- (BOOL)setSchemaURL:(NSURL *)url error:(NSError *__autoreleasing _Nullable *)outError;

/// Unload the current schema and clear the intern table.
- (void)clearSchema;

/// Validate the document in @p tree against the loaded schema.
///
/// @param tree       TSTree * produced by tree-sitter, cast to const void *.
/// @param gapBuffer  Current document gap buffer (UTF-16 text).
/// @param cache      Persistent derivative cache; keep the same dict across calls
///                   for incremental speedups.  Clear or replace when the document
///                   is closed or a new schema is loaded.
/// @param completion Called synchronously before this method returns.  Receives all
///                   validation diagnostics (may be empty).
- (void)validateTree:(const void *)tree
           gapBuffer:(UDXMLGapBuffer *)gapBuffer
               cache:(NSMutableDictionary *)cache
          completion:(void (^)(NSArray<UDDiagnosticItem *> *diagnostics))completion;

@end

NS_ASSUME_NONNULL_END
