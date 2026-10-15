//
//  UDSyntaxHighlighter.m
//  UDCodeKit
//
//  Created by artyom on 3/8/26.
//


#import "UDSyntaxHighlighter.h"
#import <tree_sitter/api.h>
#import "UDTreeSitterTypes.h"
#import "UDDecorationLayerRegistry.h"

NSString * const UDHighlightDecorationOwner = @"highlight";

static NSInteger UDCompareRangeStarts(NSValue *x, NSValue *y, void *context) {
    NSUInteger a = x.rangeValue.location, b = y.rangeValue.location;
    return a < b ? NSOrderedAscending : a > b ? NSOrderedDescending : NSOrderedSame;
}


@implementation UDSyntaxHighlighter

// at the top, after @implementation:
+ (void)load {
    [self registerDecorationLayer];
}

+ (void)registerDecorationLayer {
    [[UDDecorationLayerRegistry shared]
        registerOwner:UDHighlightDecorationOwner
                layer:0
               target:self
               action:@selector(decorationAttributesForNode:)];
}

+ (NSDictionary *)decorationAttributesForNode:(UDIntervalNode *)node {
    // Resolved at draw time against the current theme via the text storage.
    // Return nil here; UDTextModelTextStorage._attrsForNode: handles theme
    // lookup because it needs access to self.theme.  This block is a
    // placeholder that keeps the layer ordering correct.
    return nil;
}

// ---------------------------------------------------------------------------
#pragma mark - UDDecorationHighlighter overrides
// ---------------------------------------------------------------------------

- (NSString *)decorationOwner {
    return UDHighlightDecorationOwner;
}

- (void)update {
    const TSTree *tree = (const TSTree *)self.highlighter.currentParseTree;
    if (!tree) { [self clearDecorations]; return; }

    UDTextModel *model  = self.textStorage.textModel;
    NSInteger    docLen = [model getLength];
    if (docLen <= 0) { [self clearDecorations]; return; }

    NSArray<NSValue *> *changedCharRanges = self.highlighter.lastChangedCharRanges;
    if (!changedCharRanges) {
        // A fresh parse: everything.
        NSMutableArray<UDModelDeltaDecoration *> *all = [NSMutableArray array];
        TSNode root = ts_tree_root_node((TSTree *)tree);
        TSRange full = {
            .start_byte  = ts_node_start_byte(root),
            .end_byte    = ts_node_end_byte(root),
            .start_point = ts_node_start_point(root),
            .end_point   = ts_node_end_point(root),
        };
        [self _collectDecorationsForRange:full tree:(TSTree *)tree previousEnd:0 into:all];
        [self commitDecorations:all];
        return;
    }
    if (changedCharRanges.count == 0) return;   // the tree did not change

    // The changed ranges, sorted and merged: disjoint, in document order.
    NSArray<NSValue *> *sorted = [changedCharRanges sortedArrayUsingFunction:UDCompareRangeStarts context:NULL];
    NSMutableArray<NSValue *> *merged = [NSMutableArray arrayWithCapacity:sorted.count];
    for (NSValue *v in sorted) {
        NSRange r = v.rangeValue;
        NSRange last = merged.lastObject.rangeValue;
        if (merged.count && r.location <= NSMaxRange(last)) {
            merged[merged.count - 1] = [NSValue valueWithRange:NSUnionRange(last, r)];
        } else {
            [merged addObject:v];
        }
    }

    // In each range: this highlighter's decorations there go, the captures
    // there come. A capture reaching back into the previous range was
    // collected with it; a decoration reaching into two ranges goes once.
    NSString *owner = UDHighlightDecorationOwner;
    NSMutableOrderedSet<NSString *> *stale = [NSMutableOrderedSet orderedSet];
    NSMutableArray<UDModelDeltaDecoration *> *fresh = [NSMutableArray array];
    uint32_t previousEnd = 0;
    for (NSValue *v in merged) {
        NSRange r = v.rangeValue;
        NSInteger s = (NSInteger)MIN(r.location, (NSUInteger)docLen);
        NSInteger end = (NSInteger)MIN(NSMaxRange(r), (NSUInteger)docLen);
        // What overlaps the range, and what a deletion there squashed to
        // nothing (an overlap query does not return empty decorations).
        for (UDIntervalNode *node in [model decorationNodesInOffsetRange:MAX(0, s - 1) end:end + 1]) {
            if (![node.owner isEqualToString:owner]) continue;
            BOOL overlaps = node.start < end && node.end > s;
            BOOL squashed = node.start == node.end && node.start >= s && node.start <= end;
            if (overlaps || squashed) [stale addObject:node.identifier];
        }
        if (s >= end) continue;
        TSRange tr = { .start_byte = (uint32_t)(s * 2), .end_byte = (uint32_t)(end * 2) };
        [self _collectDecorationsForRange:tr tree:(TSTree *)tree previousEnd:previousEnd into:fresh];
        previousEnd = tr.end_byte;
    }
    [model deltaDecorations:stale.array newDecorations:fresh owner:owner];
    [self.textStorage applyDecorationHighlights];
}

// Every highlight decoration in the model is this highlighter's (one per
// text storage), so it finds them by owner rather than keeping their IDs.
- (void)commitDecorations:(NSArray<UDModelDeltaDecoration *> *)newDecorations {
    UDTextModel *model = self.textStorage.textModel;
    [model deltaDecorations:[model decorationsForOwner:UDHighlightDecorationOwner]
             newDecorations:newDecorations
                      owner:UDHighlightDecorationOwner];
    [self.textStorage applyDecorationHighlights];
}

- (void)clearDecorations {
    [self commitDecorations:@[]];
}

- (void)dealloc {
    UDTextModel *model = self.textStorage.textModel;
    [model deltaDecorations:[model decorationsForOwner:UDHighlightDecorationOwner]
             newDecorations:@[]
                      owner:UDHighlightDecorationOwner];
}

// ---------------------------------------------------------------------------
#pragma mark - Decoration collection
// ---------------------------------------------------------------------------

/// The captures overlapping @a r, except those that start before
/// @a previousEnd (the end of a range already collected).
- (void)_collectDecorationsForRange:(TSRange)r
                               tree:(TSTree *)tree
                        previousEnd:(uint32_t)previousEnd
                               into:(NSMutableArray<UDModelDeltaDecoration *> *)out {
    TSNode         root        = ts_tree_root_node(tree);
    TSQuery       *query       = (TSQuery *)self.highlighter.currentQuery;
    TSQueryCursor *queryCursor = (TSQueryCursor *)self.highlighter.currentQueryCursor;

    if (query && queryCursor) {
        ts_query_cursor_exec(queryCursor, query, root);
        ts_query_cursor_set_byte_range(queryCursor, r.start_byte, r.end_byte);
        TSQueryMatch match;
        while (ts_query_cursor_next_match(queryCursor, &match)) {
            for (uint32_t i = 0; i < match.capture_count; i++) {
                TSQueryCapture cap = match.captures[i];
                uint32_t nb = ts_node_start_byte(cap.node);
                uint32_t ne = ts_node_end_byte(cap.node);
                if (ne <= r.start_byte || nb >= r.end_byte) continue;
                if (nb < r.start_byte && nb < previousEnd) continue;
                uint32_t nl  = 0;
                const char *cn =
                    ts_query_capture_name_for_id(query, cap.index, &nl);
                NSString *name =
                    [[NSString alloc] initWithBytes:cn length:nl
                                          encoding:NSUTF8StringEncoding];
                UDModelDeltaDecoration *d =
                    [self _makeDecorationFromByte:nb toByte:ne name:name];
                if (d) [out addObject:d];
            }
        }
    } else {
        [self _collectNodeDecorationsForNode:root inRange:r previousEnd:previousEnd into:out];
    }
}

- (void)_collectNodeDecorationsForNode:(TSNode)node
                                inRange:(TSRange)r
                            previousEnd:(uint32_t)previousEnd
                                   into:(NSMutableArray<UDModelDeltaDecoration *> *)out {
    uint32_t nb = ts_node_start_byte(node), ne = ts_node_end_byte(node);
    if (ne <= r.start_byte || nb >= r.end_byte) return;
    if (!(nb < r.start_byte && nb < previousEnd)) {
        NSString *type = [NSString stringWithUTF8String:ts_node_type(node)];
        UDModelDeltaDecoration *d = [self _makeDecorationFromByte:nb toByte:ne name:type];
        if (d) [out addObject:d];
    }
    uint32_t cc = ts_node_child_count(node);
    for (uint32_t i = 0; i < cc; i++) {
        [self _collectNodeDecorationsForNode:ts_node_child(node, i)
                                     inRange:r
                                 previousEnd:previousEnd
                                        into:out];
    }
}

- (nullable UDModelDeltaDecoration *)_makeDecorationFromByte:(uint32_t)startByte
                                                       toByte:(uint32_t)endByte
                                                         name:(NSString *)name {
    NSUInteger sc     = UDCharIndexFromByte(startByte);
    NSUInteger ec     = UDCharIndexFromByte(endByte);
    NSUInteger docLen = (NSUInteger)[self.textStorage.textModel getLength];
    if (sc >= ec || ec > docLen) return nil;

    UDTextModel *model = self.textStorage.textModel;
    UDPosition sp = [model getPositionAt:(NSInteger)sc];
    UDPosition ep = [model getPositionAt:(NSInteger)ec];
    UDRange ur = PTRangeMake(sp.line, sp.column, ep.line, ep.column);

    UDDecorationOptions *opts =
        [[UDDecorationOptions alloc] initWithClassName:name userInfo:nil];
    UDModelDeltaDecoration *d =
        [[UDModelDeltaDecoration alloc] initWithRange:ur options:opts];
    d.stickiness = UDTrackedRangeNeverGrowsWhenTypingAtEdges;
    return d;
}

@end
