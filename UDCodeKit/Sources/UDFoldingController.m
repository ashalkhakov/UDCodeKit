/*---------------------------------------------------------------------------------------------
 *  UDFoldingController.m
 *--------------------------------------------------------------------------------------------*/

#import "UDFoldingController.h"
#import <tree_sitter/api.h>
#import "UDTreeSitterTypes.h"

/// One foldable region: a multi-line node of a foldable type, folded from
/// after its opening delimiter to its closing one.
typedef struct {
    NSInteger  line;            // 1-based line of the opening delimiter
    NSUInteger interiorStart;   // first character after the opening delimiter
    NSUInteger interiorEnd;     // first character of the closing delimiter
} UDFoldRegion;

@interface UDFoldingController ()
@property (nonatomic, strong) NSArray<NSString *>     *nodeTypes;
@property (nonatomic, weak)   NSTextView              *textView;
@property (nonatomic, weak)   UDTextModelTextStorage  *textStorage;
@property (nonatomic, weak)   UDTreeSitterHighlighter *highlighter;
@end

@implementation UDFoldingController

// ---------------------------------------------------------------------------
// MARK: - Init
// ---------------------------------------------------------------------------

- (instancetype)initWithTextView:(NSTextView *)textView
                     textStorage:(UDTextModelTextStorage *)textStorage
                     highlighter:(UDTreeSitterHighlighter *)highlighter
               foldableNodeTypes:(nullable NSArray<NSString *> *)foldableNodeTypes {
    self = [super init];
    if (!self) return nil;
    _textView    = textView;
    _textStorage = textStorage;
    _highlighter = highlighter;
    _nodeTypes   = foldableNodeTypes ?: @[@"object", @"array"];
    return self;
}

- (instancetype)initWithTextView:(NSTextView *)textView
                     textStorage:(UDTextModelTextStorage *)textStorage
                     highlighter:(UDTreeSitterHighlighter *)highlighter {
    return [self initWithTextView:textView
                      textStorage:textStorage
                      highlighter:highlighter
                foldableNodeTypes:nil];
}

- (void)setLineNumberGutterView:(UDLineNumberGutterView *)gutter {
    _lineNumberGutterView = gutter;
    gutter.foldingSource = self;
}

// ---------------------------------------------------------------------------
// MARK: - Regions, from the tree over some lines
// ---------------------------------------------------------------------------

/// Clamps [*first, *last] to the document; NO when nothing is left.
- (BOOL)_clampLines:(NSInteger *)first through:(NSInteger *)last {
    NSInteger lineCount = [_textStorage.textModel getLineCount];
    if (*first > *last || *first > lineCount || *last < 1) return NO;
    *first = MAX(*first, 1);
    *last  = MIN(*last, lineCount);
    return YES;
}

/// The regions opening on lines [first, last] — UDFoldRegion structs, in
/// tree order (outer first). Walks only the nodes overlapping those lines.
- (NSData *)_regionsOnLines:(NSInteger)first through:(NSInteger)last {
    NSMutableData *regions = [NSMutableData data];
    const TSTree *tree = (const TSTree *)_highlighter.currentParseTree;
    UDTextModel *model = _textStorage.textModel;
    if (!tree || ![self _clampLines:&first through:&last]) return regions;
    uint32_t low  = (uint32_t)[model getOffsetAt:first column:1] * 2;
    uint32_t high = (uint32_t)[model getOffsetAt:last column:[model getLineMaxColumn:last]] * 2;

    TSTreeCursor cursor = ts_tree_cursor_new(ts_tree_root_node((TSTree *)tree));
    NSUInteger depth = 0;
    for (;;) {
        TSNode node = ts_tree_cursor_current_node(&cursor);
        uint32_t children = ts_node_child_count(node);
        if (ts_node_end_point(node).row > ts_node_start_point(node).row && children >= 2 &&
            [_nodeTypes containsObject:@(ts_node_type(node))]) {
            TSNode open  = ts_node_child(node, 0);
            TSNode close = ts_node_child(node, children - 1);
            UDFoldRegion region = {
                (NSInteger)ts_node_start_point(open).row + 1,
                UDCharIndexFromByte(ts_node_end_byte(open)),
                UDCharIndexFromByte(ts_node_start_byte(close)),
            };
            if (region.line >= first && region.line <= last && region.interiorStart < region.interiorEnd) {
                [regions appendBytes:&region length:sizeof region];
            }
        }
        // Children overlapping [low, high]; then the next sibling there, or up.
        if (ts_tree_cursor_goto_first_child_for_byte(&cursor, low) >= 0) {
            if (ts_node_start_byte(ts_tree_cursor_current_node(&cursor)) <= high) {
                depth++;
                continue;
            }
            ts_tree_cursor_goto_parent(&cursor);
        }
        BOOL moved = NO;
        while (depth > 0) {
            if (ts_tree_cursor_goto_next_sibling(&cursor) &&
                ts_node_start_byte(ts_tree_cursor_current_node(&cursor)) <= high) {
                moved = YES;
                break;
            }
            ts_tree_cursor_goto_parent(&cursor);
            depth--;
        }
        if (!moved) break;
    }
    ts_tree_cursor_delete(&cursor);
    return regions;
}

// ---------------------------------------------------------------------------
// MARK: - Folds: the fold decorations
// ---------------------------------------------------------------------------

/// The fold decorations starting on lines [first, last].
- (NSArray<UDIntervalNode *> *)_foldsOnLines:(NSInteger)first through:(NSInteger)last {
    UDTextModel *model = _textStorage.textModel;
    if (![self _clampLines:&first through:&last]) return @[];
    NSInteger start = [model getOffsetAt:first column:1];
    NSInteger end   = [model getOffsetAt:last column:[model getLineMaxColumn:last]];
    NSMutableArray<UDIntervalNode *> *folds = [NSMutableArray array];
    for (UDIntervalNode *node in [model decorationNodesInOffsetRange:start end:end + 1]) {
        if ([node.owner isEqualToString:UDFoldDecorationOwner] && node.start >= start && node.start <= end) {
            [folds addObject:node];
        }
    }
    return folds;
}

/// Whether a region still opens on the line where [start, end) starts,
/// with exactly that interior.
- (BOOL)_regionExistsFrom:(NSInteger)start to:(NSInteger)end {
    if (start >= end) return NO;
    NSInteger line = [_textStorage.textModel getPositionAt:start].line;
    NSData *regions = [self _regionsOnLines:line through:line];
    const UDFoldRegion *r = regions.bytes;
    for (NSUInteger i = 0; i < regions.length / sizeof *r; i++) {
        if ((NSInteger)r[i].interiorStart == start && (NSInteger)r[i].interiorEnd == end) return YES;
    }
    return NO;
}

// ---------------------------------------------------------------------------
// MARK: - UDLineNumberGutterFoldingSource
// ---------------------------------------------------------------------------

- (NSIndexSet *)foldableLinesInRange:(NSRange)lines {
    NSMutableIndexSet *out = [NSMutableIndexSet indexSet];
    if (lines.length == 0) return out;
    NSData *regions = [self _regionsOnLines:(NSInteger)lines.location through:(NSInteger)NSMaxRange(lines) - 1];
    const UDFoldRegion *r = regions.bytes;
    for (NSUInteger i = 0; i < regions.length / sizeof *r; i++) [out addIndex:(NSUInteger)r[i].line];
    return out;
}

- (NSIndexSet *)foldedLinesInRange:(NSRange)lines {
    NSMutableIndexSet *out = [NSMutableIndexSet indexSet];
    if (lines.length == 0) return out;
    UDTextModel *model = _textStorage.textModel;
    for (UDIntervalNode *fold in [self _foldsOnLines:(NSInteger)lines.location
                                             through:(NSInteger)NSMaxRange(lines) - 1]) {
        [out addIndex:(NSUInteger)[model getPositionAt:fold.start].line];
    }
    return out;
}

// ---------------------------------------------------------------------------
// MARK: - Changes
// ---------------------------------------------------------------------------

- (void)update {
    UDTextModel *model = _textStorage.textModel;
    NSArray<NSValue *> *changed = _highlighter.lastChangedCharRanges;

    // The folds a change touched — all of them after a fresh parse — go
    // unless their region is still there.
    NSMutableArray<NSString *> *gone = [NSMutableArray array];
    if (!changed || !_highlighter.currentParseTree) {
        for (NSString *identifier in [model decorationsForOwner:UDFoldDecorationOwner]) {
            UDRange r = [model rangeForDecoration:identifier];
            if (![self _regionExistsFrom:[model getOffsetAt:r.startLineNumber column:r.startColumn]
                                      to:[model getOffsetAt:r.endLineNumber column:r.endColumn]]) {
                [gone addObject:identifier];
            }
        }
    } else {
        NSMutableSet<NSString *> *checked = [NSMutableSet set];
        for (NSValue *v in changed) {
            NSRange cr = v.rangeValue;
            NSInteger s = (NSInteger)cr.location, e = (NSInteger)NSMaxRange(cr);
            for (UDIntervalNode *fold in [model decorationNodesInOffsetRange:MAX(0, s - 1) end:e + 1]) {
                if (![fold.owner isEqualToString:UDFoldDecorationOwner] || [checked containsObject:fold.identifier]) continue;
                [checked addObject:fold.identifier];
                if (![self _regionExistsFrom:fold.start to:fold.end]) [gone addObject:fold.identifier];
            }
        }
    }
    if (gone.count) {
        [model deltaDecorations:gone newDecorations:@[] owner:UDFoldDecorationOwner];
        [_textStorage applyDecorationHighlights];
    }
    [_lineNumberGutterView setNeedsDisplay:YES];
}

- (void)toggleFoldAtLine:(NSInteger)lineNumber {
    UDTextModel *model = _textStorage.textModel;

    NSArray<UDIntervalNode *> *folds = [self _foldsOnLines:lineNumber through:lineNumber];
    if (folds.count) {
        NSMutableArray<NSString *> *ids = [NSMutableArray array];
        for (UDIntervalNode *fold in folds) [ids addObject:fold.identifier];
        [model deltaDecorations:ids newDecorations:@[] owner:UDFoldDecorationOwner];
    } else {
        NSData *regions = [self _regionsOnLines:lineNumber through:lineNumber];
        if (regions.length == 0) return;
        // Tree order: the last is the innermost.
        UDFoldRegion innermost = ((const UDFoldRegion *)regions.bytes)[regions.length / sizeof innermost - 1];
        UDPosition sp = [model getPositionAt:(NSInteger)innermost.interiorStart];
        UDPosition ep = [model getPositionAt:(NSInteger)innermost.interiorEnd];
        UDDecorationOptions *opts =
            [[UDDecorationOptions alloc] initWithClassName:@"fold" userInfo:nil];
        UDModelDeltaDecoration *d =
            [[UDModelDeltaDecoration alloc] initWithRange:PTRangeMake(sp.line, sp.column, ep.line, ep.column)
                                                  options:opts];
        d.stickiness = UDTrackedRangeNeverGrowsWhenTypingAtEdges;
        [model deltaDecorations:@[] newDecorations:@[d] owner:UDFoldDecorationOwner];
    }
    [_textStorage applyDecorationHighlights];
    [_lineNumberGutterView setNeedsDisplay:YES];
}

@end
