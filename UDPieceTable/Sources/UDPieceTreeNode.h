/*---------------------------------------------------------------------------------------------
 *  Portions Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See LICENSE.txt for license information.
 *
 *  Objective-C port of VS Code's pieceTreeBase.ts
 *  Original source: https://github.com/microsoft/vscode/blob/main/src/vs/editor/common/model/pieceTreeTextBuffer/pieceTreeBase.ts
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import "UDTypes.h"

@class UDPiece;

NS_ASSUME_NONNULL_BEGIN

// MARK: - NodeColor

typedef NS_ENUM(NSInteger, UDPieceTreeNodeColor) {
    PTNodeColorBlack = 0,
    PTNodeColorRed   = 1,
};

// MARK: - TreeNode

@interface UDPieceTreeNode : NSObject
@property (nonatomic, weak, nullable)   UDPieceTreeNode *parent;
@property (nonatomic, strong, nullable) UDPieceTreeNode *left;
@property (nonatomic, strong, nullable) UDPieceTreeNode *right;
@property (nonatomic) UDPieceTreeNodeColor color;
@property (nonatomic, strong) UDPiece *piece;
@property (nonatomic) NSInteger sizeLeft; // size of left subtree
@property (nonatomic) NSInteger lfLeft;   // line feed count in left subtree

- (instancetype)initWithPiece:(nullable UDPiece *)piece color:(UDPieceTreeNodeColor)color;

/// Returns the in-order next node (or SENTINEL if none).
- (UDPieceTreeNode *)next;
/// Returns the in-order previous node (or SENTINEL if none).
- (UDPieceTreeNode *)prev;
/// Detaches this node from the tree (sets parent/left/right to nil).
- (void)detach;

@end

// MARK: - NodePosition

typedef struct {
    __unsafe_unretained UDPieceTreeNode *node;
    NSInteger remainder;
    NSInteger nodeStartOffset;
} PTNodePosition;

NS_ASSUME_NONNULL_END
