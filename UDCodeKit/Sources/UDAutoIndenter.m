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

// Keys are told by the characters they type, not their key codes: those are
// the Mac keyboard's, and an X server's differ (its quote key is the Mac's
// Tab, its backslash the Mac's Delete).
/// Whether a tree-sitter node's type is one of @a kinds, as a language
/// configuration names them ("string", "comment", after VS Code's): C's
/// "string_literal" is a string, Rust's "line_comment" a comment.
static BOOL UDNodeTypeIsOneOf(const char *type, NSArray<NSString *> *kinds) {
    NSString *name = @(type);
    for (NSString *kind in kinds) {
        if ([name rangeOfString:kind].location != NSNotFound) return YES;
    }
    return NO;
}

static unichar UDKeyCharacter(NSEvent *event) {
    NSString *keys = event.charactersIgnoringModifiers;
    return keys.length ? [keys characterAtIndex:0] : 0;
}
static BOOL UDIsReturnKey(unichar c)        { return c == '\r' || c == '\n' || c == 0x03; }   // 0x03: the keypad's Enter
static BOOL UDIsTabKey(unichar c)           { return c == '\t'; }
static BOOL UDIsBackTabKey(unichar c)       { return c == 0x19; }
static BOOL UDIsBackspaceKey(unichar c)     { return c == 0x7f || c == 0x08; }
static BOOL UDIsForwardDeleteKey(unichar c) { return c == NSDeleteFunctionKey; }

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
- (BOOL)_handleElectricPairForChar:(NSString *)chars
                             model:(UDTextModel *)model
                              ctrl:(UDCursorsController *)ctrl;
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
    unichar key = UDKeyCharacter(event);
    if (mods == 0 && UDIsReturnKey(key)) {
        // Give the language handler first crack.
        id<UDLanguageKeyHandler> retHandler = _languageKeyHandler;
        if ([retHandler respondsToSelector:
                @selector(handleReturnKeyWithParseTree:textModel:cursorsController:)]) {
            BOOL consumed = [retHandler handleReturnKeyWithParseTree:_highlighter.currentParseTree
                                                          textModel:_textModel
                                                  cursorsController:_cursorsController];
            if (consumed) {
                [self _syncTextViewCursor];
                return YES;
            }
        }
        return [self handleReturnKey];
    }

    // --- Tab (no modifiers): give language handler first crack, else default insert ---
    if (mods == 0 && UDIsTabKey(key)) {
        id<UDLanguageKeyHandler> tabHandler = _languageKeyHandler;
        if ([tabHandler respondsToSelector:
                @selector(handleTabKeyWithParseTree:textModel:cursorsController:)]) {
            BOOL consumed = [tabHandler handleTabKeyWithParseTree:_highlighter.currentParseTree
                                                       textModel:_textModel
                                               cursorsController:_cursorsController];
            if (consumed) {
                [self _syncTextViewCursor];
                return YES;
            }
        }
        // Fall through to NSTextView default tab handling.
        return NO;
    }

    // --- Shift-Tab: dedent ---
    if ((mods == NSEventModifierFlagShift && UDIsTabKey(key)) || ((mods & ~NSEventModifierFlagShift) == 0 && UDIsBackTabKey(key))) {
        id<UDLanguageKeyHandler> stHandler = _languageKeyHandler;
        if ([stHandler respondsToSelector:
                @selector(handleShiftTabKeyWithParseTree:textModel:cursorsController:)]) {
            BOOL consumed = [stHandler handleShiftTabKeyWithParseTree:_highlighter.currentParseTree
                                                           textModel:_textModel
                                                   cursorsController:_cursorsController];
            if (consumed) {
                [self _syncTextViewCursor];
                return YES;
            }
        }
        return [self handleShiftTabKey];
    }

    // --- Delete key: give the language handler a chance to mirror the deletion
    //     BEFORE NSTextView applies it (e.g. XML tag-name synchronisation). ---
    if (mods == 0 && (UDIsBackspaceKey(key) || UDIsForwardDeleteKey(key))) {
        NSRange   sel    = _textView.selectedRange;
        NSInteger docLen = [_textModel getLength];
        NSRange   delRange = NSMakeRange(0, 0);
        BOOL      valid  = NO;
        if (sel.length > 0) {
            delRange = sel;
            valid    = YES;
        } else if (UDIsBackspaceKey(key) && sel.location > 0) {
            delRange = NSMakeRange(sel.location - 1, 1);
            valid    = YES;
        } else if (UDIsForwardDeleteKey(key) &&
                   (NSInteger)sel.location < docLen) {
            delRange = NSMakeRange(sel.location, 1);
            valid    = YES;
        }
        if (valid) {
            return [self handleDeleteRange:delRange];
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
// MARK: - Cursor sync helper
// ---------------------------------------------------------------------------

/// Pushes the controller's primary selection back into NSTextView.
/// Call this after any edit that moves the cursor through the controller.
- (void)_syncTextViewCursor {
    if (_cursorsController.selections.count == 0) return;
    UDSelection s = [_cursorsController.selections.firstObject ud_selectionValue];
    NSUInteger offset = (NSUInteger)[_textModel getOffsetAt:s.positionLineNumber
                                                     column:s.positionColumn];
    NSUInteger safe = MIN(offset, (NSUInteger)[_textModel getLength]);
    [_textView setSelectedRange:NSMakeRange(safe, 0)];
}

// ---------------------------------------------------------------------------
// MARK: - Return key (smart indentation)
// ---------------------------------------------------------------------------

- (BOOL)handleReturnKey {
    if (!_textModel || !_cursorsController) return NO;

    NSInteger docLen = [_textModel getLength];
    if (docLen == 0) return NO;

    // Read cursor position from the controller.
    UDSelection primarySel = [_cursorsController.selections.firstObject ud_selectionValue];
    NSUInteger cursorPos = (NSUInteger)[_textModel getOffsetAt:primarySel.positionLineNumber
                                                        column:primarySel.positionColumn];

    // ------------------------------------------------------------------
    // 1. Indentation of the current line.
    // ------------------------------------------------------------------
    NSString *lineIndent = [self _indentOfLineContaining:cursorPos];

    // ------------------------------------------------------------------
    // 2. Does the cursor immediately follow an indent-opening bracket?
    // ------------------------------------------------------------------
    unichar charBefore = [self _lastNonSpaceCharBefore:cursorPos];

    NSString *openChars  = nil;
    NSString *closeChars = nil;
    UDLanguageConfiguration *config = _languageConfiguration;
    if (config.brackets.count) {
        openChars  = [config openBracketCharacters];
        closeChars = [config closeBracketCharacters];
    }
    if (!openChars.length)  openChars  = @"{[";
    if (!closeChars.length) closeChars = @"}]";

    BOOL isOpenBracket  = charBefore != 0
        && ([openChars rangeOfString:[NSString stringWithCharacters:&charBefore length:1]].location != NSNotFound);
    BOOL increaseIndent = isOpenBracket && [self _isInsideIndentNodeAtOffset:cursorPos];
    NSString *newIndent = increaseIndent
        ? [lineIndent stringByAppendingString:_indentUnit]
        : lineIndent;

    // ------------------------------------------------------------------
    // 3. Electric-pair split.
    // ------------------------------------------------------------------
    unichar charAfter = ((NSUInteger)docLen > cursorPos)
        ? [_textModel getCharacterAtOffset:cursorPos] : 0;
    BOOL isCloseBracket = charAfter != 0
        && ([closeChars rangeOfString:[NSString stringWithCharacters:&charAfter length:1]].location != NSNotFound);
    BOOL split = increaseIndent && isCloseBracket;

    // ------------------------------------------------------------------
    // 4. Insert via the controller so the edit is attributed correctly.
    // ------------------------------------------------------------------
    NSString *insertText = split
        ? [NSString stringWithFormat:@"\n%@\n%@", newIndent, lineIndent]
        : [NSString stringWithFormat:@"\n%@",     newIndent];

    [_cursorsController typeText:insertText source:@"indent"];

    // For a split, the controller leaves the cursor at the very end of the
    // inserted text (after <lineIndent>). Move it back to the middle line,
    // right after <newIndent>.
    if (split) {
        NSUInteger newCursorPos = cursorPos + 1 + newIndent.length;
        UDPosition newPos = [_textModel getPositionAt:(NSInteger)newCursorPos];
        _cursorsController.selections = @[
            [NSValue ud_valueWithSelection:
                UDSelectionFromPosition(newPos.line, newPos.column)]
        ];
    }

    [self _syncTextViewCursor];
    return YES;
}

// ---------------------------------------------------------------------------
// MARK: - Shift-Tab (dedent)
// ---------------------------------------------------------------------------

- (BOOL)handleShiftTabKey {
    if (!_textModel || !_cursorsController) return NO;

    NSInteger docLen = [_textModel getLength];
    if (docLen == 0) return NO;

    // Read selection from the controller.
    UDSelection primarySel = [_cursorsController.selections.firstObject ud_selectionValue];
    NSUInteger selStart = (NSUInteger)[_textModel getOffsetAt:primarySel.selectionStartLineNumber
                                                       column:primarySel.selectionStartColumn];
    NSUInteger selEnd   = (NSUInteger)[_textModel getOffsetAt:primarySel.positionLineNumber
                                                       column:primarySel.positionColumn];
    if (selStart > selEnd) { NSUInteger tmp = selStart; selStart = selEnd; selEnd = tmp; }

    // ------------------------------------------------------------------
    // 1. Determine the range of lines to de-indent.
    // ------------------------------------------------------------------
    UDPosition startPos  = [_textModel getPositionAt:(NSInteger)selStart];
    NSInteger  startLine = startPos.line;

    NSInteger endLine;
    if (selStart == selEnd) {
        endLine = startLine;
    } else {
        UDPosition endPos = [_textModel getPositionAt:(NSInteger)selEnd];
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

    if (totalStripped == 0) return YES;

    // ------------------------------------------------------------------
    // 3. Apply deletions last-to-first through the controller.
    //    Each deletion is a collapsed selection at the strip range,
    //    replaced with empty text.
    // ------------------------------------------------------------------
    for (NSInteger i = numLines - 1; i >= 0; i--) {
        NSInteger strip     = [stripLens[(NSUInteger)i] integerValue];
        if (strip == 0) continue;
        NSInteger lineStart = [lineStartOffsets[(NSUInteger)i] integerValue];

        UDPosition ps = [_textModel getPositionAt:lineStart];
        UDPosition pe = [_textModel getPositionAt:lineStart + strip];
        _cursorsController.selections = @[
            [NSValue ud_valueWithSelection:
                UDSelectionMake(ps.line, ps.column, pe.line, pe.column)]
        ];
        [_cursorsController typeText:@"" source:@"dedent"];
    }

    // ------------------------------------------------------------------
    // 4. Restore selection adjusted for removed characters.
    // ------------------------------------------------------------------
    NSInteger firstStripped   = [stripLens[0] integerValue];
    NSInteger lineStartOffset = [lineStartOffsets[0] integerValue];
    NSInteger rawNewStart     = (NSInteger)selStart - firstStripped;
    NSUInteger newSelStart    = (NSUInteger)MAX(rawNewStart, lineStartOffset);

    if (selStart == selEnd) {
        UDPosition p = [_textModel getPositionAt:(NSInteger)newSelStart];
        _cursorsController.selections = @[
            [NSValue ud_valueWithSelection:UDSelectionFromPosition(p.line, p.column)]
        ];
    } else {
        NSInteger newEnd = (NSInteger)selEnd - totalStripped;
        if (newEnd < (NSInteger)newSelStart) newEnd = (NSInteger)newSelStart;
        UDPosition ps = [_textModel getPositionAt:(NSInteger)newSelStart];
        UDPosition pe = [_textModel getPositionAt:newEnd];
        _cursorsController.selections = @[
            [NSValue ud_valueWithSelection:
                UDSelectionMake(ps.line, ps.column, pe.line, pe.column)]
        ];
    }

    [self _syncTextViewCursor];
    return YES;
}

// ---------------------------------------------------------------------------
// MARK: - Electric-pair insertion
// ---------------------------------------------------------------------------

- (BOOL)handleTypedCharacter:(NSString *)chars {
    UDTextModel         *model = _textModel;
    UDCursorsController *ctrl  = _cursorsController;
    if (!model || !ctrl) return NO;

    // 1. Give the language handler first crack: it can override the default
    //    electric-pair behaviour (e.g. XML mode handles ">" and "/" itself).
    id<UDLanguageKeyHandler> handler = _languageKeyHandler;
    if ([handler respondsToSelector:
            @selector(handleTypedCharacter:parseTree:textModel:cursorsController:)]) {
        BOOL consumed = [handler handleTypedCharacter:chars
                                           parseTree:_highlighter.currentParseTree
                                           textModel:model
                                   cursorsController:ctrl];
        if (consumed) {
            [self _syncTextViewCursor];
            return YES;
        }
    }

    // 2. Built-in electric-pair logic driven by languageConfiguration.
    return [self _handleElectricPairForChar:chars model:model ctrl:ctrl];
}

/// Implements the default electric-pair insertion and skip-over behaviour
/// based on languageConfiguration.autoClosingPairs.
///
/// Called only when the language handler (if any) did NOT consume the event.
- (BOOL)_handleElectricPairForChar:(NSString *)chars
                             model:(UDTextModel *)model
                              ctrl:(UDCursorsController *)ctrl {
    if (chars.length != 1) return NO;

    UDLanguageConfiguration *config = _languageConfiguration;
    if (!config.autoClosingPairs.count) return NO;

    if (ctrl.selections.count == 0) return NO;
    UDSelection primarySel = [ctrl.selections.firstObject ud_selectionValue];

    unichar   typedChar = [chars characterAtIndex:0];
    NSInteger docLen    = [model getLength];

    // Convert the primary cursor position to a character offset.
    NSUInteger cursorPos = (NSUInteger)[model getOffsetAt:primarySel.positionLineNumber
                                                   column:primarySel.positionColumn];

    // ------------------------------------------------------------------
    // 1. Skip-over (asymmetric pairs only): if the typed close-bracket
    //    already sits immediately to the right of an empty cursor, advance
    //    the cursor without inserting.
    // ------------------------------------------------------------------
    if (UDSelectionIsEmpty(primarySel) && cursorPos < (NSUInteger)docLen) {
        for (UDAutoClosingPair *pair in config.autoClosingPairs) {
            // A quote, when the next character is the one that closes the
            // string the caret is in ("Reload|" -> "Reload"|), not one that
            // opens another (|"abc").
            BOOL closesString = [pair.open isEqualToString:pair.close] && pair.notIn.count > 0
                && [self _offset:cursorPos closesNodeOfTypes:pair.notIn];
            if (pair.close.length == 1
                    && [pair.close characterAtIndex:0] == typedChar
                    && (![pair.open isEqualToString:pair.close] || closesString)) {
                if ([model getCharacterAtOffset:cursorPos] == typedChar) {
                    NSUInteger newOffset = cursorPos + 1;
                    UDPosition newPos = [model getPositionAt:(NSInteger)newOffset];
                    ctrl.selections = @[
                        [NSValue ud_valueWithSelection:
                            UDSelectionFromPosition(newPos.line, newPos.column)]
                    ];
                    [self _syncTextViewCursor];
                    return YES;
                }
            }
        }
    }

    // ------------------------------------------------------------------
    // 2. Auto-close: if the typed char is an open-bracket and there is no
    //    selection, insert open+close and place the cursor between them.
    // ------------------------------------------------------------------
    if (!UDSelectionIsEmpty(primarySel)) return NO;

    for (UDAutoClosingPair *pair in config.autoClosingPairs) {
        if (pair.open.length != 1) continue;
        if ([pair.open characterAtIndex:0] != typedChar) continue;

        // autoCloseBefore: the character to the right of the cursor must be
        // in this set (or absent at end-of-document) for auto-close to fire.
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

        // A quote that closes the string open on its line goes in alone
        // ("Reload| -> "Reload"|): an unclosed string is no string node yet.
        if ([pair.open isEqualToString:pair.close]
                && [self _lineHasOpenQuote:typedChar beforeOffset:cursorPos]) {
            return NO;
        }

        // notIn: suppress auto-close when inside a restricted node type.
        if (pair.notIn.count > 0
                && [self _cursorAtOffset:cursorPos isInsideNodeTypes:pair.notIn]) {
            return NO;
        }

        // Insert the pair and position the cursor between open and close.
        NSString *insert = [NSString stringWithFormat:@"%@%@", pair.open, pair.close];
        [ctrl typeText:insert source:@"autoclose"];
        // ctrl.typeText: leaves the cursor after the close char.
        // Rewind it to between open and close.
        NSUInteger afterOpenOffset = cursorPos + pair.open.length;
        UDPosition afterOpenPos = [model getPositionAt:(NSInteger)afterOpenOffset];
        ctrl.selections = @[
            [NSValue ud_valueWithSelection:
                UDSelectionFromPosition(afterOpenPos.line, afterOpenPos.column)]
        ];
        [self _syncTextViewCursor];
        return YES;
    }

    return NO;
}

- (BOOL)handleDeleteRange:(NSRange)deleteRange {
    UDTextModel         *model = _textModel;
    UDCursorsController *ctrl  = _cursorsController;
    if (!model || !ctrl) return NO;

    id<UDLanguageKeyHandler> handler = _languageKeyHandler;
    if (!handler || ![handler respondsToSelector:
            @selector(handleDeleteRange:parseTree:textModel:cursorsController:)])
        return NO;

    BOOL consumed = [handler handleDeleteRange:deleteRange
                                     parseTree:_highlighter.currentParseTree
                                     textModel:model
                             cursorsController:ctrl];

    if (consumed) {
        [self _syncTextViewCursor];
    }

    return consumed;
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
            if (UDNodeTypeIsOneOf(rawType, nodeTypes)) return YES;
        }
        node = ts_node_parent(node);
    }
    return NO;
}

// ---------------------------------------------------------------------------
// MARK: - Private helpers (auto-indentation)
// ---------------------------------------------------------------------------

/// Whether the character at @a offset is the last of a node of one of
/// @a nodeTypes holding it: the closing quote of a string, say.
- (BOOL)_offset:(NSUInteger)offset closesNodeOfTypes:(NSArray<NSString *> *)nodeTypes {
    const TSTree *tree = (const TSTree *)_highlighter.currentParseTree;
    if (!nodeTypes.count) return NO;
    if (!tree) {
        // No parse: the quote closes when its string is open on the line.
        return [self _lineHasOpenQuote:[_textModel getCharacterAtOffset:offset] beforeOffset:offset];
    }
    uint32_t byte = byteFromChar(offset);
    TSNode node = ts_node_descendant_for_byte_range(ts_tree_root_node((TSTree *)tree), byte, byte);
    while (!ts_node_is_null(node)) {
        const char *type = ts_node_type(node);
        if (type && UDNodeTypeIsOneOf(type, nodeTypes)) {
            return ts_node_start_byte(node) < byte && ts_node_end_byte(node) == byteFromChar(offset + 1);
        }
        node = ts_node_parent(node);
    }
    return NO;
}

/// Whether the line has an odd number of (unescaped) @a quote before
/// @a offset: a string it opened is still open there.
- (BOOL)_lineHasOpenQuote:(unichar)quote beforeOffset:(NSUInteger)offset {
    UDPosition p = [_textModel getPositionAt:(NSInteger)offset];
    NSUInteger lineStart = (NSUInteger)[_textModel getOffsetAt:p.line column:1], count = 0;
    for (NSUInteger i = lineStart; i < offset; i++) {
        unichar c = [_textModel getCharacterAtOffset:i];
        if (c == '\\') { i++; continue; }
        if (c == quote) count++;
    }
    return count % 2 == 1;
}

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
