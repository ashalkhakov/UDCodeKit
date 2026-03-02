/*---------------------------------------------------------------------------------------------
 *  UDMissingNodeHighlighter.m
 *--------------------------------------------------------------------------------------------*/

#import "UDMissingNodeHighlighter.h"
#import <tree_sitter/api.h>
#import <UDPieceTable/UDIntervalTree.h>

// Tree-sitter stores byte offsets in UTF-16 (2 bytes per BMP code unit).
// Supplementary characters (U+10000+) use surrogate pairs (4 bytes each),
// so for ASCII/BMP-only content this conversion is exact.
static inline NSUInteger charFromByte(uint32_t b) { return (NSUInteger)(b / 2); }
static inline uint32_t   byteFromChar(NSUInteger c) { return (uint32_t)(c * 2); }

/// Default cap on the total number of MISSING-node pill decorations.
static const NSUInteger kDefaultMaxMissingDecorations = 100;

@interface UDMissingNodeHighlighter ()
@property (nonatomic, weak)   UDTextModelTextStorage  *textStorage;
@property (nonatomic, weak)   UDTreeSitterHighlighter *highlighter;
// All current MISSING-node decoration IDs (across all scanned ranges).
@property (nonatomic, copy)   NSArray<NSString *>     *decorationIDs;
@end

@implementation UDMissingNodeHighlighter

// ---------------------------------------------------------------------------
// MARK: - Init / dealloc
// ---------------------------------------------------------------------------

- (instancetype)initWithTextStorage:(UDTextModelTextStorage *)textStorage
                         highlighter:(UDTreeSitterHighlighter *)highlighter {
    self = [super init];
    if (!self) return nil;
    _textStorage    = textStorage;
    _highlighter    = highlighter;
    _decorationIDs  = @[];
    _maxDecorations = kDefaultMaxMissingDecorations;
    return self;
}

- (void)dealloc {
    // Clear decorations on teardown.
    UDTextModel *model = _textStorage.textModel;
    if (_decorationIDs.count) {
        [model deltaDecorations:_decorationIDs
                 newDecorations:@[]
                          owner:UDMissingNodeDecorationOwner];
    }
}

// ---------------------------------------------------------------------------
// MARK: - Public API
// ---------------------------------------------------------------------------

- (void)update {
    const TSTree *tree = (const TSTree *)_highlighter.currentParseTree;
    if (!tree) {
        [self _clearDecorations];
        return;
    }

    UDTextModel *model = _textStorage.textModel;
    NSInteger docLen   = [model getLength];
    if (docLen <= 0) {
        [self _clearDecorations];
        return;
    }

    NSArray<NSValue *> *changedRanges = _highlighter.lastChangedCharRanges;

    if (changedRanges && changedRanges.count > 0) {
        // --- Incremental update: only re-scan within the changed character ranges ---
        // 1. Find existing MISSING decorations that intersect the changed ranges.
        // 2. Remove them (they may be stale after the edit).
        // 3. Collect new MISSING nodes from within those ranges (capped).
        // 4. Decorations outside the changed ranges are preserved unchanged.

        // Find which of our current decoration IDs intersect any changed range.
        NSMutableSet<NSString *> *staleIDSet = [NSMutableSet set];
        for (NSValue *rv in changedRanges) {
            NSRange cr = [rv rangeValue];
            if (cr.length == 0) continue;
            NSArray<UDIntervalNode *> *nodes =
                [model decorationNodesInOffsetRange:(NSInteger)cr.location
                                                end:(NSInteger)NSMaxRange(cr)];
            for (UDIntervalNode *n in nodes) {
                if ([n.owner isEqualToString:UDMissingNodeDecorationOwner]) {
                    [staleIDSet addObject:n.identifier];
                }
            }
        }

        // Build the keep list (IDs not in any changed range).
        NSMutableArray<NSString *> *toKeep   = [NSMutableArray array];
        NSMutableArray<NSString *> *toRemove = [NSMutableArray array];
        for (NSString *did in _decorationIDs) {
            if ([staleIDSet containsObject:did]) {
                [toRemove addObject:did];
            } else {
                [toKeep addObject:did];
            }
        }

        // Remove stale decorations.
        if (toRemove.count > 0) {
            [model deltaDecorations:toRemove
                     newDecorations:@[]
                              owner:UDMissingNodeDecorationOwner];
        }

        // Budget: how many new pills we can still add without exceeding maxDecorations.
        NSUInteger budget = (toKeep.count < _maxDecorations)
                                ? _maxDecorations - toKeep.count : 0;

        NSMutableArray<NSString *> *updatedIDs = [toKeep mutableCopy];

        if (budget > 0) {
            NSMutableArray<UDModelDeltaDecoration *> *newDecors = [NSMutableArray array];
            TSNode root = ts_tree_root_node((TSTree *)tree);
            for (NSValue *rv in changedRanges) {
                if (budget == 0) break;
                NSRange cr  = [rv rangeValue];
                uint32_t sb = byteFromChar(cr.location);
                uint32_t eb = byteFromChar(NSMaxRange(cr));
                // Narrow to the deepest node covering the changed byte range.
                TSNode subtree =
                    ts_node_named_descendant_for_byte_range(root, sb, eb);
                if (!ts_node_is_null(subtree)) {
                    [self _collectMissingNodes:subtree
                                         model:model
                                        docLen:(NSUInteger)docLen
                                        budget:&budget
                                          into:newDecors];
                }
            }

            if (newDecors.count > 0) {
                NSArray<NSString *> *addedIDs =
                    [model deltaDecorations:@[]
                             newDecorations:newDecors
                                      owner:UDMissingNodeDecorationOwner];
                [updatedIDs addObjectsFromArray:addedIDs];
            }
        }

        _decorationIDs = [updatedIDs copy];

    } else {
        // --- Full scan (initial parse, undo/redo, or no changed ranges) ---
        NSMutableArray<UDModelDeltaDecoration *> *decors = [NSMutableArray array];
        TSNode root = ts_tree_root_node((TSTree *)tree);
        NSUInteger budget = _maxDecorations;
        [self _collectMissingNodes:root
                             model:model
                            docLen:(NSUInteger)docLen
                            budget:&budget
                              into:decors];

        _decorationIDs =
            [model deltaDecorations:_decorationIDs
                     newDecorations:decors
                              owner:UDMissingNodeDecorationOwner];
    }

    [_textStorage applyDecorationHighlights];
}

// ---------------------------------------------------------------------------
// MARK: - Tree traversal
// ---------------------------------------------------------------------------

- (void)_collectMissingNodes:(TSNode)node
                       model:(UDTextModel *)model
                      docLen:(NSUInteger)docLen
                      budget:(NSUInteger *)budget
                        into:(NSMutableArray<UDModelDeltaDecoration *> *)out {
    if (*budget == 0) return;

    if (ts_node_is_missing(node)) {
        // MISSING nodes are zero-width; mark the adjacent character.
        // The early-return at the call site guarantees docLen > 0 here.
        NSUInteger pos    = charFromByte(ts_node_start_byte(node));
        NSUInteger maxIdx = docLen - 1;
        NSUInteger start  = (pos < docLen) ? pos : maxIdx;
        UDPosition sp = [model getPositionAt:(NSInteger)start];
        UDPosition ep = [model getPositionAt:(NSInteger)(start + 1)];
        UDRange ur = PTRangeMake(sp.line, sp.column, ep.line, ep.column);

        // Store the expected token type in userInfo for diagnostics / tooltip use.
        const char *typeCStr = ts_node_type(node);
        NSString   *typeStr  = typeCStr
            ? [NSString stringWithUTF8String:typeCStr]
            : @"<unknown>";

        UDDecorationOptions *opts =
            [[UDDecorationOptions alloc] initWithClassName:@"missing"
                                                  userInfo:typeStr];
        UDModelDeltaDecoration *d =
            [[UDModelDeltaDecoration alloc] initWithRange:ur options:opts];
        d.stickiness = UDTrackedRangeNeverGrowsWhenTypingAtEdges;
        [out addObject:d];
        (*budget)--;
        // MISSING nodes have no meaningful children; no need to recurse.
        return;
    }

    uint32_t count = ts_node_child_count(node);
    for (uint32_t i = 0; i < count; i++) {
        if (*budget == 0) break;
        [self _collectMissingNodes:ts_node_child(node, i)
                             model:model
                            docLen:docLen
                            budget:budget
                              into:out];
    }
}

// ---------------------------------------------------------------------------
// MARK: - Helpers
// ---------------------------------------------------------------------------

- (void)_clearDecorations {
    if (_decorationIDs.count == 0) return;
    _decorationIDs =
        [_textStorage.textModel deltaDecorations:_decorationIDs
                                  newDecorations:@[]
                                           owner:UDMissingNodeDecorationOwner];
    [_textStorage applyDecorationHighlights];
}

@end
