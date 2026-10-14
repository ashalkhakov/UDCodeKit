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
// By overriding getCharacters:range: we use fillCharacters:range: on the
// piece tree, which iterates once per piece boundary and calls
// [NSString getCharacters:range:] on the raw backing buffers directly.
// This is essentially a memcpy per piece with zero intermediate allocations,
// reducing bulk reads of N characters spanning P pieces from O(N·log P) to
// O(N + P).  In particular it avoids the substringWithRange: allocation that
// getNearestChunkAtOffset: produces per piece (up to 65 KB per call).

- (void)getCharacters:(unichar *)buffer range:(NSRange)aRange {
    [_model fillCharacters:buffer range:aRange];
}

@end
