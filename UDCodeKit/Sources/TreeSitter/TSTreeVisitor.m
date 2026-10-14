//
//  UDTreeSitterVisitor.m
//  TestApp
//
//  Created by artyom on 3/8/26.
//

#import "TSTreeVisitor.h"

typedef struct {
    TSNode     node;
    NSUInteger depth;
    BOOL       didFireWillVisit;
} TSVisitorFrame;

@implementation TSTreeVisitor

- (instancetype)initWithDelegate:(id<TSNodeVisitor>)delegate {
    self = [super init];
    if (self) {
        _delegate = delegate;
    }
    return self;
}

// ---------------------------------------------------------------------------
#pragma mark - Public entry points
// ---------------------------------------------------------------------------

- (void)visitTree:(TSNode)rootNode {
    id<TSNodeVisitor> delegate = self.delegate;
    if (!delegate) return;

    [self _notifyWillBegin];
    [self _runDFS:rootNode depth:0 delegate:delegate];
    [self _notifyDidFinish];
}

- (void)visitChangedByteRanges:(NSArray<NSValue *> *)changedByteRanges
                        inTree:(const TSTree *)tree {
    id<TSNodeVisitor> delegate = self.delegate;
    if (!delegate || !tree || changedByteRanges.count == 0) return;

    TSNode root = ts_tree_root_node((TSTree *)tree);

    [self _notifyWillBegin];
    for (NSValue *rv in changedByteRanges) {
        NSRange br = [rv rangeValue];
        if (br.length == 0) continue;

        uint32_t sb = (uint32_t)br.location;
        uint32_t eb = (uint32_t)NSMaxRange(br);
        TSNode subtree = ts_node_named_descendant_for_byte_range(root, sb, eb);
        if (ts_node_is_null(subtree)) continue;

        [self _runDFS:subtree depth:0 delegate:delegate];
    }
    [self _notifyDidFinish];
}

// ---------------------------------------------------------------------------
#pragma mark - Iterative DFS
// ---------------------------------------------------------------------------

- (void)_runDFS:(TSNode)startNode depth:(NSUInteger)startDepth
       delegate:(id<TSNodeVisitor>)delegate {

    BOOL wantsDidVisit = [delegate respondsToSelector:
                          @selector(visitor:didVisitNode:depth:)];

    NSMutableArray<NSValue *> *stack = [NSMutableArray array];

#define PUSH(n, d, fired)                                                   \
    do {                                                                    \
        TSVisitorFrame _f = {.node=(n), .depth=(d),                         \
                             .didFireWillVisit=(fired)};                    \
        [stack addObject:[NSValue valueWithBytes:&_f                        \
                                        objCType:@encode(TSVisitorFrame)]]; \
    } while(0)

    PUSH(startNode, startDepth, NO);

    while (stack.count > 0) {
        TSVisitorFrame frame;
        [stack.lastObject getValue:&frame];

        if (!frame.didFireWillVisit) {
            BOOL descend = [delegate visitor:self
                               willVisitNode:frame.node
                                       depth:frame.depth];

            // Replace top frame with visited=YES version.
            [stack removeLastObject];
            PUSH(frame.node, frame.depth, YES);

            if (descend) {
                uint32_t count = ts_node_child_count(frame.node);
                for (uint32_t i = count; i > 0; i--) {
                    PUSH(ts_node_child(frame.node, i - 1), frame.depth + 1, NO);
                }
            }
        } else {
            [stack removeLastObject];
            if (wantsDidVisit) {
                [delegate visitor:self didVisitNode:frame.node depth:frame.depth];
            }
        }
    }

#undef PUSH
}

// ---------------------------------------------------------------------------
#pragma mark - Traversal lifecycle helpers
// ---------------------------------------------------------------------------

- (void)_notifyWillBegin {
    id<TSNodeVisitor> d = self.delegate;
    if ([d respondsToSelector:@selector(visitorWillBeginTraversal:)]) {
        [d visitorWillBeginTraversal:self];
    }
}

- (void)_notifyDidFinish {
    id<TSNodeVisitor> d = self.delegate;
    if ([d respondsToSelector:@selector(visitorDidFinishTraversal:)]) {
        [d visitorDidFinishTraversal:self];
    }
}

@end
