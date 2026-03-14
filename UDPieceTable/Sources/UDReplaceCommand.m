/*---------------------------------------------------------------------------------------------
 *  Portions Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See LICENSE.txt for license information.
 *
 *  Text replacement command.
 *  Original concept: https://github.com/microsoft/vscode/blob/main/src/vs/editor/common/commands/replaceCommand.ts
 *--------------------------------------------------------------------------------------------*/
#import "UDEditOperationResult.h"
#import "UDReplaceCommand.h"
#import "UDTextModel.h"

@implementation UDReplaceCommand {
    UDSelection _selection;
    NSString   *_text;
    BOOL        _hasTrackedOp;
}

- (instancetype)initWithSelection:(UDSelection)selection text:(NSString *)text {
    self = [super init];
    if (self) {
        _selection = selection;
        _text      = [text copy];
    }
    return self;
}

- (void)getEditOperationsForModel:(UDTextModel *)model
                          builder:(id<UDEditOperationBuilder>)builder {
    [builder addTrackedEditOperationWithRange:UDRangeFromSelection(_selection)
                                        text:_text];
}

- (UDSelection)computeCursorStateForModel:(UDTextModel *)model
                       inverseEditRanges:(NSArray<NSValue *> *)inverseEditRanges {
    // Place cursor at the end of the inserted text range (= start of undo range).
    UDRange r = UDRangeFromNSValue(inverseEditRanges.firstObject);
    return UDSelectionFromPosition(r.endLineNumber, r.endColumn);
}

@end
