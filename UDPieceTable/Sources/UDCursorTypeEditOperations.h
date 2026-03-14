/*---------------------------------------------------------------------------------------------
 *  Portions Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See LICENSE.txt for license information.
 *
 *  Cursor-oriented operations.
 *  Original concept: https://github.com/microsoft/vscode/blob/main/src/vs/editor/common/cursor/cursorTypeEditOperations.ts
 *--------------------------------------------------------------------------------------------*/
#import <UDPieceTable/UDEditOperationResult.h>

NS_ASSUME_NONNULL_BEGIN

@class UDTextModel;

/// Pure functions that, given all cursor selections, produce an
/// UDEditOperationResult containing one UDCommand per cursor.
@interface UDCursorTypeEditOperations : NSObject

/// Insert `text` at every cursor (replacing any selected range).
/// Mirrors VS Code's TypeWithoutInterceptorsOperation.getEdits().
+ (UDEditOperationResult *)typeText:(NSString *)text
                  prevOperationType:(UDEditOperationType)prevType
                         selections:(NSArray<NSValue *> *)selections; // NSValue<UDSelection>

/// Delete the character before each cursor (backspace).
/// Mirrors VS Code's DeleteOperations.deleteLeft().
+ (UDEditOperationResult *)deleteLeftWithSelections:(NSArray<NSValue *> *)selections
                                              model:(UDTextModel *)model;

/// Delete the character after each cursor (forward-delete).
+ (UDEditOperationResult *)deleteRightWithSelections:(NSArray<NSValue *> *)selections
                                               model:(UDTextModel *)model;

@end

NS_ASSUME_NONNULL_END
