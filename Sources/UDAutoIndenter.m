/*---------------------------------------------------------------------------------------------
 *  UDAutoIndenter.m
 *--------------------------------------------------------------------------------------------*/

#import "UDAutoIndenter.h"
#import "UDLanguageKeyHandler.h"
#import <tree_sitter/api.h>
#import <string.h>

// Tree-sitter stores byte offsets in UTF-16 (2 bytes per BMP code unit).
static inline uint32_t byteFromChar(NSUInteger c) { return (uint32_t)(c * 2); }

// ---------------------------------------------------------------------------
// Physical key codes (hardware layout — independent of locale)
// ---------------------------------------------------------------------------

static const unsigned short kKeyCodeReturn        = 36;
static const unsigned short kKeyCodeKeypadReturn  = 76;
static const unsigned short kKeyCodeTab           = 48;
static const unsigned short kKeyCodeBackspace     = 51;   // ⌫
static const unsigned short kKeyCodeForwardDelete = 117;  // fn+⌫ or dedicated Del key

// macOS function-key characters (arrow keys, F1–F20, Home, End, …) are encoded
// in the Unicode private-use range starting at 0xF700 (NSFunctionKeyMask area).
// These must not be treated as printable text input.
static const unichar kFunctionKeyRangeStart = 0xF700;

// ---------------------------------------------------------------------------

@interface UDAutoIndenter ()
@property (nonatomic, weak)   UDTreeSitterHighlighter *highlighter;
// Compiled tree-sitter query for @indent captures and a dedicated cursor.
@property (nonatomic, assign) TSQuery                 *tsIndentQuery;
@property (nonatomic, assign) TSQueryCursor           *tsQueryCursor;
@end

@implementation UDAutoIndenter

// ---------------------------------------------------------------------------
// MARK: - Init / dealloc
// ---------------------------------------------------------------------------

- (instancetype)initWithHighlighter:(nullable UDTreeSitterHighlighter *)highlighter
                           textView:(NSTextView *)textView
                          textModel:(UDTextModel *)textModel
                  cursorsController:(nonnull UDCursorsController *)cursorsController {
    self = [super init];
    if (!self) return nil;
    _highlighter = highlighter;
    _textView = textView;
    _textModel = textModel;
    _cursorsController = cursorsController;
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
// MARK: - Unified key event dispatch
// ---------------------------------------------------------------------------

- (BOOL)handleKeyEvent:(NSEvent *)event {
    if (!_textModel) return NO;

    NSEventModifierFlags mods =
        event.modifierFlags & (NSEventModifierFlagCommand |
                               NSEventModifierFlagControl |
                               NSEventModifierFlagOption  |
                               NSEventModifierFlagShift);

    // --- Return / KP-Return: smart indentation ---
    if (mods == 0 &&
            (event.keyCode == kKeyCodeReturn ||
             event.keyCode == kKeyCodeKeypadReturn)) {
        return [self handleReturnKey];
    }

    // --- Shift-Tab: dedent ---
    if (mods == NSEventModifierFlagShift && event.keyCode == kKeyCodeTab) {
        return [self handleShiftTabKey];
    }

    // --- Delete key: give the language handler a chance to mirror the deletion
    //     BEFORE NSTextView applies it (e.g. XML tag-name synchronisation). ---
    if (mods == 0 && (event.keyCode == kKeyCodeBackspace ||
                      event.keyCode == kKeyCodeForwardDelete)) {
        id<UDLanguageKeyHandler> handler = _languageKeyHandler;
        if ([handler respondsToSelector:
             @selector(handleDeleteRange:parseTree:textModel:cursorsController:)]) {
            NSRange   sel    = _textView.selectedRange;
            NSInteger docLen = [_textModel getLength];
            NSRange   delRange = NSMakeRange(0, 0);
            BOOL      valid  = NO;
            if (sel.length > 0) {
                delRange = sel;
                valid    = YES;
            } else if (event.keyCode == kKeyCodeBackspace && sel.location > 0) {
                delRange = NSMakeRange(sel.location - 1, 1);
                valid    = YES;
            } else if (event.keyCode == kKeyCodeForwardDelete &&
                       (NSInteger)sel.location < docLen) {
                delRange = NSMakeRange(sel.location, 1);
                valid    = YES;
            }
            if (valid) {
                return [handler handleDeleteRange:delRange
                                        parseTree:_highlighter.currentParseTree
                                        textModel:_textModel
                                cursorsController:_cursorsController];
            }
        }
    }

    // --- Single printable character: electric-pair + language handler ---
    // Permit Shift (needed for characters like '{' on many keyboards).
    // Exclude Command, Control, Option so that shortcuts are unaffected.
    if (!(mods & (NSEventModifierFlagCommand |
                  NSEventModifierFlagControl |
                  NSEventModifierFlagOption))) {
        NSString *chars = event.characters;
        if (chars.length == 1) {
            unichar ch = [chars characterAtIndex:0];
            // Only handle visible, non-control, non-delete, non-function-key characters.
            // Arrow keys and other function keys have code points in 0xF700–0xF8FF
            // (NSFunctionKeyMask area) and must not be treated as typed text.
            if (ch >= ' ' && ch != 0x7f && ch < kFunctionKeyRangeStart) {
                return [self handleTypedCharacter:chars];
            }
        }
    }

    return NO;
}

// ---------------------------------------------------------------------------
// MARK: - Return key (smart indentation)
// ---------------------------------------------------------------------------

- (BOOL)handleReturnKey {
    if (!_textView || !_textModel) return NO;

    NSRange   sel    = _textView.selectedRange;
    NSInteger docLen = [_textModel getLength];

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
                               ? [_textModel getCharacterAtOffset:afterPos] : 0;
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
    [_textView insertText:insertText replacementRange:sel];

    if (split) {
        // insertText:replacementRange: leaves the cursor at the very end of
        // the inserted text (after <lineIndent>).  Move it back to the middle
        // line, right after <newIndent>.
        NSUInteger newCursorPos = cursorPos + 1 + newIndent.length;
        [_textView setSelectedRange:NSMakeRange(newCursorPos, 0)];
    }

    return YES;
}

// ---------------------------------------------------------------------------
// MARK: - Shift-Tab (dedent)
// ---------------------------------------------------------------------------

- (BOOL)handleShiftTabKey {
    if (!_textView || !_textModel) return NO;

    NSRange   sel    = _textView.selectedRange;
    NSInteger docLen = [_textModel getLength];
    if (docLen == 0) return NO;

    // ------------------------------------------------------------------
    // 1. Determine the range of lines to de-indent.
    // ------------------------------------------------------------------
    UDPosition startPos  = [_textModel getPositionAt:(NSInteger)sel.location];
    NSInteger  startLine = startPos.line;

    NSInteger endLine;
    if (sel.length == 0) {
        endLine = startLine;
    } else {
        NSUInteger endOffset = sel.location + sel.length;
        UDPosition endPos    = [_textModel getPositionAt:(NSInteger)endOffset];
        // If the selection ends exactly at column 1 of a new line, don't
        // include that line — it has no visible characters selected.
        endLine = (endPos.column == 1 && endPos.line > startLine)
            ? endPos.line - 1
            : endPos.line;
    }

    // ------------------------------------------------------------------
    // 2. Collect (lineStartOffset, stripLen) pairs for each affected line.
    // ------------------------------------------------------------------
    NSInteger numLines = endLine - startLine + 1;
    NSMutableArray<NSNumber *> *lineStartOffsets = [NSMutableArray arrayWithCapacity:(NSUInteger)numLines];
    NSMutableArray<NSNumber *> *stripLens        = [NSMutableArray arrayWithCapacity:(NSUInteger)numLines];

    for (NSInteger line = startLine; line <= endLine; line++) {
        NSString  *content   = [_textModel getLineContent:line];
        NSInteger  strip     = [self _stripLengthForLine:content];
        NSInteger  lineStart = [_textModel getOffsetAt:line column:1];
        [lineStartOffsets addObject:@(lineStart)];
        [stripLens        addObject:@(strip)];
    }

    NSInteger totalStripped = 0;
    for (NSNumber *n in stripLens) totalStripped += n.integerValue;

    // Consume the event even when there is nothing to strip.
    if (totalStripped == 0) return YES;

    // ------------------------------------------------------------------
    // 3. Apply deletions from last line to first so that earlier character
    //    offsets remain valid after each individual edit.
    // ------------------------------------------------------------------
    for (NSInteger i = numLines - 1; i >= 0; i--) {
        NSInteger strip     = [stripLens[(NSUInteger)i] integerValue];
        if (strip == 0) continue;
        NSInteger lineStart = [lineStartOffsets[(NSUInteger)i] integerValue];
        NSRange   delRange  = NSMakeRange((NSUInteger)lineStart, (NSUInteger)strip);
        [_textView insertText:@"" replacementRange:delRange];
    }

    // ------------------------------------------------------------------
    // 4. Restore the selection, adjusted for the removed characters.
    // ------------------------------------------------------------------
    NSInteger firstStripped    = [stripLens[0] integerValue];
    NSInteger lineStartOffset  = [lineStartOffsets[0] integerValue];
    NSInteger rawNewStart      = (NSInteger)sel.location - firstStripped;
    NSUInteger newSelStart     = (NSUInteger)MAX(rawNewStart, lineStartOffset);

    if (sel.length == 0) {
        [_textView setSelectedRange:NSMakeRange(newSelStart, 0)];
    } else {
        NSInteger newEnd = (NSInteger)(sel.location + sel.length) - totalStripped;
        if (newEnd < (NSInteger)newSelStart) newEnd = (NSInteger)newSelStart;
        [_textView setSelectedRange:NSMakeRange(newSelStart,
                                        (NSUInteger)(newEnd - (NSInteger)newSelStart))];
    }

    return YES;
}

// ---------------------------------------------------------------------------
// MARK: - Electric-pair insertion
// ---------------------------------------------------------------------------

- (BOOL)handleTypedCharacter:(NSString *)chars {
    UDTextModel         *model = _textModel;
    UDCursorsController *ctrl  = _cursorsController;
    if (!model || !ctrl) return NO;

    id<UDLanguageKeyHandler> handler = _languageKeyHandler;
    if (!handler || ![handler respondsToSelector:
            @selector(handleTypedCharacter:parseTree:textModel:cursorsController:)])
        return NO;

    return [handler handleTypedCharacter:chars
                               parseTree:_highlighter.currentParseTree
                               textModel:model
                       cursorsController:ctrl];
}

- (BOOL)handleDeleteRange:(NSRange)deleteRange {
    UDTextModel         *model = _textModel;
    UDCursorsController *ctrl  = _cursorsController;
    if (!model || !ctrl) return NO;

    id<UDLanguageKeyHandler> handler = _languageKeyHandler;
    if (!handler || ![handler respondsToSelector:
            @selector(handleDeleteRange:parseTree:textModel:cursorsController:)])
        return NO;

    return [handler handleDeleteRange:deleteRange
                            parseTree:_highlighter.currentParseTree
                            textModel:model
                    cursorsController:ctrl];
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

/// Returns how many characters should be stripped from the leading whitespace
/// of @c lineContent to remove one indentation level.
- (NSInteger)_stripLengthForLine:(NSString *)lineContent {
    if (lineContent.length == 0) return 0;
    unichar first = [lineContent characterAtIndex:0];

    if (first == '\t') return 1;

    if (first == ' ') {
        NSUInteger maxStrip   = _indentUnit.length;
        NSInteger  spaceCount = 0;
        for (NSUInteger i = 0; i < lineContent.length && i < maxStrip; i++) {
            if ([lineContent characterAtIndex:i] == ' ') spaceCount++;
            else break;
        }
        return spaceCount;
    }

    return 0;
}

/// Returns the leading-whitespace prefix of the line that contains @c offset.
- (NSString *)_indentOfLineContaining:(NSUInteger)offset {
    if (!_textModel) return @"";

    UDPosition pos = [_textModel getPositionAt:(NSInteger)offset];
    NSString  *lineContent = [_textModel getLineContent:pos.line];

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
/// or 0 if none is found.
- (unichar)_lastNonSpaceCharBefore:(NSUInteger)offset {
    if (!_textModel || offset == 0) return 0;

    UDPosition pos = [_textModel getPositionAt:(NSInteger)offset];
    NSString  *lineContent = [_textModel getLineContent:pos.line];

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

            uint32_t    nameLen = 0;
            const char *capName =
                ts_query_capture_name_for_id(_tsIndentQuery, cap.index, &nameLen);
            if (nameLen != 6 || strncmp(capName, "indent", 6) != 0) continue;

            uint32_t ns = ts_node_start_byte(cap.node);
            uint32_t ne = ts_node_end_byte(cap.node);

            if (ns < byte && byte < ne) return YES;
        }
    }
    return NO;
}

@end
