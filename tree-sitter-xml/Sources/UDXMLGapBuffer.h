/*---------------------------------------------------------------------------------------------
 *  UDXMLGapBuffer.h
 *
 *  A gap buffer storing the current document text as UTF-16 code units (unichar).
 *
 *  Maintained incrementally by UDXMLRNGHighlighter:
 *    - Initialised from the full content string once per document open.
 *    - Updated in O(edit size + gap-move) on each -textWillChangeInRange:
 *      callback, which fires before the tree-sitter re-parse.
 *
 *  Text extraction:
 *    -utf8DataFromByte:toByte:intoBuffer: extracts only the requested slice from
 *    the internal unichar storage and encodes it as null-terminated UTF-8 into a
 *    caller-provided NSMutableData.  The buffer is reused across calls, so no
 *    new NSData object is allocated per slice.  The cost is proportional to the
 *    slice length, not the document length.
 *    UDXMLMirrorDoc keeps one NSMutableData (_sliceBuffer) and passes it on
 *    every call — the whole document is never materialised.
 *
 *  This avoids calling [UDTextModel getValue] (which materialises the whole
 *  piece-tree into a new NSString) on every keystroke.  Instead, getValue is
 *  called only once — on the very first treeDidUpdateWithNewTree: call — to
 *  seed the gap buffer; every subsequent edit is applied incrementally.
 *
 *  Thread safety:
 *    All mutating methods must be called on the main thread.
 *    -utf8DataFromByte:toByte:intoBuffer: is safe to call from any thread that is not
 *    concurrently mutating the buffer.
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

/// Fills @p buffer with the null-terminated UTF-8 encoding of the text span
/// @c [startByte, endByte), where byte offsets follow tree-sitter's convention:
/// a "byte" is a UTF-16 code-unit index multiplied by 2, so
/// @c charIndex = byteOffset / 2.
///
/// The buffer is truncated to zero length and then filled in-place — no new
/// NSData object is allocated.  After the call:
///   @c buffer.bytes  is a NUL-terminated UTF-8 C-string
///   @c buffer.length includes the NUL byte (content length = buffer.length - 1)
///
/// If the range is empty or out of bounds the buffer is set to a single NUL
/// byte (@c buffer.length == 1, @c buffer.bytes[0] == '\0').
///
/// This method is safe to call from any thread that is not concurrently
/// mutating the buffer.
- (void)utf8DataFromByte:(uint32_t)startByte
                  toByte:(uint32_t)endByte
              intoBuffer:(NSMutableData *)buffer;

/// Returns a new compact NSString that is a snapshot of the current buffer
/// contents (gap collapsed).
///
/// The returned string is a fresh copy and may be retained and used on any
/// thread.  Calling this method does NOT modify the buffer.
///
/// Intended for use in tests and diagnostics only.  The hot validation path
/// uses -utf8DataFromByte:toByte:intoBuffer: instead.
- (NSString *)snapshotString;

@end

NS_ASSUME_NONNULL_END
