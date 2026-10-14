/*---------------------------------------------------------------------------------------------
 *  Portions Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See LICENSE.txt for license information.
 *
 *  Decoration tracking after VS Code's intervalTree.ts: the node edit rules
 *  (stickiness) are a port of its nodeAcceptEdit; the tree is a treap with
 *  lazy offsets and subtree max-end, so that edits, inserts, removals and
 *  range queries cost O(log D) plus what they touch or return.
 *  Original source: https://github.com/microsoft/vscode/blob/main/src/vs/editor/common/model/intervalTree.ts
 *--------------------------------------------------------------------------------------------*/

#import "UDIntervalTree.h"
#import "UDTextModel.h"   // for UDDecorationOptions

// MARK: - Node
//
// Positions are stored relative to the node's frame: a node's absolute start
// is its _start plus the pending offsets (_lazy) of all its ancestors. _lazy
// applies to the node's children, not to the node itself. _maxEnd is the
// largest end in the subtree, in the node's frame.

@interface UDIntervalNode () {
@package
    NSInteger _start;
    NSInteger _end;
    NSInteger _maxEnd;
    NSInteger _lazy;
    NSUInteger _priority;
    NSUInteger _sequence;               // insertion order, breaks (start, end) ties
    UDIntervalNode *_left;
    UDIntervalNode *_right;
    __unsafe_unretained UDIntervalNode *_parent;   // nil for the root and for nodes out of a tree
    __weak UDIntervalTree *_tree;
    NSUInteger _cachedVersion;          // positions resolved at this tree version (+1; 0 = never)
    NSInteger _cachedStart;
    NSInteger _cachedEnd;
}
@end

@interface UDIntervalTree () {
@package
    NSUInteger _version;                // bumped whenever absolute positions may change
}
@end

@implementation UDIntervalNode

- (instancetype)initWithIdentifier:(NSString *)identifier
                             start:(NSInteger)start
                               end:(NSInteger)end
                           options:(UDDecorationOptions *)options
                             owner:(nullable NSString *)owner
                        stickiness:(UDTrackedRangeStickiness)stickiness {
    self = [super init];
    if (self) {
        _identifier  = [identifier copy];
        _start       = start;
        _end         = end;
        _maxEnd      = end;
        _options     = options;
        _owner       = [owner copy];
        _stickiness  = stickiness;
    }
    return self;
}

/// Resolves the node's absolute position: the sum of its ancestors' pending
/// offsets, O(depth) — or O(1) when resolved since positions last changed.
static void UDNodeResolve(UDIntervalNode *node, UDIntervalTree *tree) {
    if (node->_cachedVersion == tree->_version + 1) {
        return;
    }
    NSInteger offset = 0;
    for (UDIntervalNode *p = node->_parent; p != nil; p = p->_parent) {
        offset += p->_lazy;
    }
    node->_cachedStart = node->_start + offset;
    node->_cachedEnd = node->_end + offset;
    node->_cachedVersion = tree->_version + 1;
}

- (NSInteger)start {
    UDIntervalTree *tree = _tree;
    if (tree == nil) {
        return _start;
    }
    UDNodeResolve(self, tree);
    return _cachedStart;
}

- (NSInteger)end {
    UDIntervalTree *tree = _tree;
    if (tree == nil) {
        return _end;
    }
    UDNodeResolve(self, tree);
    return _cachedEnd;
}

@end

// MARK: - Edit rules (VS Code's nodeAcceptEdit)

/// Where the range [nodeStart, nodeEnd) goes when [editStart, editEnd) is
/// replaced with textLength characters.
static void UDRangeAcceptEdit(NSInteger nodeStart, NSInteger nodeEnd,
                              UDTrackedRangeStickiness stickiness,
                              NSInteger editStart, NSInteger editEnd,
                              NSInteger textLength, BOOL forceMoveMarkers,
                              NSInteger *outStart, NSInteger *outEnd) {
    NSInteger deleteCount = editEnd - editStart;
    NSInteger delta       = textLength - deleteCount;

    if (nodeEnd < editStart) {
        *outStart = nodeStart;
        *outEnd = nodeEnd;
        return;
    }

    if (forceMoveMarkers && nodeStart >= editStart) {
        *outStart = (nodeStart >= editEnd) ? nodeStart + delta : editStart + textLength;
        *outEnd   = (nodeEnd > editEnd) ? nodeEnd + delta : editStart + textLength;
        return;
    }

    BOOL isPureInsertion = (deleteCount == 0);

    // Start: touching the end of an insertion, stickiness decides.
    NSInteger newStart;
    if (nodeStart > editEnd) {
        newStart = nodeStart + delta;
    } else if (nodeStart == editEnd) {
        if (isPureInsertion) {
            if (stickiness == UDTrackedRangeAlwaysGrowsWhenTypingAtEdges ||
                stickiness == UDTrackedRangeGrowsOnlyWhenTypingBefore) {
                newStart = nodeStart;                      // absorbs the insert
            } else {
                newStart = nodeStart + textLength;         // pushed right of it
            }
        } else {
            newStart = nodeStart + delta;
        }
    } else if (nodeStart > editStart) {
        newStart = editStart + textLength;
    } else {
        newStart = nodeStart;
    }

    // End.
    NSInteger newEnd;
    if (nodeEnd > editEnd) {
        newEnd = nodeEnd + delta;
    } else if (nodeEnd == editEnd) {
        if (isPureInsertion) {
            if (stickiness == UDTrackedRangeAlwaysGrowsWhenTypingAtEdges ||
                stickiness == UDTrackedRangeGrowsOnlyWhenTypingAfter) {
                newEnd = nodeEnd + textLength;             // grows right
            } else {
                newEnd = nodeEnd;                          // stays
            }
        } else {
            newEnd = editStart + textLength;
        }
    } else if (nodeEnd > editStart) {
        newEnd = editStart + textLength;
    } else {
        newEnd = nodeEnd;
    }

    *outStart = newStart;
    *outEnd   = MAX(newStart, newEnd);                     // keep start <= end
}

// MARK: - Treap

static inline void UDShift(UDIntervalNode *c, NSInteger by) {
    c->_start  += by;
    c->_end    += by;
    c->_maxEnd += by;
    c->_lazy   += by;
}

/// Moves a node's pending offset into its children.
static inline void UDPushDown(UDIntervalNode *t) {
    NSInteger lazy = t->_lazy;
    if (lazy == 0) {
        return;
    }
    if (t->_left != nil) UDShift(t->_left, lazy);
    if (t->_right != nil) UDShift(t->_right, lazy);
    t->_lazy = 0;
}

/// Re-derives a node's subtree max-end and its children's parent pointers.
static inline void UDUpdate(UDIntervalNode *t) {
    NSInteger maxEnd = t->_end;
    if (t->_left != nil) {
        maxEnd = MAX(maxEnd, t->_left->_maxEnd + t->_lazy);
        t->_left->_parent = t;
    }
    if (t->_right != nil) {
        maxEnd = MAX(maxEnd, t->_right->_maxEnd + t->_lazy);
        t->_right->_parent = t;
    }
    t->_maxEnd = maxEnd;
}

/// (start, end, sequence) order.
static inline BOOL UDLess(NSInteger aStart, NSInteger aEnd, NSUInteger aSeq,
                          NSInteger bStart, NSInteger bEnd, NSUInteger bSeq) {
    if (aStart != bStart) return aStart < bStart;
    if (aEnd != bEnd) return aEnd < bEnd;
    return aSeq < bSeq;
}

/// Splits t into the nodes ordered before (start, end, sequence) and the rest.
static void UDSplitByKey(UDIntervalNode *t, NSInteger start, NSInteger end, NSUInteger sequence,
                         UDIntervalNode * __strong *outLeft, UDIntervalNode * __strong *outRight) {
    if (t == nil) {
        *outLeft = nil;
        *outRight = nil;
        return;
    }
    UDPushDown(t);
    UDIntervalNode *l = nil, *r = nil;
    if (UDLess(t->_start, t->_end, t->_sequence, start, end, sequence)) {
        UDSplitByKey(t->_right, start, end, sequence, &l, &r);
        t->_right = l;
        UDUpdate(t);
        if (r != nil) r->_parent = nil;
        *outLeft = t;
        *outRight = r;
    } else {
        UDSplitByKey(t->_left, start, end, sequence, &l, &r);
        t->_left = r;
        UDUpdate(t);
        if (l != nil) l->_parent = nil;
        *outLeft = l;
        *outRight = t;
    }
}

/// Splits t into the nodes starting at or before `start` and those after.
static void UDSplitAfterStart(UDIntervalNode *t, NSInteger start,
                              UDIntervalNode * __strong *outLeft, UDIntervalNode * __strong *outRight) {
    if (t == nil) {
        *outLeft = nil;
        *outRight = nil;
        return;
    }
    UDPushDown(t);
    UDIntervalNode *l = nil, *r = nil;
    if (t->_start <= start) {
        UDSplitAfterStart(t->_right, start, &l, &r);
        t->_right = l;
        UDUpdate(t);
        if (r != nil) r->_parent = nil;
        *outLeft = t;
        *outRight = r;
    } else {
        UDSplitAfterStart(t->_left, start, &l, &r);
        t->_left = r;
        UDUpdate(t);
        if (l != nil) l->_parent = nil;
        *outLeft = l;
        *outRight = t;
    }
}

/// Joins two treaps; every node of `left` orders before every node of `right`.
static UDIntervalNode *UDMerge(UDIntervalNode *left, UDIntervalNode *right) {
    if (left == nil) return right;
    if (right == nil) return left;
    if (left->_priority > right->_priority) {
        UDPushDown(left);
        left->_right = UDMerge(left->_right, right);
        UDUpdate(left);
        return left;
    } else {
        UDPushDown(right);
        right->_left = UDMerge(left, right->_left);
        UDUpdate(right);
        return right;
    }
}

/// In-order nodes intersecting [queryStart, queryEnd): start < queryEnd and
/// end > queryStart. `offset` turns the subtree's frame into absolute
/// positions; the positions found are cached on their nodes.
static void UDCollect(UDIntervalNode *t, NSInteger offset, NSInteger queryStart, NSInteger queryEnd,
                      NSUInteger cacheVersion, NSMutableArray<UDIntervalNode *> *result) {
    while (t != nil) {
        if (t->_maxEnd + offset <= queryStart) {
            return;                                          // nothing here ends after the query starts
        }
        NSInteger childOffset = offset + t->_lazy;
        UDCollect(t->_left, childOffset, queryStart, queryEnd, cacheVersion, result);
        NSInteger start = t->_start + offset;
        if (start >= queryEnd) {
            return;                                          // this node and its right subtree start too late
        }
        NSInteger end = t->_end + offset;
        if (end > queryStart) {
            t->_cachedStart = start;
            t->_cachedEnd = end;
            t->_cachedVersion = cacheVersion;
            [result addObject:t];
        }
        t = t->_right;                                       // the right subtree, iteratively
        offset = childOffset;
    }
}

/// Every node an edit of [editStart, editEnd) may change: start <= editEnd
/// and end >= editStart (closed bounds: a boundary touch is decided by
/// stickiness).
static void UDCollectTouched(UDIntervalNode *t, NSInteger offset, NSInteger editStart, NSInteger editEnd,
                             NSMutableArray<UDIntervalNode *> *result) {
    while (t != nil) {
        if (t->_maxEnd + offset < editStart) {
            return;
        }
        NSInteger childOffset = offset + t->_lazy;
        UDCollectTouched(t->_left, childOffset, editStart, editEnd, result);
        if (t->_start + offset > editEnd) {
            return;
        }
        if (t->_end + offset >= editStart) {
            [result addObject:t];
        }
        t = t->_right;
        offset = childOffset;
    }
}

static void UDCollectAll(UDIntervalNode *t, NSInteger offset, NSUInteger cacheVersion,
                         NSMutableArray<UDIntervalNode *> *result) {
    while (t != nil) {
        NSInteger childOffset = offset + t->_lazy;
        UDCollectAll(t->_left, childOffset, cacheVersion, result);
        t->_cachedStart = t->_start + offset;
        t->_cachedEnd = t->_end + offset;
        t->_cachedVersion = cacheVersion;
        [result addObject:t];
        t = t->_right;
        offset = childOffset;
    }
}

// MARK: - Tree

@implementation UDIntervalTree {
    UDIntervalNode *_root;
    NSMutableDictionary<NSString *, UDIntervalNode *> *_byID;
    NSMutableDictionary<id<NSCopying>, NSMutableSet<UDIntervalNode *> *> *_byOwner;   // owner (or NSNull) → nodes
    NSUInteger _nextSequence;
    uint64_t _random;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _byID = [NSMutableDictionary dictionary];
        _byOwner = [NSMutableDictionary dictionary];
        _random = 0x9E3779B97F4A7C15ULL;
    }
    return self;
}

- (NSUInteger)count {
    return _byID.count;
}

/// xorshift64*: priorities only need to be well spread, and this is the same
/// on every platform.
- (NSUInteger)nextPriority {
    _random ^= _random >> 12;
    _random ^= _random << 25;
    _random ^= _random >> 27;
    return (NSUInteger)(_random * 0x2545F4914F6CDD1DULL);
}

/// Puts a node, whose _start/_end are absolute, into the treap.
- (void)link:(UDIntervalNode *)node {
    node->_left = nil;
    node->_right = nil;
    node->_parent = nil;
    node->_lazy = 0;
    node->_maxEnd = node->_end;
    node->_tree = self;
    node->_cachedVersion = 0;
    UDIntervalNode *left = nil, *right = nil;
    UDSplitByKey(_root, node->_start, node->_end, node->_sequence, &left, &right);
    _root = UDMerge(UDMerge(left, node), right);
    _root->_parent = nil;
}

/// Takes a node out of the treap, leaving its absolute position in _start/_end.
- (void)unlink:(UDIntervalNode *)node {
    NSInteger start = node.start, end = node.end;
    UDIntervalNode *before = nil, *rest = nil, *it = nil, *after = nil;
    UDSplitByKey(_root, start, end, node->_sequence, &before, &rest);
    UDSplitByKey(rest, start, end, node->_sequence + 1, &it, &after);
    NSAssert(it == node && it->_left == nil && it->_right == nil,
             @"interval tree: node not found where its position says");
    _root = UDMerge(before, after);
    if (_root != nil) _root->_parent = nil;
    node->_start = start;
    node->_end = end;
    node->_maxEnd = end;
    node->_lazy = 0;
    node->_left = nil;
    node->_right = nil;
    node->_parent = nil;
    node->_tree = nil;
}

- (void)insert:(UDIntervalNode *)node {
    node->_sequence = _nextSequence++;
    node->_priority = [self nextPriority];
    [self link:node];
    _byID[node.identifier] = node;
    id ownerKey = node.owner ?: [NSNull null];
    NSMutableSet *owned = _byOwner[ownerKey];
    if (owned == nil) {
        owned = [NSMutableSet set];
        _byOwner[ownerKey] = owned;
    }
    [owned addObject:node];
}

- (void)remove:(UDIntervalNode *)node {
    if (_byID[node.identifier] != node) {
        return;
    }
    [self unlink:node];
    [_byID removeObjectForKey:node.identifier];
    id ownerKey = node.owner ?: [NSNull null];
    NSMutableSet *owned = _byOwner[ownerKey];
    [owned removeObject:node];
    if (owned.count == 0) {
        [_byOwner removeObjectForKey:ownerKey];
    }
}

- (nullable UDIntervalNode *)nodeWithIdentifier:(NSString *)identifier {
    return _byID[identifier];
}

- (NSArray<UDIntervalNode *> *)allNodes {
    NSMutableArray<UDIntervalNode *> *result = [NSMutableArray arrayWithCapacity:_byID.count];
    UDCollectAll(_root, 0, _version + 1, result);
    return result;
}

- (NSArray<UDIntervalNode *> *)nodesForOwner:(nullable NSString *)owner {
    NSArray<UDIntervalNode *> *owned = [_byOwner[owner ?: [NSNull null]] allObjects] ?: @[];
    return [owned sortedArrayUsingComparator:^NSComparisonResult(UDIntervalNode *a, UDIntervalNode *b) {
        NSInteger as = a.start, bs = b.start;
        if (as != bs) return as < bs ? NSOrderedAscending : NSOrderedDescending;
        NSInteger ae = a.end, be = b.end;
        if (ae != be) return ae < be ? NSOrderedAscending : NSOrderedDescending;
        return a->_sequence < b->_sequence ? NSOrderedAscending : NSOrderedDescending;
    }];
}

- (NSArray<UDIntervalNode *> *)nodesInRange:(NSInteger)queryStart
                                        end:(NSInteger)queryEnd {
    NSMutableArray<UDIntervalNode *> *result = [NSMutableArray array];
    UDCollect(_root, 0, queryStart, queryEnd, _version + 1, result);
    return result;
}

- (void)acceptEdit:(NSInteger)editStart
       deleteCount:(NSInteger)deleteCount
       insertCount:(NSInteger)insertCount
  forceMoveMarkers:(BOOL)forceMoveMarkers {
    NSInteger editEnd = editStart + deleteCount;
    NSInteger delta = insertCount - deleteCount;

    // 1. The nodes the edit touches: their stickiness decides where they go.
    NSMutableArray<UDIntervalNode *> *touched = [NSMutableArray array];
    UDCollectTouched(_root, 0, editStart, editEnd, touched);
    NSUInteger n = touched.count;
    NSInteger *starts = n ? malloc(n * sizeof(NSInteger)) : NULL;
    NSInteger *ends = n ? malloc(n * sizeof(NSInteger)) : NULL;
    for (NSUInteger i = 0; i < n; i++) {
        UDIntervalNode *node = touched[i];
        UDRangeAcceptEdit(node.start, node.end, node.stickiness, editStart, editEnd, insertCount,
                          forceMoveMarkers, &starts[i], &ends[i]);
    }
    for (UDIntervalNode *node in touched) {
        [self unlink:node];
    }

    // 2. Everything starting after the edit moves by delta, in one step: its
    // order, among itself and against what stays before, does not change.
    if (delta != 0) {
        UDIntervalNode *before = nil, *after = nil;
        UDSplitAfterStart(_root, editEnd, &before, &after);
        if (after != nil) {
            UDShift(after, delta);
        }
        _root = UDMerge(before, after);
        if (_root != nil) _root->_parent = nil;
    }
    _version++;

    // 3. The touched nodes go back where their new ranges belong.
    for (NSUInteger i = 0; i < n; i++) {
        UDIntervalNode *node = touched[i];
        node->_start = starts[i];
        node->_end = ends[i];
        [self link:node];
    }
    free(starts);
    free(ends);
}

@end
