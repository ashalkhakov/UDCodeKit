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

@end
