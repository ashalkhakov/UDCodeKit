/*---------------------------------------------------------------------------------------------
 *  Portions Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See LICENSE.txt for license information.
 *
 *  A command that modifies text/cursor state on a model.
 *  Original concept: https://github.com/microsoft/vscode/blob/main/src/vs/editor/common/editorCommon.ts
 *--------------------------------------------------------------------------------------------*/
#import <UDPieceTable/UDTypes.h>

NS_ASSUME_NONNULL_BEGIN

// MARK: - UDCommand protocol
// Mirrors VS Code's ICommand interface.

@class UDTextModel;
@protocol UDEditOperationBuilder;

@protocol UDCommand <NSObject>
/// Produce edit operations into `builder` for the given model.
- (void)getEditOperationsForModel:(UDTextModel *)model
                          builder:(id<UDEditOperationBuilder>)builder;
/// Compute the new cursor selection after the edit is applied.
/// `inverseEditRanges` is the array of UDRange after-edit result ranges,
/// one per addTrackedEditOperation call.
- (UDSelection)computeCursorStateForModel:(UDTextModel *)model
                       inverseEditRanges:(NSArray<NSValue *> *)inverseEditRanges;
@end

NS_ASSUME_NONNULL_END
