#import "UDIncrementalHighlighterBase.h"
#import <UDPieceTable/UDIntervalTree.h>

static inline NSUInteger charFromByte(uint32_t b) { return (NSUInteger)(b / 2); }
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
    _maxDecorations = [self defaultMaxDecorations];
    _visitor        = [[TSTreeVisitor alloc] initWithDelegate:self];
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

    if (changedRanges.count > 0) {
        // ---- Incremental path -------------------------------------------

        // 1. Find stale decoration IDs that overlap any changed char range.
        NSString *owner = [self decorationOwner];
        NSMutableSet<NSString *> *staleIDs = [NSMutableSet set];
        for (NSValue *rv in changedRanges) {
            NSRange cr = [rv rangeValue];
            if (cr.length == 0) continue;
            NSArray<UDIntervalNode *> *nodes =
                [model decorationNodesInOffsetRange:(NSInteger)cr.location
                                                end:(NSInteger)NSMaxRange(cr)];
            for (UDIntervalNode *n in nodes) {
                if ([n.owner isEqualToString:owner]) {
                    [staleIDs addObject:n.identifier];
                }
            }
        }

        // 2. Partition current IDs into keep / remove.
        NSMutableArray<NSString *> *toKeep   = [NSMutableArray array];
        NSMutableArray<NSString *> *toRemove = [NSMutableArray array];
        for (NSString *did in [self _currentDecorationIDs]) {
            [([staleIDs containsObject:did] ? toRemove : toKeep)
                addObject:did];
        }
        if (toRemove.count > 0) {
            [model deltaDecorations:toRemove
                     newDecorations:@[]
                              owner:owner];
        }

        // 3. Walk affected subtrees if budget remains.
        NSUInteger budget = (toKeep.count < _maxDecorations)
                                ? _maxDecorations - toKeep.count : 0;

        if (budget > 0) {
            [self _runVisitorWithBudget:budget tree:tree];

            if (_pendingDecorations.count > 0) {
                NSArray<NSString *> *added =
                    [model deltaDecorations:@[]
                             newDecorations:_pendingDecorations
                                      owner:owner];
                [toKeep addObjectsFromArray:added];
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
    if (changedRanges.count > 0) {
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
        [_visitor visitTree:ts_tree_root_node((TSTree *)tree)];
    }
}

@end
