#import "UDTreeSitterHighlighter.h"
#import <tree_sitter/api.h>

// ---------------------------------------------------------------------------
#pragma mark - UTF-16 read callback
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

static inline NSUInteger charIdxFromByte(uint32_t b) { return b / 2; }
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
@property (nonatomic, copy)   NSString      *tsPreviousString;
@property (nonatomic, copy, nullable) NSArray<NSValue *> *lastChangedCharRanges;
@end

@implementation UDTreeSitterHighlighter

// ---------------------------------------------------------------------------
#pragma mark - Init / dealloc
// ---------------------------------------------------------------------------

- (instancetype)initWithTextModel:(UDTextModel *)model {
    self = [super init];
    if (!self) return nil;
    _textModel        = model;
    _tsPreviousString = @"";
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
    _tsPreviousString = @"";

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

- (void)performIncrementalParseAfterEdit:(NSRange)editedRange
                           changeInLength:(NSInteger)delta
                            currentString:(NSString *)s {
    if (!_tsParser) return;
    TSTree *oldTree = _tsCurrentTree;
    if (oldTree && editedRange.location != NSNotFound) {
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
#pragma mark - Parsing internals
// ---------------------------------------------------------------------------

- (void)_runParseWithString:(NSString *)s oldTree:(nullable TSTree *)oldTree {
    if (!s) s = @"";
    if ([s isEqualToString:_tsPreviousString] && _tsCurrentTree) return;

    TSReadContext ctx = { .string = s, .length = s.length };
    TSInput input = { &ctx, tsReadCallback, TSInputEncodingUTF16 };
    TSTree *newTree = ts_parser_parse(_tsParser, oldTree, input);
    if (!newTree) return;

    if (oldTree) {
        uint32_t count  = 0;
        TSRange *ranges = ts_tree_get_changed_ranges(oldTree, newTree, &count);
        NSMutableArray<NSValue *> *changedCharRanges =
            [NSMutableArray arrayWithCapacity:count];
        for (uint32_t i = 0; i < count; i++) {
            NSUInteger cs = charIdxFromByte(ranges[i].start_byte);
            NSUInteger ce = charIdxFromByte(ranges[i].end_byte);
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

    _tsCurrentTree    = newTree;
    _tsPreviousString = [s copy];
}

@end
