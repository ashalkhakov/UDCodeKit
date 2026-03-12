#import "UDBracketMatchHighlighter.h"
#import "UDDecorationHighlighter.h"
#import <tree_sitter/api.h>
#import <string.h>
#import "UDDecorationLayerRegistry.h"

static inline NSUInteger charFromByte(uint32_t b) { return (NSUInteger)(b / 2); }
static inline uint32_t   byteFromChar(NSUInteger c) { return (uint32_t)(c * 2); }

static inline BOOL isBracket(unichar ch) {
    return ch == '{' || ch == '}' || ch == '[' || ch == ']' || ch == '(' || ch == ')';
}

@interface UDBracketMatchHighlighter ()
@property (nonatomic, weak) NSTextView *textView;
@end

@implementation UDBracketMatchHighlighter

+ (void)load { [self registerDecorationLayer]; }

+ (void)registerDecorationLayer {
    [[UDDecorationLayerRegistry shared]
        registerOwner:UDBracketMatchDecorationOwner
                layer:2
           attrBlock:^NSDictionary *(UDIntervalNode *node) {
        static NSColor *c;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            c = [NSColor colorWithRed:0.38 green:0.60 blue:0.90 alpha:0.35];
        });
        return @{ NSBackgroundColorAttributeName: c };
    }];
}

// ---------------------------------------------------------------------------
#pragma mark - Init / dealloc
// ---------------------------------------------------------------------------

- (instancetype)initWithTextView:(NSTextView *)textView
                     textStorage:(UDTextModelTextStorage *)textStorage
                      highlighter:(UDTreeSitterHighlighter *)highlighter {
    self = [super initWithTextStorage:textStorage highlighter:highlighter];
    if (!self) return nil;
    _textView = textView;

    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(update)
               name:NSTextViewDidChangeSelectionNotification
             object:textView];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    // super -dealloc clears decorations via -commitDecorations:@[]
}

// ---------------------------------------------------------------------------
#pragma mark - UDDecorationHighlighter overrides
// ---------------------------------------------------------------------------

- (NSString *)decorationOwner {
    return UDBracketMatchDecorationOwner;
}

- (void)update {
    const TSTree *tree = (const TSTree *)self.highlighter.currentParseTree;
    if (!tree) { [self clearDecorations]; return; }

    NSRange    selection = _textView.selectedRange;
    NSUInteger cursor    = selection.location;
    UDTextModel *model   = self.textStorage.textModel;
    NSInteger docLen     = [model getLength];
    if (docLen <= 0) { [self clearDecorations]; return; }

    // Find a bracket character adjacent to the cursor.
    NSUInteger bracketOff = NSNotFound;
    if (cursor < (NSUInteger)docLen) {
        unichar ch = [model getCharacterAtOffset:cursor];
        if (isBracket(ch)) bracketOff = cursor;
    }
    if (bracketOff == NSNotFound && cursor > 0) {
        unichar prev = [model getCharacterAtOffset:cursor - 1];
        if (isBracket(prev)) bracketOff = cursor - 1;
    }
    if (bracketOff == NSNotFound) { [self clearDecorations]; return; }

    // Walk up the tree from the deepest node covering the bracket.
    TSNode root    = ts_tree_root_node((TSTree *)tree);
    uint32_t byteOff = byteFromChar(bracketOff);
    TSNode node    = ts_node_descendant_for_byte_range(root, byteOff, byteOff + 2);
    if (ts_node_is_null(node)) { [self clearDecorations]; return; }

    TSNode openNode, closeNode;
    BOOL   found = NO;
    memset(&openNode,  0, sizeof(openNode));
    memset(&closeNode, 0, sizeof(closeNode));

    while (!ts_node_is_null(node)) {
        uint32_t childCount = ts_node_child_count(node);
        if (childCount >= 2) {
            TSNode first = ts_node_child(node, 0);
            TSNode last  = ts_node_child(node, childCount - 1);
            if (ts_node_start_byte(first) == byteOff ||
                ts_node_start_byte(last)  == byteOff) {
                openNode  = first;
                closeNode = last;
                found     = YES;
                break;
            }
        }
        node = ts_node_parent(node);
    }

    if (!found) { [self clearDecorations]; return; }

    // Build decorations for the two delimiter characters.
    NSUInteger offsets[2] = { charFromByte(ts_node_start_byte(openNode)),
                               charFromByte(ts_node_start_byte(closeNode)) };
    NSMutableArray<UDModelDeltaDecoration *> *decors = [NSMutableArray array];
    for (NSUInteger i = 0; i < 2; i++) {
        NSUInteger off = offsets[i];
        if (off >= (NSUInteger)docLen) continue;
        UDPosition sp = [model getPositionAt:(NSInteger)off];
        UDPosition ep = [model getPositionAt:(NSInteger)(off + 1)];
        UDRange r = PTRangeMake(sp.line, sp.column, ep.line, ep.column);
        UDDecorationOptions *opts =
            [[UDDecorationOptions alloc] initWithClassName:@"bracket.match"
                                                  userInfo:nil];
        UDModelDeltaDecoration *d =
            [[UDModelDeltaDecoration alloc] initWithRange:r options:opts];
        d.stickiness = UDTrackedRangeNeverGrowsWhenTypingAtEdges;
        [decors addObject:d];
    }

    [self commitDecorations:decors];
}

@end
