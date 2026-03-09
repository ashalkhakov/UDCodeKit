/*---------------------------------------------------------------------------------------------
 *  Portions Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See LICENSE.txt for license information.
 *
 *  Objective-C port of VS Code's intervalTree.ts (decoration-tracking subset)
 *  Original source: https://github.com/microsoft/vscode/blob/main/src/vs/editor/common/model/intervalTree.ts
 *--------------------------------------------------------------------------------------------*/

#import "UDIntervalTree.h"
#import "UDTextModel.h"   // for UDDecorationOptions

// MARK: - UDIntervalNode

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
        _options     = options;
        _owner       = [owner copy];
        _stickiness  = stickiness;
    }
    return self;
}

@end

// MARK: - nodeAcceptEdit (ported from VS Code intervalTree.ts)

/// Adjust one interval node's [start, end) given a single document edit.
///
/// @param node               The node to adjust (mutated in place).
/// @param editStart          Start of deleted region (= insertion point for pure inserts).
/// @param editEnd            End of deleted region (exclusive). Equal to editStart for pure inserts.
/// @param textLength         Number of characters inserted at editStart.
/// @param forceMoveMarkers   When YES the node is pushed past the edit regardless of stickiness.
///
/// Algorithm: direct port of VS Code's nodeAcceptEdit(), verified against the
/// 192 assertNodeAcceptEdit test cases in intervalTree.test.ts.
static void UDNodeAcceptEdit(UDIntervalNode *node,
                              NSInteger editStart,
                              NSInteger editEnd,
                              NSInteger textLength,
                              BOOL forceMoveMarkers) {
    NSInteger nodeStart    = node.start;
    NSInteger nodeEnd      = node.end;
    NSInteger deleteCount  = editEnd - editStart;
    NSInteger delta        = textLength - deleteCount;
    UDTrackedRangeStickiness stickiness = node.stickiness;

    // Node is entirely before the edit: nothing to do.
    if (nodeEnd < editStart) { return; }

    // forceMoveMarkers: push the node start (and end) past the edit unconditionally.
    if (forceMoveMarkers && nodeStart >= editStart) {
        if (nodeStart >= editEnd) {
            // After the deleted region: shift by net delta.
            node.start = nodeStart + delta;
        } else {
            // nodeStart is inside [editStart, editEnd): push to end of insert.
            node.start = editStart + textLength;
        }
        if (nodeEnd > editEnd) {
            node.end = nodeEnd + delta;
        } else {
            node.end = editStart + textLength;
        }
        return;
    }

    BOOL isPureInsertion = (deleteCount == 0);

    // ── Compute new start ──────────────────────────────────────────────────

    NSInteger newStart;

    if (nodeStart > editEnd) {
        // Start is strictly after the deleted region: shift by net delta.
        newStart = nodeStart + delta;

    } else if (nodeStart == editEnd) {
        // Start is at the right edge of the deleted region.
        if (isPureInsertion) {
            // Pure insertion at start boundary: apply stickiness.
            if (stickiness == UDTrackedRangeAlwaysGrowsWhenTypingAtEdges ||
                stickiness == UDTrackedRangeGrowsOnlyWhenTypingBefore) {
                newStart = nodeStart; // absorbs the insert (stays)
            } else {
                newStart = nodeStart + textLength; // pushed right of insert
            }
        } else {
            // After deletion: shift by net delta.
            newStart = nodeStart + delta;
        }

    } else if (nodeStart > editStart) {
        // Start is inside the deleted region [editStart, editEnd): collapse.
        newStart = editStart + textLength;

    } else {
        // nodeStart <= editStart: before or at the edit's start — stays.
        newStart = nodeStart;
    }

    // ── Compute new end ────────────────────────────────────────────────────

    NSInteger newEnd;

    if (nodeEnd > editEnd) {
        // End is after the deleted region: shift by net delta.
        newEnd = nodeEnd + delta;

    } else if (nodeEnd == editEnd) {
        // End is at the right edge of the deleted region.
        if (isPureInsertion) {
            // Pure insertion at end boundary: apply stickiness.
            if (stickiness == UDTrackedRangeAlwaysGrowsWhenTypingAtEdges ||
                stickiness == UDTrackedRangeGrowsOnlyWhenTypingAfter) {
                newEnd = nodeEnd + textLength; // grows right
            } else {
                newEnd = nodeEnd; // stays
            }
        } else {
            // Deletion ending at nodeEnd: collapse to end of insert.
            newEnd = editStart + textLength;
        }

    } else if (nodeEnd > editStart) {
        // End is inside the deleted region (editStart, editEnd): collapse.
        newEnd = editStart + textLength;

    } else {
        // nodeEnd == editStart (non-pure deletion only reaches here):
        // The range ends exactly where the deletion starts → unaffected.
        newEnd = nodeEnd;
    }

    node.start = newStart;
    node.end   = MAX(newStart, newEnd); // keep start <= end
}

// MARK: - UDIntervalTree

@implementation UDIntervalTree {
    NSMutableArray<UDIntervalNode *> *_nodes; // sorted by start, then end
    // Quick-lookup index for nodeWithIdentifier:
    NSMutableDictionary<NSString *, UDIntervalNode *> *_byID;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _nodes = [NSMutableArray array];
        _byID  = [NSMutableDictionary dictionary];
    }
    return self;
}

// MARK: Insert / Remove

- (void)insert:(UDIntervalNode *)node {
    // Binary-search insertion point to keep _nodes sorted by start.
    NSInteger lo = 0, hi = (NSInteger)_nodes.count;
    while (lo < hi) {
        NSInteger mid = (lo + hi) / 2;
        NSInteger midStart = _nodes[(NSUInteger)mid].start;
        if (midStart < node.start) {
            lo = mid + 1;
        } else if (midStart > node.start) {
            hi = mid;
        } else {
            // Same start: sort by end as a tiebreaker.
            if (_nodes[(NSUInteger)mid].end <= node.end) {
                lo = mid + 1;
            } else {
                hi = mid;
            }
        }
    }
    [_nodes insertObject:node atIndex:(NSUInteger)lo];
    _byID[node.identifier] = node;
}

- (void)remove:(UDIntervalNode *)node {
    [_nodes removeObjectIdenticalTo:node];
    [_byID removeObjectForKey:node.identifier];
}

// MARK: Lookup

- (nullable UDIntervalNode *)nodeWithIdentifier:(NSString *)identifier {
    return _byID[identifier];
}

- (NSArray<UDIntervalNode *> *)allNodes {
    return [_nodes copy];
}

// MARK: Range intersection

- (NSArray<UDIntervalNode *> *)nodesInRange:(NSInteger)queryStart
                                        end:(NSInteger)queryEnd {
    NSUInteger count = _nodes.count;
    if (count == 0) return @[];

    // Binary-search for the first index where node.start >= queryEnd.
    // All nodes at indices [0, upperBound) have start < queryEnd; nodes at
    // indices [upperBound, count) can never intersect [queryStart, queryEnd)
    // and are therefore skipped entirely.
    NSUInteger lo = 0, hi = count;
    while (lo < hi) {
        NSUInteger mid = lo + (hi - lo) / 2;
        if (_nodes[mid].start < queryEnd) {
            lo = mid + 1;
        } else {
            hi = mid;
        }
    }
    NSUInteger upperBound = lo;
    if (upperBound == 0) return @[];

    // A node intersects [queryStart, queryEnd) iff start < queryEnd (guaranteed by
    // upperBound) AND end > queryStart.
    NSMutableArray<UDIntervalNode *> *result = [NSMutableArray array];
    for (NSUInteger i = 0; i < upperBound; i++) {
        UDIntervalNode *n = _nodes[i];
        if (n.end > queryStart) {
            [result addObject:n];
        }
    }
    return [result copy];
}

// MARK: Edit adjustment

- (void)acceptEdit:(NSInteger)editStart
       deleteCount:(NSInteger)deleteCount
       insertCount:(NSInteger)insertCount
  forceMoveMarkers:(BOOL)forceMoveMarkers {
    NSInteger editEnd = editStart + deleteCount;
    for (UDIntervalNode *n in _nodes) {
        UDNodeAcceptEdit(n, editStart, editEnd, insertCount, forceMoveMarkers);
    }
    // Re-sort because offsets may have changed, invalidating the ordering.
    [_nodes sortUsingComparator:^NSComparisonResult(UDIntervalNode *a, UDIntervalNode *b) {
        if (a.start != b.start) {
            return (a.start < b.start) ? NSOrderedAscending : NSOrderedDescending;
        }
        if (a.end != b.end) {
            return (a.end < b.end) ? NSOrderedAscending : NSOrderedDescending;
        }
        return NSOrderedSame;
    }];
}

@end
