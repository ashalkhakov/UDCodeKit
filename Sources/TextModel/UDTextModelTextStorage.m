#import "UDTextModelTextStorage.h"
#import "UDTextModelString.h"
#import "UDTreeSitterHighlighter.h"
#import "UDSyntaxHighlighter.h"
#import "UDDecorationLayerRegistry.h"
#import <UDPieceTable/UDIntervalTree.h>

NSString * const UDFindDecorationOwner         = @"find";
NSString * const UDFoldDecorationOwner         = @"fold";
NSString * const UDBracketMatchDecorationOwner = @"bracket.match";
NSString * const UDMissingNodeDecorationOwner  = @"missing";
NSString * const UDParseErrorDecorationOwner   = @"ts.error";

// ---------------------------------------------------------------------------
#pragma mark - Base attributes
// ---------------------------------------------------------------------------

static NSDictionary<NSAttributedStringKey, id> *BaseAttributes(void) {
    NSFont *font = [NSFont userFixedPitchFontOfSize:13.0]
                ?: [NSFont systemFontOfSize:13.0];
    return @{
        NSFontAttributeName:            font,
        NSForegroundColorAttributeName: [NSColor labelColor],
    };
}

// ---------------------------------------------------------------------------
#pragma mark - Private interface
// ---------------------------------------------------------------------------

@interface UDTextModelTextStorage ()
@property (nonatomic, strong) UDTextModel             *textModel;
@property (nonatomic, strong) UDTextModelString       *modelString;
@property (nonatomic, strong) UDTreeSitterHighlighter *highlighter;
@property (nonatomic, strong) UDSyntaxHighlighter     *syntaxHighlighter;
@property (nonatomic)         BOOL                     suppressModelNotification;
@property (nonatomic)         NSUInteger               lastKnownLength;
@property (nonatomic)         BOOL                     hasPendingDirty;
@property (nonatomic)         NSInteger                pendingDirtyStart;
@property (nonatomic)         NSInteger                pendingDirtyEnd;
// ---------------------------------------------------------------------------
// Attribute-run cache.
//
// Rebuilt lazily whenever attrCacheDirty is YES.  Runs are sorted and cover
// [0, lastKnownLength) without gaps.  attrRunRangesData holds a plain C
// NSRange[] (stored as raw bytes in an NSData); attrRunAttrs[i] is the
// attribute dictionary for the i-th run.
//
// Storing ranges as a raw C array instead of NSArray<NSValue *> eliminates
// two ObjC message dispatches (objectAtIndexedSubscript: + rangeValue) and
// one NSValue struct-extraction per binary-search step.  For a 330 KB JSON
// file with ~50 000 syntax runs and O(log 50000) ≈ 16 comparisons per
// -attributesAtIndex:effectiveRange: call, this saves ~800 000 ObjC message
// sends per full-document layout pass.
// ---------------------------------------------------------------------------
@property (nonatomic, strong, nullable) NSData             *attrRunRangesData; // raw NSRange[]
@property (nonatomic, strong, nullable) NSArray<NSDictionary *> *attrRunAttrs;
@property (nonatomic)                  BOOL                     attrCacheDirty;
@end

@implementation UDTextModelTextStorage

// In +load or a dedicated +registerBuiltinLayers call from -initWithText:
+ (void)load {
    // Find
    [[UDDecorationLayerRegistry shared]
        registerOwner:UDFindDecorationOwner
                layer:1
           attrBlock:^NSDictionary *(UDIntervalNode *node) {
        return @{ NSBackgroundColorAttributeName: [NSColor systemYellowColor] };
    }];

    // Fold — collapse text visually
    [[UDDecorationLayerRegistry shared]
        registerOwner:UDFoldDecorationOwner
                layer:3
           attrBlock:^NSDictionary *(UDIntervalNode *node) {
        static NSDictionary *d;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            NSMutableParagraphStyle *s = [[NSMutableParagraphStyle alloc] init];
            s.minimumLineHeight = 1.0; s.maximumLineHeight = 1.0;
            s.lineSpacing = 0.0; s.paragraphSpacing = 0.0;
            s.paragraphSpacingBefore = 0.0;
            d = @{
                NSForegroundColorAttributeName: [NSColor clearColor],
                NSFontAttributeName:            [NSFont systemFontOfSize:0.1],
                NSParagraphStyleAttributeName:  s,
            };
        });
        return d;
    }];
}

// ---------------------------------------------------------------------------
#pragma mark - Init / dealloc
// ---------------------------------------------------------------------------

- (instancetype)initWithTextModel:(UDTextModel *)textModel {
    self = [super init];
    if (!self) return nil;

    _textModel   = textModel;
    _modelString = [[UDTextModelString alloc] initWithTextModel:_textModel];
    _highlighter = [[UDTreeSitterHighlighter alloc] initWithTextModel:_textModel];
    _syntaxHighlighter = [[UDSyntaxHighlighter alloc] initWithTextStorage:self
                                                               highlighter:_highlighter];
    _lastKnownLength = (NSUInteger)[_textModel getLength];
    _hasPendingDirty = NO;
    _pendingDirtyStart = 0;
    _pendingDirtyEnd   = 0;
    _attrCacheDirty    = YES;

    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(_modelDidChange:)
               name:UDTextModelDidChangeNotification
             object:_textModel];
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(_decorationsDidChange:)
               name:UDTextModelDecorationsDidChangeNotification
             object:_textModel];
    return self;
}

- (instancetype)initWithText:(NSString *)initialText {
    return [self initWithTextModel:[[UDTextModel alloc] initWithText:initialText]];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

// ---------------------------------------------------------------------------
#pragma mark - Decoration change notification
// ---------------------------------------------------------------------------

- (void)_decorationsDidChange:(NSNotification *)note {
    NSValue *rv = note.userInfo[@"range"];
    if (!rv) return;
    NSRange dirty = [rv rangeValue];
    if (dirty.length == 0) return;
    NSInteger s = (NSInteger)dirty.location;
    NSInteger e = (NSInteger)NSMaxRange(dirty);
    if (!_hasPendingDirty) {
        _hasPendingDirty   = YES;
        _pendingDirtyStart = s;
        _pendingDirtyEnd   = e;
    } else {
        _pendingDirtyStart = MIN(_pendingDirtyStart, s);
        _pendingDirtyEnd   = MAX(_pendingDirtyEnd,   e);
    }
    // Invalidate the attribute-run cache so the next layout pass rebuilds it.
    _attrCacheDirty = YES;
}

// ---------------------------------------------------------------------------
#pragma mark - UDTextModelDidChangeNotification (undo / redo)
// ---------------------------------------------------------------------------

- (void)_modelDidChange:(NSNotification *)note {
    if (_suppressModelNotification) return;

    NSUInteger oldLen = _lastKnownLength;
    NSUInteger newLen = (NSUInteger)[_textModel getLength];
    NSInteger  delta  = (NSInteger)newLen - (NSInteger)oldLen;
    _lastKnownLength  = newLen;
    _attrCacheDirty   = YES;

    [self beginEditing];
    [self edited:(NSTextStorageEditedCharacters | NSTextStorageEditedAttributes)
           range:NSMakeRange(0, oldLen)
 changeInLength:delta];
    [self endEditing];

    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_highlighter reparseFullString:[self->_textModel getValue]];
        [self->_syntaxHighlighter update];
        [self applyDecorationHighlights];
    });
}

// ---------------------------------------------------------------------------
#pragma mark - NSTextStorage primitives
// ---------------------------------------------------------------------------

- (NSString *)string {
    return _modelString;
}

- (NSDictionary<NSAttributedStringKey, id> *)attributesAtIndex:(NSUInteger)location
                                                effectiveRange:(NSRangePointer)outRange {
    NSUInteger docLen = _lastKnownLength;
    if (docLen == 0 || location >= docLen) {
        if (outRange) *outRange = NSMakeRange(location, 0);
        return BaseAttributes();
    }

    // Rebuild the attribute-run cache if it is stale.
    if (_attrCacheDirty || !_attrRunRangesData) {
        [self _rebuildAttrRunCache];
    }

    // Binary-search for the cached run that contains 'location'.
    // _attrRunRangesData holds a plain NSRange[] — direct C-struct access,
    // no ObjC message dispatch per step (vs. the old NSArray<NSValue*> path).
    // NSData bytes are guaranteed to be suitably aligned for any standard C
    // type, so the cast to NSRange * is safe on all supported platforms.
    NSCAssert(_attrRunRangesData.length % sizeof(NSRange) == 0,
              @"attrRunRangesData must contain whole NSRange structs");
    const NSRange *runs  = (const NSRange *)_attrRunRangesData.bytes;
    NSUInteger     count = _attrRunRangesData.length / sizeof(NSRange);
    NSArray       *attrs = _attrRunAttrs;

    NSUInteger lo = 0, hi = count;
    while (lo < hi) {
        NSUInteger mid = lo + (hi - lo) / 2;
        NSRange r = runs[mid];
        if (NSMaxRange(r) <= location) {
            lo = mid + 1;
        } else if (r.location > location) {
            hi = mid;
        } else {
            // r.location <= location < NSMaxRange(r)
            if (outRange) *outRange = r;
            return attrs[mid];
        }
    }

    // Fallback (should not be reached for a valid location).
    if (outRange) *outRange = NSMakeRange(location, 1);
    return BaseAttributes();
}

- (void)replaceCharactersInRange:(NSRange)range withString:(NSString *)str {
    if (!str) str = @"";

    NSUInteger docLen   = _lastKnownLength;
    NSUInteger clampLoc = MIN(range.location, docLen);
    NSUInteger clampEnd = MIN(NSMaxRange(range), docLen);
    NSRange    safe     = NSMakeRange(clampLoc, clampEnd - clampLoc);

    UDPosition sp = [_textModel getPositionAt:(NSInteger)safe.location];
    UDPosition ep = [_textModel getPositionAt:(NSInteger)NSMaxRange(safe)];
    UDRange    mr = PTRangeMake(sp.line, sp.column, ep.line, ep.column);
    UDTextModelEdit *edit = [[UDTextModelEdit alloc] initWithRange:mr text:str];

    _suppressModelNotification = YES;
    [_textModel applyEdits:@[edit]];
    _suppressModelNotification = NO;

    NSInteger delta  = (NSInteger)str.length - (NSInteger)safe.length;
    _lastKnownLength = (NSUInteger)((NSInteger)docLen + delta);
    _attrCacheDirty  = YES;

    [self beginEditing];
    [self edited:NSTextStorageEditedCharacters range:safe changeInLength:delta];
    [self endEditing];
}

- (void)setAttributes:(nullable NSDictionary<NSAttributedStringKey, id> *)attrs
                range:(NSRange)range {
    // Attributes derive entirely from decorations; intentional no-op.
}

// ---------------------------------------------------------------------------
#pragma mark - processEditing
// ---------------------------------------------------------------------------

- (void)processEditing {
    NSRange   editedRange = self.editedRange;
    NSInteger delta       = self.changeInLength;
    NSTextStorageEditActions mask = self.editedMask;

    [super processEditing];

    if ((mask & NSTextStorageEditedCharacters) && _highlighter.isActive) {
        NSString *snap = [_textModel getValue];
        [_highlighter performIncrementalParseAfterEdit:editedRange
                                         changeInLength:delta
                                          currentString:snap];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self->_syntaxHighlighter update];
            [self applyDecorationHighlights];
        });
    }
}

// ---------------------------------------------------------------------------
#pragma mark - Tree-sitter language setup
// ---------------------------------------------------------------------------

- (void)setTheme:(nullable TreeSitterTheme *)theme {
    _theme = theme;
    _attrCacheDirty = YES;
    // Force a full attribute redraw: the theme changes how existing highlight
    // decorations are rendered, so the entire document needs to be refreshed.
    [self _dirtyFullDocument];
}

- (void)setLanguageFunc:(nullable LanguageFunc)languageFunc
    withHighlightsQuery:(NSString *)queryText {
    [_highlighter setLanguageFunc:languageFunc withHighlightsQuery:queryText];
    if (languageFunc) {
        [_highlighter reparseFullString:[_textModel getValue]];
        [_syntaxHighlighter update];
    }
    // Force a full redraw regardless of whether decoration notifications fired,
    // since on first parse _hasPendingDirty may still be NO.
    [self _dirtyFullDocument];
    [self applyDecorationHighlights];
}

// ---------------------------------------------------------------------------
#pragma mark - Decoration highlight signalling
// ---------------------------------------------------------------------------

- (void)applyDecorationHighlights {
    NSUInteger docLen = _lastKnownLength;
    if (docLen == 0) { [self _resetPendingDirty]; return; }

    // If no decoration notifications have fired but the caller explicitly
    // asked for a full redraw (e.g. initial parse), dirty the whole document.
    if (!_hasPendingDirty) return;

    NSUInteger ds = (NSUInteger)MAX(0LL, _pendingDirtyStart);
    NSUInteger de = (NSUInteger)MIN((NSInteger)docLen, _pendingDirtyEnd);
    [self _resetPendingDirty];
    if (de <= ds) return;

    [self beginEditing];
    [self edited:NSTextStorageEditedAttributes
           range:NSMakeRange(ds, de - ds)
 changeInLength:0];
    [self endEditing];
}

- (void)applyDecorationHighlightsInRange:(NSRange)range {
    NSUInteger docLen = _lastKnownLength;
    if (docLen == 0 || range.length == 0) return;
    NSUInteger loc = MIN(range.location, docLen);
    NSUInteger len = MIN(range.length, docLen - loc);
    if (len == 0) return;
    [self beginEditing];
    [self edited:NSTextStorageEditedAttributes
           range:NSMakeRange(loc, len)
 changeInLength:0];
    [self endEditing];
}

// ---------------------------------------------------------------------------
#pragma mark - Private helpers
// ---------------------------------------------------------------------------

- (void)_dirtyFullDocument {
    NSUInteger docLen = _lastKnownLength;
    if (docLen == 0) return;
    if (!_hasPendingDirty) {
        _hasPendingDirty   = YES;
        _pendingDirtyStart = 0;
        _pendingDirtyEnd   = (NSInteger)docLen;
    } else {
        _pendingDirtyStart = 0;
        _pendingDirtyEnd   = MAX(_pendingDirtyEnd, (NSInteger)docLen);
    }
}

- (void)_resetPendingDirty {
    _hasPendingDirty   = NO;
    _pendingDirtyStart = 0;
    _pendingDirtyEnd   = 0;
}

// ---------------------------------------------------------------------------
#pragma mark - Attribute-run cache helpers
// ---------------------------------------------------------------------------

/// Returns the merged attribute dictionary for the given set of decoration
/// nodes covering a single text segment.  Syntax-highlight nodes (owner ==
/// UDHighlightDecorationOwner) are resolved against the current theme; all
/// other nodes go through UDDecorationLayerRegistry.
- (NSDictionary<NSAttributedStringKey, id> *)_mergedAttrsForCovering:
        (NSArray<UDIntervalNode *> *)covering {
    NSMutableDictionary *merged =
        [NSMutableDictionary dictionaryWithDictionary:BaseAttributes()];

    NSMutableArray<UDIntervalNode *> *nonTheme = nil;

    for (UDIntervalNode *node in covering) {
        if ([node.owner isEqualToString:UDHighlightDecorationOwner]) {
            if (_theme && node.options.className) {
                NSDictionary *themeAttrs =
                    [_theme styleAttributesForName:node.options.className];
                if (themeAttrs) [merged addEntriesFromDictionary:themeAttrs];
            }
        } else {
            if (!nonTheme) nonTheme = [NSMutableArray array];
            [nonTheme addObject:node];
        }
    }

    if (nonTheme.count > 0) {
        NSDictionary *rest =
            [[UDDecorationLayerRegistry shared]
                mergedAttributesForNodes:nonTheme
                         baseAttributes:@{}];
        [merged addEntriesFromDictionary:rest];
    }

    return [merged copy];
}

/// Rebuilds the attribute-run cache by performing a single pass over all
/// decoration nodes in the document.
///
/// Algorithm (O(N log N)):
///  1. Fetch all decoration nodes in one O(N) query (allNodes, sorted by start).
///  2. Collect all boundary offsets (node starts and ends) and sort them.
///  3. Sweep left-to-right, maintaining an "active" set of nodes covering the
///     current segment.  At each segment boundary, emit one run with the merged
///     attributes of the active set.
///
/// After this method the cache is clean.  All subsequent calls to
/// -attributesAtIndex:effectiveRange: are O(log K) binary searches over a
/// plain C NSRange[] (no ObjC message dispatch per comparison step).
- (void)_rebuildAttrRunCache {
    _attrCacheDirty = NO;

    NSUInteger docLen = _lastKnownLength;
    if (docLen == 0) {
        _attrRunRangesData = [NSData data];
        _attrRunAttrs      = @[];
        return;
    }

    // ── 1. Fetch all decoration nodes (one query, sorted by start) ──────────
    NSArray<UDIntervalNode *> *allNodes =
        [_textModel decorationNodesInOffsetRange:0 end:(NSInteger)docLen];

    if (allNodes.count == 0) {
        NSRange whole = NSMakeRange(0, docLen);
        _attrRunRangesData = [NSData dataWithBytes:&whole length:sizeof(NSRange)];
        _attrRunAttrs      = @[ BaseAttributes() ];
        return;
    }

    // ── 2. Collect boundary offsets ─────────────────────────────────────────
    // Each node contributes its (clamped) start and end as boundaries.
    // Using NSMutableSet for automatic deduplication.
    NSMutableSet<NSNumber *> *boundarySet =
        [NSMutableSet setWithCapacity:allNodes.count * 2 + 2];
    [boundarySet addObject:@(0LL)];
    [boundarySet addObject:@((NSInteger)docLen)];
    for (UDIntervalNode *n in allNodes) {
        NSInteger s = MAX(0LL, n.start);
        NSInteger e = MIN((NSInteger)docLen, n.end);
        [boundarySet addObject:@(s)];
        if (e > 0) [boundarySet addObject:@(e)];
    }
    NSArray<NSNumber *> *bounds =
        [[boundarySet allObjects] sortedArrayUsingSelector:@selector(compare:)];

    NSUInteger numSeg = bounds.count > 1 ? bounds.count - 1 : 0;
    if (numSeg == 0) {
        NSRange whole = NSMakeRange(0, docLen);
        _attrRunRangesData = [NSData dataWithBytes:&whole length:sizeof(NSRange)];
        _attrRunAttrs      = @[ BaseAttributes() ];
        return;
    }

    // ── 3. Sweep left-to-right ───────────────────────────────────────────────
    // 'active' holds nodes whose ranges overlap the current segment.
    // 'nodeIdx' advances through allNodes (sorted by start) as the sweep moves.
    //
    // Ranges are appended as raw NSRange structs into an NSMutableData so the
    // binary search in -attributesAtIndex:effectiveRange: can access them via
    // a plain C pointer — no ObjC message dispatch or NSValue unboxing.
    NSMutableData            *runRangesData =
        [NSMutableData dataWithCapacity:numSeg * sizeof(NSRange)];
    NSMutableArray<NSDictionary *> *runAttrs =
        [NSMutableArray arrayWithCapacity:numSeg];
    NSMutableArray<UDIntervalNode *> *active =
        [NSMutableArray arrayWithCapacity:4];
    NSUInteger nodeIdx   = 0;
    NSUInteger nodeCount = allNodes.count;

    for (NSUInteger seg = 0; seg < numSeg; seg++) {
        NSInteger segStart = [bounds[seg]     integerValue];
        NSInteger segEnd   = [bounds[seg + 1] integerValue];

        // Remove nodes whose ranges ended at or before segStart.
        for (NSUInteger ai = active.count; ai > 0; ai--) {
            if (active[ai - 1].end <= segStart) {
                [active removeObjectAtIndex:ai - 1];
            }
        }
        // Add nodes that start at or before segStart and extend into this segment.
        while (nodeIdx < nodeCount && allNodes[nodeIdx].start <= segStart) {
            UDIntervalNode *n = allNodes[nodeIdx++];
            if (n.end > segStart) [active addObject:n];
        }

        NSRange r = NSMakeRange((NSUInteger)segStart,
                                (NSUInteger)(segEnd - segStart));
        [runRangesData appendBytes:&r length:sizeof(NSRange)];
        [runAttrs addObject:[self _mergedAttrsForCovering:active]];
    }

    _attrRunRangesData = [runRangesData copy];
    _attrRunAttrs      = [runAttrs copy];
}

@end
