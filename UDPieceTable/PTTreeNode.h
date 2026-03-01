/*---------------------------------------------------------------------------------------------
 *  Portions Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See LICENSE.txt for license information.
 *
 *  Objective-C port of VS Code's pieceTreeBase.ts
 *  Original source: https://github.com/microsoft/vscode/blob/main/src/vs/editor/common/model/pieceTreeTextBuffer/pieceTreeBase.ts
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import "PTTypes.h"

@class PTPiece;

NS_ASSUME_NONNULL_BEGIN

// MARK: - NodeColor

typedef NS_ENUM(NSInteger, PTNodeColor) {
    PTNodeColorBlack = 0,
    PTNodeColorRed   = 1,
};

// MARK: - TreeNode

@interface PTTreeNode : NSObject
@property (nonatomic, weak, nullable)   PTTreeNode *parent;
@property (nonatomic, strong, nullable) PTTreeNode *left;
@property (nonatomic, strong, nullable) PTTreeNode *right;
@property (nonatomic) PTNodeColor color;
@property (nonatomic, strong) PTPiece *piece;
@property (nonatomic) NSInteger sizeLeft; // size of left subtree
@property (nonatomic) NSInteger lfLeft;   // line feed count in left subtree

- (instancetype)initWithPiece:(nullable PTPiece *)piece color:(PTNodeColor)color;

/// Returns the in-order next node (or SENTINEL if none).
- (PTTreeNode *)next;
/// Returns the in-order previous node (or SENTINEL if none).
- (PTTreeNode *)prev;
/// Detaches this node from the tree (sets parent/left/right to nil).
- (void)detach;

@end

// MARK: - NodePosition

typedef struct {
    __unsafe_unretained PTTreeNode *node;
    NSInteger remainder;
    NSInteger nodeStartOffset;
} PTNodePosition;

NS_ASSUME_NONNULL_END
