/*---------------------------------------------------------------------------------------------
 *  UDXMLMirrorDoc.h
 *
 *  Maintains a live libxml2 xmlDoc that mirrors the Tree-sitter XML parse tree.
 *  Used by UDRNGValidator so that libxml2's relaxng.h API can validate the
 *  document structure without re-parsing the source text.
 *
 *  Text handling:
 *    UDXMLMirrorDoc does NOT own a text buffer.  The caller captures a text
 *    snapshot from UDTextModel.getValue on the main thread and forwards it (along
 *    with a pre-built line-start index) to the background serial queue via
 *    -updateTextSnapshot:lineIndexData: before each -applyTree:changedRanges: call.
 *
 *    Text slices for individual nodes are extracted on the fly from the
 *    snapshot and transcoded UTF-16 → UTF-8 via .UTF8String — no persistent
 *    UTF-8 copy of the whole document is kept.
 *
 *    Element line numbers are resolved in O(log n) via binary search on the
 *    pre-built line-start index, rather than O(char count) newline scans.
 *
 *  Rebuild strategy:
 *    -applyTree:changedRanges: uses a single "diffing rebuild" that traverses
 *    the existing libxml2 tree and the new tree-sitter tree in lockstep.  It
 *    finds (a) deleted nodes, (b) added nodes, and (c) modified nodes, then
 *    updates the libxml2 tree in-place, recording the shallowest dirty element
 *    in the `dirtyRoot` property for incremental revalidation by the caller.
 *
 *    A full build is performed on the first call (when there is no existing
 *    xmlDoc) or when the root element tag name has changed.
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
/// Before each -applyTree:changedRanges: call, the caller must update the
/// stored text snapshot via -updateTextSnapshot:lineIndexData:.  Both methods
/// must be called on the same serial background queue.
///
/// The xmlDoc is owned by this object; callers must not call xmlFreeDoc on it.
@interface UDXMLMirrorDoc : NSObject

/// The current mirror document.  Valid after a successful -applyTree:… call;
/// NULL if no tree has been built yet or the last build failed.
/// Do NOT free this pointer — it is owned by UDXMLMirrorDoc.
@property (nonatomic, readonly, nullable) xmlDocPtr xmlDoc;

/// The shallowest xmlNode that was changed during the most recent
/// -applyTree:changedRanges: call.  NULL if the document was unchanged.
/// The validator can use this to revalidate only the affected subtree.
/// Do NOT free this pointer — it is part of the xmlDoc tree.
@property (nonatomic, readonly, nullable) xmlNodePtr dirtyRoot;

// ---------------------------------------------------------------------------
// MARK: - Text snapshot management
// ---------------------------------------------------------------------------

/// Update the stored text snapshot and line-start index.
///
/// Must be called on the validation queue before each -applyTree:changedRanges:
/// call.  Both parameters are captured on the main thread from UDTextModel and
/// forwarded to the background queue.
///
/// @param text          Full document text snapshot (UTF-16 NSString).
/// @param lineIndexData NSData wrapping a C array of @c NSUInteger values where
///                      @c lineIndex[i] is the 0-based UTF-16 char offset of the
///                      start of 0-indexed line i.  @c lineIndex[0] == 0.
///                      The number of lines equals
///                      @c data.length / sizeof(NSUInteger).
- (void)updateTextSnapshot:(NSString *)text lineIndexData:(NSData *)lineIndexData;

// ---------------------------------------------------------------------------
// MARK: - XML tree operations
// ---------------------------------------------------------------------------

/// Diffing rebuild: traverses the old libxml2 tree and the new tree-sitter tree
/// in lockstep, detecting added, deleted, and modified nodes, then updates the
/// libxml2 tree in-place.
///
/// -updateTextSnapshot:lineIndexData: must have been called before this method.
///
/// On the first call (no existing xmlDoc) a full build is performed.
/// The @p changedRanges parameter is reserved for a future optimisation that
/// limits traversal to structurally changed regions; it is currently unused.
///
/// @param newTree       TSTree * (cast from const void *) produced by tree-sitter.
/// @param changedRanges NSArray of NSValue-wrapped NSRanges covering the
///                      structurally changed character regions.  May be nil.
- (void)applyTree:(const void *)newTree
    changedRanges:(nullable NSArray<NSValue *> *)changedRanges;

@end

NS_ASSUME_NONNULL_END
