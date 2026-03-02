/*---------------------------------------------------------------------------------------------
 *  UDTextModelTextStorage.m
 *--------------------------------------------------------------------------------------------*/

#import "UDTextModelTextStorage.h"
#import "UDTextModelString.h"
#import "UDTreeSitterHighlighter.h"

NSString * const UDFindDecorationOwner = @"find";

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
// MARK: - Private interface
// ---------------------------------------------------------------------------

@interface UDTextModelTextStorage ()
@property (nonatomic, strong) UDTextModel              *textModel;
@property (nonatomic, strong) UDTextModelString        *modelString;
@property (nonatomic, strong) UDTreeSitterHighlighter  *highlighter;
@property (nonatomic)         BOOL                      suppressModelNotification;
@property (nonatomic)         NSUInteger                lastKnownLength;

// Cached attribute run partition: parallel arrays covering [0, docLen).
@property (nonatomic, strong) NSArray<NSValue *>      *attrRunRanges;
@property (nonatomic, strong) NSArray<NSDictionary *> *attrRunAttrs;
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
    _attrRunRanges          = @[];
    _attrRunAttrs           = @[];

    [self _rebuildAttributeRuns];

    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(_modelDidChange:)
               name:UDTextModelDidChangeNotification
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

- (NSDictionary<NSAttributedStringKey, id> *)attributesAtIndex:(NSUInteger)location
                                                effectiveRange:(NSRangePointer)outRange {
    NSUInteger len = _lastKnownLength;
    if (len == 0 || location >= len) {
        if (outRange) *outRange = NSMakeRange(location, 0);
        return BaseAttributes();
    }

    NSUInteger lo = 0, hi = _attrRunRanges.count;
    while (lo < hi) {
        NSUInteger mid = (lo + hi) / 2;
        NSRange r = [_attrRunRanges[mid] rangeValue];
        if (location < r.location) {
            hi = mid;
        } else if (location >= NSMaxRange(r)) {
            lo = mid + 1;
        } else {
            if (outRange) *outRange = r;
            return _attrRunAttrs[mid];
        }
    }

    if (outRange) *outRange = NSMakeRange(location, len - location);
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
// MARK: - Decoration highlights
// ---------------------------------------------------------------------------

- (void)applyDecorationHighlights {
    [self _rebuildAttributeRuns];

    NSUInteger len = _lastKnownLength;
    if (len == 0) return;

    [self beginEditing];
    [self edited:NSTextStorageEditedAttributes
           range:NSMakeRange(0, len)
 changeInLength:0];
    [self endEditing];
}

// ---------------------------------------------------------------------------
// MARK: - Attribute run cache
// ---------------------------------------------------------------------------

- (void)_rebuildAttributeRuns {
    NSUInteger docLen = _lastKnownLength;
    if (docLen == 0) {
        _attrRunRanges = @[];
        _attrRunAttrs  = @[];
        return;
    }

    NSDictionary *base = BaseAttributes();
    NSMutableArray *tuples = [NSMutableArray array];

    // Layer 0: syntax highlights (foreground) from the highlighter's theme.
    TreeSitterTheme *theme = _highlighter.theme;
    if (theme) {
        for (NSString *did in [_textModel decorationsForOwner:UDHighlightDecorationOwner]) {
            UDRange r = [_textModel rangeForDecoration:did];
            if (r.startLineNumber == 0) continue;
            UDDecorationOptions *opts = [_textModel optionsForDecoration:did];
            if (!opts.className) continue;
            NSDictionary *ta = [theme styleAttributesForName:opts.className];
            if (!ta) continue;
            NSInteger s = [_textModel getOffsetAt:r.startLineNumber column:r.startColumn];
            NSInteger e = [_textModel getOffsetAt:r.endLineNumber   column:r.endColumn];
            if (s < 0 || e <= s || (NSUInteger)e > docLen) continue;
            [tuples addObject:@{ @"s":@(s), @"e":@(e), @"a":ta, @"l":@0 }];
        }
    }

    // Layer 1: find-match highlights (yellow background).
    NSColor *findBG = [NSColor systemYellowColor];
    for (NSString *did in [_textModel decorationsForOwner:UDFindDecorationOwner]) {
        UDRange r = [_textModel rangeForDecoration:did];
        if (r.startLineNumber == 0) continue;
        NSInteger s = [_textModel getOffsetAt:r.startLineNumber column:r.startColumn];
        NSInteger e = [_textModel getOffsetAt:r.endLineNumber   column:r.endColumn];
        if (s < 0 || e <= s || (NSUInteger)e > docLen) continue;
        [tuples addObject:@{ @"s":@(s), @"e":@(e),
                             @"a":@{ NSBackgroundColorAttributeName: findBG },
                             @"l":@1 }];
    }

    // Collect boundary offsets and build the partition.
    NSMutableSet<NSNumber *> *boundSet = [NSMutableSet set];
    [boundSet addObject:@0];
    [boundSet addObject:@(docLen)];
    for (NSDictionary *t in tuples) {
        [boundSet addObject:t[@"s"]];
        [boundSet addObject:t[@"e"]];
    }
    NSArray<NSNumber *> *bounds =
        [[boundSet allObjects] sortedArrayUsingSelector:@selector(compare:)];

    NSMutableArray<NSValue *>      *rrs = [NSMutableArray array];
    NSMutableArray<NSDictionary *> *ras = [NSMutableArray array];

    for (NSUInteger i = 0; i + 1 < bounds.count; i++) {
        NSUInteger segS = [bounds[i]     unsignedIntegerValue];
        NSUInteger segE = [bounds[i + 1] unsignedIntegerValue];
        if (segS >= segE) continue;

        NSMutableDictionary *merged = [NSMutableDictionary dictionaryWithDictionary:base];
        for (NSInteger layer = 0; layer <= 1; layer++) {
            for (NSDictionary *t in tuples) {
                if ([t[@"l"] integerValue] != layer) continue;
                NSUInteger ts_ = [t[@"s"] unsignedIntegerValue];
                NSUInteger te_ = [t[@"e"] unsignedIntegerValue];
                if (ts_ <= segS && te_ >= segE) {
                    [merged addEntriesFromDictionary:t[@"a"]];
                }
            }
        }
        [rrs addObject:[NSValue valueWithRange:NSMakeRange(segS, segE - segS)]];
        [ras addObject:[merged copy]];
    }

    if (rrs.count == 0) {
        [rrs addObject:[NSValue valueWithRange:NSMakeRange(0, docLen)]];
        [ras addObject:base];
    }

    _attrRunRanges = [rrs copy];
    _attrRunAttrs  = [ras copy];
}

@end
