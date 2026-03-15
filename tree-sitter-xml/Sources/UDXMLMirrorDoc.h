/*---------------------------------------------------------------------------------------------
 *  UDXMLMirrorDoc.h
 *
 *  Maintains a live libxml2 xmlDoc that mirrors the Tree-sitter XML parse tree.
 *  Used by UDRNGValidator so that libxml2's relaxng.h API can validate the
 *  document structure without re-parsing the source text.
 *
 *  Thread safety:
 *    All methods must be called on the same serial background queue (owned by
 *    UDXMLRNGHighlighter).
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import <libxml/tree.h>
#import <tree_sitter/api.h>

NS_ASSUME_NONNULL_BEGIN

/// Maintains a live libxml2 xmlDoc mirroring the Tree-sitter XML parse tree.
///
/// Call -rebuildFromTree:sourceText: for a full rebuild, or
/// -applyTree:changedRanges:rangeCount:sourceText: for an incremental update
/// after a Tree-sitter incremental re-parse.
///
/// The xmlDoc is owned by this object; callers must not call xmlFreeDoc on it.
@interface UDXMLMirrorDoc : NSObject

/// The current mirror document.  Valid after a successful -rebuild… or -apply…
/// call; NULL if no tree has been built yet or the last build failed.
/// Do NOT free this pointer — it is owned by UDXMLMirrorDoc.
@property (nonatomic, readonly, nullable) xmlDocPtr xmlDoc;

/// The xmlNode that was touched during the most recent incremental update.
/// The validator re-walks the subtree rooted here rather than the whole doc.
/// NULL after a full rebuild or if the last update was a no-op.
@property (nonatomic, readonly, nullable) xmlNodePtr dirtyRoot;

/// Full rebuild from a complete parse tree.  Discards any previous xmlDoc.
///
/// @param tree        TSTree * (cast from const void *) produced by tree-sitter.
/// @param sourceText  Full UTF-16 source text of the document (as stored by
///                    UDTextModel and parsed by tree-sitter with UTF-16 encoding).
- (void)rebuildFromTree:(const void *)tree
             sourceText:(NSString *)sourceText;

/// Incremental update driven by tree-sitter's changed ranges.
/// Falls back to a full rebuild when the changed ranges are nil or empty.
///
/// @param newTree       Newly parsed TSTree * (cast from const void *).
/// @param changedRanges NSArray of NSValue-wrapped NSRanges covering the
///                      structurally changed character regions.  May be nil.
/// @param sourceText    Full UTF-16 source text after the edit.
- (void)applyTree:(const void *)newTree
    changedRanges:(nullable NSArray<NSValue *> *)changedRanges
       sourceText:(NSString *)sourceText;

@end

NS_ASSUME_NONNULL_END
