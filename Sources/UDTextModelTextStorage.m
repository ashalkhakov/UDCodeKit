/*---------------------------------------------------------------------------------------------
 *  UDTextModelTextStorage.m
 *--------------------------------------------------------------------------------------------*/

#import "UDTextModelTextStorage.h"
#import <tree_sitter/api.h>

NSString * const UDFindDecorationOwner      = @"find";
NSString * const UDHighlightDecorationOwner = @"highlight";

// ---------------------------------------------------------------------------
// MARK: - UTF-16 read callback (tree-sitter input)
// ---------------------------------------------------------------------------

#define TS_READ_BUFFER_CHARS 1024

typedef struct {
    NSString     *string;
    NSUInteger    length;
    unichar       buffer[TS_READ_BUFFER_CHARS];
} TSReadContext;

static const char *tsReadCallback(void *payload, uint32_t byteOffset,
                                   TSPoint position, uint32_t *bytesRead) {
    TSReadContext *ctx = (TSReadContext *)payload;
    NSUInteger charOffset = byteOffset / 2;
    if (charOffset >= ctx->length) { *bytesRead = 0; return NULL; }
    NSUInteger charsToRead = MIN(TS_READ_BUFFER_CHARS, ctx->length - charOffset);
    [ctx->string getCharacters:ctx->buffer range:NSMakeRange(charOffset, charsToRead)];
    *bytesRead = (uint32_t)(charsToRead * sizeof(unichar));
    return (const char *)ctx->buffer;
}

// byte <-> NSString character-index helpers (tree-sitter speaks UTF-16)
static inline NSUInteger charIdxFromByte(uint32_t b) { return b / 2; }
static inline uint32_t   byteFromCharIdx(NSUInteger i) { return (uint32_t)(i * 2); }

// ---------------------------------------------------------------------------
// MARK: - Default text attributes
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
@property (nonatomic, strong) NSMutableAttributedString *attrStorage;
@property (nonatomic, strong) UDTextModel               *textModel;
@property (nonatomic)         BOOL                       suppressModelNotification;

// tree-sitter state (accessed on the main thread)
@property (nonatomic, assign) LanguageFunc   languageFuncInternal;
@property (nonatomic, assign) TSParser      *tsParser;
@property (nonatomic, assign) TSTree        *tsCurrentTree;
@property (nonatomic, assign) TSQuery       *tsQuery;
@property (nonatomic, assign) TSQueryCursor *tsQueryCursor;
@property (nonatomic, copy)   NSString      *tsPreviousString;

// current 'highlight' decoration IDs (replaced on every parse)
@property (nonatomic, strong) NSArray<NSString *> *highlightDecorationIDs;
@end

@implementation UDTextModelTextStorage

// ---------------------------------------------------------------------------
// MARK: - Init / dealloc
// ---------------------------------------------------------------------------

- (instancetype)initWithText:(NSString *)initialText {
    self = [super init];
    if (!self) return nil;

    _textModel              = [[UDTextModel alloc] initWithText:initialText];
    _suppressModelNotification = NO;
    _attrStorage = [[NSMutableAttributedString alloc]
                        initWithString:initialText
                            attributes:BaseAttributes()];
    _tsPreviousString        = @"";
    _highlightDecorationIDs  = @[];

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

    NSString *newText = [_textModel getValue];
    NSString *oldText = [_attrStorage string];
    if ([newText isEqualToString:oldText]) return;

    NSInteger delta = (NSInteger)newText.length - (NSInteger)oldText.length;

    [self beginEditing];
    [_attrStorage replaceCharactersInRange:NSMakeRange(0, oldText.length) withString:newText];
    if (newText.length > 0) {
        [_attrStorage setAttributes:BaseAttributes() range:NSMakeRange(0, newText.length)];
    }
    [self edited:NSTextStorageEditedCharacters | NSTextStorageEditedAttributes
           range:NSMakeRange(0, newText.length)
 changeInLength:delta];
    [self endEditing];

    dispatch_async(dispatch_get_main_queue(), ^{
        [self _reparseFullString:newText];
        [self applyDecorationHighlights];
    });
}

// ---------------------------------------------------------------------------
// MARK: - NSTextStorage primitives
// ---------------------------------------------------------------------------

- (NSString *)string {
    return [_attrStorage string];
}

- (NSDictionary<NSAttributedStringKey, id> *)attributesAtIndex:(NSUInteger)location
                                                effectiveRange:(NSRangePointer)effectiveRange {
    NSUInteger len = _attrStorage.length;
    if (len == 0 || location >= len) {
        if (effectiveRange) { *effectiveRange = NSMakeRange(NSNotFound, 0); }
        return @{};
    }
    return [_attrStorage attributesAtIndex:location effectiveRange:effectiveRange];
}

- (void)replaceCharactersInRange:(NSRange)range withString:(NSString *)str {
    if (!str) str = @"";

    NSUInteger docLen   = (NSUInteger)[_textModel getLength];
    NSUInteger clampLoc = MIN(range.location, docLen);
    NSUInteger clampEnd = MIN(range.location + range.length, docLen);
    NSRange    safe     = NSMakeRange(clampLoc, clampEnd - clampLoc);

    [self beginEditing];

    UDPosition sp = [_textModel getPositionAt:(NSInteger)safe.location];
    UDPosition ep = [_textModel getPositionAt:(NSInteger)(safe.location + safe.length)];
    UDRange    mr = PTRangeMake(sp.line, sp.column, ep.line, ep.column);
    UDTextModelEdit *edit = [[UDTextModelEdit alloc] initWithRange:mr text:str];

    _suppressModelNotification = YES;
    [_textModel applyEdits:@[edit]];
    _suppressModelNotification = NO;

    NSInteger delta = (NSInteger)str.length - (NSInteger)safe.length;
    [_attrStorage replaceCharactersInRange:safe withString:str];
    [self edited:NSTextStorageEditedCharacters range:safe changeInLength:delta];
    [self endEditing];
}

- (void)setAttributes:(nullable NSDictionary<NSAttributedStringKey, id> *)attrs
                range:(NSRange)range {
    NSUInteger len = _attrStorage.length;
    if (range.length == 0 || range.location >= len) return;
    NSRange safe = NSMakeRange(range.location, MIN(range.length, len - range.location));

    [self beginEditing];

    // Preserve any existing background highlight so the layout manager does not
    // wipe out find-match colours.
    NSMutableDictionary *merged = [NSMutableDictionary dictionaryWithDictionary:attrs ?: @{}];
    if (!merged[NSBackgroundColorAttributeName] && safe.length > 0) {
        NSColor *existingBG = [_attrStorage attribute:NSBackgroundColorAttributeName
                                              atIndex:safe.location
                                       effectiveRange:nil];
        if (existingBG) merged[NSBackgroundColorAttributeName] = existingBG;
    }

    [_attrStorage setAttributes:merged range:safe];
    [self edited:NSTextStorageEditedAttributes range:safe changeInLength:0];
    [self endEditing];
}

// ---------------------------------------------------------------------------
// MARK: - Public tree-sitter API
// ---------------------------------------------------------------------------

- (void)setLanguageFunc:(nullable LanguageFunc)languageFunc
    withHighlightsQuery:(NSString *)queryText {
    _languageFuncInternal = languageFunc;
    [self _tearDownTreeSitter];
    _tsPreviousString       = @"";
    _highlightDecorationIDs = @[];

    if (!languageFunc) return;

    _tsParser = ts_parser_new();
    const TSLanguage *lang = languageFunc();
    if (lang) ts_parser_set_language(_tsParser, lang);

    if (queryText.length) {
        uint32_t errOffset = 0;
        TSQueryError errType = TSQueryErrorNone;
        const char *utf8 = [queryText cStringUsingEncoding:NSUTF8StringEncoding];
        _tsQuery = ts_query_new(lang, utf8, (uint32_t)strlen(utf8), &errOffset, &errType);
        if (errType != TSQueryErrorNone || !_tsQuery) {
            NSLog(@"[UDTextModelTextStorage] query parse error at offset %u (type %d)",
                  errOffset, errType);
            if (_tsQuery) { ts_query_delete(_tsQuery); _tsQuery = NULL; }
        } else {
            _tsQueryCursor = ts_query_cursor_new();
        }
    }

    NSString *snapshot = [self.string copy];
    [self _reparseFullString:snapshot];
    [self applyDecorationHighlights];
}

// ---------------------------------------------------------------------------
// MARK: - Tree-sitter parsing
// ---------------------------------------------------------------------------

/// Perform an incremental (or full) parse after an edit.
- (void)_performIncrementalParseAfterEdit:(NSRange)editedRange
                             changeInLength:(NSInteger)delta
                              currentString:(NSString *)currentString {
    if (!_tsParser) return;

    TSTree *oldTree = _tsCurrentTree;

    if (oldTree && editedRange.location != NSNotFound) {
        NSInteger oldLen = (NSInteger)editedRange.length - delta;
        uint32_t startByte  = byteFromCharIdx(editedRange.location);
        uint32_t oldEndByte = byteFromCharIdx(editedRange.location + (NSUInteger)MAX(0, oldLen));
        uint32_t newEndByte = byteFromCharIdx(editedRange.location + editedRange.length);
        TSInputEdit ie = { startByte, oldEndByte, newEndByte, {0,0}, {0,0}, {0,0} };
        ts_tree_edit(oldTree, &ie);
    }

    [self _runParseWithString:currentString oldTree:oldTree];
}

/// Parse the entire string from scratch (used for initial parse and undo/redo).
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

    // Compute changed ranges and update decorations accordingly.
    if (oldTree) {
        uint32_t count = 0;
        TSRange *ranges = ts_tree_get_changed_ranges(oldTree, newTree, &count);
        NSMutableArray<UDModelDeltaDecoration *> *newDecors = [NSMutableArray array];
        for (uint32_t i = 0; i < count; i++) {
            [self _collectDecorationsForRange:ranges[i] tree:newTree into:newDecors];
        }
        // Merge: keep decorations outside changed ranges, replace inside.
        [self _replaceHighlightDecorationsInRanges:ranges count:count
                                      withNewOnes:newDecors
                                           string:s];
        free(ranges);
        ts_tree_delete(oldTree);
    } else {
        // Full parse – replace all highlight decorations.
        NSMutableArray<UDModelDeltaDecoration *> *newDecors = [NSMutableArray array];
        TSNode root = ts_tree_root_node(newTree);
        TSRange full = {
            .start_byte  = ts_node_start_byte(root),
            .end_byte    = ts_node_end_byte(root),
            .start_point = ts_node_start_point(root),
            .end_point   = ts_node_end_point(root),
        };
        [self _collectDecorationsForRange:full tree:newTree into:newDecors];
        _highlightDecorationIDs =
            [_textModel deltaDecorations:_highlightDecorationIDs
                          newDecorations:newDecors
                                   owner:UDHighlightDecorationOwner];
    }

    _tsCurrentTree    = newTree;
    _tsPreviousString = [s copy];
}

/// Walk the query cursor over newTree limited to tsRange and populate newDecors.
- (void)_collectDecorationsForRange:(TSRange)tsRange
                               tree:(TSTree *)tree
                               into:(NSMutableArray<UDModelDeltaDecoration *> *)out {
    TSNode root = ts_tree_root_node(tree);

    if (_tsQuery && _tsQueryCursor) {
        ts_query_cursor_exec(_tsQueryCursor, _tsQuery, root);
        ts_query_cursor_set_byte_range(_tsQueryCursor,
                                       tsRange.start_byte, tsRange.end_byte);
        TSQueryMatch match;
        while (ts_query_cursor_next_match(_tsQueryCursor, &match)) {
            for (uint32_t i = 0; i < match.capture_count; i++) {
                TSQueryCapture cap = match.captures[i];
                uint32_t len = 0;
                const char *cname =
                    ts_query_capture_name_for_id(_tsQuery, cap.index, &len);
                NSString *captureName = [[NSString alloc]
                    initWithBytes:cname length:len encoding:NSUTF8StringEncoding];

                uint32_t nb = ts_node_start_byte(cap.node);
                uint32_t ne = ts_node_end_byte(cap.node);
                if (ne <= tsRange.start_byte || nb >= tsRange.end_byte) continue;

                UDModelDeltaDecoration *d =
                    [self _makeDecorationFromByte:nb toByte:ne captureName:captureName];
                if (d) [out addObject:d];
            }
        }
    } else {
        // No query: walk the tree by node type.
        [self _collectNodeDecorations:root inRange:tsRange into:out];
    }
}

- (void)_collectNodeDecorations:(TSNode)node
                        inRange:(TSRange)range
                           into:(NSMutableArray<UDModelDeltaDecoration *> *)out {
    uint32_t nb = ts_node_start_byte(node);
    uint32_t ne = ts_node_end_byte(node);
    if (ne <= range.start_byte || nb >= range.end_byte) return;

    const char *type = ts_node_type(node);
    NSString *typeName = @(type);
    UDModelDeltaDecoration *d =
        [self _makeDecorationFromByte:nb toByte:ne captureName:typeName];
    if (d) [out addObject:d];

    uint32_t cc = ts_node_child_count(node);
    for (uint32_t i = 0; i < cc; i++) {
        [self _collectNodeDecorations:ts_node_child(node, i) inRange:range into:out];
    }
}

- (nullable UDModelDeltaDecoration *)_makeDecorationFromByte:(uint32_t)startByte
                                                       toByte:(uint32_t)endByte
                                                  captureName:(NSString *)name {
    NSUInteger startChar = charIdxFromByte(startByte);
    NSUInteger endChar   = charIdxFromByte(endByte);
    NSUInteger docLen    = (NSUInteger)[_textModel getLength];
    if (startChar >= endChar || endChar > docLen) return nil;

    UDPosition sp = [_textModel getPositionAt:(NSInteger)startChar];
    UDPosition ep = [_textModel getPositionAt:(NSInteger)endChar];
    UDRange r = PTRangeMake(sp.line, sp.column, ep.line, ep.column);

    UDDecorationOptions *opts = [[UDDecorationOptions alloc]
                                  initWithClassName:name userInfo:nil];
    UDModelDeltaDecoration *d = [[UDModelDeltaDecoration alloc] initWithRange:r options:opts];
    d.stickiness = UDTrackedRangeNeverGrowsWhenTypingAtEdges;
    return d;
}

/// Replace only the highlight decorations that cover any of the given changed
/// TSRanges, leaving decorations outside those ranges untouched.
- (void)_replaceHighlightDecorationsInRanges:(TSRange *)changedRanges
                                        count:(uint32_t)count
                                 withNewOnes:(NSArray<UDModelDeltaDecoration *> *)newDecors
                                      string:(NSString *)s {
    NSUInteger docLen = (NSUInteger)[_textModel getLength];

    // Compute the union byte range of all changed TS ranges.
    if (count == 0) return;
    uint32_t unionStart = changedRanges[0].start_byte;
    uint32_t unionEnd   = changedRanges[0].end_byte;
    for (uint32_t i = 1; i < count; i++) {
        if (changedRanges[i].start_byte < unionStart)
            unionStart = changedRanges[i].start_byte;
        if (changedRanges[i].end_byte > unionEnd)
            unionEnd = changedRanges[i].end_byte;
    }
    NSUInteger startChar = charIdxFromByte(unionStart);
    NSUInteger endChar   = MIN(charIdxFromByte(unionEnd), docLen);
    if (startChar > docLen) return;

    UDPosition sp = [_textModel getPositionAt:(NSInteger)startChar];
    UDPosition ep = [_textModel getPositionAt:(NSInteger)endChar];
    UDRange    changedModelRange = PTRangeMake(sp.line, sp.column, ep.line, ep.column);

    // Find existing decorations inside the changed range and remove them,
    // keeping all others.
    NSArray<NSString *> *inRange =
        [_textModel decorationsInRange:changedModelRange];

    // Filter to only 'highlight' owner ones.
    NSMutableArray<NSString *> *toRemove = [NSMutableArray array];
    NSMutableArray<NSString *> *toKeep   = [NSMutableArray array];
    NSSet *inRangeSet = [NSSet setWithArray:inRange];
    for (NSString *did in _highlightDecorationIDs) {
        if ([inRangeSet containsObject:did]) {
            [toRemove addObject:did];
        } else {
            [toKeep addObject:did];
        }
    }

    // deltaDecorations: remove stale ones and add new ones.
    NSArray<NSString *> *addedIDs =
        [_textModel deltaDecorations:toRemove
                      newDecorations:newDecors
                               owner:UDHighlightDecorationOwner];

    _highlightDecorationIDs = [toKeep arrayByAddingObjectsFromArray:addedIDs];
}

// ---------------------------------------------------------------------------
// MARK: - processEditing
// ---------------------------------------------------------------------------

- (void)processEditing {
    NSRange editedRange = [self editedRange];
    NSInteger delta     = [self changeInLength];

    [super processEditing];

    if ((self.editedMask & NSTextStorageEditedCharacters) && _tsParser) {
        NSString *snap = [self.string copy];
        [self _performIncrementalParseAfterEdit:editedRange
                                  changeInLength:delta
                                   currentString:snap];
        [self applyDecorationHighlights];
    }
}

// ---------------------------------------------------------------------------
// MARK: - Decoration highlights
// ---------------------------------------------------------------------------

- (void)applyDecorationHighlights {
    NSUInteger len = _attrStorage.length;
    if (len == 0) return;

    [self beginEditing];

    // --- Reset to base attributes first ---
    [_attrStorage setAttributes:BaseAttributes() range:NSMakeRange(0, len)];

    // --- Apply 'highlight' (syntax) foreground colours ---
    NSArray<NSString *> *hlIDs =
        [_textModel decorationsForOwner:UDHighlightDecorationOwner];
    for (NSString *did in hlIDs) {
        UDRange          r    = [_textModel rangeForDecoration:did];
        UDDecorationOptions *opts = [_textModel optionsForDecoration:did];
        if (r.startLineNumber == 0 || !opts.className) continue;

        NSInteger startOff = [_textModel getOffsetAt:r.startLineNumber column:r.startColumn];
        NSInteger endOff   = [_textModel getOffsetAt:r.endLineNumber   column:r.endColumn];
        if (startOff < 0 || endOff <= startOff || (NSUInteger)endOff > len) continue;

        NSDictionary *attrs = [_theme styleAttributesForName:opts.className];
        if (!attrs) continue;

        NSRange nsRange = NSMakeRange((NSUInteger)startOff,
                                      (NSUInteger)(endOff - startOff));
        [_attrStorage addAttributes:attrs range:nsRange];
    }

    // --- Apply 'find' (search) background colours ---
    NSArray<NSString *> *findIDs =
        [_textModel decorationsForOwner:UDFindDecorationOwner];
    NSColor *findBG = [NSColor systemYellowColor];
    for (NSString *did in findIDs) {
        UDRange r = [_textModel rangeForDecoration:did];
        if (r.startLineNumber == 0) continue;

        NSInteger startOff = [_textModel getOffsetAt:r.startLineNumber column:r.startColumn];
        NSInteger endOff   = [_textModel getOffsetAt:r.endLineNumber   column:r.endColumn];
        if (startOff < 0 || endOff <= startOff || (NSUInteger)endOff > len) continue;

        NSRange nsRange = NSMakeRange((NSUInteger)startOff,
                                      (NSUInteger)(endOff - startOff));
        [_attrStorage addAttribute:NSBackgroundColorAttributeName
                             value:findBG
                             range:nsRange];
    }

    [self edited:NSTextStorageEditedAttributes range:NSMakeRange(0, len) changeInLength:0];
    [self endEditing];
}

@end
