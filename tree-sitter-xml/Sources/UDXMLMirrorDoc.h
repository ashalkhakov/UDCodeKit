/*---------------------------------------------------------------------------------------------
 *  UDXMLMirrorDoc.h
 *
 *  Maintains a live libxml2 xmlDoc that mirrors the Tree-sitter XML parse tree.
 *  Used by UDRNGValidator so that libxml2's relaxng.h API can validate the
 *  document structure without re-parsing the source text.
 *
 *  Text handling:
 *    UDXMLMirrorDoc does NOT own a persistent text buffer.  The caller passes
 *    a UDXMLGapBuffer reference directly to -applyTree:changedRanges:gapBuffer:.
 *    Text slices for individual XML nodes are extracted on the fly by calling
 *    -[UDXMLGapBuffer utf8DataFromByte:toByte:intoBuffer:], which encodes only the
 *    requested byte range as UTF-8 — no full-document snapshot is ever created.
 *
 *    Element line numbers are derived directly from tree-sitter node start points
 *    (TSPoint.row) in O(1) per node — no external line-start index is needed.
 *
 *  Rebuild strategy:
 *    -applyTree:changedRanges:gapBuffer: uses a single "diffing rebuild" that
 *    traverses the existing libxml2 tree and the new tree-sitter tree in lockstep.
 *    It finds (a) deleted nodes, (b) added nodes, and (c) modified nodes, then
 *    updates the libxml2 tree in-place, recording the shallowest dirty element
 *    in the `dirtyRoot` property for incremental revalidation by the caller.
 *
 *    A full build is performed on the first call (when there is no existing
 *    xmlDoc) or when the root element tag name has changed.
 *
 *  Thread safety:
 *    All methods must be called on the same serial background queue (owned by
 *    UDXMLRNGHighlighter).  The UDXMLGapBuffer passed to applyTree: is read but
 *    not retained past the return of that method.  The caller must ensure the
 *    buffer is not concurrently mutated while applyTree: is running.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import <libxml/tree.h>
#import <tree_sitter/api.h>

@class UDXMLGapBuffer;

NS_ASSUME_NONNULL_BEGIN

/// Maintains a live libxml2 xmlDoc mirroring the Tree-sitter XML parse tree.
///
/// Call -applyTree:changedRanges:gapBuffer: after each tree-sitter re-parse
/// to apply a diffing rebuild.  The xmlDoc is owned by this object; callers
/// must not call xmlFreeDoc on it.
@interface UDXMLMirrorDoc : NSObject

/// The current mirror document.  Valid after a successful
/// -applyTree:changedRanges:gapBuffer: call; NULL if no tree has been built
/// yet or the last build failed.
/// Do NOT free this pointer — it is owned by UDXMLMirrorDoc.
@property (nonatomic, readonly, nullable) xmlDocPtr xmlDoc;

/// The shallowest xmlNode that was changed during the most recent
/// -applyTree:changedRanges:gapBuffer: call.  NULL if the document was
/// unchanged.  The validator can use this to revalidate only the affected
/// subtree.  Do NOT free this pointer — it is part of the xmlDoc tree.
@property (nonatomic, readonly, nullable) xmlNodePtr dirtyRoot;

// ---------------------------------------------------------------------------
// MARK: - XML tree operations
// ---------------------------------------------------------------------------

/// Diffing rebuild: traverses the old libxml2 tree and the new tree-sitter tree
/// in lockstep, detecting added, deleted, and modified nodes, then updates the
/// libxml2 tree in-place.
///
/// On the first call (no existing xmlDoc) a full build is performed.
/// The @p changedRanges parameter is reserved for a future optimisation that
/// limits traversal to structurally changed regions; it is currently unused.
///
/// @param newTree       TSTree * (cast from const void *) produced by tree-sitter.
/// @param changedRanges NSArray of NSValue-wrapped NSRanges covering the
///                      structurally changed character regions.  May be nil.
/// @param gapBuffer     The current document gap buffer, used to extract UTF-8
///                      slices for XML element names, attribute names/values, and
///                      text content.  Tree-sitter byte offsets (UTF-16 char index
///                      × 2) are forwarded directly to
///                      -[UDXMLGapBuffer utf8DataFromByte:toByte:intoBuffer:] — no full-buffer
///                      snapshot is ever materialised.
///                      The buffer is NOT retained past the return of this method;
///                      the caller must ensure it is not concurrently mutated.
- (void)applyTree:(const void *)newTree
    changedRanges:(nullable NSArray<NSValue *> *)changedRanges
        gapBuffer:(UDXMLGapBuffer *)gapBuffer;

@end

NS_ASSUME_NONNULL_END
