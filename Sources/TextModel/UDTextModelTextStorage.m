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

- (instancetype)initWithText:(NSString *)initialText {
    self = [super init];
    if (!self) return nil;

    _textModel   = [[UDTextModel alloc] initWithText:initialText];
    _modelString = [[UDTextModelString alloc] initWithTextModel:_textModel];
    _highlighter = [[UDTreeSitterHighlighter alloc] initWithTextModel:_textModel];
    _syntaxHighlighter = [[UDSyntaxHighlighter alloc] initWithTextStorage:self
                                                               highlighter:_highlighter];
    _lastKnownLength = initialText.length;
    _hasPendingDirty = NO;
    _pendingDirtyStart = 0;
    _pendingDirtyEnd   = 0;

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

    NSArray<UDIntervalNode *> *covering =
        [_textModel decorationNodesInOffsetRange:(NSInteger)location
                                             end:(NSInteger)location + 1];

    // Syntax highlight (layer 0) is the one case that needs the theme,
    // so we handle it here and pass nil from its registered block.
    NSMutableArray<UDIntervalNode *> *nonTheme = [NSMutableArray array];
    NSMutableDictionary *merged =
        [NSMutableDictionary dictionaryWithDictionary:BaseAttributes()];

    for (UDIntervalNode *node in covering) {
        if ([node.owner isEqualToString:UDHighlightDecorationOwner]) {
            if (_theme && node.options.className) {
                NSDictionary *themeAttrs =
                    [_theme styleAttributesForName:node.options.className];
                if (themeAttrs) [merged addEntriesFromDictionary:themeAttrs];
            }
        } else {
            [nonTheme addObject:node];
        }
    }

    // All other layers go through the registry.
    NSDictionary *rest =
        [[UDDecorationLayerRegistry shared]
            mergedAttributesForNodes:nonTheme
                     baseAttributes:@{}];
    [merged addEntriesFromDictionary:rest];

    if (outRange) {
        NSUInteger effStart = 0, effEnd = docLen;
        for (UDIntervalNode *node in covering) {
            effStart = MAX(effStart, (NSUInteger)MAX(0LL, node.start));
            effEnd   = MIN(effEnd,   (NSUInteger)MAX(0LL, node.end));
        }
        if (effEnd > location + 1) {
            NSArray<UDIntervalNode *> *right =
                [_textModel decorationNodesInOffsetRange:(NSInteger)location + 1
                                                     end:(NSInteger)effEnd];
            for (UDIntervalNode *n in right) {
                if (n.start > (NSInteger)location) {
                    NSUInteger ns = (NSUInteger)MAX(0LL, n.start);
                    if (ns < effEnd) effEnd = ns;
                }
            }
        }
        if (effStart < location) {
            NSArray<UDIntervalNode *> *left =
                [_textModel decorationNodesInOffsetRange:(NSInteger)effStart
                                                     end:(NSInteger)location + 1];
            for (UDIntervalNode *n in left) {
                if (n.end > (NSInteger)effStart && n.end <= (NSInteger)location) {
                    NSUInteger ne = (NSUInteger)MAX(0LL, n.end);
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

@end
