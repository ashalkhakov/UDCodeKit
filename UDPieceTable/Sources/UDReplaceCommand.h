/*---------------------------------------------------------------------------------------------
 *  Portions Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See LICENSE.txt for license information.
 *
 *  Text replacement command.
 *  Original concept: https://github.com/microsoft/vscode/blob/main/src/vs/editor/common/commands/replaceCommand.ts
 *--------------------------------------------------------------------------------------------*/
#import <UDPieceTable/UDCommand.h>

NS_ASSUME_NONNULL_BEGIN

/// Replaces [range] with [text], then places the cursor at the end
/// of the inserted text. Mirrors VS Code's ReplaceCommand.
@interface UDReplaceCommand : NSObject <UDCommand>

- (instancetype)initWithSelection:(UDSelection)selection
                             text:(NSString *)text;
@end

NS_ASSUME_NONNULL_END
