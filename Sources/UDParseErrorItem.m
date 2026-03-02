/*---------------------------------------------------------------------------------------------
 *  UDParseErrorItem.m
 *--------------------------------------------------------------------------------------------*/

#import "UDParseErrorItem.h"

@implementation UDParseErrorItem

- (instancetype)initWithLine:(NSInteger)line
                      column:(NSInteger)column
                     message:(NSString *)message {
    self = [super init];
    if (self) {
        _line    = line;
        _column  = column;
        _message = [message copy];
    }
    return self;
}

@end
