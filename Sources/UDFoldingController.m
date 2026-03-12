/*---------------------------------------------------------------------------------------------
 *  UDFoldingController.m
 *--------------------------------------------------------------------------------------------*/

#import "UDFoldingController.h"
#import "UDTextModel.h"
#import <tree_sitter/api.h>

// Tree-sitter stores byte offsets in UTF-16 (2 bytes per BMP code unit).
// Supplementary characters (U+10000+) use surrogate pairs (4 bytes each),
// so for ASCII/BMP-only content this conversion is exact.
static inline NSUInteger charFromByte(uint32_t b) { return (NSUInteger)(b / 2); }

// ---------------------------------------------------------------------------
// MARK: - Internal fold-region record
// ---------------------------------------------------------------------------

/// One foldable region discovered in the parse tree.
@interface _UDFoldRegion : NSObject
@property (nonatomic) NSInteger   startLine;      // 1-based line of the opening delimiter
@property (nonatomic) NSUInteger  interiorStart;  // first char of the interior (after '{')
@property (nonatomic) NSUInteger  interiorEnd;    // first char of the closing delimiter
@end
@implementation _UDFoldRegion
@end

// ---------------------------------------------------------------------------
// MARK: - Private interface
// ---------------------------------------------------------------------------

@interface UDFoldingController ()
@property (nonatomic, strong) NSArray<NSString *>  *nodeTypes;
@property (nonatomic, weak)   NSTextView           *textView;
@property (nonatomic, weak)   UDTextModelTextStorage *textStorage;
@property (nonatomic, weak)   UDTreeSitterHighlighter *highlighter;

// Map from 1-based start line → _UDFoldRegion (all foldable regions in the document).
@property (nonatomic, strong) NSDictionary<NSNumber *, _UDFoldRegion *> *regionsByLine;

// Map from 1-based start line → decoration IDs (only for currently folded regions).
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSArray<NSString *> *>
                              *foldDecorationsByLine;

@property (nonatomic, copy)   NSSet<NSNumber *> *foldableLineNumbers;
@property (nonatomic, copy)   NSSet<NSNumber *> *foldedLineNumbers;
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
    _regionsByLine        = @{};
    _foldDecorationsByLine = [NSMutableDictionary dictionary];
    _foldableLineNumbers  = [NSSet set];
    _foldedLineNumbers    = [NSSet set];
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

// ---------------------------------------------------------------------------
// MARK: - Public API
// ---------------------------------------------------------------------------

- (void)update {
    const TSTree *tree = (const TSTree *)_highlighter.currentParseTree;
    UDTextModel  *model = _textStorage.textModel;

    // -- 1. Collect current foldable regions from tree. --
    NSMutableDictionary<NSNumber *, _UDFoldRegion *> *newRegions =
        [NSMutableDictionary dictionary];
    if (tree) {
        NSMutableArray<_UDFoldRegion *> *found = [NSMutableArray array];
        TSNode root = ts_tree_root_node((TSTree *)tree);
        [self _collectFoldableNodes:root into:found model:model];
        for (_UDFoldRegion *r in found) {
            newRegions[@(r.startLine)] = r;
        }
    }
    _regionsByLine = [newRegions copy];

    // -- 2. Remove fold decorations whose regions no longer exist. --
    NSMutableDictionary *updatedDecors =
        [NSMutableDictionary dictionaryWithDictionary:_foldDecorationsByLine];
    NSMutableSet<NSNumber *> *toUnfold = [NSMutableSet set];
    for (NSNumber *line in _foldDecorationsByLine) {
        if (!newRegions[line]) {
            [toUnfold addObject:line];
        }
    }
    for (NSNumber *line in toUnfold) {
        NSArray<NSString *> *ids = _foldDecorationsByLine[line];
        [model deltaDecorations:ids newDecorations:@[] owner:UDFoldDecorationOwner];
        [updatedDecors removeObjectForKey:line];
    }
    _foldDecorationsByLine = updatedDecors;

    // -- 3. Rebuild public sets. --
    [self _rebuildPublicSets];

    // -- 4. Sync gutter if attached. --
    [self _syncGutter];
}

- (void)toggleFoldAtLine:(NSInteger)lineNumber {
    _UDFoldRegion *region = _regionsByLine[@(lineNumber)];
    if (!region) return;

    UDTextModel *model = _textStorage.textModel;

    if (_foldDecorationsByLine[@(lineNumber)]) {
        // Currently folded → unfold.
        NSArray<NSString *> *ids = _foldDecorationsByLine[@(lineNumber)];
        [model deltaDecorations:ids newDecorations:@[] owner:UDFoldDecorationOwner];
        [_foldDecorationsByLine removeObjectForKey:@(lineNumber)];
    } else {
        // Not folded → fold.
        NSUInteger docLen  = (NSUInteger)[model getLength];
        NSUInteger startOff = region.interiorStart;
        NSUInteger endOff   = region.interiorEnd;
        if (startOff >= endOff || endOff > docLen) return;

        UDPosition sp = [model getPositionAt:(NSInteger)startOff];
        UDPosition ep = [model getPositionAt:(NSInteger)endOff];
        UDRange    ur = PTRangeMake(sp.line, sp.column, ep.line, ep.column);

        UDDecorationOptions *opts =
            [[UDDecorationOptions alloc] initWithClassName:@"fold" userInfo:nil];
        UDModelDeltaDecoration *d =
            [[UDModelDeltaDecoration alloc] initWithRange:ur options:opts];
        d.stickiness = UDTrackedRangeNeverGrowsWhenTypingAtEdges;

        NSArray<NSString *> *ids =
            [model deltaDecorations:@[]
                     newDecorations:@[d]
                              owner:UDFoldDecorationOwner];
        _foldDecorationsByLine[@(lineNumber)] = ids;
    }

    [_textStorage applyDecorationHighlights];
    [self _rebuildPublicSets];
    [self _syncGutter];
}

// ---------------------------------------------------------------------------
// MARK: - Tree traversal
// ---------------------------------------------------------------------------

- (void)_collectFoldableNodes:(TSNode)node
                         into:(NSMutableArray<_UDFoldRegion *> *)out
                        model:(UDTextModel *)model {
    TSPoint startPt = ts_node_start_point(node);
    TSPoint endPt   = ts_node_end_point(node);

    // Only multi-line nodes are foldable.
    if (endPt.row > startPt.row) {
        NSString *type = [NSString stringWithUTF8String:ts_node_type(node)];
        if ([_nodeTypes containsObject:type]) {
            uint32_t childCount = ts_node_child_count(node);
            if (childCount >= 2) {
                TSNode firstChild = ts_node_child(node, 0);
                TSNode lastChild  = ts_node_child(node, childCount - 1);

                NSUInteger openStart  = charFromByte(ts_node_start_byte(firstChild));
                NSUInteger closeStart = charFromByte(ts_node_start_byte(lastChild));

                // The fold interior is: from after the opening delimiter to the
                // start of the closing delimiter.  Both boundaries must be valid.
                NSInteger docLen = [model getLength];
                if ((NSInteger)openStart >= 0 && (NSInteger)closeStart <= docLen
                        && openStart < closeStart) {
                    UDPosition openPos =
                        [model getPositionAt:(NSInteger)openStart];

                    _UDFoldRegion *region = [[_UDFoldRegion alloc] init];
                    region.startLine     = openPos.line;
                    region.interiorStart = charFromByte(ts_node_end_byte(firstChild));
                    region.interiorEnd   = closeStart;
                    [out addObject:region];
                }
            }
        }
    }

    // Recurse into children.
    uint32_t childCount = ts_node_child_count(node);
    for (uint32_t i = 0; i < childCount; i++) {
        [self _collectFoldableNodes:ts_node_child(node, i) into:out model:model];
    }
}

// ---------------------------------------------------------------------------
// MARK: - Helpers
// ---------------------------------------------------------------------------

- (void)_rebuildPublicSets {
    _foldableLineNumbers =
        [NSSet setWithArray:_regionsByLine.allKeys];
    _foldedLineNumbers   =
        [NSSet setWithArray:_foldDecorationsByLine.allKeys];
}

- (void)_syncGutter {
    UDLineNumberGutterView *gutter = _lineNumberGutterView;
    if (!gutter) return;
    gutter.foldableLines = _foldableLineNumbers;
    gutter.foldedLines   = _foldedLineNumbers;
}

@end
