#import "UDIncrementalHighlighterBase.h"
#import <UDPieceTable/UDIntervalTree.h>

static inline uint32_t   byteFromChar(NSUInteger c) { return (uint32_t)(c * 2); }

@interface UDIncrementalHighlighterBase ()
@property (nonatomic, strong) NSMutableArray<UDModelDeltaDecoration *> *pendingDecorations;
@property (nonatomic, assign) NSUInteger currentDocLen;
@end

@implementation UDIncrementalHighlighterBase

// ---------------------------------------------------------------------------
#pragma mark - Init
// ---------------------------------------------------------------------------

- (instancetype)initWithTextStorage:(UDTextModelTextStorage *)textStorage
                         highlighter:(UDTreeSitterHighlighter *)highlighter {
    self = [super initWithTextStorage:textStorage highlighter:highlighter];
    if (!self) return nil;
    _maxDecorations  = [self defaultMaxDecorations];
    _alwaysFullScan  = NO;
    return self;
}

// ---------------------------------------------------------------------------
#pragma mark - Public entry point
// ---------------------------------------------------------------------------

- (void)update {
    const TSTree *tree = (const TSTree *)self.highlighter.currentParseTree;
    if (!tree) { [self clearDecorations]; return; }

    UDTextModel *model  = self.textStorage.textModel;
    NSInteger    docLen = [model getLength];
    if (docLen <= 0) { [self clearDecorations]; return; }

    _currentDocLen = (NSUInteger)docLen;
    NSArray<NSValue *> *changedRanges = self.highlighter.lastChangedCharRanges;

    // changedRanges == nil  → full re-parse just occurred (undo/redo or first load)
    // changedRanges == @[]  → incremental re-parse but tree is structurally identical
    // changedRanges.count>0 → incremental re-parse with tree changes

    BOOL doFullScan = _alwaysFullScan || (changedRanges == nil);

    if (!doFullScan && changedRanges.count == 0) {
        // Incremental parse produced no tree changes — existing decorations are
        // still accurate.  Nothing to do.
        return;
    }

    if (!doFullScan) {
        // ---- Incremental path ---------------------------------------------------
        //
        // A decoration marks the start of an error node. Where the tree
        // changed, or the edits put text, the decorations go and the walk
        // finds the error nodes there again; elsewhere the nodes are the
        // same, and so are their decorations.

        NSString *owner = [self decorationOwner];
        // 1. Stale: what starts in a changed range or at its end (an empty
        //    range is where edits only deleted, squashing what was there to
        //    nothing). At its end: a MISSING node's decoration covers the
        //    character after it, and text typed where it is missing pushes
        //    the decoration to just past that text.
        NSMutableSet<NSString *> *staleIDs = [NSMutableSet set];
        for (NSValue *rv in changedRanges) {
            NSRange cr = [rv rangeValue];
            NSInteger s = (NSInteger)cr.location, e = (NSInteger)NSMaxRange(cr);
            NSArray<UDIntervalNode *> *nodes =
                [model decorationNodesInOffsetRange:MAX(0, s - 1) end:e + 1];
            for (UDIntervalNode *n in nodes) {
                if (![n.owner isEqualToString:owner]) continue;
                if (n.start >= s && n.start <= e) [staleIDs addObject:n.identifier];
            }
        }
        NSMutableArray<NSString *> *toKeep   = [NSMutableArray array];
        NSMutableArray<NSString *> *toRemove = [NSMutableArray array];
        NSMutableSet<NSNumber *>   *keptStarts = [NSMutableSet set];
        for (NSString *did in [self _currentDecorationIDs]) {
            if ([staleIDs containsObject:did]) {
                [toRemove addObject:did];
            } else {
                UDRange r = [model rangeForDecoration:did];
                [toKeep addObject:did];
                [keptStarts addObject:@([model getOffsetAt:r.startLineNumber column:r.startColumn])];
            }
        }
        if (toRemove.count > 0) {
            [model deltaDecorations:toRemove newDecorations:@[] owner:owner];
        }

        // 2. New: what the walk of the changed ranges finds that no kept
        //    decoration already marks (two ranges can reach one node).
        NSUInteger budget = (toKeep.count < _maxDecorations)
                                ? _maxDecorations - toKeep.count : 0;
        if (budget > 0) {
            [self _runVisitorWithBudget:budget tree:tree];
            NSMutableArray<UDModelDeltaDecoration *> *fresh =
                [NSMutableArray arrayWithCapacity:_pendingDecorations.count];
            for (UDModelDeltaDecoration *d in _pendingDecorations) {
                NSNumber *start = @([model getOffsetAt:d.range.startLineNumber column:d.range.startColumn]);
                if ([keptStarts containsObject:start]) continue;
                [keptStarts addObject:start];
                [fresh addObject:d];
            }
            if (fresh.count > 0) {
                [toKeep addObjectsFromArray:[model deltaDecorations:@[] newDecorations:fresh owner:owner]];
            }
        }

        [self _setDecorationIDs:[toKeep copy]];
        _pendingDecorations = nil;

    } else {
        // ---- Full scan --------------------------------------------------
        [self _runVisitorWithBudget:_maxDecorations tree:tree];
        [self commitDecorations:_pendingDecorations];
        _pendingDecorations = nil;
    }

    [self didFinishUpdate];
}

// ---------------------------------------------------------------------------
#pragma mark - Subclass overrides — default implementations
// ---------------------------------------------------------------------------

- (BOOL)willVisitNode:(TSNode)node depth:(NSUInteger)depth {
    [self doesNotRecognizeSelector:_cmd];
    return NO;
}

- (NSUInteger)defaultMaxDecorations { return 100; }


- (void)didFinishUpdate {}

// ---------------------------------------------------------------------------
#pragma mark - Private
// ---------------------------------------------------------------------------

- (void)_runVisitorWithBudget:(NSUInteger)budget tree:(const TSTree *)tree {
    _remainingBudget    = budget;
    _pendingDecorations = [NSMutableArray array];

    TSNode root = ts_tree_root_node((TSTree *)tree);
    NSArray<NSValue *> *changedRanges = self.highlighter.lastChangedCharRanges;
    if (!_alwaysFullScan && changedRanges.count > 0) {
        for (NSValue *rv in changedRanges) {
            NSRange cr = [rv rangeValue];
            [self _walkErrorsUnder:root from:byteFromChar(cr.location) to:byteFromChar(NSMaxRange(cr))];
        }
    } else {
        [self _walkErrorsUnder:root from:0 to:UINT32_MAX];
    }
}

/// Offers -willVisitNode:depth: the nodes under @a root that hold an error
/// and reach [low, high] (a node ending at @a low or starting at @a high
/// counts: a MISSING node there is empty), depth first, in order. Skips
/// subtrees without errors and children outside the range, so it costs the
/// paths to the errors in the range, not the tree.
- (void)_walkErrorsUnder:(TSNode)root from:(uint32_t)low to:(uint32_t)high {
    TSTreeCursor cursor = ts_tree_cursor_new(root);
    NSUInteger depth = 0;
    for (;;) {
        TSNode node = ts_tree_cursor_current_node(&cursor);
        BOOL descend = ts_node_has_error(node) && _remainingBudget > 0 && [self willVisitNode:node depth:depth];
        // First child ending at or after `low`.
        if (descend && ts_tree_cursor_goto_first_child_for_byte(&cursor, low > 0 ? low - 1 : 0) >= 0) {
            if (ts_node_start_byte(ts_tree_cursor_current_node(&cursor)) <= high) {
                depth++;
                continue;
            }
            ts_tree_cursor_goto_parent(&cursor);
        }
        // The next sibling still in the range, or up.
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
}

@end
