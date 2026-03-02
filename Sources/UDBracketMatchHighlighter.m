/*---------------------------------------------------------------------------------------------
 *  UDBracketMatchHighlighter.m
 *--------------------------------------------------------------------------------------------*/

#import "UDBracketMatchHighlighter.h"
#import <tree_sitter/api.h>
#import <string.h>

// Tree-sitter stores byte offsets in UTF-16 (2 bytes per BMP code unit).
// Supplementary characters (U+10000+) use surrogate pairs (4 bytes each),
// so for ASCII/BMP-only content this conversion is exact.
static inline NSUInteger charFromByte(uint32_t b) { return (NSUInteger)(b / 2); }
static inline uint32_t   byteFromChar(NSUInteger c) { return (uint32_t)(c * 2); }

// Returns YES if ch is an opening or closing delimiter.
static inline BOOL isBracket(unichar ch) {
    return ch == '{' || ch == '}' || ch == '[' || ch == ']' || ch == '(' || ch == ')';
}

@interface UDBracketMatchHighlighter ()
@property (nonatomic, weak) NSTextView            *textView;
@property (nonatomic, weak) UDTextModelTextStorage *textStorage;
@property (nonatomic, weak) UDTreeSitterHighlighter *highlighter;
@property (nonatomic, copy) NSArray<NSString *>   *decorationIDs;
@end

@implementation UDBracketMatchHighlighter

// ---------------------------------------------------------------------------
// MARK: - Init / dealloc
// ---------------------------------------------------------------------------

- (instancetype)initWithTextView:(NSTextView *)textView
                     textStorage:(UDTextModelTextStorage *)textStorage
                      highlighter:(UDTreeSitterHighlighter *)highlighter {
    self = [super init];
    if (!self) return nil;
    _textView    = textView;
    _textStorage = textStorage;
    _highlighter = highlighter;
    _decorationIDs = @[];

    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(update)
               name:NSTextViewDidChangeSelectionNotification
             object:textView];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    // Clear decorations on teardown.
    [_textStorage.textModel deltaDecorations:_decorationIDs
                              newDecorations:@[]
                                       owner:UDBracketMatchDecorationOwner];
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

    // Determine cursor position in characters.
    NSRange selection  = _textView.selectedRange;
    NSUInteger cursor  = selection.location;
    UDTextModel *model = _textStorage.textModel;
    NSInteger docLen   = [model getLength];
    if (docLen <= 0) { [self _clearDecorations]; return; }

    // Find the bracket character adjacent to the cursor.
    NSUInteger bracketOff = NSNotFound;
    if (cursor < (NSUInteger)docLen) {
        unichar ch = [model getCharacterAtOffset:cursor];
        if (isBracket(ch)) bracketOff = cursor;
    }
    if (bracketOff == NSNotFound && cursor > 0) {
        unichar prevCh = [model getCharacterAtOffset:cursor - 1];
        if (isBracket(prevCh)) bracketOff = cursor - 1;
    }
    if (bracketOff == NSNotFound) {
        [self _clearDecorations];
        return;
    }

    // Walk the tree to find the container node whose first or last child
    // starts at bracketOff.
    TSNode root = ts_tree_root_node((TSTree *)tree);
    uint32_t byteOff = byteFromChar(bracketOff);

    // Start from the deepest node that covers the bracket.
    TSNode node = ts_node_descendant_for_byte_range(root, byteOff, byteOff + 2);
    if (ts_node_is_null(node)) { [self _clearDecorations]; return; }

    TSNode openNode;
    TSNode closeNode;
    BOOL   found     = NO;
    memset(&openNode,  0, sizeof(openNode));
    memset(&closeNode, 0, sizeof(closeNode));

    // Walk up until we find a parent whose first child or last child is at bracketOff.
    while (!ts_node_is_null(node)) {
        uint32_t childCount = ts_node_child_count(node);
        if (childCount >= 2) {
            TSNode firstChild = ts_node_child(node, 0);
            TSNode lastChild  = ts_node_child(node, childCount - 1);
            uint32_t firstByte = ts_node_start_byte(firstChild);
            uint32_t lastByte  = ts_node_start_byte(lastChild);

            if (firstByte == byteOff || lastByte == byteOff) {
                openNode  = firstChild;
                closeNode = lastChild;
                found     = YES;
                break;
            }
        }
        node = ts_node_parent(node);
    }

    if (!found) { [self _clearDecorations]; return; }

    NSUInteger openOff  = charFromByte(ts_node_start_byte(openNode));
    NSUInteger closeOff = charFromByte(ts_node_start_byte(closeNode));

    // Build decorations for both delimiter characters.
    NSMutableArray<UDModelDeltaDecoration *> *decors = [NSMutableArray array];
    NSUInteger bracketOffsets[2] = { openOff, closeOff };
    for (NSUInteger idx = 0; idx < 2; idx++) {
        NSUInteger off = bracketOffsets[idx];
        if (off >= (NSUInteger)docLen) continue;
        UDPosition sp = [model getPositionAt:(NSInteger)off];
        UDPosition ep = [model getPositionAt:(NSInteger)(off + 1)];
        UDRange    r  = PTRangeMake(sp.line, sp.column, ep.line, ep.column);
        UDDecorationOptions *opts =
            [[UDDecorationOptions alloc] initWithClassName:@"bracket.match"
                                                  userInfo:nil];
        UDModelDeltaDecoration *d =
            [[UDModelDeltaDecoration alloc] initWithRange:r options:opts];
        d.stickiness = UDTrackedRangeNeverGrowsWhenTypingAtEdges;
        [decors addObject:d];
    }

    _decorationIDs =
        [model deltaDecorations:_decorationIDs
                 newDecorations:decors
                          owner:UDBracketMatchDecorationOwner];
    [_textStorage applyDecorationHighlights];
}

// ---------------------------------------------------------------------------
// MARK: - Helpers
// ---------------------------------------------------------------------------

- (void)_clearDecorations {
    if (_decorationIDs.count == 0) return;
    _decorationIDs =
        [_textStorage.textModel deltaDecorations:_decorationIDs
                                  newDecorations:@[]
                                           owner:UDBracketMatchDecorationOwner];
    [_textStorage applyDecorationHighlights];
}

@end
