/*---------------------------------------------------------------------------------------------
 *  UDTreeSitterHighlighter.m
 *--------------------------------------------------------------------------------------------*/

#import "UDTreeSitterHighlighter.h"
#import <tree_sitter/api.h>

// Owner string for highlight decorations on the model.
NSString * const UDHighlightDecorationOwner = @"highlight";

// ---------------------------------------------------------------------------
// MARK: - UTF-16 read callback
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

// Tree-sitter uses UTF-16: each NSString code unit is 2 bytes.
static inline NSUInteger charIdxFromByte(uint32_t b) { return b / 2; }
static inline uint32_t   byteFromCharIdx(NSUInteger i) { return (uint32_t)(i * 2); }

// ---------------------------------------------------------------------------
// MARK: - Private interface
// ---------------------------------------------------------------------------

@interface UDTreeSitterHighlighter ()
@property (nonatomic, weak) UDTextModel *textModel;

@property (nonatomic, assign) LanguageFunc   languageFuncInternal;
@property (nonatomic, assign) TSParser      *tsParser;
@property (nonatomic, assign) TSTree        *tsCurrentTree;
@property (nonatomic, assign) TSQuery       *tsQuery;
@property (nonatomic, assign) TSQueryCursor *tsQueryCursor;
@property (nonatomic, copy)   NSString      *tsPreviousString;

@property (nonatomic, strong) NSArray<NSString *> *highlightDecorationIDs;
@end

@implementation UDTreeSitterHighlighter

// ---------------------------------------------------------------------------
// MARK: - Init / dealloc
// ---------------------------------------------------------------------------

- (instancetype)initWithTextModel:(UDTextModel *)model {
    self = [super init];
    if (!self) return nil;
    _textModel              = model;
    _tsPreviousString       = @"";
    _highlightDecorationIDs = @[];
    return self;
}

- (void)dealloc {
    [self _tearDown];
}

- (void)_tearDown {
    if (_tsQueryCursor) { ts_query_cursor_delete(_tsQueryCursor); _tsQueryCursor = NULL; }
    if (_tsCurrentTree) { ts_tree_delete(_tsCurrentTree);         _tsCurrentTree = NULL; }
    if (_tsQuery)       { ts_query_delete(_tsQuery);              _tsQuery       = NULL; }
    if (_tsParser)      { ts_parser_delete(_tsParser);            _tsParser      = NULL; }
}

// ---------------------------------------------------------------------------
// MARK: - Public API
// ---------------------------------------------------------------------------

- (BOOL)isActive {
    return _tsParser != NULL;
}

- (void)setLanguageFunc:(nullable LanguageFunc)languageFunc
    withHighlightsQuery:(NSString *)queryText {
    _languageFuncInternal = languageFunc;
    [self _tearDown];
    _tsPreviousString       = @"";
    // Remove stale decorations from the model.
    if (_highlightDecorationIDs.count) {
        [_textModel deltaDecorations:_highlightDecorationIDs
                      newDecorations:@[]
                               owner:UDHighlightDecorationOwner];
        _highlightDecorationIDs = @[];
    }

    if (!languageFunc) return;

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
            NSLog(@"[UDTreeSitterHighlighter] query error at offset %u, type %d",
                  errOffset, errType);
            if (_tsQuery) { ts_query_delete(_tsQuery); _tsQuery = NULL; }
        } else {
            _tsQueryCursor = ts_query_cursor_new();
        }
    }
}

- (void)performIncrementalParseAfterEdit:(NSRange)editedRange
                           changeInLength:(NSInteger)delta
                            currentString:(NSString *)s {
    if (!_tsParser) return;

    TSTree *oldTree = _tsCurrentTree;
    if (oldTree && editedRange.location != NSNotFound) {
        // editedRange.length = new text length; delta = new - old.
        // So old length = editedRange.length - delta, always >= 0.
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

- (void)reparseFullString:(NSString *)s {
    if (!_tsParser) return;
    if (_tsCurrentTree) { ts_tree_delete(_tsCurrentTree); _tsCurrentTree = NULL; }
    _tsPreviousString = @"";
    [self _runParseWithString:s oldTree:NULL];
}

// ---------------------------------------------------------------------------
// MARK: - Parsing internals
// ---------------------------------------------------------------------------

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
            [self _replaceDecorationsInRanges:ranges count:count withNewOnes:newDecors];
        }
        free(ranges);
        ts_tree_delete(oldTree);
    } else {
        NSMutableArray<UDModelDeltaDecoration *> *all = [NSMutableArray array];
        TSNode root = ts_tree_root_node(newTree);
        TSRange full;
        full.start_byte  = ts_node_start_byte(root);
        full.end_byte    = ts_node_end_byte(root);
        full.start_point = ts_node_start_point(root);
        full.end_point   = ts_node_end_point(root);
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
                const char *cn =
                    ts_query_capture_name_for_id(_tsQuery, cap.index, &nl);
                NSString *name = [[NSString alloc] initWithBytes:cn length:nl
                                                        encoding:NSUTF8StringEncoding];
                UDModelDeltaDecoration *d =
                    [self _makeDecorationByte:nb toByte:ne name:name];
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
    NSUInteger docLen = (NSUInteger)[_textModel getLength];
    if (sc >= ec || ec > docLen) return nil;
    UDPosition sp = [_textModel getPositionAt:(NSInteger)sc];
    UDPosition ep = [_textModel getPositionAt:(NSInteger)ec];
    UDRange ur = PTRangeMake(sp.line, sp.column, ep.line, ep.column);
    UDDecorationOptions *opts =
        [[UDDecorationOptions alloc] initWithClassName:name userInfo:nil];
    UDModelDeltaDecoration *d =
        [[UDModelDeltaDecoration alloc] initWithRange:ur options:opts];
    d.stickiness = UDTrackedRangeNeverGrowsWhenTypingAtEdges;
    return d;
}

- (void)_replaceDecorationsInRanges:(TSRange *)changedRanges
                               count:(uint32_t)count
                         withNewOnes:(NSArray<UDModelDeltaDecoration *> *)newDecors {
    if (count == 0) return;
    NSUInteger docLen = (NSUInteger)[_textModel getLength];

    uint32_t uStart = changedRanges[0].start_byte;
    uint32_t uEnd   = changedRanges[0].end_byte;
    for (uint32_t i = 1; i < count; i++) {
        if (changedRanges[i].start_byte < uStart) uStart = changedRanges[i].start_byte;
        if (changedRanges[i].end_byte   > uEnd)   uEnd   = changedRanges[i].end_byte;
    }
    NSUInteger sc = charIdxFromByte(uStart);
    NSUInteger ec = MIN(charIdxFromByte(uEnd), docLen);
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
