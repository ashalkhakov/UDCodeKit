/*---------------------------------------------------------------------------------------------
 *  UDTextModelTextStorage.m
 *--------------------------------------------------------------------------------------------*/

#import "UDTextModelTextStorage.h"
#import "UDTextModelString.h"
#import <tree_sitter/api.h>

NSString * const UDFindDecorationOwner      = @"find";
NSString * const UDHighlightDecorationOwner = @"highlight";

// ---------------------------------------------------------------------------
// MARK: - UTF-16 read callback (tree-sitter input)
// ---------------------------------------------------------------------------

#define TS_READ_BUFFER_CHARS 1024

typedef struct {
    NSString  *string;
    NSUInteger length;
    unichar    buffer[TS_READ_BUFFER_CHARS];
} TSReadContext;

static const char *tsReadCallback(void *payload, uint32_t byteOffset,
                                   TSPoint position, uint32_t *bytesRead) {
    TSReadContext *ctx = (TSReadContext *)payload;
    NSUInteger charOffset = byteOffset / 2;
    if (charOffset >= ctx->length) { *bytesRead = 0; return NULL; }
    NSUInteger n = MIN(TS_READ_BUFFER_CHARS, ctx->length - charOffset);
    [ctx->string getCharacters:ctx->buffer range:NSMakeRange(charOffset, n)];
    *bytesRead = (uint32_t)(n * sizeof(unichar));
    return (const char *)ctx->buffer;
}

// Tree-sitter uses UTF-16 encoding: each NSString code unit occupies 2 bytes.
// Character index = byte_offset / 2;  byte_offset = character_index * 2.
static inline NSUInteger charIdxFromByte(uint32_t b) { return b / 2; }
static inline uint32_t   byteFromCharIdx(NSUInteger i) { return (uint32_t)(i * 2); }

// ---------------------------------------------------------------------------
// MARK: - Base attributes (font + color applied when no decoration matches)
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
@property (nonatomic, strong) UDTextModel        *textModel;
@property (nonatomic, strong) UDTextModelString  *modelString;  // live-reading string primitive
@property (nonatomic)         BOOL                suppressModelNotification;
// Document length tracked here so we can compute changeInLength in _modelDidChange:.
@property (nonatomic)         NSUInteger          lastKnownLength;

// Cached attribute runs, rebuilt by _rebuildAttributeRuns.
// _attrRunRanges[i] is an NSValue(NSRange); _attrRunAttrs[i] is a NSDictionary.
// Together they form a complete, non-overlapping partition of [0, docLen).
@property (nonatomic, strong) NSArray<NSValue *>      *attrRunRanges;
@property (nonatomic, strong) NSArray<NSDictionary *> *attrRunAttrs;

// tree-sitter state (main thread only)
@property (nonatomic, assign) LanguageFunc   languageFuncInternal;
@property (nonatomic, assign) TSParser      *tsParser;
@property (nonatomic, assign) TSTree        *tsCurrentTree;
@property (nonatomic, assign) TSQuery       *tsQuery;
@property (nonatomic, assign) TSQueryCursor *tsQueryCursor;
@property (nonatomic, copy)   NSString      *tsPreviousString;

// IDs of decorations currently registered under UDHighlightDecorationOwner.
@property (nonatomic, strong) NSArray<NSString *> *highlightDecorationIDs;
@end

@implementation UDTextModelTextStorage

// ---------------------------------------------------------------------------
// MARK: - Init / dealloc
// ---------------------------------------------------------------------------

- (instancetype)initWithText:(NSString *)initialText {
    self = [super init];
    if (!self) return nil;

    _textModel               = [[UDTextModel alloc] initWithText:initialText];
    _modelString             = [[UDTextModelString alloc] initWithTextModel:_textModel];
    _suppressModelNotification = NO;
    _lastKnownLength         = initialText.length;
    _attrRunRanges           = @[];
    _attrRunAttrs            = @[];
    _tsPreviousString        = @"";
    _highlightDecorationIDs  = @[];

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
    [self _tearDownTreeSitter];
}

- (void)_tearDownTreeSitter {
    if (_tsQueryCursor) { ts_query_cursor_delete(_tsQueryCursor); _tsQueryCursor = NULL; }
    if (_tsCurrentTree) { ts_tree_delete(_tsCurrentTree);         _tsCurrentTree = NULL; }
    if (_tsQuery)       { ts_query_delete(_tsQuery);              _tsQuery       = NULL; }
    if (_tsParser)      { ts_parser_delete(_tsParser);            _tsParser      = NULL; }
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

    // Report the full document as replaced so layout managers re-layout.
    [self beginEditing];
    [self edited:(NSTextStorageEditedCharacters | NSTextStorageEditedAttributes)
           range:NSMakeRange(0, oldLen)
 changeInLength:delta];
    [self endEditing];

    // Re-parse and rebuild highlight runs on the next run loop turn.
    dispatch_async(dispatch_get_main_queue(), ^{
        [self _reparseFullString:self->_modelString];
        [self applyDecorationHighlights];
    });
}

// ---------------------------------------------------------------------------
// MARK: - NSTextStorage primitives
// ---------------------------------------------------------------------------

- (NSString *)string {
    // Return the live UDTextModelString — reads directly from the model
    // without materialising a full copy, exactly as UDPieceTreeTextStorage does.
    return _modelString;
}

- (NSDictionary<NSAttributedStringKey, id> *)attributesAtIndex:(NSUInteger)location
                                                effectiveRange:(NSRangePointer)outRange {
    NSUInteger len = _lastKnownLength;
    if (len == 0 || location >= len) {
        if (outRange) *outRange = NSMakeRange(location, 0);
        return BaseAttributes();
    }

    // Binary search over the cached runs.
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

    // Fallback: should not happen when runs cover [0, len).
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
    // All attributes are computed on-the-fly from decorations via
    // attributesAtIndex:effectiveRange:. This method is intentionally a no-op.
}

// ---------------------------------------------------------------------------
// MARK: - processEditing
// ---------------------------------------------------------------------------

- (void)processEditing {
    NSRange   editedRange = self.editedRange;
    NSInteger delta       = self.changeInLength;
    NSTextStorageEditActions mask = self.editedMask;

    [super processEditing];

    if ((mask & NSTextStorageEditedCharacters) && _tsParser) {
        // Snapshot the live string for the parser (single getValue call).
        NSString *snap = [_textModel getValue];
        [self _performIncrementalParseAfterEdit:editedRange
                                 changeInLength:delta
                                  currentString:snap];
        // Schedule attribute rebuild on the next run loop turn so we don't
        // re-enter NSTextStorage editing from within processEditing.
        dispatch_async(dispatch_get_main_queue(), ^{
            [self applyDecorationHighlights];
        });
    }
}

// ---------------------------------------------------------------------------
// MARK: - Public: tree-sitter language setup
// ---------------------------------------------------------------------------

- (void)setLanguageFunc:(nullable LanguageFunc)languageFunc
    withHighlightsQuery:(NSString *)queryText {
    _languageFuncInternal = languageFunc;
    [self _tearDownTreeSitter];
    _tsPreviousString       = @"";
    _highlightDecorationIDs = @[];

    if (!languageFunc) {
        [self applyDecorationHighlights];
        return;
    }

    _tsParser = ts_parser_new();
    const TSLanguage *lang = languageFunc();
    if (lang) ts_parser_set_language(_tsParser, lang);

    if (queryText.length) {
        uint32_t errOffset = 0;
        TSQueryError errType = TSQueryErrorNone;
        const char *utf8 = [queryText cStringUsingEncoding:NSUTF8StringEncoding];
        _tsQuery = ts_query_new(lang, utf8, (uint32_t)strlen(utf8),
                                &errOffset, &errType);
        if (errType != TSQueryErrorNone || !_tsQuery) {
            NSLog(@"[UDTextModelTextStorage] TS query error at offset %u, type %d",
                  errOffset, errType);
            if (_tsQuery) { ts_query_delete(_tsQuery); _tsQuery = NULL; }
        } else {
            _tsQueryCursor = ts_query_cursor_new();
        }
    }

    [self _reparseFullString:[_textModel getValue]];
    [self applyDecorationHighlights];
}

// ---------------------------------------------------------------------------
// MARK: - Public: decoration highlights
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

/// Rebuild _attrRunRanges / _attrRunAttrs from the current set of decorations.
/// Produces a complete, non-overlapping partition of [0, docLen) where each
/// segment carries the merged attributes of all decorations that cover it.
- (void)_rebuildAttributeRuns {
    NSUInteger docLen = _lastKnownLength;
    if (docLen == 0) {
        _attrRunRanges = @[];
        _attrRunAttrs  = @[];
        return;
    }

    NSDictionary *base = BaseAttributes();

    // Collect flat (startOffset, endOffset, attrs, layer) tuples.
    // layer 0 = syntax highlights (foreground), layer 1 = find matches (background, on top).
    NSMutableArray *tuples = [NSMutableArray array];

    if (_theme) {
        for (NSString *did in [_textModel decorationsForOwner:UDHighlightDecorationOwner]) {
            UDRange r = [_textModel rangeForDecoration:did];
            if (r.startLineNumber == 0) continue;
            UDDecorationOptions *opts = [_textModel optionsForDecoration:did];
            if (!opts.className) continue;
            NSDictionary *ta = [_theme styleAttributesForName:opts.className];
            if (!ta) continue;
            NSInteger s = [_textModel getOffsetAt:r.startLineNumber column:r.startColumn];
            NSInteger e = [_textModel getOffsetAt:r.endLineNumber   column:r.endColumn];
            if (s < 0 || e <= s || (NSUInteger)e > docLen) continue;
            [tuples addObject:@{ @"s":@(s), @"e":@(e), @"a":ta, @"l":@0 }];
        }
    }

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

    // Collect all unique boundary offsets.
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

        // Start with base, then merge layer-0 decorations, then layer-1.
        NSMutableDictionary *merged = [NSMutableDictionary dictionaryWithDictionary:base];
        for (NSInteger layer = 0; layer <= 1; layer++) {
            for (NSDictionary *t in tuples) {
                if ([t[@"l"] integerValue] != layer) continue;
                NSUInteger ts = [t[@"s"] unsignedIntegerValue];
                NSUInteger te = [t[@"e"] unsignedIntegerValue];
                if (ts <= segS && te >= segE) {
                    [merged addEntriesFromDictionary:t[@"a"]];
                }
            }
        }
        [rrs addObject:[NSValue valueWithRange:NSMakeRange(segS, segE - segS)]];
        [ras addObject:[merged copy]];
    }

    if (rrs.count == 0) {
        // No decorations: single run covering the whole document.
        [rrs addObject:[NSValue valueWithRange:NSMakeRange(0, docLen)]];
        [ras addObject:base];
    }

    _attrRunRanges = [rrs copy];
    _attrRunAttrs  = [ras copy];
}

// ---------------------------------------------------------------------------
// MARK: - Tree-sitter parsing internals
// ---------------------------------------------------------------------------

- (void)_performIncrementalParseAfterEdit:(NSRange)editedRange
                            changeInLength:(NSInteger)delta
                             currentString:(NSString *)s {
    if (!_tsParser) return;

    TSTree *oldTree = _tsCurrentTree;
    if (oldTree && editedRange.location != NSNotFound) {
        // editedRange covers the new text (length = str.length); delta = str.length - safe.length.
        // So oldLen = safe.length = editedRange.length - delta, which is always >= 0.
        NSInteger signedOldLen = (NSInteger)editedRange.length - delta;
        NSUInteger oldLen = (signedOldLen > 0) ? (NSUInteger)signedOldLen : 0;
        uint32_t sb  = byteFromCharIdx(editedRange.location);
        uint32_t oeb = byteFromCharIdx(editedRange.location + oldLen);
        uint32_t neb = byteFromCharIdx(NSMaxRange(editedRange));
        TSInputEdit ie = { sb, oeb, neb, {0,0}, {0,0}, {0,0} };
        ts_tree_edit(oldTree, &ie);
    }
    [self _runParseWithString:s oldTree:oldTree];
}

- (void)_reparseFullString:(NSString *)s {
    if (!_tsParser) return;
    if (_tsCurrentTree) { ts_tree_delete(_tsCurrentTree); _tsCurrentTree = NULL; }
    _tsPreviousString = @"";
    [self _runParseWithString:s oldTree:NULL];
}

- (void)_runParseWithString:(NSString *)s oldTree:(TSTree *)oldTree {
    if (!s) s = @"";
    if ([s isEqualToString:_tsPreviousString] && _tsCurrentTree) return;

    TSReadContext ctx = { .string = s, .length = s.length };
    TSInput input = { &ctx, tsReadCallback, TSInputEncodingUTF16 };
    TSTree *newTree = ts_parser_parse(_tsParser, oldTree, input);
    if (!newTree) return;

    if (oldTree) {
        uint32_t count = 0;
        TSRange *ranges = ts_tree_get_changed_ranges(oldTree, newTree, &count);
        if (count > 0) {
            NSMutableArray<UDModelDeltaDecoration *> *newDecors = [NSMutableArray array];
            for (uint32_t i = 0; i < count; i++) {
                [self _collectDecorationsForRange:ranges[i] tree:newTree into:newDecors];
            }
            [self _replaceHighlightDecorationsInRanges:ranges
                                                 count:count
                                           withNewOnes:newDecors];
        }
        free(ranges);
        ts_tree_delete(oldTree);
    } else {
        NSMutableArray<UDModelDeltaDecoration *> *all = [NSMutableArray array];
        TSNode root = ts_tree_root_node(newTree);
        TSRange full = { ts_node_start_byte(root), ts_node_end_byte(root),
                         ts_node_start_point(root), ts_node_end_point(root) };
        [self _collectDecorationsForRange:full tree:newTree into:all];
        _highlightDecorationIDs =
            [_textModel deltaDecorations:_highlightDecorationIDs
                          newDecorations:all
                                   owner:UDHighlightDecorationOwner];
    }

    _tsCurrentTree    = newTree;
    _tsPreviousString = [s copy];
}

- (void)_collectDecorationsForRange:(TSRange)r
                               tree:(TSTree *)tree
                               into:(NSMutableArray<UDModelDeltaDecoration *> *)out {
    TSNode root = ts_tree_root_node(tree);
    if (_tsQuery && _tsQueryCursor) {
        ts_query_cursor_exec(_tsQueryCursor, _tsQuery, root);
        ts_query_cursor_set_byte_range(_tsQueryCursor, r.start_byte, r.end_byte);
        TSQueryMatch match;
        while (ts_query_cursor_next_match(_tsQueryCursor, &match)) {
            for (uint32_t i = 0; i < match.capture_count; i++) {
                TSQueryCapture cap = match.captures[i];
                uint32_t nb = ts_node_start_byte(cap.node);
                uint32_t ne = ts_node_end_byte(cap.node);
                if (ne <= r.start_byte || nb >= r.end_byte) continue;
                uint32_t nl = 0;
                const char *cn = ts_query_capture_name_for_id(_tsQuery, cap.index, &nl);
                NSString *name = [[NSString alloc] initWithBytes:cn length:nl
                                                        encoding:NSUTF8StringEncoding];
                UDModelDeltaDecoration *d = [self _makeDecorationByte:nb toByte:ne name:name];
                if (d) [out addObject:d];
            }
        }
    } else {
        [self _collectNodeDecorations:root inRange:r into:out];
    }
}

- (void)_collectNodeDecorations:(TSNode)node
                        inRange:(TSRange)r
                           into:(NSMutableArray<UDModelDeltaDecoration *> *)out {
    uint32_t nb = ts_node_start_byte(node), ne = ts_node_end_byte(node);
    if (ne <= r.start_byte || nb >= r.end_byte) return;
    NSString *type = [NSString stringWithUTF8String:ts_node_type(node)];
    UDModelDeltaDecoration *d = [self _makeDecorationByte:nb toByte:ne name:type];
    if (d) [out addObject:d];
    uint32_t cc = ts_node_child_count(node);
    for (uint32_t i = 0; i < cc; i++) {
        [self _collectNodeDecorations:ts_node_child(node, i) inRange:r into:out];
    }
}

- (nullable UDModelDeltaDecoration *)_makeDecorationByte:(uint32_t)startByte
                                                   toByte:(uint32_t)endByte
                                                     name:(NSString *)name {
    NSUInteger sc = charIdxFromByte(startByte), ec = charIdxFromByte(endByte);
    NSUInteger docLen = _lastKnownLength;
    if (sc >= ec || ec > docLen) return nil;
    UDPosition sp = [_textModel getPositionAt:(NSInteger)sc];
    UDPosition ep = [_textModel getPositionAt:(NSInteger)ec];
    UDRange ur = PTRangeMake(sp.line, sp.column, ep.line, ep.column);
    UDDecorationOptions *opts = [[UDDecorationOptions alloc] initWithClassName:name
                                                                      userInfo:nil];
    UDModelDeltaDecoration *d = [[UDModelDeltaDecoration alloc] initWithRange:ur options:opts];
    d.stickiness = UDTrackedRangeNeverGrowsWhenTypingAtEdges;
    return d;
}

- (void)_replaceHighlightDecorationsInRanges:(TSRange *)changedRanges
                                        count:(uint32_t)count
                                  withNewOnes:(NSArray<UDModelDeltaDecoration *> *)newDecors {
    if (count == 0) return;
    NSUInteger docLen = _lastKnownLength;

    uint32_t uStart = changedRanges[0].start_byte, uEnd = changedRanges[0].end_byte;
    for (uint32_t i = 1; i < count; i++) {
        if (changedRanges[i].start_byte < uStart) uStart = changedRanges[i].start_byte;
        if (changedRanges[i].end_byte   > uEnd)   uEnd   = changedRanges[i].end_byte;
    }
    NSUInteger sc = charIdxFromByte(uStart), ec = MIN(charIdxFromByte(uEnd), docLen);
    if (sc > docLen) return;

    UDPosition sp = [_textModel getPositionAt:(NSInteger)sc];
    UDPosition ep = [_textModel getPositionAt:(NSInteger)ec];
    UDRange cmr = PTRangeMake(sp.line, sp.column, ep.line, ep.column);

    NSSet *inRangeSet =
        [NSSet setWithArray:[_textModel decorationsInRange:cmr]];
    NSMutableArray *toRemove = [NSMutableArray array];
    NSMutableArray *toKeep   = [NSMutableArray array];
    for (NSString *did in _highlightDecorationIDs) {
        if ([inRangeSet containsObject:did]) {
            [toRemove addObject:did];
        } else {
            [toKeep addObject:did];
        }
    }

    NSArray<NSString *> *added =
        [_textModel deltaDecorations:toRemove
                      newDecorations:newDecors
                               owner:UDHighlightDecorationOwner];
    _highlightDecorationIDs = [toKeep arrayByAddingObjectsFromArray:added];
}

@end
