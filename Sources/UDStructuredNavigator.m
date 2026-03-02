/*---------------------------------------------------------------------------------------------
 *  UDStructuredNavigator.m
 *--------------------------------------------------------------------------------------------*/

#import "UDStructuredNavigator.h"
#import <tree_sitter/api.h>
#import <string.h>

// Tree-sitter stores byte offsets in UTF-16 (2 bytes per BMP code unit).
// Supplementary characters (U+10000+) use surrogate pairs (4 bytes each),
// so for ASCII/BMP-only content this conversion is exact.
static inline NSUInteger charFromByte(uint32_t b) { return (NSUInteger)(b / 2); }
static inline uint32_t   byteFromChar(NSUInteger c) { return (uint32_t)(c * 2); }

/// Returns a guaranteed-null TSNode (ts_node_is_null() == YES).
static inline TSNode TSNullNode(void) {
    TSNode n;
    memset(&n, 0, sizeof(n));
    return n;
}

@interface UDStructuredNavigator ()
@property (nonatomic, weak) NSTextView            *textView;
@property (nonatomic, weak) UDTreeSitterHighlighter *highlighter;
@property (nonatomic, weak) UDTextModel           *textModel;
@end

@implementation UDStructuredNavigator

// ---------------------------------------------------------------------------
// MARK: - Init
// ---------------------------------------------------------------------------

- (instancetype)initWithTextView:(NSTextView *)textView
                      highlighter:(UDTreeSitterHighlighter *)highlighter
                        textModel:(UDTextModel *)textModel {
    self = [super init];
    if (!self) return nil;
    _textView   = textView;
    _highlighter = highlighter;
    _textModel  = textModel;
    return self;
}

// ---------------------------------------------------------------------------
// MARK: - Public navigation API
// ---------------------------------------------------------------------------

- (void)moveToParent {
    TSNode current = [self _nodeForCurrentSelection];
    if (ts_node_is_null(current)) return;
    TSNode parent = ts_node_parent(current);
    if (ts_node_is_null(parent)) return;
    [self _selectNode:parent];
}

- (void)moveToFirstChild {
    TSNode current = [self _nodeForCurrentSelection];
    if (ts_node_is_null(current)) return;
    uint32_t namedCount = ts_node_named_child_count(current);
    if (namedCount == 0) return;
    TSNode child = ts_node_named_child(current, 0);
    if (ts_node_is_null(child)) return;
    [self _selectNode:child];
}

- (void)moveToPrevSibling {
    TSNode current = [self _nodeForCurrentSelection];
    if (ts_node_is_null(current)) return;
    TSNode prev = ts_node_prev_named_sibling(current);
    if (ts_node_is_null(prev)) return;
    [self _selectNode:prev];
}

- (void)moveToNextSibling {
    TSNode current = [self _nodeForCurrentSelection];
    if (ts_node_is_null(current)) return;
    TSNode next = ts_node_next_named_sibling(current);
    if (ts_node_is_null(next)) return;
    [self _selectNode:next];
}

// ---------------------------------------------------------------------------
// MARK: - Node ↔ selection mapping
// ---------------------------------------------------------------------------

/// Returns the deepest *named* tree-sitter node that fully covers the current
/// NSTextView selection.  Returns a null TSNode if no tree is available or the
/// document is empty.
- (TSNode)_nodeForCurrentSelection {
    const TSTree *tree = (const TSTree *)_highlighter.currentParseTree;
    if (!tree) return TSNullNode();

    NSInteger docLen = [_textModel getLength];
    if (docLen <= 0) return TSNullNode();

    NSRange sel = _textView.selectedRange;
    // Clamp to valid document range.
    NSUInteger selStart = MIN(sel.location, (NSUInteger)docLen);
    NSUInteger selEnd   = MIN(NSMaxRange(sel), (NSUInteger)docLen);

    uint32_t startByte = byteFromChar(selStart);
    uint32_t endByte   = byteFromChar(selEnd);

    TSNode root = ts_tree_root_node((TSTree *)tree);
    // ts_node_named_descendant_for_byte_range returns the deepest NAMED node
    // whose range contains [startByte, endByte).
    TSNode node = ts_node_named_descendant_for_byte_range(root, startByte, endByte);
    return node;
}

/// Sets the NSTextView selection to the character range covered by @c node and
/// scrolls the node into view.
- (void)_selectNode:(TSNode)node {
    NSInteger docLen = [_textModel getLength];
    if (docLen <= 0) return;

    NSUInteger start = charFromByte(ts_node_start_byte(node));
    NSUInteger end   = charFromByte(ts_node_end_byte(node));

    // Clamp to document boundaries.
    start = MIN(start, (NSUInteger)docLen);
    end   = MIN(end,   (NSUInteger)docLen);
    if (start > end) end = start;

    NSRange range = NSMakeRange(start, end - start);
    [_textView setSelectedRange:range];
    [_textView scrollRangeToVisible:range];
}

@end
