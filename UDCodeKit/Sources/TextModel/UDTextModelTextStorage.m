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
    static NSDictionary *attributes;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSFont *font = [NSFont userFixedPitchFontOfSize:13.0]
                    ?: [NSFont systemFontOfSize:13.0];
        attributes = @{
            NSFontAttributeName:            font,
            NSForegroundColorAttributeName: [NSColor labelColor],
        };
    });
    return attributes;
}

// ---------------------------------------------------------------------------
#pragma mark - Attribute runs, a window at a time
// ---------------------------------------------------------------------------

/// The attribute runs of one window of the text — [start, end), aligned to
/// UDAttributeWindowLength — built from the decorations overlapping it.
static const NSUInteger UDAttributeWindowLength = 4096;
/// How many windows are kept: what a screenful or two of layout reads.
static const NSUInteger UDAttributeWindowsKept = 4;

@interface UDAttributeWindow : NSObject {
@public
    NSUInteger start, end;
    NSData *runs;                    // NSRange[], sorted, covering [start, end)
    NSArray<NSDictionary *> *attrs;  // attrs[i] for runs[i]
}
@end
@implementation UDAttributeWindow
@end

static int UDCompareOffsets(const void *x, const void *y) {
    NSInteger a = *(const NSInteger *)x, b = *(const NSInteger *)y;
    return a < b ? -1 : a > b;
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
// The model's alternativeVersionId as of the last change this storage has
// told its layout managers of. Another observer of the same change may ask
// for highlights first (notification order is AppKit's or GNUstep's to
// choose), while the string already reads the new text but layout has not
// heard of it; such a request waits until the storage catches up.
@property (nonatomic)         NSInteger                seenVersionId;
@property (nonatomic)         BOOL                     highlightsDeferred;
// Attribute runs, built a window at a time as layout asks for them (most
// recently used first); all dropped when the text or a decoration changes.
// Layout reads what it lays out, so it costs what is on screen.
@property (nonatomic, strong) NSMutableArray<UDAttributeWindow *> *attrWindows;
@property (nonatomic)         BOOL                                 attrCacheDirty;
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
    _cursorsController = [[UDCursorsController alloc] initWithModel:textModel];
    _modelString = [[UDTextModelString alloc] initWithTextModel:_textModel];
    _highlighter = [[UDTreeSitterHighlighter alloc] initWithTextModel:_textModel];
    _syntaxHighlighter = [[UDSyntaxHighlighter alloc] initWithTextStorage:self
                                                               highlighter:_highlighter];
    _lastKnownLength = (NSUInteger)[_textModel getLength];
    _seenVersionId   = _textModel.alternativeVersionId;
    _hasPendingDirty = NO;
    _pendingDirtyStart = 0;
    _pendingDirtyEnd   = 0;
    _attrCacheDirty    = YES;
    _attrWindows       = [NSMutableArray array];

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
#pragma mark - UDTextModelDidChangeNotification (undo, redo, edits made on the model)
// ---------------------------------------------------------------------------

- (void)_modelDidChange:(NSNotification *)note {
    if (_suppressModelNotification) return;

    NSArray<UDTextModelContentChange *> *changes = note.userInfo[UDTextModelChangesKey];
    _lastKnownLength = (NSUInteger)[_textModel getLength];
    _seenVersionId   = _textModel.alternativeVersionId;
    _attrCacheDirty  = YES;

    // Each change, as the model made it: the parse tree learns of it, and the
    // layout managers of the range it replaced. The changes run end to start,
    // so each one's offsets hold as the ones before it left the text; the
    // last is the first in the document, and the cursor goes after its text.
    NSUInteger postEditCursorOffset = NSNotFound;
    [self beginEditing];
    for (UDTextModelContentChange *change in changes) {
        NSUInteger start  = (NSUInteger)change.rangeOffset;
        NSUInteger oldEnd = start + (NSUInteger)change.rangeLength;
        NSUInteger newEnd = start + change.text.length;
        if (_highlighter.isActive) {
            UDRange r = change.range;
            [_highlighter applyEditAtOffset:start
                                     oldEnd:oldEnd
                                     newEnd:newEnd
                              startPosition:(UDPosition){ r.startLineNumber, r.startColumn }
                             oldEndPosition:(UDPosition){ r.endLineNumber, r.endColumn }
                             newEndPosition:[change endPositionOfText]];
        }
        [self edited:NSTextStorageEditedCharacters
               range:NSMakeRange(start, (NSUInteger)change.rangeLength)
      changeInLength:(NSInteger)change.text.length - change.rangeLength];
        postEditCursorOffset = newEnd;
    }
    [self endEditing];

    // After endEditing, NSLayoutManager has moved all text views' cursors to
    // the end of the invalidated range. Override that with the correct position.
    if (postEditCursorOffset != NSNotFound) {
        NSUInteger clampedOffset = MIN(postEditCursorOffset, _lastKnownLength);
        NSRange cursorRange = NSMakeRange(clampedOffset, 0);
        for (NSLayoutManager *lm in self.layoutManagers) {
            for (NSTextContainer *tc in lm.textContainers) {
                NSTextView *tv = tc.textView;
                if (tv) {
                    // stillSelecting:YES prevents _syncSelectionsToController
                    // from firing mid-update; the controller is synced below.
                    [tv setSelectedRanges:@[ [NSValue valueWithRange:cursorRange] ]
                                 affinity:NSSelectionAffinityDownstream
                           stillSelecting:YES];
                    // Now sync the controller to match.
                    if ([tv respondsToSelector:@selector(syncCursorControllerFromSelection)]) {
                        [tv setSelectedRanges:@[ [NSValue valueWithRange:cursorRange] ]
                                     affinity:NSSelectionAffinityDownstream
                               stillSelecting:NO];
                    }
                }
            }
        }
    }
    [self _applyDeferredHighlights];
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

    if (_attrCacheDirty) {
        [_attrWindows removeAllObjects];
        _attrCacheDirty = NO;
    }
    UDAttributeWindow *window = nil;
    for (NSUInteger i = 0; i < _attrWindows.count; i++) {
        UDAttributeWindow *w = _attrWindows[i];
        if (location >= w->start && location < w->end) {
            window = w;
            if (i > 0) {
                [_attrWindows removeObjectAtIndex:i];
                [_attrWindows insertObject:w atIndex:0];
            }
            break;
        }
    }
    if (!window) {
        NSUInteger start = location - location % UDAttributeWindowLength;
        window = [self _attributeWindowFrom:start to:MIN(start + UDAttributeWindowLength, docLen)];
        [_attrWindows insertObject:window atIndex:0];
        if (_attrWindows.count > UDAttributeWindowsKept) [_attrWindows removeLastObject];
    }

    // Binary search of the window's runs. A run is cut at the window's
    // edges; the effective range may be shorter than the attributes' extent.
    const NSRange *runs  = (const NSRange *)window->runs.bytes;
    NSUInteger     count = window->runs.length / sizeof(NSRange);
    NSUInteger lo = 0, hi = count;
    while (lo < hi) {
        NSUInteger mid = lo + (hi - lo) / 2;
        NSRange r = runs[mid];
        if (NSMaxRange(r) <= location) {
            lo = mid + 1;
        } else if (r.location > location) {
            hi = mid;
        } else {
            if (outRange) *outRange = r;
            return window->attrs[mid];
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

    if (_highlighter.isActive) {
        NSUInteger newEnd = safe.location + str.length;
        [_highlighter applyEditAtOffset:safe.location
                                 oldEnd:NSMaxRange(safe)
                                 newEnd:newEnd
                          startPosition:sp
                         oldEndPosition:ep
                         newEndPosition:[_textModel getPositionAt:(NSInteger)newEnd]];
    }

    NSInteger delta  = (NSInteger)str.length - (NSInteger)safe.length;
    _lastKnownLength = (NSUInteger)((NSInteger)docLen + delta);
    _seenVersionId   = _textModel.alternativeVersionId;
    _attrCacheDirty  = YES;

    [self edited:NSTextStorageEditedCharacters range:safe changeInLength:delta];
    [self _applyDeferredHighlights];
}

- (void)setAttributes:(nullable NSDictionary<NSAttributedStringKey, id> *)attrs
                range:(NSRange)range {
    // Attributes derive entirely from decorations; intentional no-op.
}

// Fixing attributes sets attributes, which do not change here — and AppKit's
// glyph-info fix asks for the longest range without NSGlyphInfo, which is
// the whole text: every edit would read every attribute run.
- (void)fixAttributesInRange:(NSRange)range {
}

// ---------------------------------------------------------------------------
#pragma mark - processEditing
// ---------------------------------------------------------------------------

- (void)processEditing {
    NSUInteger mask = self.editedMask;

    [super processEditing];

    if ((mask & NSTextStorageEditedCharacters) && _highlighter.isActive) {
        [_highlighter reparseAfterEdits];
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
        [_highlighter reparseFromModel];
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
    if (_textModel.alternativeVersionId != _seenVersionId) {
        _highlightsDeferred = YES;
        return;
    }
    NSUInteger docLen = _lastKnownLength;
    if (docLen == 0) { [self _resetPendingDirty]; return; }
    if (!_hasPendingDirty) return;

    NSUInteger ds = (NSUInteger)MAX(0LL, _pendingDirtyStart);
    NSUInteger de = (NSUInteger)MIN((NSInteger)docLen, _pendingDirtyEnd);
    [self _resetPendingDirty];
    if (de <= ds) return;

    // Save selectedRanges across all attached layout managers' text views
    // before posting the attributes-only edit notification. NSTextView resets
    // its cursor to {0,0} when it receives a full-document attribute change,
    // so we must restore it afterwards.
    NSMutableArray<NSMutableArray<NSValue *> *> *savedRanges = [NSMutableArray array];
    NSMutableArray<NSTextView *> *textViews = [NSMutableArray array];
    for (NSLayoutManager *lm in self.layoutManagers) {
        for (NSTextContainer *tc in lm.textContainers) {
            NSTextView *tv = tc.textView;
            if (tv) {
                [textViews addObject:tv];
                [savedRanges addObject:[tv.selectedRanges mutableCopy]];
            }
        }
    }

    [self beginEditing];
    [self edited:NSTextStorageEditedAttributes
           range:NSMakeRange(ds, de - ds)
 changeInLength:0];
    [self endEditing];

    // Restore selections without triggering _syncSelectionsToController
    // (stillSelecting:YES suppresses the feedback loop into the cursor controller).
    for (NSUInteger i = 0; i < textViews.count; i++) {
        [textViews[i] setSelectedRanges:savedRanges[i]
                               affinity:NSSelectionAffinityDownstream
                         stillSelecting:YES];
    }
}

- (void)applyDecorationHighlightsInRange:(NSRange)range {
    if (_textModel.alternativeVersionId != _seenVersionId) {
        // In the model's new offsets, as the pending range is.
        if (range.length > 0) {
            NSInteger s = (NSInteger)range.location, e = (NSInteger)NSMaxRange(range);
            _pendingDirtyStart = _hasPendingDirty ? MIN(_pendingDirtyStart, s) : s;
            _pendingDirtyEnd   = _hasPendingDirty ? MAX(_pendingDirtyEnd, e) : e;
            _hasPendingDirty   = YES;
        }
        _highlightsDeferred = YES;
        return;
    }
    NSUInteger docLen = _lastKnownLength;
    if (docLen == 0 || range.length == 0) return;
    NSUInteger loc = MIN(range.location, docLen);
    NSUInteger len = MIN(range.length, docLen - loc);
    if (len == 0) return;

    NSMutableArray<NSMutableArray<NSValue *> *> *savedRanges = [NSMutableArray array];
    NSMutableArray<NSTextView *> *textViews = [NSMutableArray array];
    for (NSLayoutManager *lm in self.layoutManagers) {
        for (NSTextContainer *tc in lm.textContainers) {
            NSTextView *tv = tc.textView;
            if (tv) {
                [textViews addObject:tv];
                [savedRanges addObject:[tv.selectedRanges mutableCopy]];
            }
        }
    }

    [self beginEditing];
    [self edited:NSTextStorageEditedAttributes
           range:NSMakeRange(loc, len)
 changeInLength:0];
    [self endEditing];

    for (NSUInteger i = 0; i < textViews.count; i++) {
        [textViews[i] setSelectedRanges:savedRanges[i]
                               affinity:NSSelectionAffinityDownstream
                         stillSelecting:YES];
    }
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

/// A highlight request made while the storage was behind the model, now that
/// it has caught up.
- (void)_applyDeferredHighlights {
    if (!_highlightsDeferred) return;
    _highlightsDeferred = NO;
    [self applyDecorationHighlights];
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

/// The attribute runs of [start, end), from the decorations overlapping it:
/// their starts and ends inside the window cut it into segments, and each
/// segment gets the merged attributes of the decorations covering it.
/// Costs the decorations overlapping the window, plus a logarithmic lookup.
- (UDAttributeWindow *)_attributeWindowFrom:(NSUInteger)start to:(NSUInteger)end {
    UDAttributeWindow *window = [[UDAttributeWindow alloc] init];
    window->start = start;
    window->end   = end;

    // Sorted by start.
    NSArray<UDIntervalNode *> *nodes =
        [_textModel decorationNodesInOffsetRange:(NSInteger)start end:(NSInteger)end];

    NSUInteger capacity = nodes.count * 2 + 2, count = 0;
    NSInteger *bounds = malloc(capacity * sizeof(NSInteger));
    bounds[count++] = (NSInteger)start;
    bounds[count++] = (NSInteger)end;
    for (UDIntervalNode *n in nodes) {
        if (n.start > (NSInteger)start && n.start < (NSInteger)end) bounds[count++] = n.start;
        if (n.end   > (NSInteger)start && n.end   < (NSInteger)end) bounds[count++] = n.end;
    }
    qsort(bounds, count, sizeof(NSInteger), UDCompareOffsets);

    NSMutableData *runs = [NSMutableData dataWithCapacity:count * sizeof(NSRange)];
    NSMutableArray<NSDictionary *> *attrs = [NSMutableArray arrayWithCapacity:count];
    NSMutableArray<UDIntervalNode *> *active = [NSMutableArray array];
    NSUInteger next = 0;
    for (NSUInteger i = 0; i + 1 < count; i++) {
        NSInteger segStart = bounds[i], segEnd = bounds[i + 1];
        if (segEnd <= segStart) continue;     // a repeated boundary
        for (NSUInteger a = active.count; a > 0; a--) {
            if (active[a - 1].end <= segStart) [active removeObjectAtIndex:a - 1];
        }
        while (next < nodes.count && nodes[next].start <= segStart) {
            UDIntervalNode *n = nodes[next++];
            if (n.end > segStart) [active addObject:n];
        }
        NSRange r = NSMakeRange((NSUInteger)segStart, (NSUInteger)(segEnd - segStart));
        [runs appendBytes:&r length:sizeof(NSRange)];
        [attrs addObject:active.count ? [self _mergedAttrsForCovering:active] : BaseAttributes()];
    }
    free(bounds);

    window->runs  = runs;
    window->attrs = attrs;
    return window;
}

@end
