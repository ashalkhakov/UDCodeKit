/*---------------------------------------------------------------------------------------------
 *  UDMissingNodeHighlighter.m
 *--------------------------------------------------------------------------------------------*/

#import "UDMissingNodeHighlighter.h"
#import <tree_sitter/api.h>

// Tree-sitter stores byte offsets in UTF-16 (2 bytes per BMP code unit).
// Supplementary characters (U+10000+) use surrogate pairs (4 bytes each),
// so for ASCII/BMP-only content this conversion is exact.
static inline NSUInteger charFromByte(uint32_t b) { return (NSUInteger)(b / 2); }

@interface UDMissingNodeHighlighter ()
@property (nonatomic, weak)   UDTextModelTextStorage  *textStorage;
@property (nonatomic, weak)   UDTreeSitterHighlighter *highlighter;
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

    NSMutableArray<UDModelDeltaDecoration *> *decors = [NSMutableArray array];
    TSNode root = ts_tree_root_node((TSTree *)tree);
    [self _collectMissingNodes:root model:model docLen:(NSUInteger)docLen into:decors];

    _decorationIDs =
        [model deltaDecorations:_decorationIDs
                 newDecorations:decors
                          owner:UDMissingNodeDecorationOwner];
    [_textStorage applyDecorationHighlights];
}

// ---------------------------------------------------------------------------
// MARK: - Tree traversal
// ---------------------------------------------------------------------------

- (void)_collectMissingNodes:(TSNode)node
                       model:(UDTextModel *)model
                      docLen:(NSUInteger)docLen
                        into:(NSMutableArray<UDModelDeltaDecoration *> *)out {
    if (ts_node_is_missing(node)) {
        // MISSING nodes are zero-width; mark the adjacent character.
        // The early-return at the call site guarantees docLen > 0 here.
        NSUInteger pos   = charFromByte(ts_node_start_byte(node));
        NSUInteger maxIdx = docLen - 1;
        NSUInteger start = (pos < docLen) ? pos : maxIdx;
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
        // MISSING nodes have no meaningful children; no need to recurse.
        return;
    }

    uint32_t count = ts_node_child_count(node);
    for (uint32_t i = 0; i < count; i++) {
        [self _collectMissingNodes:ts_node_child(node, i)
                             model:model
                            docLen:docLen
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
