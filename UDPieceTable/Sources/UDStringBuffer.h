/*---------------------------------------------------------------------------------------------
 *  Portions Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See LICENSE.txt for license information.
 *
 *  Objective-C port of VS Code's pieceTreeBase.ts
 *  Original source: https://github.com/microsoft/vscode/blob/main/src/vs/editor/common/model/pieceTreeTextBuffer/pieceTreeBase.ts
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// MARK: - StringBuffer

@interface UDStringBuffer : NSObject
/// The buffer's text. Original buffers never change; the change buffer
/// (buffers[0]) only grows, through -appendString:, so a range read from it
/// stays valid.
@property (nonatomic, readonly) NSString *buffer;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *lineStarts; // array of NSInteger offsets
- (instancetype)initWithBuffer:(NSString *)buffer lineStarts:(NSArray<NSNumber *> *)lineStarts;
/// Appends in place: amortised O(length of string), whatever the buffer's size.
- (void)appendString:(NSString *)string;
@end

NS_ASSUME_NONNULL_END
