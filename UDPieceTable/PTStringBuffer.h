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

@interface PTStringBuffer : NSObject
@property (nonatomic, strong) NSString *buffer;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *lineStarts; // array of NSInteger offsets
- (instancetype)initWithBuffer:(NSString *)buffer lineStarts:(NSArray<NSNumber *> *)lineStarts;
@end

NS_ASSUME_NONNULL_END
