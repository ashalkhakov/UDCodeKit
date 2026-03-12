/*---------------------------------------------------------------------------------------------
 *  UDTextEditing.m  —  Implementation of UDTextEdit.
 *--------------------------------------------------------------------------------------------*/

#import "UDTextEditing.h"

@implementation UDTextEdit

- (instancetype)initWithRange:(NSRange)range text:(NSString *)text {
    self = [super init];
    if (self) {
        _range = range;
        _text  = [text copy];
    }
    return self;
}

@end
