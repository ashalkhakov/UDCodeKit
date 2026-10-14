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
    // Walk up through any anonymous CST intermediaries to reach the nearest
    // named ancestor.  ts_node_parent() returns the immediate CST parent which
    // may itself be anonymous (e.g. a bracketing group or punctuation wrapper).
    TSNode parent = ts_node_parent(current);
    while (!ts_node_is_null(parent) && !ts_node_is_named(parent)) {
        parent = ts_node_parent(parent);
    }
    if (ts_node_is_null(parent)) return; // already at root — stay put
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

/// Returns the deepest named AST node that contains the current cursor position
/// or selection — this is the "hole" in Sufrin's modeless structure editing model.
///
/// The cursor/selection is treated as a character-range query [start, end).  When
/// the cursor is a bare insertion point (zero-length selection) start == end; in
/// that case we extend the query by one UTF-16 code unit so that
/// ts_node_named_descendant_for_byte_range receives a non-empty range and returns
/// the deepest node that properly contains the cursor, rather than the root.
///
/// Returns a null TSNode when no parse tree is available or the document is empty.
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
    // For a bare cursor (zero-length selection) startByte == endByte.
    // ts_node_named_descendant_for_byte_range with an empty range returns the
    // root; extend by one code unit to get the correct innermost node.
    // Clamp to the actual document byte length so we never exceed the tree's
    // valid range (tree-sitter uses UTF-16: 2 bytes per BMP code unit).
    if (endByte == startByte) {
        uint32_t docByteLen = byteFromChar((NSUInteger)docLen);
        endByte = MIN(startByte + 2, docByteLen);
        if (endByte == startByte) endByte = docByteLen; // cursor is at doc end
    }

    TSNode root = ts_tree_root_node((TSTree *)tree);
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
