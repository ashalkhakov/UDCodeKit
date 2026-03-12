/*---------------------------------------------------------------------------------------------
 *  UDAutoIndenterTests.m
 *
 *  Unit tests for UDAutoIndenter covering:
 *    • handleReturnKey — indent computation, open-bracket indent increase,
 *      electric-pair split, custom bracket config, custom indent unit.
 *    • handleTypedCharacter: — auto-close insertion, skip-over, autoCloseBefore
 *      suppression, no-op when no config or selection is present.
 *
 *  Test setup mirrors UDTextEditorViewController.viewDidLoad: a real NSTextView
 *  is created and its layout manager is re-wired to a UDTextModelTextStorage so
 *  that insertText:replacementRange: goes through the normal NSTextStorage →
 *  UDTextModel pipeline.  All objects are held by local ARC variables in each
 *  test method so the weak references inside UDAutoIndenter stay live.
 *--------------------------------------------------------------------------------------------*/

#import <XCTest/XCTest.h>
#import "UDAutoIndenter.h"
#import "UDTextModelTextStorage.h"
#import "UDLanguageConfiguration.h"
#import <UDPieceTable/UDPieceTable.h>

// ---------------------------------------------------------------------------
// MARK: - Helpers
// ---------------------------------------------------------------------------

static UDLanguageConfiguration *UDConfigWithPairs(NSArray *pairs) {
    return [UDLanguageConfiguration configurationFromDictionary:
            @{ @"autoClosingPairs": pairs }];
}

static UDLanguageConfiguration *UDConfigWithPairsAndBefore(NSArray *pairs,
                                                            NSString *autoCloseBefore) {
    return [UDLanguageConfiguration configurationFromDictionary:@{
        @"autoClosingPairs": pairs,
        @"autoCloseBefore":  autoCloseBefore,
    }];
}

// ---------------------------------------------------------------------------

@interface UDAutoIndenterTests : XCTestCase
@end

@implementation UDAutoIndenterTests

// ---------------------------------------------------------------------------
// MARK: - Test helper
// ---------------------------------------------------------------------------

/// Creates a (UDAutoIndenter, NSTextView, UDTextModelTextStorage) triple for
/// the given text and cursor offset.  Out-parameters keep the objects alive
/// for the full body of the calling test method.
///
/// The wiring replicates UDTextEditorViewController.viewDidLoad:
///   1. Create UDTextModelTextStorage with the desired text.
///   2. Remove the text view's default layout manager from the default
///      NSTextStorage and add it to the custom storage instead.
///   3. Set the initial cursor position.
- (UDAutoIndenter *)_indenterWithText:(NSString *)text
                               cursor:(NSUInteger)offset
                              storage:(__strong UDTextModelTextStorage **)storageOut
                             textView:(__strong NSTextView **)tvOut {
    UDTextModelTextStorage *storage =
        [[UDTextModelTextStorage alloc] initWithText:text];

    NSTextView *tv =
        [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 500, 400)];

    // Re-wire the layout manager (same as UDTextEditorViewController).
    NSLayoutManager *lm = tv.layoutManager;
    [[lm textStorage] removeLayoutManager:lm];
    [storage addLayoutManager:lm];

    [tv setSelectedRange:NSMakeRange(offset, 0)];

    if (storageOut) *storageOut = storage;
    if (tvOut)      *tvOut      = tv;

    return [[UDAutoIndenter alloc] initWithTextView:tv
                                         highlighter:nil
                                           textModel:storage.textModel];
}

// ---------------------------------------------------------------------------
// MARK: - handleReturnKey
// ---------------------------------------------------------------------------

/// Empty document: the method must return NO and leave the model unchanged.
- (void)testReturnKey_emptyDocument_returnsNO {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    UDAutoIndenter *ind =
        [self _indenterWithText:@"" cursor:0 storage:&storage textView:&tv];
    XCTAssertFalse([ind handleReturnKey]);
    XCTAssertEqualObjects([storage.textModel getValue], @"",
                          @"Empty document must not be modified");
    (void)tv;
}

/// Plain text with leading whitespace: Return copies the indent of the
/// current line (no bracket, no increase).
- (void)testReturnKey_plainLine_copiesIndent {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    // Cursor at end of "  hello"
    UDAutoIndenter *ind =
        [self _indenterWithText:@"  hello" cursor:7 storage:&storage textView:&tv];
    XCTAssertTrue([ind handleReturnKey]);
    XCTAssertEqualObjects([storage.textModel getValue], @"  hello\n  ");
    (void)tv;
}

/// Cursor at column 1 of a line (no preceding character on that line):
/// Return inserts a bare newline with no indent.
- (void)testReturnKey_cursorAtLineStart_noIndent {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    // text = "foo\n  bar", cursor at offset 4 = start of "  bar"
    UDAutoIndenter *ind =
        [self _indenterWithText:@"foo\n  bar" cursor:4
                        storage:&storage textView:&tv];
    XCTAssertTrue([ind handleReturnKey]);
    XCTAssertEqualObjects([storage.textModel getValue], @"foo\n\n  bar");
    (void)tv;
}

/// Cursor directly after a `{` on an indented line: indent should increase
/// by one indentUnit (default: two spaces).
- (void)testReturnKey_afterOpenBrace_increasesIndent {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    // text = "  {", cursor at end (offset 3)
    UDAutoIndenter *ind =
        [self _indenterWithText:@"  {" cursor:3 storage:&storage textView:&tv];
    XCTAssertTrue([ind handleReturnKey]);
    // lineIndent="  ", newIndent="    " (2+2 spaces)
    XCTAssertEqualObjects([storage.textModel getValue], @"  {\n    ");
    (void)tv;
}

/// Electric-pair split: cursor is between `{` and `}`.
/// Return should produce three lines and leave the cursor on the middle line.
- (void)testReturnKey_betweenBraces_electricSplit {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    // text = "  {}", cursor between { and } (offset 3)
    UDAutoIndenter *ind =
        [self _indenterWithText:@"  {}" cursor:3 storage:&storage textView:&tv];
    XCTAssertTrue([ind handleReturnKey]);
    // Expected: "  {\n    \n  }"
    XCTAssertEqualObjects([storage.textModel getValue], @"  {\n    \n  }");
    // Cursor: cursorPos(3) + 1('\n') + newIndent.length(4) = 8
    XCTAssertEqual(tv.selectedRange.location, (NSUInteger)8);
    (void)storage;
}

/// Custom language configuration with `(` and `)` as brackets: pressing
/// Return after `(` should increase the indentation.
- (void)testReturnKey_customBracketConfig_parenthesis {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    UDAutoIndenter *ind =
        [self _indenterWithText:@"(" cursor:1 storage:&storage textView:&tv];
    ind.languageConfiguration =
        [UDLanguageConfiguration configurationFromDictionary:@{
            @"brackets": @[@[@"(", @")"], @[@"{", @"}"]],
        }];
    XCTAssertTrue([ind handleReturnKey]);
    // lineIndent="", newIndent="  " (default indentUnit)
    XCTAssertEqualObjects([storage.textModel getValue], @"(\n  ");
    (void)tv;
}

/// Custom indent unit (tab character): newline should use a tab.
- (void)testReturnKey_tabIndentUnit {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    UDAutoIndenter *ind =
        [self _indenterWithText:@"\t{" cursor:2 storage:&storage textView:&tv];
    ind.indentUnit = @"\t";
    XCTAssertTrue([ind handleReturnKey]);
    // lineIndent="\t", newIndent="\t\t"
    XCTAssertEqualObjects([storage.textModel getValue], @"\t{\n\t\t");
    (void)tv;
}

/// Whitespace before cursor is skipped, but only to the end of the current
/// line: a `{` followed by spaces should still be detected as charBefore.
- (void)testReturnKey_openBraceWithTrailingSpaces_increasesIndent {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    // text = "{   ", cursor at end (offset 4) — last non-space before cursor is `{`
    UDAutoIndenter *ind =
        [self _indenterWithText:@"{   " cursor:4 storage:&storage textView:&tv];
    XCTAssertTrue([ind handleReturnKey]);
    XCTAssertEqualObjects([storage.textModel getValue], @"{   \n  ");
    (void)tv;
}

// ---------------------------------------------------------------------------
// MARK: - handleTypedCharacter:
// ---------------------------------------------------------------------------

/// No language configuration → method should return NO immediately.
- (void)testTypedChar_noConfig_returnsNO {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    UDAutoIndenter *ind =
        [self _indenterWithText:@"" cursor:0 storage:&storage textView:&tv];
    // languageConfiguration is nil by default — no autoClosingPairs
    XCTAssertFalse([ind handleTypedCharacter:@"{"]);
    XCTAssertEqualObjects([storage.textModel getValue], @"");
    (void)tv;
}

/// Typing an open bracket inserts the pair and places the cursor between them.
- (void)testTypedChar_openBracket_insertsPair {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    UDAutoIndenter *ind =
        [self _indenterWithText:@"" cursor:0 storage:&storage textView:&tv];
    ind.languageConfiguration =
        UDConfigWithPairs(@[@{@"open": @"{", @"close": @"}"}]);
    XCTAssertTrue([ind handleTypedCharacter:@"{"]);
    XCTAssertEqualObjects([storage.textModel getValue], @"{}");
    XCTAssertEqual(tv.selectedRange.location, (NSUInteger)1,
                   @"Cursor must be between open and close brackets");
    (void)storage;
}

/// Typing a close bracket when that character already sits immediately to the
/// right of the cursor advances the cursor (skip-over) without inserting.
- (void)testTypedChar_closeBracket_skipOver {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    // text = "{}", cursor between { and } (offset 1)
    UDAutoIndenter *ind =
        [self _indenterWithText:@"{}" cursor:1 storage:&storage textView:&tv];
    ind.languageConfiguration =
        UDConfigWithPairs(@[@{@"open": @"{", @"close": @"}"}]);
    XCTAssertTrue([ind handleTypedCharacter:@"}"]);
    // Model must be unchanged (no insertion)
    XCTAssertEqualObjects([storage.textModel getValue], @"{}");
    // Cursor must have moved past the existing `}`
    XCTAssertEqual(tv.selectedRange.location, (NSUInteger)2);
    (void)storage;
}

/// Non-empty selection: auto-close must not fire (return NO).
- (void)testTypedChar_withSelection_returnsNO {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    UDAutoIndenter *ind =
        [self _indenterWithText:@"foo" cursor:0 storage:&storage textView:&tv];
    [tv setSelectedRange:NSMakeRange(0, 3)];   // select all
    ind.languageConfiguration =
        UDConfigWithPairs(@[@{@"open": @"{", @"close": @"}"}]);
    XCTAssertFalse([ind handleTypedCharacter:@"{"]);
    XCTAssertEqualObjects([storage.textModel getValue], @"foo",
                          @"Model must not change when selection is non-empty");
    (void)tv;
}

/// autoCloseBefore: when the character to the right of the cursor is NOT in
/// the allowed set, auto-close is suppressed.
- (void)testTypedChar_autoCloseBefore_suppressedWhenCharNotInSet {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    // Cursor at offset 0, char to the right is 'a' — not in "}])"
    UDAutoIndenter *ind =
        [self _indenterWithText:@"a" cursor:0 storage:&storage textView:&tv];
    ind.languageConfiguration =
        UDConfigWithPairsAndBefore(@[@{@"open": @"{", @"close": @"}"}], @"}])");
    XCTAssertFalse([ind handleTypedCharacter:@"{"]);
    XCTAssertEqualObjects([storage.textModel getValue], @"a",
                          @"Auto-close must be suppressed when char-right is not in autoCloseBefore");
    (void)tv;
}

/// autoCloseBefore: when the character to the right IS in the allowed set,
/// auto-close fires normally.
- (void)testTypedChar_autoCloseBefore_firesWhenCharInSet {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    // Cursor at offset 0, char to the right is '}' — which IS in "}])"
    UDAutoIndenter *ind =
        [self _indenterWithText:@"}" cursor:0 storage:&storage textView:&tv];
    ind.languageConfiguration =
        UDConfigWithPairsAndBefore(@[@{@"open": @"{", @"close": @"}"}], @"}])");
    XCTAssertTrue([ind handleTypedCharacter:@"{"]);
    XCTAssertEqualObjects([storage.textModel getValue], @"{}}");
    XCTAssertEqual(tv.selectedRange.location, (NSUInteger)1);
    (void)storage;
}

/// autoCloseBefore: at end of document (no char to the right), auto-close
/// must fire even when autoCloseBefore is set.
- (void)testTypedChar_autoCloseBefore_firesAtEndOfDocument {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    // Empty document, cursor at end
    UDAutoIndenter *ind =
        [self _indenterWithText:@"" cursor:0 storage:&storage textView:&tv];
    ind.languageConfiguration =
        UDConfigWithPairsAndBefore(@[@{@"open": @"{", @"close": @"}"}], @"}])");
    XCTAssertTrue([ind handleTypedCharacter:@"{"]);
    XCTAssertEqualObjects([storage.textModel getValue], @"{}");
    XCTAssertEqual(tv.selectedRange.location, (NSUInteger)1);
    (void)storage;
}

@end
