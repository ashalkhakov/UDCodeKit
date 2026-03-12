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

    NSRange   sel    = tv.selectedRange;
    NSInteger docLen = [model getLength];

    // When the document is empty, fall through to NSTextView default.
    if (docLen == 0) return NO;

    NSUInteger cursorPos = sel.location;

    // ------------------------------------------------------------------
    // 1. Indentation of the current line.
    // ------------------------------------------------------------------
    NSString *lineIndent = [self _indentOfLineContaining:cursorPos];

    // ------------------------------------------------------------------
    // 2. Does the cursor immediately follow an indent-opening bracket?
    //    Only increase indentation when:
    //      (a) the last non-space character on the current line is an
    //          opening bracket from the language's bracket configuration
    //          (falls back to { and [ when no config is set), AND
    //      (b) the tree-sitter query confirms we are inside an @indent node
    //          (this rules out brackets inside string literals).
    // ------------------------------------------------------------------
    unichar charBefore = [self _lastNonSpaceCharBefore:cursorPos];

    // Build the set of open/close bracket characters from language config.
    NSString *openChars  = nil;
    NSString *closeChars = nil;
    UDLanguageConfiguration *config = _languageConfiguration;
    if (config.brackets.count) {
        openChars  = [config openBracketCharacters];
        closeChars = [config closeBracketCharacters];
    }
    // Fall back to the built-in defaults when no config is available.
    if (!openChars.length)  openChars  = @"{[";
    if (!closeChars.length) closeChars = @"}]";

    BOOL isOpenBracket = charBefore != 0
        && ([openChars rangeOfString:[NSString stringWithCharacters:&charBefore length:1]].location != NSNotFound);
    BOOL increaseIndent = isOpenBracket
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
                               ? [model getCharacterAtOffset:afterPos] : 0;
    BOOL isCloseBracket = charAfter != 0
        && ([closeChars rangeOfString:[NSString stringWithCharacters:&charAfter length:1]].location != NSNotFound);
    BOOL split = increaseIndent && isCloseBracket;

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
// MARK: - Electric-pair insertion
// ---------------------------------------------------------------------------

- (BOOL)handleTypedCharacter:(NSString *)chars {
    if (chars.length != 1) return NO;

    UDLanguageConfiguration *config = _languageConfiguration;
    if (!config.autoClosingPairs.count) return NO;

    NSTextView  *tv    = _textView;
    UDTextModel *model = _textModel;
    if (!tv || !model) return NO;

    NSRange   sel      = tv.selectedRange;
    NSInteger docLen   = [model getLength];

    unichar    typedChar = [chars characterAtIndex:0];
    NSUInteger cursorPos = sel.location;

    // ------------------------------------------------------------------
    // 1. Skip-over: if the typed char is a close-bracket that already sits
    //    immediately to the right of the cursor (insertion point only),
    //    advance the cursor rather than inserting.  Only applies to
    //    asymmetric pairs (open != close) to avoid false-positives with
    //    symmetric pairs like quotes.
    // ------------------------------------------------------------------
    if (sel.length == 0 && cursorPos < (NSUInteger)docLen) {
        for (UDAutoClosingPair *pair in config.autoClosingPairs) {
            if (pair.close.length == 1
                    && [pair.close characterAtIndex:0] == typedChar
                    && ![pair.open isEqualToString:pair.close]) {
                unichar nextChar = [model getCharacterAtOffset:cursorPos];
                if (nextChar == typedChar) {
                    [tv setSelectedRange:NSMakeRange(cursorPos + 1, 0)];
                    return YES;
                }
            }
        }
    }

    // ------------------------------------------------------------------
    // 2. Auto-close: if the typed char is an open-bracket of a pair, insert
    //    open + close and place the cursor between them.
    // ------------------------------------------------------------------
    if (sel.length > 0) return NO;   // don't auto-close when text is selected

    for (UDAutoClosingPair *pair in config.autoClosingPairs) {
        if (pair.open.length != 1) continue;
        if ([pair.open characterAtIndex:0] != typedChar) continue;

        // autoCloseBefore: the character to the right of the cursor must be
        // in this set (or absent) for auto-close to fire.
        if (config.autoCloseBefore.length) {
            unichar charAfter = (cursorPos < (NSUInteger)docLen)
                              ? [model getCharacterAtOffset:cursorPos] : 0;
            if (charAfter != 0) {
                NSString *charAfterStr =
                    [NSString stringWithCharacters:&charAfter length:1];
                if ([config.autoCloseBefore
                        rangeOfString:charAfterStr].location == NSNotFound) {
                    return NO;
                }
            }
        }

        // notIn: suppress auto-close when inside a restricted node type.
        if (pair.notIn.count > 0
                && [self _cursorAtOffset:cursorPos isInsideNodeTypes:pair.notIn]) {
            return NO;
        }

        // Insert the pair and position the cursor between open and close.
        NSString *insert =
            [NSString stringWithFormat:@"%@%@", pair.open, pair.close];
        [tv insertText:insert replacementRange:sel];
        [tv setSelectedRange:NSMakeRange(cursorPos + 1, 0)];
        return YES;
    }

    return NO;
}

// ---------------------------------------------------------------------------
// MARK: - Private helpers (electric-pair)
// ---------------------------------------------------------------------------

/// Returns YES when the cursor at @c offset is inside any tree-sitter node
/// whose type appears in @c nodeTypes (e.g. @c "string" or @c "comment").
///
/// Walks up the ancestor chain from the deepest node covering the cursor
/// position.  Falls back to NO when no parse tree is available.
- (BOOL)_cursorAtOffset:(NSUInteger)offset
      isInsideNodeTypes:(NSArray<NSString *> *)nodeTypes {
    if (!nodeTypes.count) return NO;

    const TSTree *tree = (const TSTree *)_highlighter.currentParseTree;
    if (!tree) return NO;

    uint32_t byte = byteFromChar(offset);
    TSNode   root = ts_tree_root_node((TSTree *)tree);
    TSNode   node = ts_node_descendant_for_byte_range(root, byte, byte);
    if (ts_node_is_null(node)) return NO;

    while (!ts_node_is_null(node)) {
        const char *rawType = ts_node_type(node);
        if (rawType) {
            NSString *typeStr = [NSString stringWithUTF8String:rawType];
            if ([nodeTypes containsObject:typeStr]) return YES;
        }
        node = ts_node_parent(node);
    }
    return NO;
}

// ---------------------------------------------------------------------------
// MARK: - Private helpers (auto-indentation)
// ---------------------------------------------------------------------------

/// Returns the leading-whitespace prefix of the line that contains @c offset,
/// up to (but not including) the cursor column.
///
/// Uses @c getPositionAt: to find the line number and @c getLineContent: to
/// obtain only that line's text — no full-document string is materialised.
- (NSString *)_indentOfLineContaining:(NSUInteger)offset {
    UDTextModel *model = _textModel;
    if (!model) return @"";

    UDPosition pos = [model getPositionAt:(NSInteger)offset];
    NSString  *lineContent = [model getLineContent:pos.line];

    // pos.column is 1-based; characters 0..(pos.column-2) precede the cursor.
    NSUInteger limit = (NSUInteger)(pos.column - 1);
    NSMutableString *indent = [NSMutableString string];
    for (NSUInteger j = 0; j < limit && j < lineContent.length; j++) {
        unichar c = [lineContent characterAtIndex:j];
        if (c == ' ' || c == '\t') { [indent appendFormat:@"%C", c]; }
        else break;
    }
    return [indent copy];
}

/// Returns the last non-space/tab character before @c offset on the SAME LINE,
/// or 0 if none is found (blank line, only whitespace, or start of document).
///
/// Uses @c getPositionAt: and @c getLineContent: to restrict the search to the
/// current line without materialising the full document string.
- (unichar)_lastNonSpaceCharBefore:(NSUInteger)offset {
    UDTextModel *model = _textModel;
    if (!model || offset == 0) return 0;

    UDPosition pos = [model getPositionAt:(NSInteger)offset];
    NSString  *lineContent = [model getLineContent:pos.line];

    // pos.column is 1-based; the character immediately before the cursor is
    // at 0-based index (pos.column - 2).
    NSInteger startIdx = (NSInteger)pos.column - 2;
    for (NSInteger j = startIdx; j >= 0; j--) {
        unichar c = [lineContent characterAtIndex:(NSUInteger)j];
        if (c == ' ' || c == '\t') continue;
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
