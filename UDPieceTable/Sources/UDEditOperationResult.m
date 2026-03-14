/*---------------------------------------------------------------------------------------------
 *  Portions Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See LICENSE.txt for license information.
 *
 *  Mirrors VS Code's EditOperationResult (cursorCommon.ts)
 *--------------------------------------------------------------------------------------------*/

#import "UDEditOperationResult.h"

@implementation UDEditOperationResult

- (instancetype)initWithType:(UDEditOperationType)type
                    commands:(NSArray<id<UDCommand>> *)commands
  shouldPushStackElementBefore:(BOOL)before
   shouldPushStackElementAfter:(BOOL)after {
    self = [super init];
    if (self) {
        _type                       = type;
        _commands                   = [commands copy];
        _shouldPushStackElementBefore = before;
        _shouldPushStackElementAfter  = after;
    }
    return self;
}

@end
