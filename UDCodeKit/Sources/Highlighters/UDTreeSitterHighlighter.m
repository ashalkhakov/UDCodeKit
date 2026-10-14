#import "UDTreeSitterHighlighter.h"
#import <tree_sitter/api.h>

// ---------------------------------------------------------------------------
#pragma mark - UTF-16 read callback (reads directly from UDTextModel)
// ---------------------------------------------------------------------------

/// Buffer size for the tree-sitter read callback.  Tree-sitter requests
/// TS_READ_BUFFER_CHARS UTF-16 code units at a time; we fill the buffer from
/// the model using fillCharacters:range: — no full-document materialisation.
#define TS_READ_BUFFER_CHARS 1024

typedef struct {
    /// The text model to read from.  This struct is only ever used on the main
    /// thread (tree-sitter parsing always runs on the main thread), so retaining
    /// a raw pointer with __unsafe_unretained is safe here.
    __unsafe_unretained UDTextModel *model;
    NSUInteger                       length; ///< Current document length (chars).
    unichar                          buffer[TS_READ_BUFFER_CHARS];
} TSModelReadContext;

static const char *tsModelReadCallback(void *payload, uint32_t byteOffset,
                                        TSPoint position, uint32_t *bytesRead) {
    TSModelReadContext *ctx = (TSModelReadContext *)payload;
    NSUInteger charOffset = byteOffset / 2;
    if (charOffset >= ctx->length) { *bytesRead = 0; return NULL; }
    NSUInteger n = MIN(TS_READ_BUFFER_CHARS, ctx->length - charOffset);
    [ctx->model fillCharacters:ctx->buffer range:NSMakeRange(charOffset, n)];
    *bytesRead = (uint32_t)(n * sizeof(unichar));
    return (const char *)ctx->buffer;
}

static inline uint32_t   byteFromCharIdx(NSUInteger i) { return (uint32_t)(i * 2); }

// ---------------------------------------------------------------------------
#pragma mark - Private interface
// ---------------------------------------------------------------------------

@interface UDTreeSitterHighlighter ()
@property (nonatomic, weak)   UDTextModel   *textModel;
@property (nonatomic, assign) LanguageFunc   languageFuncInternal;
@property (nonatomic, assign) TSParser      *tsParser;
@property (nonatomic, assign) TSTree        *tsCurrentTree;
@property (nonatomic, assign) TSQuery       *tsQuery;
@property (nonatomic, assign) TSQueryCursor *tsQueryCursor;
@property (nonatomic, copy, nullable) NSArray<NSValue *> *lastChangedCharRanges;
@end

@implementation UDTreeSitterHighlighter

// ---------------------------------------------------------------------------
#pragma mark - Init / dealloc
// ---------------------------------------------------------------------------

- (instancetype)initWithTextModel:(UDTextModel *)model {
    self = [super init];
    if (!self) return nil;
    _textModel = model;
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
#pragma mark - Public API
// ---------------------------------------------------------------------------

- (BOOL)isActive { return _tsParser != NULL; }

- (const void *)currentParseTree   { return _tsCurrentTree;    }
- (const void *)currentQuery       { return _tsQuery;          }
- (const void *)currentQueryCursor { return _tsQueryCursor;    }

- (void)setLanguageFunc:(nullable LanguageFunc)languageFunc
    withHighlightsQuery:(nullable NSString *)queryText {
    _languageFuncInternal = languageFunc;
    [self _tearDown];

    if (!languageFunc) return;

    _tsParser = ts_parser_new();
    const TSLanguage *lang = languageFunc();
    if (lang) ts_parser_set_language(_tsParser, lang);

    if (queryText.length) {
        uint32_t errOffset  = 0;
        TSQueryError errType = TSQueryErrorNone;
        const char *utf8    = [queryText cStringUsingEncoding:NSUTF8StringEncoding];
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

/// A model position (1-based line and column) as tree-sitter's point: 0-based
/// row, and the column in bytes of the UTF-16 input.
static inline TSPoint pointFromPosition(UDPosition p) {
    return (TSPoint){ (uint32_t)(p.line - 1), byteFromCharIdx((NSUInteger)(p.column - 1)) };
}

- (void)applyEditAtOffset:(NSUInteger)start
                   oldEnd:(NSUInteger)oldEnd
                   newEnd:(NSUInteger)newEnd
            startPosition:(UDPosition)startPosition
           oldEndPosition:(UDPosition)oldEndPosition
           newEndPosition:(UDPosition)newEndPosition {
    if (!_tsParser || !_tsCurrentTree) return;
    // Rows and columns too, not only bytes: nodes the parse reuses keep the
    // points the edit gives them (folding reads their rows).
    TSInputEdit ie = {
        byteFromCharIdx(start), byteFromCharIdx(oldEnd), byteFromCharIdx(newEnd),
        pointFromPosition(startPosition), pointFromPosition(oldEndPosition), pointFromPosition(newEndPosition)
    };
    ts_tree_edit(_tsCurrentTree, &ie);
}

- (void)reparseAfterEdits {
    if (!_tsParser) return;
    [self _runParseOldTree:_tsCurrentTree];
}

- (void)reparseFromModel {
    if (!_tsParser) return;
    if (_tsCurrentTree) { ts_tree_delete(_tsCurrentTree); _tsCurrentTree = NULL; }
    [self _runParseOldTree:NULL];
}

// ---------------------------------------------------------------------------
#pragma mark - Parsing internals
// ---------------------------------------------------------------------------

/// Core parse step.  Reads from the UDTextModel via tsModelReadCallback —
/// no full-document NSString materialisation needed.
- (void)_runParseOldTree:(nullable TSTree *)oldTree {
    UDTextModel *model = _textModel;
    if (!model) return;

    NSUInteger len = (NSUInteger)[model getLength];
    TSModelReadContext ctx = { .model = model, .length = len };
    TSInput input = { &ctx, tsModelReadCallback, TSInputEncodingUTF16LE };
    TSTree *newTree = ts_parser_parse(_tsParser, oldTree, input);
    if (!newTree) return;

    if (oldTree) {
        uint32_t count  = 0;
        TSRange *ranges = ts_tree_get_changed_ranges(oldTree, newTree, &count);
        NSMutableArray<NSValue *> *changedCharRanges =
            [NSMutableArray arrayWithCapacity:count];
        for (uint32_t i = 0; i < count; i++) {
            NSUInteger cs = UDCharIndexFromByte(ranges[i].start_byte);
            NSUInteger ce = UDCharIndexFromByte(ranges[i].end_byte);
            [changedCharRanges addObject:
                [NSValue valueWithRange:NSMakeRange(cs, ce > cs ? ce - cs : 0)]];
        }
        _lastChangedCharRanges = [changedCharRanges copy];
        free(ranges);
        ts_tree_delete(oldTree);
    } else {
        // Full re-parse: consumers should treat the whole document as changed.
        _lastChangedCharRanges = nil;
    }

    _tsCurrentTree = newTree;
}

@end
