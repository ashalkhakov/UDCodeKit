/*---------------------------------------------------------------------------------------------
 *  UDAutoIndenterTests.m
 *
 *  Unit tests for UDAutoIndenter covering:
 *    • handleReturnKeyWithTextView:model: — indent computation, open-bracket
 *      indent increase, electric-pair split, custom bracket config, custom
 *      indent unit.
 *    • handleTypedCharacter:textView:model: — auto-close insertion, skip-over,
 *      autoCloseBefore suppression, no-op when no config or selection present.
 *    • handleShiftTabKeyWithTextView:model: — single-line, multi-line, edge cases.
 *
 *  All public key-handling methods take explicit textView/model parameters
 *  (no stored weak references), which makes the test setup simpler: we create
 *  a real NSTextView + UDTextModelTextStorage pair and pass them directly.
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

    return [[UDAutoIndenter alloc] initWithHighlighter:nil];
}

// Convenience: runs a return-key action and returns the indenter.
- (UDAutoIndenter *)_indenterForReturnInText:(NSString *)text
                                      cursor:(NSUInteger)offset
                                     storage:(__strong UDTextModelTextStorage **)sOut
                                    textView:(__strong NSTextView **)tvOut {
    return [self _indenterWithText:text cursor:offset storage:sOut textView:tvOut];
}

// ---------------------------------------------------------------------------
// MARK: - handleReturnKeyWithTextView:model:
// ---------------------------------------------------------------------------

- (void)testReturnKey_emptyDocument_returnsNO {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    UDAutoIndenter *ind =
        [self _indenterWithText:@"" cursor:0 storage:&storage textView:&tv];
    XCTAssertFalse([ind handleReturnKeyWithTextView:tv model:storage.textModel]);
    XCTAssertEqualObjects([storage.textModel getValue], @"",
                          @"Empty document must not be modified");
    (void)tv;
}

- (void)testReturnKey_plainLine_copiesIndent {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    UDAutoIndenter *ind =
        [self _indenterWithText:@"  hello" cursor:7 storage:&storage textView:&tv];
    XCTAssertTrue([ind handleReturnKeyWithTextView:tv model:storage.textModel]);
    XCTAssertEqualObjects([storage.textModel getValue], @"  hello\n  ");
    (void)tv;
}

- (void)testReturnKey_cursorAtLineStart_noIndent {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    UDAutoIndenter *ind =
        [self _indenterWithText:@"foo\n  bar" cursor:4
                        storage:&storage textView:&tv];
    XCTAssertTrue([ind handleReturnKeyWithTextView:tv model:storage.textModel]);
    XCTAssertEqualObjects([storage.textModel getValue], @"foo\n\n  bar");
    (void)tv;
}

- (void)testReturnKey_afterOpenBrace_increasesIndent {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    UDAutoIndenter *ind =
        [self _indenterWithText:@"  {" cursor:3 storage:&storage textView:&tv];
    XCTAssertTrue([ind handleReturnKeyWithTextView:tv model:storage.textModel]);
    XCTAssertEqualObjects([storage.textModel getValue], @"  {\n    ");
    (void)tv;
}

- (void)testReturnKey_betweenBraces_electricSplit {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    UDAutoIndenter *ind =
        [self _indenterWithText:@"  {}" cursor:3 storage:&storage textView:&tv];
    XCTAssertTrue([ind handleReturnKeyWithTextView:tv model:storage.textModel]);
    XCTAssertEqualObjects([storage.textModel getValue], @"  {\n    \n  }");
    XCTAssertEqual(tv.selectedRange.location, (NSUInteger)8);
    (void)storage;
}

- (void)testReturnKey_customBracketConfig_parenthesis {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    UDAutoIndenter *ind =
        [self _indenterWithText:@"(" cursor:1 storage:&storage textView:&tv];
    ind.languageConfiguration =
        [UDLanguageConfiguration configurationFromDictionary:@{
            @"brackets": @[@[@"(", @")"], @[@"{", @"}"]],
        }];
    XCTAssertTrue([ind handleReturnKeyWithTextView:tv model:storage.textModel]);
    XCTAssertEqualObjects([storage.textModel getValue], @"(\n  ");
    (void)tv;
}

- (void)testReturnKey_tabIndentUnit {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    UDAutoIndenter *ind =
        [self _indenterWithText:@"\t{" cursor:2 storage:&storage textView:&tv];
    ind.indentUnit = @"\t";
    XCTAssertTrue([ind handleReturnKeyWithTextView:tv model:storage.textModel]);
    XCTAssertEqualObjects([storage.textModel getValue], @"\t{\n\t\t");
    (void)tv;
}

- (void)testReturnKey_openBraceWithTrailingSpaces_increasesIndent {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    UDAutoIndenter *ind =
        [self _indenterWithText:@"{   " cursor:4 storage:&storage textView:&tv];
    XCTAssertTrue([ind handleReturnKeyWithTextView:tv model:storage.textModel]);
    XCTAssertEqualObjects([storage.textModel getValue], @"{   \n  ");
    (void)tv;
}

// ---------------------------------------------------------------------------
// MARK: - handleTypedCharacter:textView:model:
// ---------------------------------------------------------------------------

- (void)testTypedChar_noConfig_returnsNO {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    UDAutoIndenter *ind =
        [self _indenterWithText:@"" cursor:0 storage:&storage textView:&tv];
    XCTAssertFalse([ind handleTypedCharacter:@"{" textView:tv model:storage.textModel]);
    XCTAssertEqualObjects([storage.textModel getValue], @"");
    (void)tv;
}

- (void)testTypedChar_openBracket_insertsPair {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    UDAutoIndenter *ind =
        [self _indenterWithText:@"" cursor:0 storage:&storage textView:&tv];
    ind.languageConfiguration =
        UDConfigWithPairs(@[@{@"open": @"{", @"close": @"}"}]);
    XCTAssertTrue([ind handleTypedCharacter:@"{" textView:tv model:storage.textModel]);
    XCTAssertEqualObjects([storage.textModel getValue], @"{}");
    XCTAssertEqual(tv.selectedRange.location, (NSUInteger)1,
                   @"Cursor must be between open and close brackets");
    (void)storage;
}

- (void)testTypedChar_closeBracket_skipOver {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    UDAutoIndenter *ind =
        [self _indenterWithText:@"{}" cursor:1 storage:&storage textView:&tv];
    ind.languageConfiguration =
        UDConfigWithPairs(@[@{@"open": @"{", @"close": @"}"}]);
    XCTAssertTrue([ind handleTypedCharacter:@"}" textView:tv model:storage.textModel]);
    XCTAssertEqualObjects([storage.textModel getValue], @"{}");
    XCTAssertEqual(tv.selectedRange.location, (NSUInteger)2);
    (void)storage;
}

- (void)testTypedChar_withSelection_returnsNO {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    UDAutoIndenter *ind =
        [self _indenterWithText:@"foo" cursor:0 storage:&storage textView:&tv];
    [tv setSelectedRange:NSMakeRange(0, 3)];
    ind.languageConfiguration =
        UDConfigWithPairs(@[@{@"open": @"{", @"close": @"}"}]);
    XCTAssertFalse([ind handleTypedCharacter:@"{" textView:tv model:storage.textModel]);
    XCTAssertEqualObjects([storage.textModel getValue], @"foo",
                          @"Model must not change when selection is non-empty");
    (void)tv;
}

- (void)testTypedChar_autoCloseBefore_suppressedWhenCharNotInSet {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    UDAutoIndenter *ind =
        [self _indenterWithText:@"a" cursor:0 storage:&storage textView:&tv];
    ind.languageConfiguration =
        UDConfigWithPairsAndBefore(@[@{@"open": @"{", @"close": @"}"}], @"}])");
    XCTAssertFalse([ind handleTypedCharacter:@"{" textView:tv model:storage.textModel]);
    XCTAssertEqualObjects([storage.textModel getValue], @"a");
    (void)tv;
}

- (void)testTypedChar_autoCloseBefore_firesWhenCharInSet {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    UDAutoIndenter *ind =
        [self _indenterWithText:@"}" cursor:0 storage:&storage textView:&tv];
    ind.languageConfiguration =
        UDConfigWithPairsAndBefore(@[@{@"open": @"{", @"close": @"}"}], @"}])");
    XCTAssertTrue([ind handleTypedCharacter:@"{" textView:tv model:storage.textModel]);
    XCTAssertEqualObjects([storage.textModel getValue], @"{}}");
    XCTAssertEqual(tv.selectedRange.location, (NSUInteger)1);
    (void)storage;
}

- (void)testTypedChar_autoCloseBefore_firesAtEndOfDocument {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    UDAutoIndenter *ind =
        [self _indenterWithText:@"" cursor:0 storage:&storage textView:&tv];
    ind.languageConfiguration =
        UDConfigWithPairsAndBefore(@[@{@"open": @"{", @"close": @"}"}], @"}])");
    XCTAssertTrue([ind handleTypedCharacter:@"{" textView:tv model:storage.textModel]);
    XCTAssertEqualObjects([storage.textModel getValue], @"{}");
    XCTAssertEqual(tv.selectedRange.location, (NSUInteger)1);
    (void)storage;
}

// ---------------------------------------------------------------------------
// MARK: - handleShiftTabKeyWithTextView:model:
// ---------------------------------------------------------------------------

- (void)testShiftTab_emptyDocument_returnsNO {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    UDAutoIndenter *ind =
        [self _indenterWithText:@"" cursor:0 storage:&storage textView:&tv];
    XCTAssertFalse([ind handleShiftTabKeyWithTextView:tv model:storage.textModel]);
    XCTAssertEqualObjects([storage.textModel getValue], @"");
    (void)tv;
}

- (void)testShiftTab_noLeadingWhitespace_returnsYES_noChange {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    UDAutoIndenter *ind =
        [self _indenterWithText:@"hello" cursor:5 storage:&storage textView:&tv];
    XCTAssertTrue([ind handleShiftTabKeyWithTextView:tv model:storage.textModel]);
    XCTAssertEqualObjects([storage.textModel getValue], @"hello");
    (void)tv;
}

- (void)testShiftTab_twoSpaceIndent_removesOneUnit {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    UDAutoIndenter *ind =
        [self _indenterWithText:@"  hello" cursor:7 storage:&storage textView:&tv];
    XCTAssertTrue([ind handleShiftTabKeyWithTextView:tv model:storage.textModel]);
    XCTAssertEqualObjects([storage.textModel getValue], @"hello");
    XCTAssertEqual(tv.selectedRange.location, (NSUInteger)5,
                   @"Cursor must shift back by 2 (the stripped spaces)");
    (void)storage;
}

- (void)testShiftTab_partialIndent_removesAllSpaces {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    UDAutoIndenter *ind =
        [self _indenterWithText:@" hello" cursor:6 storage:&storage textView:&tv];
    XCTAssertTrue([ind handleShiftTabKeyWithTextView:tv model:storage.textModel]);
    XCTAssertEqualObjects([storage.textModel getValue], @"hello");
    XCTAssertEqual(tv.selectedRange.location, (NSUInteger)5);
    (void)storage;
}

- (void)testShiftTab_fourSpaceIndent_removesOneUnit {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    UDAutoIndenter *ind =
        [self _indenterWithText:@"    hello" cursor:9 storage:&storage textView:&tv];
    XCTAssertTrue([ind handleShiftTabKeyWithTextView:tv model:storage.textModel]);
    XCTAssertEqualObjects([storage.textModel getValue], @"  hello");
    XCTAssertEqual(tv.selectedRange.location, (NSUInteger)7);
    (void)storage;
}

- (void)testShiftTab_tabIndent_removesOneTab {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    UDAutoIndenter *ind =
        [self _indenterWithText:@"\thello" cursor:6 storage:&storage textView:&tv];
    XCTAssertTrue([ind handleShiftTabKeyWithTextView:tv model:storage.textModel]);
    XCTAssertEqualObjects([storage.textModel getValue], @"hello");
    XCTAssertEqual(tv.selectedRange.location, (NSUInteger)5);
    (void)storage;
}

- (void)testShiftTab_cursorAtLineStart_clampsToLineStart {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    UDAutoIndenter *ind =
        [self _indenterWithText:@"  hello" cursor:0 storage:&storage textView:&tv];
    XCTAssertTrue([ind handleShiftTabKeyWithTextView:tv model:storage.textModel]);
    XCTAssertEqualObjects([storage.textModel getValue], @"hello");
    XCTAssertEqual(tv.selectedRange.location, (NSUInteger)0);
    (void)storage;
}

- (void)testShiftTab_multiLineSelection_removesFromEachLine {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    UDAutoIndenter *ind =
        [self _indenterWithText:@"  foo\n  bar" cursor:0 storage:&storage textView:&tv];
    [tv setSelectedRange:NSMakeRange(0, 11)];
    XCTAssertTrue([ind handleShiftTabKeyWithTextView:tv model:storage.textModel]);
    XCTAssertEqualObjects([storage.textModel getValue], @"foo\nbar");
    XCTAssertEqual(tv.selectedRange.location, (NSUInteger)0);
    XCTAssertEqual(tv.selectedRange.length,   (NSUInteger)7);
    (void)storage;
}

- (void)testShiftTab_selectionEndsAtLineStart_doesNotDedentLastLine {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    UDAutoIndenter *ind =
        [self _indenterWithText:@"  foo\n  bar" cursor:0 storage:&storage textView:&tv];
    [tv setSelectedRange:NSMakeRange(0, 6)];
    XCTAssertTrue([ind handleShiftTabKeyWithTextView:tv model:storage.textModel]);
    XCTAssertEqualObjects([storage.textModel getValue], @"foo\n  bar");
    XCTAssertEqual(tv.selectedRange.location, (NSUInteger)0);
    XCTAssertEqual(tv.selectedRange.length,   (NSUInteger)4);
    (void)storage;
}

- (void)testShiftTab_customFourSpaceUnit_removesFourSpaces {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    UDAutoIndenter *ind =
        [self _indenterWithText:@"    hello" cursor:9 storage:&storage textView:&tv];
    ind.indentUnit = @"    ";
    XCTAssertTrue([ind handleShiftTabKeyWithTextView:tv model:storage.textModel]);
    XCTAssertEqualObjects([storage.textModel getValue], @"hello");
    XCTAssertEqual(tv.selectedRange.location, (NSUInteger)5);
    (void)storage;
}

@end
