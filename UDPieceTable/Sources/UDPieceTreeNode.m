//
//  PTTreeNode.m
//  UDPieceTable
//
//  Created by artyom on 3/1/26.
//

#import "UDPieceTree+Internal.h"

// MARK: - UDPieceTreeNode

@implementation UDPieceTreeNode

- (instancetype)initWithPiece:(nullable UDPiece *)piece color:(UDPieceTreeNodeColor)color {
    self = [super init];
    if (self) {
        _piece    = piece;
        _color    = color;
        _sizeLeft = 0;
        _lfLeft   = 0;
        // Self-referential initially; caller must set up sentinel references.
        _parent = self;
        _left   = self;
        _right  = self;
    }
    return self;
}

- (UDPieceTreeNode *)next {
    UDPieceTreeNode *s = Sentinel();
    if (self.right != s) {
        return Leftest(self.right);
    }
    UDPieceTreeNode *node = self;
    while (node.parent != s) {
        if (node.parent.left == node) { break; }
        node = node.parent;
    }
    if (node.parent == s) { return s; }
    return node.parent;
}

- (UDPieceTreeNode *)prev {
    UDPieceTreeNode *s = Sentinel();
    if (self.left != s) {
        return Rightest(self.left);
    }
    UDPieceTreeNode *node = self;
    while (node.parent != s) {
        if (node.parent.right == node) { break; }
        node = node.parent;
    }
    if (node.parent == s) { return s; }
    return node.parent;
}

- (void)detach {
    _parent = nil;
    _left   = nil;
    _right  = nil;
}

@end
