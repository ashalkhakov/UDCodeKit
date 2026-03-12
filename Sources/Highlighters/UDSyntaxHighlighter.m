//
//  UDSyntaxHighlighter.m
//  TestApp
//
//  Created by artyom on 3/8/26.
//


#import "UDSyntaxHighlighter.h"
#import <tree_sitter/api.h>
#import "UDDecorationLayerRegistry.h"

NSString * const UDHighlightDecorationOwner = @"highlight";

static inline NSUInteger charIdxFromByte(uint32_t b) { return b / 2; }

@implementation UDSyntaxHighlighter

// at the top, after @implementation:
+ (void)load {
    [self registerDecorationLayer];
}

+ (void)registerDecorationLayer {
    [[UDDecorationLayerRegistry shared]
        registerOwner:UDHighlightDecorationOwner
                layer:0
           attrBlock:^NSDictionary *(UDIntervalNode *node) {
        // Resolved at draw time against the current theme via the text storage.
        // Return nil here; UDTextModelTextStorage._attrsForNode: handles theme
        // lookup because it needs access to self.theme.  This block is a
        // placeholder that keeps the layer ordering correct.
        return nil;
    }];
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

    if (changedCharRanges) {
        // Incremental path: replace decorations only in the changed byte ranges.
        if (changedCharRanges.count == 0) return; // nothing changed

        // Convert char ranges → TSRanges for query filtering.
        NSUInteger n = changedCharRanges.count;
        TSRange *tsRanges = (TSRange *)malloc(n * sizeof(TSRange));
        for (NSUInteger i = 0; i < n; i++) {
            NSRange cr     = [changedCharRanges[i] rangeValue];
            TSPoint zero   = {0, 0};
            tsRanges[i]    = (TSRange){
                .start_byte  = (uint32_t)(cr.location * 2),
                .end_byte    = (uint32_t)(NSMaxRange(cr) * 2),
                .start_point = zero,
                .end_point   = zero,
            };
        }

        NSMutableArray<UDModelDeltaDecoration *> *newDecors = [NSMutableArray array];
        for (NSUInteger i = 0; i < n; i++) {
            [self _collectDecorationsForRange:tsRanges[i]
                                         tree:(TSTree *)tree
                                         into:newDecors];
        }

        [self _replaceDecorationsInTSRanges:tsRanges
                                      count:(uint32_t)n
                                 withNewOnes:newDecors
                                      docLen:(NSUInteger)docLen];
        free(tsRanges);

    } else {
        // Full path: replace all decorations.
        NSMutableArray<UDModelDeltaDecoration *> *all = [NSMutableArray array];
        TSNode root = ts_tree_root_node((TSTree *)tree);
        TSRange full = {
            .start_byte  = ts_node_start_byte(root),
            .end_byte    = ts_node_end_byte(root),
            .start_point = ts_node_start_point(root),
            .end_point   = ts_node_end_point(root),
        };
        [self _collectDecorationsForRange:full tree:(TSTree *)tree into:all];
        [self commitDecorations:all];
    }
}

// ---------------------------------------------------------------------------
#pragma mark - Decoration collection
// ---------------------------------------------------------------------------

- (void)_collectDecorationsForRange:(TSRange)r
                               tree:(TSTree *)tree
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
        [self _collectNodeDecorationsForNode:root inRange:r into:out];
    }
}

- (void)_collectNodeDecorationsForNode:(TSNode)node
                                inRange:(TSRange)r
                                   into:(NSMutableArray<UDModelDeltaDecoration *> *)out {
    uint32_t nb = ts_node_start_byte(node), ne = ts_node_end_byte(node);
    if (ne <= r.start_byte || nb >= r.end_byte) return;
    NSString *type = [NSString stringWithUTF8String:ts_node_type(node)];
    UDModelDeltaDecoration *d = [self _makeDecorationFromByte:nb toByte:ne name:type];
    if (d) [out addObject:d];
    uint32_t cc = ts_node_child_count(node);
    for (uint32_t i = 0; i < cc; i++) {
        [self _collectNodeDecorationsForNode:ts_node_child(node, i)
                                     inRange:r
                                        into:out];
    }
}

- (nullable UDModelDeltaDecoration *)_makeDecorationFromByte:(uint32_t)startByte
                                                       toByte:(uint32_t)endByte
                                                         name:(NSString *)name {
    NSUInteger sc     = charIdxFromByte(startByte);
    NSUInteger ec     = charIdxFromByte(endByte);
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

// ---------------------------------------------------------------------------
#pragma mark - Incremental decoration replacement
// ---------------------------------------------------------------------------

/// Replaces only the decorations that fall within the union of changedRanges,
/// preserving all others.  Calls through to UDDecorationHighlighter's
/// internal ID list via the protected -_replaceDecorationIDs:keeping:adding: hook.
- (void)_replaceDecorationsInTSRanges:(TSRange *)changedRanges
                                 count:(uint32_t)count
                            withNewOnes:(NSArray<UDModelDeltaDecoration *> *)newDecors
                                docLen:(NSUInteger)docLen {
    if (count == 0) return;

    // Union of all changed byte ranges → one character range for the lookup.
    uint32_t uStart = changedRanges[0].start_byte;
    uint32_t uEnd   = changedRanges[0].end_byte;
    for (uint32_t i = 1; i < count; i++) {
        if (changedRanges[i].start_byte < uStart) uStart = changedRanges[i].start_byte;
        if (changedRanges[i].end_byte   > uEnd)   uEnd   = changedRanges[i].end_byte;
    }

    NSUInteger sc = charIdxFromByte(uStart);
    NSUInteger ec = MIN(charIdxFromByte(uEnd), docLen);
    if (sc > docLen) return;

    UDTextModel *model = self.textStorage.textModel;
    UDPosition sp = [model getPositionAt:(NSInteger)sc];
    UDPosition ep = [model getPositionAt:(NSInteger)ec];
    UDRange cmr = PTRangeMake(sp.line, sp.column, ep.line, ep.column);

    // Ask the model which decoration IDs are inside the union range.
    NSSet *inRangeSet =
        [NSSet setWithArray:[model decorationsInRange:cmr]];

    // Partition: IDs inside the changed area are replaced; outside are kept.
    NSMutableArray<NSString *> *toRemove = [NSMutableArray array];
    NSMutableArray<NSString *> *toKeep   = [NSMutableArray array];
    for (NSString *did in [self _currentDecorationIDs]) {
        [([inRangeSet containsObject:did] ? toRemove : toKeep)
            addObject:did];
    }

    NSArray<NSString *> *added =
        [model deltaDecorations:toRemove
                 newDecorations:newDecors
                          owner:UDHighlightDecorationOwner];

    [self _setDecorationIDs:[toKeep arrayByAddingObjectsFromArray:added]];
}

@end
