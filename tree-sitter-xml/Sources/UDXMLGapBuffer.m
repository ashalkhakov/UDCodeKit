/*---------------------------------------------------------------------------------------------
 *  UDXMLGapBuffer.m
 *--------------------------------------------------------------------------------------------*/

#import "UDXMLGapBuffer.h"
#import <string.h>
#import <stdlib.h>

/// Initial gap size in unichars allocated when the buffer is first created.
static const NSUInteger kInitialGapSize = 256;

/// When the gap must grow, the new gap is at least this many unichars.
static const NSUInteger kGrowMinGapSize = 256;

@implementation UDXMLGapBuffer {
    unichar    *_buf;       ///< flat unichar allocation
    NSUInteger  _capacity;  ///< total allocated unichars (text + gap)
    NSUInteger  _gapStart;  ///< first gap slot (inclusive)
    NSUInteger  _gapEnd;    ///< first slot after gap (exclusive)
}

// ---------------------------------------------------------------------------
// MARK: - Init / dealloc
// ---------------------------------------------------------------------------

- (instancetype)initWithString:(NSString *)content {
    self = [super init];
    if (!self) return nil;

    NSUInteger len = content.length;
    _capacity  = len + kInitialGapSize;
    _buf       = (unichar *)malloc(_capacity * sizeof(unichar));
    if (!_buf) return nil;

    [content getCharacters:_buf range:NSMakeRange(0, len)];
    _gapStart  = len;
    _gapEnd    = _capacity;
    return self;
}

- (void)dealloc {
    free(_buf);
    _buf = NULL;
}

// ---------------------------------------------------------------------------
// MARK: - Public property
// ---------------------------------------------------------------------------

- (NSUInteger)length {
    return _capacity - (_gapEnd - _gapStart);
}

// ---------------------------------------------------------------------------
// MARK: - Gap management (private)
// ---------------------------------------------------------------------------

/// Move the gap so that _gapStart == position.
- (void)_moveGapTo:(NSUInteger)position {
    if (position == _gapStart) return;

    NSUInteger gapSize = _gapEnd - _gapStart;

    if (position < _gapStart) {
        // Move gap left: copy text that was before the gap to just after it.
        NSUInteger n = _gapStart - position;
        memmove(_buf + _gapEnd - n, _buf + position, n * sizeof(unichar));
    } else {
        // Move gap right: copy text that was after the gap to just before it.
        NSUInteger n = position - _gapStart;
        memmove(_buf + _gapStart, _buf + _gapEnd, n * sizeof(unichar));
    }
    _gapStart = position;
    _gapEnd   = position + gapSize;
}

/// Ensure the gap can fit at least @p needed unichars.
/// If the current gap is already large enough, this is a no-op.
- (void)_ensureGapCapacity:(NSUInteger)needed {
    NSUInteger gapSize = _gapEnd - _gapStart;
    if (gapSize >= needed) return;

    NSUInteger newGapSize = MAX(needed, kGrowMinGapSize) * 2;
    NSUInteger textLen    = _capacity - gapSize;
    NSUInteger newCap     = textLen + newGapSize;

    unichar *newBuf = (unichar *)malloc(newCap * sizeof(unichar));
    if (!newBuf) {
        NSLog(@"[UDXMLGapBuffer] -_ensureGapCapacity: malloc failed (requested %lu unichars); "
              @"buffer is no longer consistent — validation results may be incorrect",
              (unsigned long)newCap);
        return; // out of memory — buffer is left intact but may be too small to insert
    }

    // Copy pre-gap text.
    if (_gapStart > 0)
        memcpy(newBuf, _buf, _gapStart * sizeof(unichar));

    // Copy post-gap text at its new position.
    NSUInteger tailLen = _capacity - _gapEnd;
    if (tailLen > 0)
        memcpy(newBuf + _gapStart + newGapSize, _buf + _gapEnd, tailLen * sizeof(unichar));

    free(_buf);
    _buf      = newBuf;
    _gapEnd   = _gapStart + newGapSize;
    _capacity = newCap;
}

// ---------------------------------------------------------------------------
// MARK: - Public mutation
// ---------------------------------------------------------------------------

- (void)replaceCharactersInRange:(NSRange)range withString:(NSString *)replacement {
    NSUInteger deleteLen = range.length;
    NSUInteger insertLen = replacement.length;

    // 1. Move the gap to the start of the affected range.
    [self _moveGapTo:range.location];

    // 2. Absorb the deleted characters into the gap (extend gapEnd rightward).
    _gapEnd += deleteLen;

    // 3. Ensure the gap is large enough for the replacement text.
    if (insertLen > 0) {
        [self _ensureGapCapacity:insertLen];
        [replacement getCharacters:_buf + _gapStart range:NSMakeRange(0, insertLen)];
    }

    // 4. Consume the inserted characters from the front of the gap.
    _gapStart += insertLen;
}

// ---------------------------------------------------------------------------
// MARK: - UTF-8 slice
// ---------------------------------------------------------------------------

- (NSData *)utf8DataFromByte:(uint32_t)startByte toByte:(uint32_t)endByte {
    static const char kNul = '\0';

    // Convert tree-sitter byte offsets to char indices.
    // The redundant `startByte >= endByte` guard is intentional: it makes the
    // empty-range check explicit at the byte-offset level before the division.
    NSUInteger start = (NSUInteger)(startByte / 2);
    NSUInteger end   = (NSUInteger)(endByte   / 2);
    NSUInteger totalLen = self.length;

    if (start >= totalLen || end <= start) {
        return [NSData dataWithBytes:&kNul length:1];
    }
    if (end > totalLen) end = totalLen;
    NSUInteger sliceLen = end - start;

    // Allocate a temporary buffer for just the slice's unichar values.
    unichar *tmp = (unichar *)malloc(sliceLen * sizeof(unichar));
    if (!tmp) return [NSData dataWithBytes:&kNul length:1];

    // Fill from the two segments of the gap buffer, skipping the gap itself.
    //
    // Logical char index i maps to:
    //   i < _gapStart  →  _buf[i]
    //   i >= _gapStart →  _buf[_gapEnd + (i - _gapStart)]
    //
    NSUInteger written = 0;

    if (start < _gapStart) {
        // Pre-gap segment: chars [start, min(end, _gapStart))
        NSUInteger segEnd = (end < _gapStart) ? end : _gapStart;
        NSUInteger segLen = segEnd - start;
        memcpy(tmp, _buf + start, segLen * sizeof(unichar));
        written += segLen;
    }

    if (end > _gapStart) {
        // Post-gap segment: logical chars [max(start, _gapStart), end)
        //                   → _buf[_gapEnd + offset] where offset = i - _gapStart
        NSUInteger logicalStart = (start > _gapStart) ? start : _gapStart;
        NSUInteger offset       = logicalStart - _gapStart;
        NSUInteger segLen       = end - logicalStart;
        memcpy(tmp + written, _buf + _gapEnd + offset, segLen * sizeof(unichar));
        written += segLen;
    }

    NSAssert(written == sliceLen,
             @"[UDXMLGapBuffer] utf8DataFromByte:toByte: slice length mismatch: "
              "expected %lu, wrote %lu", (unsigned long)sliceLen, (unsigned long)written);

    // Wrap the unichar array in an NSString without copying (transfers ownership).
    // Foundation handles surrogate pairs and other encoding subtleties.
    NSString *sliceStr = [[NSString alloc] initWithCharactersNoCopy:tmp
                                                             length:sliceLen
                                                       freeWhenDone:YES];
    if (!sliceStr) {
        free(tmp);
        return [NSData dataWithBytes:&kNul length:1];
    }

    // Encode as UTF-8 and append a NUL terminator for libxml2 / C-string use.
    NSData *utf8 = [sliceStr dataUsingEncoding:NSUTF8StringEncoding];
    if (!utf8) return [NSData dataWithBytes:&kNul length:1];

    NSMutableData *result = [NSMutableData dataWithCapacity:utf8.length + 1];
    [result appendData:utf8];
    [result appendBytes:&kNul length:1];
    return result;
}

// ---------------------------------------------------------------------------
// MARK: - Snapshot
// ---------------------------------------------------------------------------

- (NSString *)snapshotString {
    NSUInteger len = self.length;
    if (len == 0) return @"";

    unichar *snapshot = (unichar *)malloc(len * sizeof(unichar));
    if (!snapshot) return @"";

    // Copy pre-gap text.
    if (_gapStart > 0)
        memcpy(snapshot, _buf, _gapStart * sizeof(unichar));

    // Copy post-gap text.
    NSUInteger tailLen = _capacity - _gapEnd;
    if (tailLen > 0)
        memcpy(snapshot + _gapStart, _buf + _gapEnd, tailLen * sizeof(unichar));

    // Hand off ownership of the snapshot buffer to the NSString to avoid a copy.
    NSString *result = [[NSString alloc] initWithCharactersNoCopy:snapshot
                                                           length:len
                                                     freeWhenDone:YES];
    if (!result) {
        free(snapshot);
        return @"";
    }
    return result;
}

@end
