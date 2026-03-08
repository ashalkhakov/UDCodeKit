#import "UDIncrementalHighlighterBase.h"
#import <UDPieceTable/UDIntervalTree.h>

static inline uint32_t   byteFromChar(NSUInteger c) { return (uint32_t)(c * 2); }

@interface UDIncrementalHighlighterBase ()
@property (nonatomic, strong) NSMutableArray<UDModelDeltaDecoration *> *pendingDecorations;
@property (nonatomic, assign) NSUInteger currentDocLen;
@end

@implementation UDIncrementalHighlighterBase {
    TSTreeVisitor *_visitor;
}

// ---------------------------------------------------------------------------
#pragma mark - Init
// ---------------------------------------------------------------------------

- (instancetype)initWithTextStorage:(UDTextModelTextStorage *)textStorage
                         highlighter:(UDTreeSitterHighlighter *)highlighter {
    self = [super initWithTextStorage:textStorage highlighter:highlighter];
    if (!self) return nil;
    _maxDecorations  = [self defaultMaxDecorations];
    _alwaysFullScan  = NO;
    _visitor         = [[TSTreeVisitor alloc] initWithDelegate:self];
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
        // ---- Correct incremental path -------------------------------------------
        //
        // lastChangedCharRanges is derived from ts_tree_get_changed_ranges, which
        // is the structural diff of the old vs new parse trees.  Non-local error-
        // recovery effects are therefore captured: if an ERROR node disappeared or
        // moved, its range appears in changedRanges.
        //
        // Rule: a decoration at start offset S belongs to an error node that
        // *started* at S.  If S is outside every changed range the node is
        // identical in both trees → decoration is still valid.  We only touch
        // decorations (and emit new ones) for positions inside a changed range.

        NSString *owner = [self decorationOwner];

        // 1. Find stale decoration IDs whose START offset falls within any changed
        //    char range.  Range-overlap would incorrectly flag decorations that
        //    merely span into the changed area but started before it.
        NSMutableSet<NSString *> *staleIDs = [NSMutableSet set];
        for (NSValue *rv in changedRanges) {
            NSRange cr = [rv rangeValue];
            if (cr.length == 0) continue;
            NSArray<UDIntervalNode *> *nodes =
                [model decorationNodesInOffsetRange:(NSInteger)cr.location
                                                end:(NSInteger)NSMaxRange(cr)];
            for (UDIntervalNode *n in nodes) {
                if ([n.owner isEqualToString:owner] &&
                    n.start >= (NSInteger)cr.location &&
                    n.start <  (NSInteger)NSMaxRange(cr)) {
                    [staleIDs addObject:n.identifier];
                }
            }
        }

        // 2. Partition current IDs into keep / remove.
        NSMutableArray<NSString *> *toKeep   = [NSMutableArray array];
        NSMutableArray<NSString *> *toRemove = [NSMutableArray array];
        for (NSString *did in [self _currentDecorationIDs]) {
            BOOL isStale = [staleIDs containsObject:did];
            [( isStale ? toRemove : toKeep) addObject:did];
        }
        if (toRemove.count > 0) {
            [model deltaDecorations:toRemove newDecorations:@[] owner:owner];
        }

        // 3. Walk changed subtrees to find new error-node candidates.
        NSUInteger budget = (toKeep.count < _maxDecorations)
                                ? _maxDecorations - toKeep.count : 0;

        if (budget > 0) {
            [self _runVisitorWithBudget:budget tree:tree];

            // 4. Post-filter: only keep candidates whose start offset falls within
            //    a changed range.  Also deduplicate — two changed ranges can resolve
            //    to the same large ERROR-node subtree, yielding duplicate entries.
            if (_pendingDecorations.count > 0) {
                NSMutableArray<UDModelDeltaDecoration *> *filtered =
                    [NSMutableArray arrayWithCapacity:_pendingDecorations.count];
                NSMutableSet<NSNumber *> *seenOffsets = [NSMutableSet set];

                for (UDModelDeltaDecoration *d in _pendingDecorations) {
                    NSInteger startOff = [model getOffsetAt:d.range.startLineNumber
                                                     column:d.range.startColumn];
                    NSNumber *key = @(startOff);
                    if ([seenOffsets containsObject:key]) {
                        continue; // skip duplicate decoration at same start offset
                    }

                    for (NSValue *rv in changedRanges) {
                        NSRange cr = [rv rangeValue];
                        if (startOff >= (NSInteger)cr.location &&
                            startOff <  (NSInteger)NSMaxRange(cr)) {
                            [filtered addObject:d];
                            [seenOffsets addObject:key];
                            break;
                        }
                    }
                }

                if (filtered.count > 0) {
                    NSArray<NSString *> *added =
                        [model deltaDecorations:@[]
                                 newDecorations:filtered
                                          owner:owner];
                    [toKeep addObjectsFromArray:added];
                }
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
#pragma mark - TSNodeVisitor (bridge to subclass hook)
// ---------------------------------------------------------------------------

- (BOOL)visitor:(id)visitor willVisitNode:(TSNode)node depth:(NSUInteger)depth {
    if (_remainingBudget == 0) return NO;
    return [self willVisitNode:node depth:depth];
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

    NSArray<NSValue *> *changedRanges = self.highlighter.lastChangedCharRanges;
    if (!_alwaysFullScan && changedRanges.count > 0) {
        // Incremental: walk only the subtrees covering changed byte ranges.
        NSMutableArray<NSValue *> *byteRanges =
            [NSMutableArray arrayWithCapacity:changedRanges.count];
        for (NSValue *rv in changedRanges) {
            NSRange cr = [rv rangeValue];
            NSRange br = NSMakeRange(
                byteFromChar(cr.location),
                byteFromChar(NSMaxRange(cr)) - byteFromChar(cr.location));
            [byteRanges addObject:[NSValue valueWithRange:br]];
        }
        [_visitor visitChangedByteRanges:byteRanges inTree:tree];
    } else {
        // Full scan (initial load, undo/redo, or alwaysFullScan = YES).
        [_visitor visitTree:ts_tree_root_node((TSTree *)tree)];
    }
}

@end
