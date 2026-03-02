/*---------------------------------------------------------------------------------------------
 *  Portions Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See LICENSE.txt for license information.
 *
 *  Objective-C port of VS Code's pieceTreeBase.ts
 *  Original source: https://github.com/microsoft/vscode/blob/main/src/vs/editor/common/model/pieceTreeTextBuffer/pieceTreeBase.ts
 *--------------------------------------------------------------------------------------------*/

#import "UDStringBuffer.h"

// MARK: - UDStringBuffer

@implementation UDStringBuffer

- (instancetype)initWithBuffer:(NSString *)buffer lineStarts:(NSArray<NSNumber *> *)lineStarts {
    self = [super init];
    if (self) {
        _buffer = [buffer copy];
        _lineStarts = [lineStarts mutableCopy];
    }
    return self;
}

@end
