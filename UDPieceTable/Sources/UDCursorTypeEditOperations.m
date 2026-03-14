/*---------------------------------------------------------------------------------------------
 *  Portions Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See LICENSE.txt for license information.
 *
 *  Cursor-oriented operations.
 *  Original concept: https://github.com/microsoft/vscode/blob/main/src/vs/editor/common/cursor/cursorTypeEditOperations.ts
 *--------------------------------------------------------------------------------------------*/
#import "UDCursorTypeEditOperations.h"
#import "UDReplaceCommand.h"
#import "UDTextModel.h"

@implementation UDCursorTypeEditOperations

+ (UDEditOperationResult *)typeText:(NSString *)text
                  prevOperationType:(UDEditOperationType)prevType
                         selections:(NSArray<NSValue *> *)selections {
    NSMutableArray<id<UDCommand>> *commands = [NSMutableArray array];
    for (NSValue *v in selections) {
        UDSelection sel;
        [v getValue:&sel];
        [commands addObject:[[UDReplaceCommand alloc] initWithSelection:sel text:text]];
    }

    // Push a stack element between different operation types (VS Code's
    // shouldPushStackElementBetween logic, simplified).
    BOOL isTyping = (prevType == UDEditOperationTypeTypingOther
                  || prevType == UDEditOperationTypeTypingFirst);
    return [[UDEditOperationResult alloc]
              initWithType:UDEditOperationTypeTypingOther
                 commands:commands
  shouldPushStackElementBefore:!isTyping
   shouldPushStackElementAfter:NO];
}

+ (UDEditOperationResult *)deleteLeftWithSelections:(NSArray<NSValue *> *)selections
                                              model:(UDTextModel *)model {
    NSMutableArray<id<UDCommand>> *commands = [NSMutableArray array];
    for (NSValue *v in selections) {
        UDSelection sel;
        [v getValue:&sel];

        UDRange deleteRange;
        if (!UDSelectionIsEmpty(sel)) {
            // Delete the selection.
            deleteRange = UDRangeFromSelection(sel);
        } else {
            // Delete one character to the left of the cursor.
            NSInteger line = sel.positionLineNumber;
            NSInteger col  = sel.positionColumn;
            if (col > 1) {
                deleteRange = PTRangeMake(line, col - 1, line, col);
            } else if (line > 1) {
                NSInteger prevLineLen = [model getLineLength:line - 1];
                deleteRange = PTRangeMake(line - 1, prevLineLen + 1, line, 1);
            } else {
                // Already at beginning — no-op command.
                deleteRange = PTRangeMake(line, col, line, col);
            }
        }
        [commands addObject:[[UDReplaceCommand alloc]
                                initWithSelection:UDSelectionMake(deleteRange.startLineNumber,
                                                                   deleteRange.startColumn,
                                                                   deleteRange.endLineNumber,
                                                                   deleteRange.endColumn)
                                             text:@""]];
    }
    return [[UDEditOperationResult alloc]
              initWithType:UDEditOperationTypeOther
                 commands:commands
  shouldPushStackElementBefore:NO
   shouldPushStackElementAfter:NO];
}

+ (UDEditOperationResult *)deleteRightWithSelections:(NSArray<NSValue *> *)selections
                                               model:(UDTextModel *)model {
    NSMutableArray<id<UDCommand>> *commands = [NSMutableArray array];
    for (NSValue *v in selections) {
        UDSelection sel;
        [v getValue:&sel];

        UDRange deleteRange;
        if (!UDSelectionIsEmpty(sel)) {
            deleteRange = UDRangeFromSelection(sel);
        } else {
            NSInteger line    = sel.positionLineNumber;
            NSInteger col     = sel.positionColumn;
            NSInteger lineMax = [model getLineMaxColumn:line];
            if (col < lineMax) {
                deleteRange = PTRangeMake(line, col, line, col + 1);
            } else if (line < [model getLineCount]) {
                deleteRange = PTRangeMake(line, col, line + 1, 1);
            } else {
                deleteRange = PTRangeMake(line, col, line, col); // no-op
            }
        }
        [commands addObject:[[UDReplaceCommand alloc]
                                initWithSelection:UDSelectionMake(deleteRange.startLineNumber,
                                                                   deleteRange.startColumn,
                                                                   deleteRange.endLineNumber,
                                                                   deleteRange.endColumn)
                                             text:@""]];
    }
    return [[UDEditOperationResult alloc]
              initWithType:UDEditOperationTypeOther
                 commands:commands
  shouldPushStackElementBefore:NO
   shouldPushStackElementAfter:NO];
}

@end
