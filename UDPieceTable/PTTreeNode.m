//
//  PTTreeNode.m
//  UDPieceTable
//
//  Created by artyom on 3/1/26.
//

#import "PTTreeNode.h"

extern PTTreeNode *Sentinel(void);
extern PTTreeNode *Leftest(PTTreeNode *node);
extern PTTreeNode *Rightest(PTTreeNode *node);

// MARK: - PTTreeNode

@implementation PTTreeNode

- (instancetype)initWithPiece:(nullable PTPiece *)piece color:(PTNodeColor)color {
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

- (PTTreeNode *)next {
    PTTreeNode *s = Sentinel();
    if (self.right != s) {
        return Leftest(self.right);
    }
    PTTreeNode *node = self;
    while (node.parent != s) {
        if (node.parent.left == node) { break; }
        node = node.parent;
    }
    if (node.parent == s) { return s; }
    return node.parent;
}

- (PTTreeNode *)prev {
    PTTreeNode *s = Sentinel();
    if (self.left != s) {
        return Rightest(self.left);
    }
    PTTreeNode *node = self;
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
