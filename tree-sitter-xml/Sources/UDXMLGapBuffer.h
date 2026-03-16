/*---------------------------------------------------------------------------------------------
 *  UDXMLGapBuffer.h
 *
 *  A gap buffer storing the current document text as UTF-16 code units (unichar).
 *
 *  Maintained incrementally by UDXMLRNGHighlighter:
 *    - Initialised from the full content string once per document open.
 *    - Updated in O(edit size + gap-move) on each -textWillChangeInRange:
 *      callback, which fires before the tree-sitter re-parse.
 *    - A compact snapshot (gap collapsed) is taken at validation time and
 *      passed as the textSource: parameter to -applyTree:changedRanges:textSource:.
 *
 *  This avoids calling [UDTextModel getValue] (which materialises the whole
 *  piece-tree into a new NSString) on every keystroke.  Instead, getValue is
 *  called only once — on the very first treeDidUpdateWithNewTree: call — to
 *  seed the gap buffer; every subsequent edit is applied incrementally.
 *
 *  Thread safety:
 *    All mutating methods must be called on the main thread.
 *    -snapshotString creates and returns a new NSString that may be used on
 *    any thread after the method returns.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Gap buffer for incremental UTF-16 text tracking.
///
/// Internally stores text as a flat `unichar` array with a movable gap:
///
///   buf[ 0 .. gapStart )            — text before the gap
///   buf[ gapStart .. gapEnd )       — unused gap space
///   buf[ gapEnd .. capacity )       — text after the gap
///
/// Accessing, inserting, or deleting near the current gap position is O(1);
/// editing at a distant position requires an O(n) gap move.
@interface UDXMLGapBuffer : NSObject

/// Initialises the buffer with the given string content.
/// The gap is placed at the end of the initial content.
- (instancetype)initWithString:(NSString *)content NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// Applies a text edit: replaces the @p range of UTF-16 characters (0-based)
/// with the characters in @p replacement.
///
/// Must be called on the main thread.  Matches the NSRange used by
/// -textWillChangeInRange:replacementString: in UDDocumentService.
- (void)replaceCharactersInRange:(NSRange)range withString:(NSString *)replacement;

/// Total number of valid (non-gap) UTF-16 code units currently stored.
@property (nonatomic, readonly) NSUInteger length;

/// Returns a new compact NSString that is a snapshot of the current buffer
/// contents (gap collapsed).
///
/// The returned string is a fresh copy and may be retained and used on any
/// thread.  Calling this method does NOT modify the buffer.
- (NSString *)snapshotString;

@end

NS_ASSUME_NONNULL_END
