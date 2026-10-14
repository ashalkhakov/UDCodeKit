/*---------------------------------------------------------------------------------------------
 *  Portions Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See LICENSE.txt for license information.
 *
 *  Objective-C port of VS Code's pieceTreeBase.ts
 *  Original source: https://github.com/microsoft/vscode/blob/main/src/vs/editor/common/model/pieceTreeTextBuffer/pieceTreeBase.ts
 *--------------------------------------------------------------------------------------------*/

#import "UDStringBuffer.h"

// MARK: - UDStringBuffer

@implementation UDStringBuffer {
    NSString *_buffer;
    NSMutableString *_mutableBuffer;   // set once the buffer is first appended to
}

- (instancetype)initWithBuffer:(NSString *)buffer lineStarts:(NSArray<NSNumber *> *)lineStarts {
    self = [super init];
    if (self) {
        _buffer = [buffer copy];
        _lineStarts = [lineStarts mutableCopy];
    }
    return self;
}

- (NSString *)buffer {
    return _mutableBuffer ?: _buffer;
}

- (void)appendString:(NSString *)string {
    if (_mutableBuffer == nil) {
        _mutableBuffer = [_buffer mutableCopy];   // once; appends then grow it in place
        _buffer = nil;
    }
    [_mutableBuffer appendString:string];
}

@end
