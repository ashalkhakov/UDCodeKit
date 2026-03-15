/*---------------------------------------------------------------------------------------------
 *  UDXMLMirrorDoc.h
 *
 *  Maintains a live libxml2 xmlDoc that mirrors the Tree-sitter XML parse tree.
 *  Used by UDRNGValidator so that libxml2's relaxng.h API can validate the
 *  document structure without re-parsing the source text.
 *
 *  Text buffer:
 *    UDXMLMirrorDoc owns a private NSMutableString that is kept in sync with
 *    the document text without ever materialising the full document as a snapshot.
 *
 *    • -setInitialContent: seeds the buffer once (on document open or after undo).
 *    • -applyEditWithCharRange:replacement: applies each incremental edit (typed
 *      text, delete, etc.) in O(edit-size) time with no full-document copy.
 *    • When building XML nodes, text is extracted from the buffer by character
 *      range and transcoded UTF-16 → UTF-8 on the fly for libxml2 — no separate
 *      UTF-8 copy of the whole document is kept.
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
/// Call -setInitialContent: once before the first parse, then
/// -applyEditWithCharRange:replacement: for each subsequent keystroke.
/// Call -rebuildFromTree: for a full rebuild, or
/// -applyTree:changedRanges: for an update after an incremental re-parse.
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

/// The current text content of the internal buffer.  The returned string is
/// @c _textBuffer itself (not a copy); callers on the same serial queue may
/// read it safely.  Do not retain past the next -applyEditWithCharRange: call.
@property (nonatomic, readonly, nullable) NSString *textContent;

// ---------------------------------------------------------------------------
// MARK: - Text buffer management
// ---------------------------------------------------------------------------

/// Seeds the internal text buffer with @p content.
/// Call this once on document open and on any full-rebuild (undo/redo).
///
/// @param content  The full document text.
- (void)setInitialContent:(NSString *)content;

/// Applies a single incremental text edit to the internal buffer.
/// The parameters match those from -textWillChangeInRange:replacementString:.
///
/// Each replacement string is transcoded from UTF-16 to UTF-8 on the fly
/// when it is later passed to libxml2 — no full-document UTF-8 copy is made.
///
/// @param charRange   Pre-edit character range (0-based UTF-16 code units).
/// @param replacement Replacement string (may be empty for deletions).
- (void)applyEditWithCharRange:(NSRange)charRange replacement:(NSString *)replacement;

// ---------------------------------------------------------------------------
// MARK: - XML tree operations
// ---------------------------------------------------------------------------

/// Full rebuild from a complete parse tree using the internal text buffer.
/// Discards any previous xmlDoc.
///
/// @param tree  TSTree * (cast from const void *) produced by tree-sitter.
- (void)rebuildFromTree:(const void *)tree;

/// Incremental update driven by tree-sitter's changed ranges.
/// Falls back to a full rebuild when the changed ranges are nil or empty.
///
/// @param newTree       Newly parsed TSTree * (cast from const void *).
/// @param changedRanges NSArray of NSValue-wrapped NSRanges covering the
///                      structurally changed character regions.  May be nil.
- (void)applyTree:(const void *)newTree
    changedRanges:(nullable NSArray<NSValue *> *)changedRanges;

@end

NS_ASSUME_NONNULL_END
