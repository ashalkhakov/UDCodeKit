/*---------------------------------------------------------------------------------------------
 *  UDJsonKeyHandler.m
 *--------------------------------------------------------------------------------------------*/

#import "UDJsonKeyHandler.h"
#import <tree_sitter/api.h>
#include <string.h>

// Tree-sitter uses UTF-16 encoding: 2 bytes per BMP code unit.
static inline uint32_t _charToByte(NSUInteger c) { return (uint32_t)(c * 2); }
static inline NSUInteger _byteToChar(uint32_t b)  { return (NSUInteger)(b / 2); }

/// Returns YES when the tree-sitter node type name represents a JSON value.
static BOOL _isJSONValueType(const char *type) {
    if (!type) return NO;
    return strcmp(type, "string")  == 0
        || strcmp(type, "number")  == 0
        || strcmp(type, "object")  == 0
        || strcmp(type, "array")   == 0
        || strcmp(type, "true")    == 0
        || strcmp(type, "false")   == 0
        || strcmp(type, "null")    == 0;
}

/// Returns YES when c could be the first character of a JSON value.
static BOOL _isJSONValueStart(unichar c) {
    return c == '"'
        || c == '{'
        || c == '['
        || (c >= '0' && c <= '9')
        || c == '-'
        || c == 't'  // true
        || c == 'f'  // false
        || c == 'n'; // null
}

// ---------------------------------------------------------------------------

@implementation UDJsonKeyHandler

+ (instancetype)sharedHandler {
    static UDJsonKeyHandler *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[UDJsonKeyHandler alloc] init]; });
    return instance;
}

// ---------------------------------------------------------------------------
// MARK: - handleTypedCharacter:
// ---------------------------------------------------------------------------

- (BOOL)handleTypedCharacter:(NSString *)chars
                   parseTree:(nullable const void *)parseTree
                   textModel:(UDTextModel *)model
           cursorsController:(UDCursorsController *)ctrl {
    if (chars.length != 1) return NO;
    if (ctrl.selections.count == 0) return NO;

    UDSelection primary = [ctrl.selections.firstObject ud_selectionValue];
    if (!UDSelectionIsEmpty(primary)) return NO;

    NSUInteger cursorPos = (NSUInteger)[model getOffsetAt:primary.positionLineNumber
                                                   column:primary.positionColumn];
    NSInteger docLen = [model getLength];
    unichar ch = [chars characterAtIndex:0];

    if (ch == '"') {
        return [self _handleQuote:parseTree model:model ctrl:ctrl
                           cursor:cursorPos docLen:docLen];
    }

    if (ch == '{' || ch == '[') {
        return [self _handleOpenBracket:ch parseTree:parseTree model:model ctrl:ctrl
                                 cursor:cursorPos docLen:docLen];
    }

    if (ch == 't' || ch == 'f' || ch == 'n') {
        return [self _handleBooleanLiteral:ch parseTree:parseTree model:model ctrl:ctrl
                                    cursor:cursorPos docLen:docLen];
    }

    return NO;
}

// ---------------------------------------------------------------------------
// MARK: - handleReturnKeyWithParseTree:
// ---------------------------------------------------------------------------

- (BOOL)handleReturnKeyWithParseTree:(nullable const void *)parseTree
                           textModel:(UDTextModel *)model
                   cursorsController:(UDCursorsController *)ctrl {
    if (!parseTree) return NO;
    if (ctrl.selections.count == 0) return NO;

    UDSelection primary = [ctrl.selections.firstObject ud_selectionValue];
    if (!UDSelectionIsEmpty(primary)) return NO;

    NSUInteger cursorPos = (NSUInteger)[model getOffsetAt:primary.positionLineNumber
                                                   column:primary.positionColumn];
    NSInteger docLen = [model getLength];

    // Cursor must be at the end of a JSON value.
    const TSTree *tree = (const TSTree *)parseTree;
    if (![self _cursorIsAtEndOfValue:cursorPos tree:tree]) return NO;

    // Scan forward (skipping horizontal whitespace on the same line) to find
    // the next non-space, non-tab character.
    NSUInteger scanPos = cursorPos;
    while ((NSInteger)scanPos < docLen) {
        unichar c = [model getCharacterAtOffset:scanPos];
        if (c == ' ' || c == '\t') { scanPos++; } else { break; }
    }
    unichar afterValue = ((NSInteger)scanPos < docLen)
        ? [model getCharacterAtOffset:scanPos] : 0;

    // If followed by `,` (already has comma), `}`, `]`, or EOL/EOF: no comma.
    if (afterValue == ','  || afterValue == '}'  ||
        afterValue == ']'  || afterValue == '\n' ||
        afterValue == '\r' || afterValue == 0) {
        return NO; // Let base handle the newline.
    }

    // Insert `,\n` + current line's leading whitespace.
    NSString *indent = [self _indentOfLineContaining:cursorPos model:model];
    NSString *insertText = [NSString stringWithFormat:@",\n%@", indent];
    [ctrl typeText:insertText source:@"autocomma"];
    return YES;
}

// ---------------------------------------------------------------------------
// MARK: - handleTabKeyWithParseTree:
// ---------------------------------------------------------------------------

- (BOOL)handleTabKeyWithParseTree:(nullable const void *)parseTree
                        textModel:(UDTextModel *)model
                cursorsController:(UDCursorsController *)ctrl {
    if (!parseTree) return NO;
    if (ctrl.selections.count == 0) return NO;

    UDSelection primary = [ctrl.selections.firstObject ud_selectionValue];
    if (!UDSelectionIsEmpty(primary)) return NO;

    NSUInteger cursorPos = (NSUInteger)[model getOffsetAt:primary.positionLineNumber
                                                   column:primary.positionColumn];

    const TSTree *tree = (const TSTree *)parseTree;
    if (![self _cursorIsAfterObjectKey:cursorPos tree:tree model:model]) return NO;

    [ctrl typeText:@": " source:@"autocolon"];
    return YES;
}

// ---------------------------------------------------------------------------
// MARK: - handleShiftTabKeyWithParseTree:
// ---------------------------------------------------------------------------

- (BOOL)handleShiftTabKeyWithParseTree:(nullable const void *)parseTree
                             textModel:(UDTextModel *)model
                     cursorsController:(UDCursorsController *)ctrl {
    // No JSON-specific shift-tab behaviour; let the base de-indent handle it.
    return NO;
}

// ---------------------------------------------------------------------------
// MARK: - handleDeleteRange:
// ---------------------------------------------------------------------------

- (BOOL)handleDeleteRange:(NSRange)deleteRange
                parseTree:(nullable const void *)parseTree
                textModel:(UDTextModel *)model
        cursorsController:(UDCursorsController *)ctrl {
    if (deleteRange.length == 0) return NO;

    NSInteger docLen = [model getLength];
    NSUInteger start = deleteRange.location;
    NSUInteger end   = deleteRange.location + deleteRange.length;
    if ((NSInteger)end > docLen) return NO;

    // Whole-word deletion for JSON keyword literals (true / false / null).
    // When a partial delete (e.g. a single backspace) falls inside a keyword
    // literal, expand the range to delete the entire word in one keystroke.
    if (parseTree) {
        const TSTree *tree = (const TSTree *)parseTree;
        uint32_t byte = _charToByte(start);
        TSNode node = ts_node_descendant_for_byte_range(ts_tree_root_node(tree), byte, byte);
        while (!ts_node_is_null(node)) {
            const char *t = ts_node_type(node);
            if (!t) break;
            if (strcmp(t, "true") == 0 || strcmp(t, "false") == 0 || strcmp(t, "null") == 0) {
                NSUInteger nodeStart = _byteToChar(ts_node_start_byte(node));
                NSUInteger nodeEnd   = _byteToChar(ts_node_end_byte(node));
                // Only expand when deleteRange is a strict subset of the literal
                // (i.e. the user pressed backspace/forward-delete inside the word).
                // A range already covering the full literal falls through to the
                // trailing-comma cleanup below.
                if (deleteRange.length < nodeEnd - nodeStart &&
                    start >= nodeStart && end <= nodeEnd) {
                    UDPosition sp = [model getPositionAt:(NSInteger)nodeStart];
                    UDPosition ep = [model getPositionAt:(NSInteger)nodeEnd];
                    ctrl.selections = @[ [NSValue ud_valueWithSelection:
                                          UDSelectionMake(sp.line, sp.column,
                                                          ep.line, ep.column)] ];
                    [ctrl typeText:@"" source:@"deleteliteral"];
                    return YES;
                }
                break;
            }
            if (strcmp(t, "document") == 0) break;
            node = ts_node_parent(node);
        }
    }

    // Check what follows the deletion range (skip whitespace).
    NSUInteger nextPos = end;
    while ((NSInteger)nextPos < docLen) {
        unichar c = [model getCharacterAtOffset:nextPos];
        if (c == ' ' || c == '\t' || c == '\n' || c == '\r') { nextPos++; } else { break; }
    }
    unichar nextChar = ((NSInteger)nextPos < docLen)
        ? [model getCharacterAtOffset:nextPos] : 0;

    // Only act if this would be the last element / property.
    if (nextChar != '}' && nextChar != ']') return NO;

    // Check what precedes the deletion range (skip whitespace).
    NSUInteger prevPos = start;
    while (prevPos > 0) {
        unichar c = [model getCharacterAtOffset:prevPos - 1];
        if (c == ' ' || c == '\t' || c == '\n' || c == '\r') { prevPos--; } else { break; }
    }
    if (prevPos == 0) return NO;
    if ([model getCharacterAtOffset:prevPos - 1] != ',') return NO;

    // Extend deletion to also remove the `,` + any whitespace between it and deleteRange.
    NSUInteger newStart = prevPos - 1; // position of the `,`

    // Use ctrl typeText:@"" (non-collapsed selection) so both the production
    // model and the test stub's NSMutableString are updated consistently.
    UDPosition sp = [model getPositionAt:(NSInteger)newStart];
    UDPosition ep = [model getPositionAt:(NSInteger)end];
    ctrl.selections = @[ [NSValue ud_valueWithSelection:
                          UDSelectionMake(sp.line, sp.column, ep.line, ep.column)] ];
    [ctrl typeText:@"" source:@"autocomma"];
    return YES;
}

// ---------------------------------------------------------------------------
// MARK: - Private: `"` handler
// ---------------------------------------------------------------------------

- (BOOL)_handleQuote:(nullable const void *)parseTree
               model:(UDTextModel *)model
                ctrl:(UDCursorsController *)ctrl
              cursor:(NSUInteger)cursorPos
              docLen:(NSInteger)docLen {
    // Skip-over: if the character immediately to the right of the cursor is `"`,
    // advance past it (symmetric pairs are not skip-over by the base handler).
    if ((NSInteger)cursorPos >= docLen) return NO;
    if ([model getCharacterAtOffset:cursorPos] != '"') return NO;

    NSUInteger afterSkip = cursorPos + 1;

    // Insert auto-colon if we just closed a property key.
    if ([self _shouldInsertColonAfter:afterSkip model:model parseTree:parseTree]) {
        UDPosition pos = [model getPositionAt:(NSInteger)afterSkip];
        ctrl.selections = @[ [NSValue ud_valueWithSelection:
                               UDSelectionFromPosition(pos.line, pos.column)] ];
        [ctrl typeText:@": " source:@"autocolon"];
    } else {
        // Just advance past the closing `"`.
        UDPosition pos = [model getPositionAt:(NSInteger)afterSkip];
        ctrl.selections = @[ [NSValue ud_valueWithSelection:
                               UDSelectionFromPosition(pos.line, pos.column)] ];
    }
    return YES;
}

// ---------------------------------------------------------------------------
// MARK: - Private: `t` / `f` handler — boolean-literal autocomplete
// ---------------------------------------------------------------------------

- (BOOL)_handleBooleanLiteral:(unichar)ch
                    parseTree:(nullable const void *)parseTree
                        model:(UDTextModel *)model
                         ctrl:(UDCursorsController *)ctrl
                       cursor:(NSUInteger)cursorPos
                       docLen:(NSInteger)docLen {
    if (![self _cursorIsInValuePosition:cursorPos model:model parseTree:parseTree]) return NO;
    NSString *completion = (ch == 't') ? @"true" : (ch == 'f') ? @"false" : @"null";
    [ctrl typeText:completion source:@"autocomplete"];
    return YES;
}

/// Returns YES when `cursorPos` is a JSON value-start position:
///   • right after `:` (object value)
///   • right after `[` (first array element)
///   • right after `,` inside an array (subsequent element)
///   • at offset 0 (root document value)
///
/// Returns NO when the cursor is inside a string node (via tree) or when the
/// preceding context is a comma in an object (next token should be a key).
- (BOOL)_cursorIsInValuePosition:(NSUInteger)cursorPos
                           model:(UDTextModel *)model
                       parseTree:(nullable const void *)parseTree {
    // Cursor inside a string node → not a literal-start position.
    if (parseTree && cursorPos > 0) {
        const TSTree *tree = (const TSTree *)parseTree;
        uint32_t byte = _charToByte(cursorPos - 1);
        TSNode node = ts_node_descendant_for_byte_range(ts_tree_root_node(tree), byte, byte);
        while (!ts_node_is_null(node)) {
            const char *t = ts_node_type(node);
            if (!t) break;
            if (strcmp(t, "string") == 0 || strcmp(t, "string_content") == 0) return NO;
            if (strcmp(t, "document") == 0) break;
            node = ts_node_parent(node);
        }
    }

    // Find the preceding non-whitespace character.
    NSUInteger scanPos = cursorPos;
    while (scanPos > 0) {
        unichar c = [model getCharacterAtOffset:scanPos - 1];
        if (c == ' ' || c == '\t' || c == '\n' || c == '\r') { scanPos--; } else { break; }
    }
    if (scanPos == 0) return YES; // start of document → root value position
    unichar prev = [model getCharacterAtOffset:scanPos - 1];

    if (prev == ':') return YES; // object pair value
    if (prev == '[') return YES; // first array element

    if (prev == ',') {
        // Use the tree to distinguish a comma in an array (value follows)
        // from a comma in an object (key follows).
        if (!parseTree) return YES; // no tree: assume value position
        const TSTree *tree = (const TSTree *)parseTree;
        uint32_t byte = _charToByte(scanPos - 1);
        TSNode node = ts_node_descendant_for_byte_range(ts_tree_root_node(tree), byte, byte);
        while (!ts_node_is_null(node)) {
            const char *t = ts_node_type(node);
            if (!t) break;
            if (strcmp(t, "array") == 0) return YES;
            if (strcmp(t, "object") == 0 || strcmp(t, "pair") == 0) return NO;
            if (strcmp(t, "document") == 0) break;
            node = ts_node_parent(node);
        }
        return NO;
    }

    return NO;
}

// ---------------------------------------------------------------------------
// MARK: - Private: `{` / `[` handler
// ---------------------------------------------------------------------------

- (BOOL)_handleOpenBracket:(unichar)ch
                 parseTree:(nullable const void *)parseTree
                     model:(UDTextModel *)model
                      ctrl:(UDCursorsController *)ctrl
                    cursor:(NSUInteger)cursorPos
                    docLen:(NSInteger)docLen {
    if (![self _needsTrailingCommaAt:cursorPos model:model parseTree:parseTree docLen:docLen]) {
        // No comma needed — let the base electric-pair handle `{}` / `[]`.
        return NO;
    }

    unichar closeChar = (ch == '{') ? '}' : ']';
    NSString *open  = [NSString stringWithCharacters:&ch        length:1];
    NSString *close = [NSString stringWithCharacters:&closeChar length:1];

    // Insert `{},` or `[],`, then place cursor between open and close.
    NSString *insertion = [NSString stringWithFormat:@"%@%@,", open, close];
    [ctrl typeText:insertion source:@"autoclose"];

    NSUInteger betweenOffset = cursorPos + 1; // after the open bracket
    UDPosition betweenPos = [model getPositionAt:(NSInteger)betweenOffset];
    ctrl.selections = @[ [NSValue ud_valueWithSelection:
                           UDSelectionFromPosition(betweenPos.line, betweenPos.column)] ];
    return YES;
}

// ---------------------------------------------------------------------------
// MARK: - Private: auto-colon predicate
// ---------------------------------------------------------------------------

/// Returns YES if a `: ` should be inserted at `afterCloseOffset` (the position
/// just after the closing `"` of a potential key string).
- (BOOL)_shouldInsertColonAfter:(NSUInteger)afterCloseOffset
                          model:(UDTextModel *)model
                      parseTree:(nullable const void *)parseTree {
    NSInteger docLen = [model getLength];

    // Skip horizontal whitespace.
    NSUInteger checkPos = afterCloseOffset;
    while ((NSInteger)checkPos < docLen) {
        unichar c = [model getCharacterAtOffset:checkPos];
        if (c == ' ' || c == '\t') { checkPos++; } else { break; }
    }
    // Already has a colon.
    if ((NSInteger)checkPos < docLen &&
        [model getCharacterAtOffset:checkPos] == ':') return NO;

    // Tree-based check.
    if (parseTree) {
        const TSTree *tree = (const TSTree *)parseTree;
        TSNode root = ts_tree_root_node(tree);

        // afterCloseOffset - 1 is the closing `"`.
        if (afterCloseOffset == 0) return NO;
        uint32_t byte = _charToByte(afterCloseOffset - 1);
        TSNode node = ts_node_descendant_for_byte_range(root, byte, byte);

        while (!ts_node_is_null(node)) {
            const char *type = ts_node_type(node);
            if (!type) break;

            if (strcmp(type, "string") == 0) {
                TSNode parent = ts_node_parent(node);
                if (ts_node_is_null(parent)) return NO;
                const char *pt = ts_node_type(parent);
                if (!pt) return NO;

                if (strcmp(pt, "pair") == 0) {
                    // Key: the first named child of a pair.
                    TSNode key = ts_node_child_by_field_name(parent, "key", 3);
                    if (!ts_node_is_null(key) &&
                        ts_node_start_byte(key) == ts_node_start_byte(node)) {
                        // Key found; colon needed only if the pair is incomplete
                        // (has no value child yet).
                        return ts_node_named_child_count(parent) < 2;
                    }
                } else if (strcmp(pt, "object") == 0) {
                    // Direct child of object — error-recovered unpaired key.
                    return YES;
                }
                return NO;
            }

            if (strcmp(type, "pair") == 0 || strcmp(type, "object") == 0 ||
                strcmp(type, "array") == 0 || strcmp(type, "document") == 0) break;

            node = ts_node_parent(node);
        }
        return NO;
    }

    // Text-based fallback: scan backward to find the opening `"`, then check
    // what precedes it — if it is `{` or `,` (skipping whitespace) we are
    // likely in key position.
    if (afterCloseOffset < 2) return NO;
    NSUInteger scanPos = afterCloseOffset - 2; // char before closing `"`

    while (scanPos > 0) {
        unichar c = [model getCharacterAtOffset:scanPos];
        if (c == '"') break;
        if (c == '\n') return NO; // multi-line: be conservative
        scanPos--;
    }
    if ([model getCharacterAtOffset:scanPos] != '"') return NO;
    if (scanPos == 0) return NO;

    NSUInteger ctxPos = scanPos - 1;
    while (ctxPos > 0) {
        unichar c = [model getCharacterAtOffset:ctxPos];
        if (c == ' ' || c == '\t' || c == '\n' || c == '\r') { ctxPos--; } else { break; }
    }
    unichar ctxChar = [model getCharacterAtOffset:ctxPos];
    return ctxChar == '{' || ctxChar == ',';
}

// ---------------------------------------------------------------------------
// MARK: - Private: trailing-comma predicate
// ---------------------------------------------------------------------------

/// Returns YES when inserting a pair at `cursorPos` would need a trailing `,`
/// (i.e. the cursor is immediately before another JSON value).
- (BOOL)_needsTrailingCommaAt:(NSUInteger)cursorPos
                        model:(UDTextModel *)model
                    parseTree:(nullable const void *)parseTree
                       docLen:(NSInteger)docLen {
    if ((NSInteger)cursorPos >= docLen) return NO;

    // Scan forward, skipping whitespace, to find the next real character.
    NSUInteger pos = cursorPos;
    while ((NSInteger)pos < docLen) {
        unichar c = [model getCharacterAtOffset:pos];
        if (c == ' ' || c == '\t' || c == '\n' || c == '\r') { pos++; } else { break; }
    }
    if ((NSInteger)pos >= docLen) return NO;

    unichar nextChar = [model getCharacterAtOffset:pos];
    if (!_isJSONValueStart(nextChar)) return NO;

    // Use tree to confirm the next value's parent is an array or object.
    if (parseTree) {
        const TSTree *tree = (const TSTree *)parseTree;
        TSNode root = ts_tree_root_node(tree);
        uint32_t byte = _charToByte(pos);
        TSNode node = ts_node_descendant_for_byte_range(root, byte, byte);
        if (ts_node_is_null(node)) return NO;
        TSNode parent = ts_node_parent(node);
        if (ts_node_is_null(parent)) return NO;
        const char *pt = ts_node_type(parent);
        return pt && (strcmp(pt, "array") == 0 || strcmp(pt, "object") == 0);
    }

    return YES; // Without tree, trust the value-start check.
}

// ---------------------------------------------------------------------------
// MARK: - Private: cursor-at-end-of-value
// ---------------------------------------------------------------------------

/// Returns YES when the cursor is positioned exactly at the end of a JSON value
/// node according to the parse tree.
- (BOOL)_cursorIsAtEndOfValue:(NSUInteger)cursorPos
                         tree:(const TSTree *)tree {
    if (cursorPos == 0) return NO;
    uint32_t byte = _charToByte(cursorPos - 1);
    TSNode node = ts_node_descendant_for_byte_range(ts_tree_root_node(tree), byte, byte);
    while (!ts_node_is_null(node)) {
        if (_byteToChar(ts_node_end_byte(node)) == cursorPos &&
            _isJSONValueType(ts_node_type(node))) {
            return YES;
        }
        node = ts_node_parent(node);
    }
    return NO;
}

// ---------------------------------------------------------------------------
// MARK: - Private: cursor-after-object-key
// ---------------------------------------------------------------------------

/// Returns YES when the cursor is right after a property key string inside an
/// object, meaning a `: ` would make the document progress toward validity.
- (BOOL)_cursorIsAfterObjectKey:(NSUInteger)cursorPos
                           tree:(const TSTree *)tree
                          model:(UDTextModel *)model {
    if (cursorPos == 0) return NO;
    uint32_t byte = _charToByte(cursorPos - 1);
    TSNode node = ts_node_descendant_for_byte_range(ts_tree_root_node(tree), byte, byte);

    while (!ts_node_is_null(node)) {
        const char *type = ts_node_type(node);
        if (!type) break;

        if (strcmp(type, "string") == 0) {
            // Must end exactly at cursorPos.
            if (_byteToChar(ts_node_end_byte(node)) != cursorPos) {
                node = ts_node_parent(node);
                continue;
            }
            TSNode parent = ts_node_parent(node);
            if (ts_node_is_null(parent)) return NO;
            const char *pt = ts_node_type(parent);
            if (!pt) return NO;

            if (strcmp(pt, "pair") == 0) {
                TSNode key = ts_node_child_by_field_name(parent, "key", 3);
                return !ts_node_is_null(key) &&
                       ts_node_start_byte(key) == ts_node_start_byte(node);
            }
            if (strcmp(pt, "object") == 0 || strcmp(pt, "ERROR") == 0) return YES; // error-recovered key
            return NO;
        }

        if (strcmp(type, "pair") == 0 || strcmp(type, "object") == 0 ||
            strcmp(type, "array") == 0 || strcmp(type, "document") == 0) break;

        node = ts_node_parent(node);
    }
    return NO;
}

// ---------------------------------------------------------------------------
// MARK: - Private: indentation helper
// ---------------------------------------------------------------------------

/// Returns the leading whitespace of the line that contains `offset`.
- (NSString *)_indentOfLineContaining:(NSUInteger)offset model:(UDTextModel *)model {
    UDPosition pos = [model getPositionAt:(NSInteger)offset];
    NSString *lineContent = [model getLineContent:pos.line];
    NSUInteger indentLen = 0;
    while (indentLen < lineContent.length) {
        unichar c = [lineContent characterAtIndex:indentLen];
        if (c == ' ' || c == '\t') { indentLen++; } else { break; }
    }
    return [lineContent substringToIndex:indentLen];
}

@end
