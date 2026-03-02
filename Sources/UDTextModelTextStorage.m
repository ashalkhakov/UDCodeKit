/*---------------------------------------------------------------------------------------------
 *  UDTextModelTextStorage.m
 *--------------------------------------------------------------------------------------------*/

#import "UDTextModelTextStorage.h"
#import "UDTextModelString.h"
#import "UDTreeSitterHighlighter.h"
#import <UDPieceTable/UDIntervalTree.h>

NSString * const UDFindDecorationOwner         = @"find";
NSString * const UDFoldDecorationOwner         = @"fold";
NSString * const UDBracketMatchDecorationOwner = @"bracket.match";
NSString * const UDMissingNodeDecorationOwner  = @"missing";

// ---------------------------------------------------------------------------
// MARK: - Base attributes
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
// MARK: - Per-layer attribute helpers
// ---------------------------------------------------------------------------

/// Returns the decoration layer (0–4) for the given owner string, or -1 if unknown.
static inline NSInteger LayerForOwner(NSString * _Nullable owner) {
    if (!owner) return -1;
    if ([owner isEqualToString:@"highlight"])     return 0;
    if ([owner isEqualToString:@"find"])          return 1;
    if ([owner isEqualToString:@"bracket.match"]) return 2;
    if ([owner isEqualToString:@"fold"])          return 3;
    if ([owner isEqualToString:@"missing"])       return 4;
    return -1;
}

static NSColor *BracketMatchBGColor(void) {
    static NSColor *c;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        c = [NSColor colorWithRed:0.38 green:0.60 blue:0.90 alpha:0.35];
    });
    return c;
}

static NSColor *MissingNodeBGColor(void) {
    static NSColor *c;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        c = [NSColor colorWithRed:0.95 green:0.42 blue:0.13 alpha:0.85];
    });
    return c;
}

static NSDictionary *FoldAttributes(void) {
    static NSDictionary *d;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableParagraphStyle *s = [[NSMutableParagraphStyle alloc] init];
        s.minimumLineHeight = 1.0;
        s.maximumLineHeight = 1.0;
        s.lineSpacing = 0.0;
        s.paragraphSpacing = 0.0;
        s.paragraphSpacingBefore = 0.0;
        d = @{
            NSForegroundColorAttributeName: [NSColor clearColor],
            NSFontAttributeName:            [NSFont systemFontOfSize:0.1],
            NSParagraphStyleAttributeName:  s,
        };
    });
    return d;
}

// ---------------------------------------------------------------------------
// MARK: - Private interface
// ---------------------------------------------------------------------------

@interface UDTextModelTextStorage ()
@property (nonatomic, strong) UDTextModel              *textModel;
@property (nonatomic, strong) UDTextModelString        *modelString;
@property (nonatomic, strong) UDTreeSitterHighlighter  *highlighter;
@property (nonatomic)         BOOL                      suppressModelNotification;
@property (nonatomic)         NSUInteger                lastKnownLength;

// Union of decoration change ranges that have been recorded since the last
// -applyDecorationHighlights flush.  _hasPendingDirty tracks whether any dirty
// range has accumulated; _pendingDirtyStart/_pendingDirtyEnd carry the bounds.
@property (nonatomic)         BOOL                      hasPendingDirty;
@property (nonatomic)         NSInteger                 pendingDirtyStart;
@property (nonatomic)         NSInteger                 pendingDirtyEnd;
@end

@implementation UDTextModelTextStorage

// ---------------------------------------------------------------------------
// MARK: - Init / dealloc
// ---------------------------------------------------------------------------

- (instancetype)initWithText:(NSString *)initialText {
    self = [super init];
    if (!self) return nil;

    _textModel              = [[UDTextModel alloc] initWithText:initialText];
    _modelString            = [[UDTextModelString alloc] initWithTextModel:_textModel];
    _highlighter            = [[UDTreeSitterHighlighter alloc] initWithTextModel:_textModel];
    _suppressModelNotification = NO;
    _lastKnownLength        = initialText.length;
    _hasPendingDirty        = NO;
    _pendingDirtyStart      = 0;
    _pendingDirtyEnd        = 0;

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

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

// ---------------------------------------------------------------------------
// MARK: - Theme forwarding
// ---------------------------------------------------------------------------

- (void)setTheme:(TreeSitterTheme *)theme {
    _highlighter.theme = theme;
}

- (TreeSitterTheme *)theme {
    return _highlighter.theme;
}

// ---------------------------------------------------------------------------
// MARK: - Decoration change notification
// ---------------------------------------------------------------------------

/// Called synchronously from UDTextModel.deltaDecorations:newDecorations:owner: with
/// the union character range of all added/removed decorations.  We simply accumulate
/// the dirty range here; the actual NSTextStorage notification is deferred to the
/// next -applyDecorationHighlights call so that batched decoration updates produce
/// a single layout pass rather than one per deltaDecorations: call.
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
}

// ---------------------------------------------------------------------------
// MARK: - UDTextModelDidChangeNotification (undo / redo)
// ---------------------------------------------------------------------------

- (void)_modelDidChange:(NSNotification *)note {
    if (_suppressModelNotification) return;

    NSUInteger oldLen = _lastKnownLength;
    NSUInteger newLen = (NSUInteger)[_textModel getLength];
    NSInteger  delta  = (NSInteger)newLen - (NSInteger)oldLen;
    _lastKnownLength  = newLen;

    [self beginEditing];
    [self edited:(NSTextStorageEditedCharacters | NSTextStorageEditedAttributes)
           range:NSMakeRange(0, oldLen)
 changeInLength:delta];
    [self endEditing];

    dispatch_async(dispatch_get_main_queue(), ^{
        [self->_highlighter reparseFullString:[self->_textModel getValue]];
        [self applyDecorationHighlights];
    });
}

// ---------------------------------------------------------------------------
// MARK: - NSTextStorage primitives
// ---------------------------------------------------------------------------

- (NSString *)string {
    return _modelString;
}

/// Compute attributes for the character at @c location on-the-fly by querying
/// the interval tree for decoration nodes that cover this position.
///
/// This replaces the former precomputed _attrRunRanges/_attrRunAttrs cache.
/// Work is proportional to the number of decorations covering the queried
/// range, not the total document size.
- (NSDictionary<NSAttributedStringKey, id> *)attributesAtIndex:(NSUInteger)location
                                                effectiveRange:(NSRangePointer)outRange {
    NSUInteger docLen = _lastKnownLength;
    if (docLen == 0 || location >= docLen) {
        if (outRange) *outRange = NSMakeRange(location, 0);
        return BaseAttributes();
    }

    // Query interval nodes that cover this single character position.
    // nodesInRange(s, e) returns nodes where start < e AND end > s, so
    // with e = location+1 we get exactly start <= location AND end > location.
    NSArray<UDIntervalNode *> *covering =
        [_textModel decorationNodesInOffsetRange:(NSInteger)location
                                             end:(NSInteger)location + 1];

    // Merge attributes in layer order (lower layer first; higher layer overrides).
    NSMutableDictionary *merged = [NSMutableDictionary dictionaryWithDictionary:BaseAttributes()];
    NSUInteger effStart = 0;
    NSUInteger effEnd   = docLen;

    for (NSInteger layer = 0; layer <= 4; layer++) {
        for (UDIntervalNode *node in covering) {
            if (LayerForOwner(node.owner) != layer) continue;
            // node.start <= location AND node.end > location is guaranteed by
            // nodesInRange(location, location+1); no additional guard needed.

            // Tighten effective range to the intersection of all covering spans.
            effStart = MAX(effStart, (NSUInteger)MAX(0LL, node.start));
            effEnd   = MIN(effEnd,   (NSUInteger)MAX(0LL, node.end));

            NSDictionary *attrs = [self _attrsForNode:node];
            if (attrs) [merged addEntriesFromDictionary:attrs];
        }
    }

    if (outRange) {
        // Narrow effEnd: find the nearest decoration that STARTS after location
        // (within our current effEnd) — it marks a future attribute boundary.
        // nodesInRange returns nodes in insertion order (sorted by start per
        // UDIntervalTree.insert), so we scan all and take the minimum start > location.
        if (effEnd > location + 1) {
            NSArray<UDIntervalNode *> *rightBoundary =
                [_textModel decorationNodesInOffsetRange:(NSInteger)location + 1
                                                     end:(NSInteger)effEnd];
            for (UDIntervalNode *node in rightBoundary) {
                if (node.start > (NSInteger)location) {
                    NSUInteger ns = (NSUInteger)MAX(0LL, node.start);
                    if (ns < effEnd) effEnd = ns;
                }
            }
        }

        // Narrow effStart: find the nearest decoration that ENDS at or before
        // location (within our current effStart) — it marks a past boundary.
        if (effStart < location) {
            NSArray<UDIntervalNode *> *leftBoundary =
                [_textModel decorationNodesInOffsetRange:(NSInteger)effStart
                                                     end:(NSInteger)location + 1];
            for (UDIntervalNode *node in leftBoundary) {
                if (node.end > (NSInteger)effStart && node.end <= (NSInteger)location) {
                    NSUInteger ne = (NSUInteger)MAX(0LL, node.end);
                    if (ne > effStart) effStart = ne;
                }
            }
        }

        if (effEnd <= effStart) effEnd = MIN(effStart + 1, docLen);
        *outRange = NSMakeRange(effStart, effEnd - effStart);
    }

    return [merged copy];
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

    [self beginEditing];
    [self edited:NSTextStorageEditedCharacters range:safe changeInLength:delta];
    [self endEditing];
}

- (void)setAttributes:(nullable NSDictionary<NSAttributedStringKey, id> *)attrs
                range:(NSRange)range {
    // Attributes derive entirely from decorations; this is a no-op.
}

// ---------------------------------------------------------------------------
// MARK: - processEditing
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
            [self applyDecorationHighlights];
        });
    }
}

// ---------------------------------------------------------------------------
// MARK: - Tree-sitter language setup
// ---------------------------------------------------------------------------

- (void)setLanguageFunc:(nullable LanguageFunc)languageFunc
    withHighlightsQuery:(NSString *)queryText {
    [_highlighter setLanguageFunc:languageFunc withHighlightsQuery:queryText];

    if (languageFunc) {
        [_highlighter reparseFullString:[_textModel getValue]];
    }
    [self applyDecorationHighlights];
}

// ---------------------------------------------------------------------------
// MARK: - Decoration highlight signalling
// ---------------------------------------------------------------------------

- (void)applyDecorationHighlights {
    // Flush any accumulated dirty ranges recorded by _decorationsDidChange:.
    // If no decoration changes have been recorded since the last flush, this
    // is a no-op (avoids forcing a full document re-layout unnecessarily).
    if (!_hasPendingDirty) return;

    NSUInteger docLen = _lastKnownLength;
    if (docLen == 0) { [self _resetPendingDirty]; return; }

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
// MARK: - Attribute helpers
// ---------------------------------------------------------------------------

/// Map a decoration interval node to its visual attribute dict based on owner.
- (nullable NSDictionary *)_attrsForNode:(UDIntervalNode *)node {
    NSString *owner = node.owner;
    if ([owner isEqualToString:UDHighlightDecorationOwner]) {
        TreeSitterTheme *theme = _highlighter.theme;
        if (!theme || !node.options.className) return nil;
        return [theme styleAttributesForName:node.options.className];
    }
    if ([owner isEqualToString:UDFindDecorationOwner]) {
        return @{ NSBackgroundColorAttributeName: [NSColor systemYellowColor] };
    }
    if ([owner isEqualToString:UDBracketMatchDecorationOwner]) {
        return @{ NSBackgroundColorAttributeName: BracketMatchBGColor() };
    }
    if ([owner isEqualToString:UDFoldDecorationOwner]) {
        return FoldAttributes();
    }
    if ([owner isEqualToString:UDMissingNodeDecorationOwner]) {
        return @{
            NSBackgroundColorAttributeName: MissingNodeBGColor(),
            NSForegroundColorAttributeName: [NSColor whiteColor],
        };
    }
    return nil;
}

- (void)_resetPendingDirty {
    _hasPendingDirty   = NO;
    _pendingDirtyStart = 0;
    _pendingDirtyEnd   = 0;
}

@end
