/*---------------------------------------------------------------------------------------------
 *  UDJsonKeyHandlerTests.m
 *
 *  Unit tests for UDJsonKeyHandler — JSON-aware editing triggered by typed
 *  characters, Return, Tab, and Backspace.
 *
 *  Strategy
 *  --------
 *  All tests drive the handler through a minimal UDStubCursorsController that
 *  records the selections set on it and applies insertions / deletions to an
 *  NSMutableString so assertions can be made against final document text and
 *  cursor offset.
 *
 *  We use the real tree-sitter JSON parser (tree_sitter_json()) to produce
 *  parse trees so that node-type strings match exactly what production code
 *  sees.
 *
 *  NOTE: The grammar C sources (parser.c, lib.c) are not committed;
 *  run  tree-sitter-json/fetch-deps.sh  before building this target.
 *--------------------------------------------------------------------------------------------*/

#import <XCTest/XCTest.h>
#import <tree_sitter/api.h>
#import "UDJsonKeyHandler.h"
#import <UDPieceTable/UDPieceTable.h>

// ---------------------------------------------------------------------------
// MARK: - Minimal stub cursor controller
// ---------------------------------------------------------------------------

/// Implements the parts of UDCursorsController used by UDJsonKeyHandler so
/// that all handler entry-points can be tested without a live AppKit text view.
///
/// selections are processed in descending start-offset order so edits at
/// higher offsets are applied first and do not invalidate lower offsets.
@interface UDStubCursorsController : UDCursorsController
@property (nonatomic, readonly)  NSMutableString    *text;
@property (nonatomic, strong)    NSArray<NSValue *> *selections;
- (instancetype)initWithText:(NSMutableString *)text;
@end

@implementation UDStubCursorsController {
    NSMutableString    *_text;
    NSArray<NSValue *> *_mySelections;
}

@synthesize selections = _mySelections;

- (instancetype)initWithText:(NSMutableString *)text {
    UDTextModel *dummy = [[UDTextModel alloc] initWithText:@""];
    self = [super initWithModel:dummy];
    if (!self) return nil;
    _text = [text mutableCopy];
    _mySelections = @[];
    return self;
}

- (NSMutableString *)text { return _text; }

- (void)typeText:(NSString *)insertText source:(NSString *)source {
    NSUInteger count = _mySelections.count;
    if (count == 0) return;

    NSMutableArray<NSNumber *> *indices = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger i = 0; i < count; i++) [indices addObject:@(i)];

    // Apply edits in descending start-offset order so earlier offsets stay valid.
    [indices sortUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) {
        UDSelection sa = [_mySelections[[a unsignedIntegerValue]] ud_selectionValue];
        UDSelection sb = [_mySelections[[b unsignedIntegerValue]] ud_selectionValue];
        NSInteger oa = [self _offsetForLine:sa.selectionStartLineNumber column:sa.selectionStartColumn];
        NSInteger ob = [self _offsetForLine:sb.selectionStartLineNumber column:sb.selectionStartColumn];
        return ob - oa; // descending
    }];

    NSMutableDictionary<NSNumber *, NSValue *> *afterByIdx =
        [NSMutableDictionary dictionaryWithCapacity:count];

    for (NSNumber *idxNum in indices) {
        NSUInteger idx = [idxNum unsignedIntegerValue];
        UDSelection sel = [_mySelections[idx] ud_selectionValue];
        NSInteger start = [self _offsetForLine:sel.selectionStartLineNumber
                                        column:sel.selectionStartColumn];
        NSInteger end   = [self _offsetForLine:sel.positionLineNumber
                                        column:sel.positionColumn];
        if (start > end) { NSInteger tmp = start; start = end; end = tmp; }
        NSRange range = NSMakeRange((NSUInteger)start, (NSUInteger)(end - start));
        [_text replaceCharactersInRange:range withString:insertText];
        NSUInteger newOffset = (NSUInteger)start + insertText.length;
        UDPosition p = [self _positionForOffset:newOffset];
        afterByIdx[idxNum] = [NSValue ud_valueWithSelection:
                              UDSelectionFromPosition(p.line, p.column)];
    }

    NSMutableArray *after = [NSMutableArray arrayWithCapacity:count];
    for (NSUInteger i = 0; i < count; i++) [after addObject:afterByIdx[@(i)]];
    _mySelections = [after copy];
}

/// Naive 1-based line/column → 0-based character offset inside _text.
- (NSInteger)_offsetForLine:(NSInteger)line column:(NSInteger)column {
    NSArray<NSString *> *lines = [_text componentsSeparatedByString:@"\n"];
    NSInteger off = 0;
    for (NSInteger i = 1; i < line && i < (NSInteger)lines.count; i++)
        off += (NSInteger)[lines[(NSUInteger)(i - 1)] length] + 1;
    return off + column - 1;
}

/// Naive 0-based offset → 1-based UDPosition inside _text.
- (UDPosition)_positionForOffset:(NSUInteger)offset {
    NSInteger line = 1, col = 1;
    for (NSUInteger i = 0; i < offset && i < _text.length; i++) {
        if ([_text characterAtIndex:i] == '\n') { line++; col = 1; }
        else col++;
    }
    return (UDPosition){ .line = line, .column = col };
}

@end

// ---------------------------------------------------------------------------
// MARK: - Tree-sitter JSON parse helper
// ---------------------------------------------------------------------------

extern const TSLanguage *tree_sitter_json(void);

/// Parses `text` with the JSON grammar (UTF-16 LE encoding) and returns a
/// TSTree. The caller must call ts_tree_delete() when done.
static TSTree *ParseJSON(NSString *text) {
    TSParser *parser = ts_parser_new();
    ts_parser_set_language(parser, tree_sitter_json());
    NSData *utf16 = [text dataUsingEncoding:NSUTF16LittleEndianStringEncoding];
    TSTree *tree = ts_parser_parse_string_encoding(
        parser, NULL,
        (const char *)utf16.bytes, (uint32_t)utf16.length,
        TSInputEncodingUTF16LE);
    ts_parser_delete(parser);
    return tree;
}

// ---------------------------------------------------------------------------
// MARK: - Test class
// ---------------------------------------------------------------------------

@interface UDJsonKeyHandlerTests : XCTestCase
@property (nonatomic, strong) UDJsonKeyHandler *handler;
@end

@implementation UDJsonKeyHandlerTests

- (void)setUp {
    [super setUp];
    _handler = [[UDJsonKeyHandler alloc] init];
}

// ---------------------------------------------------------------------------
// MARK: - Test helpers
// ---------------------------------------------------------------------------

/// Returns the 0-based cursor offset from a stub controller's first selection.
- (NSInteger)_cursorOffsetFromCtrl:(UDStubCursorsController *)ctrl {
    if (ctrl.selections.count == 0) return -1;
    UDSelection s = [ctrl.selections.firstObject ud_selectionValue];
    // Walk the stub's final text to convert 1-based line/column to 0-based offset.
    NSArray<NSString *> *lines = [ctrl.text componentsSeparatedByString:@"\n"];
    NSInteger off = 0;
    for (NSInteger i = 1; i < s.positionLineNumber && i < (NSInteger)lines.count; i++)
        off += (NSInteger)[lines[(NSUInteger)(i - 1)] length] + 1;
    return off + s.positionColumn - 1;
}

/// Build a stub for `doc` with cursor at `offset`, run handleTypedCharacter:
/// and return whether the handler consumed the event.
- (BOOL)_handlerConsumedChar:(NSString *)ch
                  inDocument:(NSString *)doc
                cursorOffset:(NSUInteger)offset {
    TSTree *tree = ParseJSON(doc);
    UDTextModel *model = [[UDTextModel alloc] initWithText:doc];
    NSMutableString *mutable = [doc mutableCopy];
    UDStubCursorsController *ctrl = [[UDStubCursorsController alloc] initWithText:mutable];
    UDPosition pos = [model getPositionAt:(NSInteger)offset];
    ctrl.selections = @[[NSValue ud_valueWithSelection:
                         UDSelectionFromPosition(pos.line, pos.column)]];
    BOOL consumed = [_handler handleTypedCharacter:ch
                                         parseTree:tree
                                         textModel:model
                                 cursorsController:ctrl];
    ts_tree_delete(tree);
    return consumed;
}

/// Drive handleTypedCharacter:… and assert resulting text and cursor.
/// Pass NSUIntegerMax for expectedCursor to skip the cursor assertion.
- (void)_assertTyping:(NSString *)ch
           inDocument:(NSString *)doc
         cursorOffset:(NSUInteger)offset
         producesText:(NSString *)expectedText
             cursorAt:(NSUInteger)expectedCursor {
    TSTree *tree = ParseJSON(doc);
    UDTextModel *model = [[UDTextModel alloc] initWithText:doc];
    NSMutableString *mutable = [doc mutableCopy];
    UDStubCursorsController *ctrl = [[UDStubCursorsController alloc] initWithText:mutable];
    UDPosition pos = [model getPositionAt:(NSInteger)offset];
    ctrl.selections = @[[NSValue ud_valueWithSelection:
                         UDSelectionFromPosition(pos.line, pos.column)]];
    [_handler handleTypedCharacter:ch
                         parseTree:tree
                         textModel:model
                 cursorsController:ctrl];
    ts_tree_delete(tree);
    XCTAssertEqualObjects(ctrl.text, expectedText);
    if (expectedCursor != NSUIntegerMax && ctrl.selections.count > 0) {
        XCTAssertEqual((NSUInteger)[self _cursorOffsetFromCtrl:ctrl], expectedCursor);
    }
}

/// Drive handleReturnKeyWithParseTree:… and assert resulting text.
- (void)_assertReturn:(NSString *)doc
         cursorOffset:(NSUInteger)offset
         producesText:(NSString *)expectedText {
    TSTree *tree = ParseJSON(doc);
    UDTextModel *model = [[UDTextModel alloc] initWithText:doc];
    NSMutableString *mutable = [doc mutableCopy];
    UDStubCursorsController *ctrl = [[UDStubCursorsController alloc] initWithText:mutable];
    UDPosition pos = [model getPositionAt:(NSInteger)offset];
    ctrl.selections = @[[NSValue ud_valueWithSelection:
                         UDSelectionFromPosition(pos.line, pos.column)]];
    [_handler handleReturnKeyWithParseTree:tree textModel:model cursorsController:ctrl];
    ts_tree_delete(tree);
    XCTAssertEqualObjects(ctrl.text, expectedText);
}

/// Drive handleReturnKeyWithParseTree:… and return whether it was consumed.
- (BOOL)_returnConsumedInDocument:(NSString *)doc cursorOffset:(NSUInteger)offset {
    TSTree *tree = ParseJSON(doc);
    UDTextModel *model = [[UDTextModel alloc] initWithText:doc];
    NSMutableString *mutable = [doc mutableCopy];
    UDStubCursorsController *ctrl = [[UDStubCursorsController alloc] initWithText:mutable];
    UDPosition pos = [model getPositionAt:(NSInteger)offset];
    ctrl.selections = @[[NSValue ud_valueWithSelection:
                         UDSelectionFromPosition(pos.line, pos.column)]];
    BOOL consumed = [_handler handleReturnKeyWithParseTree:tree
                                               textModel:model
                                       cursorsController:ctrl];
    ts_tree_delete(tree);
    return consumed;
}

/// Drive handleTabKeyWithParseTree:… and assert resulting text and cursor.
- (void)_assertTab:(NSString *)doc
      cursorOffset:(NSUInteger)offset
      producesText:(NSString *)expectedText
          cursorAt:(NSUInteger)expectedCursor {
    TSTree *tree = ParseJSON(doc);
    UDTextModel *model = [[UDTextModel alloc] initWithText:doc];
    NSMutableString *mutable = [doc mutableCopy];
    UDStubCursorsController *ctrl = [[UDStubCursorsController alloc] initWithText:mutable];
    UDPosition pos = [model getPositionAt:(NSInteger)offset];
    ctrl.selections = @[[NSValue ud_valueWithSelection:
                         UDSelectionFromPosition(pos.line, pos.column)]];
    [_handler handleTabKeyWithParseTree:tree textModel:model cursorsController:ctrl];
    ts_tree_delete(tree);
    XCTAssertEqualObjects(ctrl.text, expectedText);
    if (expectedCursor != NSUIntegerMax && ctrl.selections.count > 0) {
        XCTAssertEqual((NSUInteger)[self _cursorOffsetFromCtrl:ctrl], expectedCursor);
    }
}

/// Drive handleTabKeyWithParseTree:… and return whether it was consumed.
- (BOOL)_tabConsumedInDocument:(NSString *)doc cursorOffset:(NSUInteger)offset {
    TSTree *tree = ParseJSON(doc);
    UDTextModel *model = [[UDTextModel alloc] initWithText:doc];
    NSMutableString *mutable = [doc mutableCopy];
    UDStubCursorsController *ctrl = [[UDStubCursorsController alloc] initWithText:mutable];
    UDPosition pos = [model getPositionAt:(NSInteger)offset];
    ctrl.selections = @[[NSValue ud_valueWithSelection:
                         UDSelectionFromPosition(pos.line, pos.column)]];
    BOOL consumed = [_handler handleTabKeyWithParseTree:tree
                                             textModel:model
                                     cursorsController:ctrl];
    ts_tree_delete(tree);
    return consumed;
}

/// Drive handleDeleteRange:… and assert resulting text.
- (void)_assertDelete:(NSRange)deleteRange
           inDocument:(NSString *)doc
         producesText:(NSString *)expectedText {
    TSTree *tree = ParseJSON(doc);
    UDTextModel *model = [[UDTextModel alloc] initWithText:doc];
    NSMutableString *mutable = [doc mutableCopy];
    UDStubCursorsController *ctrl = [[UDStubCursorsController alloc] initWithText:mutable];
    UDPosition pos = [model getPositionAt:(NSInteger)deleteRange.location];
    ctrl.selections = @[[NSValue ud_valueWithSelection:
                         UDSelectionFromPosition(pos.line, pos.column)]];
    [_handler handleDeleteRange:deleteRange
                      parseTree:tree
                      textModel:model
              cursorsController:ctrl];
    ts_tree_delete(tree);
    XCTAssertEqualObjects(ctrl.text, expectedText);
}

// ===========================================================================
// MARK: 1. `"` typed — skip-over
// ===========================================================================
// The handler should advance the cursor past an existing closing `"` and
// return YES without inserting a second `"` into the document.
//
// Layout of  {"key": ""}  (0-based offsets):
//   0:{ 1:" 2:k 3:e 4:y 5:" 6:: 7:  8:" 9:" 10:}
//
// The empty string value has opening `"` at 8 and closing `"` at 9.
// Cursor at offset 9 = immediately before the closing `"` at index 9.

- (void)testQuote_skipOver_inObjectValue {
    [self _assertTyping:@"\"" inDocument:@"{\"key\": \"\"}"
           cursorOffset:9          // before the closing '"' of the empty value
           producesText:@"{\"key\": \"\"}"  // text unchanged
               cursorAt:10];       // cursor advanced past the '"'
}

- (void)testQuote_skipOver_emptyStringInArray {
    // [""] — cursor at 2 (before closing '"'), text unchanged, cursor at 3.
    [self _assertTyping:@"\"" inDocument:@"[\"\"]"
           cursorOffset:2
           producesText:@"[\"\"]"
               cursorAt:3];
}

- (void)testQuote_noSkipOver_noPairPresent {
    // `[` — no closing '"' to the right; handler returns NO.
    BOOL consumed = [self _handlerConsumedChar:@"\"" inDocument:@"[" cursorOffset:1];
    XCTAssertFalse(consumed);
}

- (void)testQuote_noSkipOver_differentCharAhead {
    // `{"key": 1}` — char at offset 8 is `1`, not `"`. Handler returns NO.
    BOOL consumed = [self _handlerConsumedChar:@"\"" inDocument:@"{\"key\": 1}" cursorOffset:8];
    XCTAssertFalse(consumed);
}

// ===========================================================================
// MARK: 2. `"` typed — auto-colon after object key
// ===========================================================================
// After skipping over the closing `"` of an object key string that has no `:`
// following it, the handler must insert `: ` and advance the cursor after it.
//
// Layout of  {"key"  (0-based offsets):
//   0:{ 1:" 2:k 3:e 4:y 5:"
//
// Cursor at offset 5 = before the closing `"` at index 5.
// After skip-over the cursor is at 6 (end-of-doc); no `:` follows → insert `: `.

- (void)testQuote_autoColon_afterObjectKey {
    [self _assertTyping:@"\"" inDocument:@"{\"key\""
           cursorOffset:5          // before the closing '"' of key
           producesText:@"{\"key\": "  // ': ' appended
               cursorAt:8];        // past the inserted ': '
}

- (void)testQuote_autoColon_secondPropertyKey {
    // {"a": 1, "b"  — "b" at offsets 9-11, cursor at 11 (before closing '"').
    // After skip-over cursor is at 12 (end-of-doc); no ':' follows → insert ': '.
    [self _assertTyping:@"\"" inDocument:@"{\"a\": 1, \"b\""
           cursorOffset:11
           producesText:@"{\"a\": 1, \"b\": "
               cursorAt:14];
}

- (void)testQuote_noAutoColon_insideValue_string {
    // {"key": "val"  — cursor at 12 (before the closing '"' of "val").
    // "val" is a pair *value*, not a bare key → no colon inserted.
    // Layout: 0:{ 1:" 2:k 3:e 4:y 5:" 6:: 7:  8:" 9:v 10:a 11:l 12:"
    [self _assertTyping:@"\"" inDocument:@"{\"key\": \"val\""
           cursorOffset:12         // before closing '"' of "val"
           producesText:@"{\"key\": \"val\""  // text unchanged
               cursorAt:13];       // cursor advanced past '"'
}

- (void)testQuote_noAutoColon_inArray {
    // ["item"  — string in an array is not an object key → no colon.
    // Layout: 0:[ 1:" 2:i 3:t 4:e 5:m 6:"
    [self _assertTyping:@"\"" inDocument:@"[\"item\""
           cursorOffset:6          // before closing '"' of "item"
           producesText:@"[\"item\""  // text unchanged
               cursorAt:7];        // cursor advanced
}

// ===========================================================================
// MARK: 3. `{` typed — trailing comma
// ===========================================================================
// When typing `{` at a position immediately before another JSON value (number,
// string, array, etc.) inside an array or object, the handler inserts `{},`
// and positions the cursor between the braces.

- (void)testOpenBrace_trailingComma_beforeStringInArray {
    // ["second"]  — cursor at 1 (before the first '"').
    // Typing '{' should insert '{}, ' making ["{},"second"].
    // Layout: 0:[ 1:" 2:s 3:e 4:c 5:o 6:n 7:d 8:" 9:]
    [self _assertTyping:@"{" inDocument:@"[\"second\"]"
           cursorOffset:1
           producesText:@"[{},\"second\"]"
               cursorAt:2];    // cursor between '{' and '}'
}

- (void)testOpenBrace_noTrailingComma_atEndOfArray {
    // [] — cursor at 1 (inside empty array). No value follows → NO.
    BOOL consumed = [self _handlerConsumedChar:@"{" inDocument:@"[]" cursorOffset:1];
    XCTAssertFalse(consumed);
}

- (void)testOpenBrace_noTrailingComma_beforeClosingBracket {
    // ["a"]  — cursor at 4 (after '"a"', before ']'). No comma needed.
    BOOL consumed = [self _handlerConsumedChar:@"{" inDocument:@"[\"a\"]" cursorOffset:4];
    XCTAssertFalse(consumed);
}

// ===========================================================================
// MARK: 4. `[` typed — trailing comma
// ===========================================================================

- (void)testOpenBracket_trailingComma_beforeNumberInArray {
    // [42]  — cursor at 1 (before '4'). Typing '[' → [[],42].
    [self _assertTyping:@"[" inDocument:@"[42]"
           cursorOffset:1
           producesText:@"[[],42]"
               cursorAt:2];    // cursor between '[' and ']'
}

- (void)testOpenBracket_noTrailingComma_atEnd {
    // [] empty — no following value, no comma needed.
    BOOL consumed = [self _handlerConsumedChar:@"[" inDocument:@"[]" cursorOffset:1];
    XCTAssertFalse(consumed);
}

// ===========================================================================
// MARK: 5. Return key — comma + newline when not the last element
// ===========================================================================
// The handler inserts `,\n` (+ current line's indentation) when the cursor is
// at the end of a JSON value and the next non-whitespace token on the same
// line is another value rather than `}`, `]`, `,`, or a line ending.

- (void)testReturn_insertCommaNewline_afterStringValue_notLast {
    // {"a": "val" "b": 2}  — cursor at offset 11 (after the closing '"' of "val").
    // Layout: 0:{ 1:" 2:a 3:" 4:: 5:  6:" 7:v 8:a 9:l 10:" 11:  12:" ...
    // Next non-whitespace at 12 is '"' (start of "b"), not a terminator.
    // Insert ',\n' at offset 11; the existing space before "b" is preserved.
    [self _assertReturn:@"{\"a\": \"val\" \"b\": 2}"
           cursorOffset:11
           producesText:@"{\"a\": \"val\",\n \"b\": 2}"];
}

- (void)testReturn_insertCommaNewline_afterNumberInArray {
    // [1 2]  — cursor at offset 2 (after '1').
    // Next non-whitespace at 3 is '2', not a terminator → insert ',\n'.
    [self _assertReturn:@"[1 2]"
           cursorOffset:2
           producesText:@"[1,\n 2]"];
}

- (void)testReturn_noComma_lastElement {
    // [42]  — cursor at 3 (after '42', before ']'). Last element → NO.
    BOOL consumed = [self _returnConsumedInDocument:@"[42]" cursorOffset:3];
    XCTAssertFalse(consumed);
}

- (void)testReturn_noComma_alreadyHasComma {
    // {"a": 1, "b": 2}  — cursor at 7 (after '1'); ',' follows → NO.
    // Layout: 0:{ 1:" 2:a 3:" 4:: 5:  6:1 7:, ...
    BOOL consumed = [self _returnConsumedInDocument:@"{\"a\": 1, \"b\": 2}" cursorOffset:7];
    XCTAssertFalse(consumed);
}

- (void)testReturn_noComma_nilParseTree {
    // Without a parse tree the handler cannot determine context → NO.
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"[1]"];
    NSMutableString *mutable = [@"[1]" mutableCopy];
    UDStubCursorsController *ctrl = [[UDStubCursorsController alloc] initWithText:mutable];
    UDPosition pos = [model getPositionAt:2];
    ctrl.selections = @[[NSValue ud_valueWithSelection:
                         UDSelectionFromPosition(pos.line, pos.column)]];
    BOOL consumed = NO;
    XCTAssertNoThrow(consumed = [_handler handleReturnKeyWithParseTree:nil
                                                            textModel:model
                                                    cursorsController:ctrl]);
    XCTAssertFalse(consumed);
}

// ===========================================================================
// MARK: 6. Tab key — auto-colon after object property key
// ===========================================================================
// When the cursor is right after the closing `"` of an object key string
// that has no `:` following it, Tab inserts `: ` and advances the cursor.

- (void)testTab_insertColon_afterObjectKey {
    // {"name"  — cursor at 7 (past the closing '"').
    // Layout: 0:{ 1:" 2:n 3:a 4:m 5:e 6:" — length 7.
    [self _assertTab:@"{\"name\"" cursorOffset:7
        producesText:@"{\"name\": "
            cursorAt:9];    // 7 + 2 for ': '
}

- (void)testTab_insertColon_secondKey {
    // {"a": 1, "b"  — cursor at 12 (past closing '"' of "b").
    [self _assertTab:@"{\"a\": 1, \"b\"" cursorOffset:12
        producesText:@"{\"a\": 1, \"b\": "
            cursorAt:14];
}

- (void)testTab_noColon_afterObjectValue {
    // {"k": "v"  — cursor at 9, just past '"v"'. Not a key position → NO.
    BOOL consumed = [self _tabConsumedInDocument:@"{\"k\": \"v\"" cursorOffset:9];
    XCTAssertFalse(consumed);
}

- (void)testTab_noColon_alreadyHasColon {
    // {"name": value  — cursor at 7 (right after the key's '"'). The key already
    // has a colon in the pair → NO.
    BOOL consumed = [self _tabConsumedInDocument:@"{\"name\": " cursorOffset:7];
    XCTAssertFalse(consumed);
}

- (void)testTab_noColon_nilParseTree {
    // Without a parse tree the handler cannot determine context → NO.
    BOOL consumed = NO;
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"{\"k\""];
    NSMutableString *mutable = [@"{\"k\"" mutableCopy];
    UDStubCursorsController *ctrl = [[UDStubCursorsController alloc] initWithText:mutable];
    UDPosition pos = [model getPositionAt:4];
    ctrl.selections = @[[NSValue ud_valueWithSelection:
                         UDSelectionFromPosition(pos.line, pos.column)]];
    XCTAssertNoThrow(consumed = [_handler handleTabKeyWithParseTree:nil
                                                        textModel:model
                                                cursorsController:ctrl]);
    XCTAssertFalse(consumed);
}

// ===========================================================================
// MARK: 7. Delete — remove preceding comma when deleting the last element
// ===========================================================================
// When the deletion range covers the *last* element / property in an array or
// object (i.e., the next non-whitespace char after the range is `}` or `]`)
// and the character immediately before the range (skipping whitespace) is `,`,
// the handler extends the deletion to also remove that `,`.

- (void)testDelete_removePrecedingComma_lastElementInArray {
    // [1, 2]  — delete range covers '2' at offset 4 (length 1).
    // '2' is the last element; ',' precedes it at offset 2 → delete ', 2'.
    // Layout: 0:[ 1:1 2:, 3:  4:2 5:]
    [self _assertDelete:NSMakeRange(4, 1) inDocument:@"[1, 2]"
           producesText:@"[1]"];
}

- (void)testDelete_removePrecedingComma_lastPropertyInObject {
    // {"a": 1, "b": 2}  — delete range covers '"b": 2' (offset 9, length 6).
    // It is the last property; ',' precedes it → delete ', "b": 2'.
    // Layout: 0:{ 1:" 2:a 3:" 4:: 5:  6:1 7:, 8:  9:" 10:b 11:" 12:: 13:  14:2 15:}
    [self _assertDelete:NSMakeRange(9, 6) inDocument:@"{\"a\": 1, \"b\": 2}"
           producesText:@"{\"a\": 1}"];
}

- (void)testDelete_noPrecedingCommaRemoval_notLastElement {
    // [1, 2, 3]  — delete '1' at offset 1. '1' is NOT the last element → NO.
    // The ctrl.text remains unchanged.
    [self _assertDelete:NSMakeRange(1, 1) inDocument:@"[1, 2, 3]"
           producesText:@"[1, 2, 3]"];
}

- (void)testDelete_noPrecedingCommaRemoval_noPrecedingComma {
    // [42]  — delete '42' (offset 1, length 2). Only element; no ',' before it → NO.
    [self _assertDelete:NSMakeRange(1, 2) inDocument:@"[42]"
           producesText:@"[42]"];
}

- (void)testDelete_noPrecedingCommaRemoval_zeroLength {
    // Zero-length delete range is always a no-op.
    [self _assertDelete:NSMakeRange(3, 0) inDocument:@"[1, 2]"
           producesText:@"[1, 2]"];
}

// ===========================================================================
// MARK: 8. No-crash edge cases
// ===========================================================================

- (void)testNocrash_typedCharacter_atBoundaryCursor {
    // Cursor at offset 0 in a valid document — should not crash.
    TSTree *tree = ParseJSON(@"{}");
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"{}"];
    NSMutableString *mutable = [@"{}" mutableCopy];
    UDStubCursorsController *ctrl = [[UDStubCursorsController alloc] initWithText:mutable];
    ctrl.selections = @[[NSValue ud_valueWithSelection:UDSelectionFromPosition(1, 1)]];
    XCTAssertNoThrow([_handler handleTypedCharacter:@"\""
                                          parseTree:tree
                                          textModel:model
                                  cursorsController:ctrl]);
    ts_tree_delete(tree);
}

- (void)testNocrash_zeroLengthDelete {
    TSTree *tree = ParseJSON(@"[1, 2]");
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"[1, 2]"];
    NSMutableString *mutable = [@"[1, 2]" mutableCopy];
    UDStubCursorsController *ctrl = [[UDStubCursorsController alloc] initWithText:mutable];
    ctrl.selections = @[[NSValue ud_valueWithSelection:UDSelectionFromPosition(1, 1)]];
    XCTAssertNoThrow([_handler handleDeleteRange:NSMakeRange(0, 0)
                                       parseTree:tree
                                       textModel:model
                               cursorsController:ctrl]);
    ts_tree_delete(tree);
    XCTAssertEqualObjects(ctrl.text, @"[1, 2]");
}

@end
