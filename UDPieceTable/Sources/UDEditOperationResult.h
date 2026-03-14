/*---------------------------------------------------------------------------------------------
 *  Portions Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See LICENSE.txt for license information.
 *
 *  Cursor-oriented operations.
 *  Original concept: https://github.com/microsoft/vscode/blob/main/src/vs/editor/common/cursorCommon.ts
 *--------------------------------------------------------------------------------------------*/
#import <Foundation/Foundation.h>
#import <UDPieceTable/UDTypes.h>
#import <UDPieceTable/UDCommand.h>

NS_ASSUME_NONNULL_BEGIN

// MARK: - UDEditOperationType

typedef NS_ENUM(NSInteger, UDEditOperationType) {
    UDEditOperationTypeOther      = 0,
    UDEditOperationTypeTypingOther,
    UDEditOperationTypeTypingFirst,
};

// MARK: - UDEditOperationBuilder protocol

@protocol UDEditOperationBuilder <NSObject>
- (void)addEditOperationWithRange:(UDRange)range text:(nullable NSString *)text;
- (void)addTrackedEditOperationWithRange:(UDRange)range text:(nullable NSString *)text;
@end

// MARK: - UDEditOperationResult
// Bundles a set of per-cursor commands and stack/push metadata.

@interface UDEditOperationResult : NSObject
@property (nonatomic, readonly) UDEditOperationType type;
@property (nonatomic, readonly) NSArray<id<UDCommand>> *commands; // one per cursor
@property (nonatomic, readonly) BOOL shouldPushStackElementBefore;
@property (nonatomic, readonly) BOOL shouldPushStackElementAfter;

- (instancetype)initWithType:(UDEditOperationType)type
                    commands:(NSArray<id<UDCommand>> *)commands
  shouldPushStackElementBefore:(BOOL)before
   shouldPushStackElementAfter:(BOOL)after;
@end

NS_ASSUME_NONNULL_END
