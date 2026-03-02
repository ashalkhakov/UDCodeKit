/*---------------------------------------------------------------------------------------------
 *  UDAutoIndenter.m
 *--------------------------------------------------------------------------------------------*/

#import "UDAutoIndenter.h"
#import <tree_sitter/api.h>
#import <string.h>

// Tree-sitter stores byte offsets in UTF-16 (2 bytes per BMP code unit).
static inline uint32_t byteFromChar(NSUInteger c) { return (uint32_t)(c * 2); }

@interface UDAutoIndenter ()
@property (nonatomic, weak)   NSTextView              *textView;
@property (nonatomic, weak)   UDTreeSitterHighlighter *highlighter;
@property (nonatomic, weak)   UDTextModel             *textModel;
// Compiled tree-sitter query for @indent captures and a dedicated cursor.
@property (nonatomic, assign) TSQuery                 *tsIndentQuery;
@property (nonatomic, assign) TSQueryCursor           *tsQueryCursor;
@end

@implementation UDAutoIndenter

// ---------------------------------------------------------------------------
// MARK: - Init / dealloc
// ---------------------------------------------------------------------------

- (instancetype)initWithTextView:(NSTextView *)textView
                      highlighter:(UDTreeSitterHighlighter *)highlighter
                        textModel:(UDTextModel *)textModel {
    self = [super init];
    if (!self) return nil;
    _textView    = textView;
    _highlighter = highlighter;
    _textModel   = textModel;
    _indentUnit  = @"  "; // default: 2 spaces
    return self;
}

- (void)dealloc {
    [self _tearDownQuery];
}

- (void)_tearDownQuery {
    if (_tsQueryCursor) { ts_query_cursor_delete(_tsQueryCursor); _tsQueryCursor = NULL; }
    if (_tsIndentQuery) { ts_query_delete(_tsIndentQuery);        _tsIndentQuery = NULL; }
}

// ---------------------------------------------------------------------------
// MARK: - Configuration
// ---------------------------------------------------------------------------

- (void)configureWithLanguageFunc:(LanguageFunc)languageFunc
                      indentsQuery:(NSString *)indentsQuery {
    [self _tearDownQuery];
    if (!languageFunc || !indentsQuery.length) return;

    const TSLanguage *lang = (const TSLanguage *)languageFunc();
    if (!lang) return;

    const char *utf8 = [indentsQuery cStringUsingEncoding:NSUTF8StringEncoding];
    uint32_t errOffset = 0;
    TSQueryError errType = TSQueryErrorNone;
    _tsIndentQuery = ts_query_new(lang, utf8, (uint32_t)strlen(utf8),
                                  &errOffset, &errType);
    if (errType != TSQueryErrorNone || !_tsIndentQuery) {
        NSLog(@"[UDAutoIndenter] indent query error at offset %u type %d",
              errOffset, errType);
        if (_tsIndentQuery) { ts_query_delete(_tsIndentQuery); _tsIndentQuery = NULL; }
        return;
    }
    _tsQueryCursor = ts_query_cursor_new();
}

// ---------------------------------------------------------------------------
// MARK: - Public API
// ---------------------------------------------------------------------------

- (BOOL)handleReturnKey {
    NSTextView  *tv      = _textView;
    UDTextModel *model   = _textModel;
    if (!tv || !model) return NO;

    NSRange     sel    = tv.selectedRange;
    NSString   *text   = [model getValue];
    NSInteger   docLen = [model getLength];

    // When the document is empty, fall through to NSTextView default.
    if (docLen == 0) return NO;

    NSUInteger cursorPos = sel.location;

    // ------------------------------------------------------------------
    // 1. Indentation of the current line.
    // ------------------------------------------------------------------
    NSString *lineIndent = [self _indentOfLineContaining:cursorPos inText:text];

    // ------------------------------------------------------------------
    // 2. Does the cursor immediately follow an indent-opening bracket?
    //    Only increase indentation when:
    //      (a) the last non-space character on the current line is { or [
    //          (these are the indent-opening tokens for JSON; extend this
    //          check for other languages that use different openers), AND
    //      (b) the tree-sitter query confirms we are inside an @indent node
    //          (this rules out { or [ inside a string literal).
    // ------------------------------------------------------------------
    unichar charBefore   = [self _lastNonSpaceCharBefore:cursorPos inText:text];
    BOOL    increaseIndent = (charBefore == '{' || charBefore == '[')
                             && [self _isInsideIndentNodeAtOffset:cursorPos];

    NSString *newIndent = increaseIndent
        ? [lineIndent stringByAppendingString:_indentUnit]
        : lineIndent;

    // ------------------------------------------------------------------
    // 3. Electric-pair split: if a closing bracket sits right after the
    //    cursor (e.g.  { | } ), split it so the cursor ends up on the
    //    indented middle line and the closing bracket moves to its own line.
    // ------------------------------------------------------------------
    NSUInteger afterPos  = sel.location + sel.length;
    unichar    charAfter = (afterPos < (NSUInteger)docLen)
                               ? [text characterAtIndex:afterPos] : 0;
    BOOL split = increaseIndent && (charAfter == '}' || charAfter == ']');

    // ------------------------------------------------------------------
    // 4. Build the replacement string.
    //
    //    Normal:  "\n<newIndent>"
    //    Split:   "\n<newIndent>\n<lineIndent>"   (cursor on first new line)
    // ------------------------------------------------------------------
    NSString *insertText = split
        ? [NSString stringWithFormat:@"\n%@\n%@", newIndent, lineIndent]
        : [NSString stringWithFormat:@"\n%@",     newIndent];

    // Apply via NSTextView so the edit flows through the normal
    // NSTextStorage → UDTextModel pipeline (undo, re-parse, highlights).
    [tv insertText:insertText replacementRange:sel];

    if (split) {
        // insertText:replacementRange: leaves the cursor at the very end of
        // the inserted text (after <lineIndent>).  Move it back to the middle
        // line, right after <newIndent>.
        NSUInteger newCursorPos = cursorPos + 1 + newIndent.length;
        [tv setSelectedRange:NSMakeRange(newCursorPos, 0)];
    }

    return YES;
}

// ---------------------------------------------------------------------------
// MARK: - Private helpers
// ---------------------------------------------------------------------------

/// Returns the leading-whitespace prefix of the line that contains @c offset.
- (NSString *)_indentOfLineContaining:(NSUInteger)offset inText:(NSString *)text {
    if (offset == 0) return @"";

    // Walk backwards to find the start of the current line.
    NSUInteger lineStart = 0;
    NSUInteger i = offset;
    while (i > 0) {
        i--;
        unichar c = [text characterAtIndex:i];
        if (c == '\n' || c == '\r') { lineStart = i + 1; break; }
    }

    // Collect spaces and tabs up to the first non-whitespace character
    // (or to the cursor, whichever comes first).
    NSMutableString *indent = [NSMutableString string];
    for (NSUInteger j = lineStart; j < offset; j++) {
        unichar c = [text characterAtIndex:j];
        if (c == ' ' || c == '\t') { [indent appendFormat:@"%C", c]; }
        else break;
    }
    return [indent copy];
}

/// Returns the last non-space/tab character before @c offset on the SAME LINE,
/// or 0 if none is found (the line is blank, only whitespace, or offset is 0).
/// Stops and returns 0 when a line-ending character (\n or \r) is encountered,
/// so the search is always restricted to the current line.
- (unichar)_lastNonSpaceCharBefore:(NSUInteger)offset inText:(NSString *)text {
    if (offset == 0) return 0;
    NSInteger i = (NSInteger)offset - 1;
    while (i >= 0) {
        unichar c = [text characterAtIndex:(NSUInteger)i];
        if (c == ' ' || c == '\t') { i--; continue; }
        // Stop at line endings — do not search into the previous line.
        if (c == '\n' || c == '\r') return 0;
        return c;
    }
    return 0;
}

/// Returns YES when the cursor at @c offset is strictly inside an @indent
/// tree-sitter node, meaning a newline here should increase indentation.
///
/// Runs the compiled indent query on the current parse tree and checks whether
/// the cursor's byte offset lies strictly after the start byte and at or before
/// the end byte of any @indent capture.  This correctly rejects the case where
/// a '{' or '[' is inside a string literal (the enclosing `string` node does
/// not match the @indent query).
///
/// Falls back to YES (trusting the caller's character check) when no indent
/// query has been configured or no parse tree is available.
- (BOOL)_isInsideIndentNodeAtOffset:(NSUInteger)offset {
    if (!_tsIndentQuery || !_tsQueryCursor) return YES;

    const TSTree *tree = (const TSTree *)_highlighter.currentParseTree;
    if (!tree) return YES;

    NSInteger docLen = [_textModel getLength];
    if (docLen <= 0) return NO;

    uint32_t byte = byteFromChar(offset);

    TSNode root = ts_tree_root_node((TSTree *)tree);
    ts_query_cursor_exec(_tsQueryCursor, _tsIndentQuery, root);

    TSQueryMatch match;
    while (ts_query_cursor_next_match(_tsQueryCursor, &match)) {
        for (uint32_t i = 0; i < match.capture_count; i++) {
            TSQueryCapture cap = match.captures[i];

            // Only consider @indent captures (skip @dedent or others).
            uint32_t    nameLen = 0;
            const char *capName =
                ts_query_capture_name_for_id(_tsIndentQuery, cap.index, &nameLen);
            if (nameLen != 6 || strncmp(capName, "indent", 6) != 0) continue;

            uint32_t ns = ts_node_start_byte(cap.node);
            uint32_t ne = ts_node_end_byte(cap.node);

            // Cursor is inside this node if: node opened before the cursor
            // and hasn't closed yet (end_byte is exclusive in tree-sitter).
            if (ns < byte && byte < ne) return YES;
        }
    }
    return NO;
}

@end
