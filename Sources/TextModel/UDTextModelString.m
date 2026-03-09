/*---------------------------------------------------------------------------------------------
 *  UDTextModelString.m
 *--------------------------------------------------------------------------------------------*/

#import "UDTextModelString.h"

@interface UDTextModelString ()
@property (nonatomic, strong) UDTextModel *model;
@end

@implementation UDTextModelString

- (instancetype)initWithTextModel:(UDTextModel *)model {
    self = [super init];
    if (self) {
        _model = model;
    }
    return self;
}

// NSString primitives -------------------------------------------------------

- (NSUInteger)length {
    return (NSUInteger)[_model getLength];
}

- (unichar)characterAtIndex:(NSUInteger)index {
    NSUInteger len = (NSUInteger)[_model getLength];
    if (index >= len) {
        @throw [NSException exceptionWithName:NSRangeException
            reason:[NSString stringWithFormat:
                @"UDTextModelString: index %lu out of bounds (length %lu)",
                (unsigned long)index, (unsigned long)len]
            userInfo:nil];
    }
    return [_model getCharacterAtOffset:index];
}

// NSString optimisation -------------------------------------------------------
//
// NSLayoutManager (and other Cocoa text machinery) reads characters both
// individually via characterAtIndex: and in bulk via getCharacters:range:.
// The default NSString implementation of getCharacters:range: repeatedly calls
// characterAtIndex:, which performs an O(log P) piece-tree traversal per
// character (P = number of pieces).
//
// By overriding getCharacters:range: we amortise the tree traversal: each
// piece in the requested range contributes at most one tree lookup, turning
// bulk reads of N characters spanning P pieces from O(N log P) to O(N + P).
// This is the hot path for NSLayoutManager glyph generation.

- (void)getCharacters:(unichar *)buffer range:(NSRange)aRange {
    NSInteger offset = (NSInteger)aRange.location;
    NSInteger end    = (NSInteger)NSMaxRange(aRange);
    unichar  *dst    = buffer;

    while (offset < end) {
        NSString *chunk = [_model getNearestChunkAtOffset:(NSUInteger)offset];
        // An empty chunk within a valid range indicates piece-tree corruption.
        NSCAssert(chunk.length > 0,
                  @"UDTextModelString: getNearestChunkAtOffset:%ld returned empty "
                  @"(docLen=%lu, rangeEnd=%ld)",
                  (long)offset, (unsigned long)[_model getLength], (long)end);
        if (chunk.length == 0) break;
        // Clamp to the requested range: the chunk may extend past 'end'.
        NSUInteger chunkLen = MIN(chunk.length, (NSUInteger)(end - offset));
        [chunk getCharacters:dst range:NSMakeRange(0, chunkLen)];
        dst    += chunkLen;
        offset += (NSInteger)chunkLen;
    }
}

@end
