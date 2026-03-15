/*---------------------------------------------------------------------------------------------
 *  UDAutoIndenterTests.m
 *
 *  Unit tests for UDAutoIndenter covering:
 *    • handleReturnKey — indent computation, open-bracket indent increase,
 *      electric-pair split, custom bracket config, custom indent unit.
 *    • handleTypedCharacter: — auto-close insertion, skip-over,
 *      autoCloseBefore suppression, no-op when no config or selection present.
 *    • handleShiftTabKey — single-line, multi-line, edge cases.
 *
 *  Key-handling methods now use stored textView/textModel/cursorsController
 *  properties set at init time.  Tests create all three objects and pass them
 *  to the designated initialiser.  ctrlOut keeps the UDCursorsController alive
 *  (the indenter holds it weakly).
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

/// Creates a (UDAutoIndenter, NSTextView, UDTextModelTextStorage,
/// UDCursorsController) quad for the given text and cursor offset.
///
/// @param ctrlOut  REQUIRED — keeps the UDCursorsController alive for the
///                 full test body (the indenter holds it weakly).
- (UDAutoIndenter *)_indenterWithText:(NSString *)text
                               cursor:(NSUInteger)offset
                              storage:(__strong UDTextModelTextStorage **)storageOut
                             textView:(__strong NSTextView **)tvOut
                                 ctrl:(__strong UDCursorsController **)ctrlOut {
    UDTextModelTextStorage *storage =
        [[UDTextModelTextStorage alloc] initWithText:text];
    UDTextModel *model = storage.textModel;

    NSTextView *tv =
        [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 500, 400)];

    // Re-wire the layout manager (same as UDTextEditorViewController).
    NSLayoutManager *lm = tv.layoutManager;
    [[lm textStorage] removeLayoutManager:lm];
    [storage addLayoutManager:lm];

    // Create the cursors controller and set the initial cursor position.
    UDCursorsController *ctrl = [[UDCursorsController alloc] initWithModel:model];
    UDPosition pos = [model getPositionAt:(NSInteger)offset];
    ctrl.selections = @[
        [NSValue ud_valueWithSelection:UDSelectionFromPosition(pos.line, pos.column)]
    ];

    // Also sync NSTextView (used by handleKeyEvent: for the delete path).
    [tv setSelectedRange:NSMakeRange(offset, 0)];

    if (storageOut) *storageOut = storage;
    if (tvOut)      *tvOut      = tv;
    if (ctrlOut)    *ctrlOut    = ctrl;

    return [[UDAutoIndenter alloc] initWithHighlighter:nil
                                              textView:tv
                                             textModel:model
                                   cursorsController:ctrl];
}

// ---------------------------------------------------------------------------
// MARK: - handleReturnKey
// ---------------------------------------------------------------------------

- (void)testReturnKey_emptyDocument_returnsNO {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    UDCursorsController *ctrl;
    UDAutoIndenter *ind =
        [self _indenterWithText:@"" cursor:0 storage:&storage textView:&tv ctrl:&ctrl];
    XCTAssertFalse([ind handleReturnKey]);
    XCTAssertEqualObjects([storage.textModel getValue], @"",
                          @"Empty document must not be modified");
    (void)tv; (void)ctrl;
}

- (void)testReturnKey_plainLine_copiesIndent {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    UDCursorsController *ctrl;
    UDAutoIndenter *ind =
        [self _indenterWithText:@"  hello" cursor:7 storage:&storage textView:&tv ctrl:&ctrl];
    XCTAssertTrue([ind handleReturnKey]);
    XCTAssertEqualObjects([storage.textModel getValue], @"  hello\n  ");
    (void)tv; (void)ctrl;
}

- (void)testReturnKey_cursorAtLineStart_noIndent {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    UDCursorsController *ctrl;
    UDAutoIndenter *ind =
        [self _indenterWithText:@"foo\n  bar" cursor:4
                        storage:&storage textView:&tv ctrl:&ctrl];
    XCTAssertTrue([ind handleReturnKey]);
    XCTAssertEqualObjects([storage.textModel getValue], @"foo\n\n  bar");
    (void)tv; (void)ctrl;
}

- (void)testReturnKey_afterOpenBrace_increasesIndent {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    UDCursorsController *ctrl;
    UDAutoIndenter *ind =
        [self _indenterWithText:@"  {" cursor:3 storage:&storage textView:&tv ctrl:&ctrl];
    XCTAssertTrue([ind handleReturnKey]);
    XCTAssertEqualObjects([storage.textModel getValue], @"  {\n    ");
    (void)tv; (void)ctrl;
}

- (void)testReturnKey_betweenBraces_electricSplit {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    UDCursorsController *ctrl;
    UDAutoIndenter *ind =
        [self _indenterWithText:@"  {}" cursor:3 storage:&storage textView:&tv ctrl:&ctrl];
    XCTAssertTrue([ind handleReturnKey]);
    XCTAssertEqualObjects([storage.textModel getValue], @"  {\n    \n  }");
    XCTAssertEqual(tv.selectedRange.location, (NSUInteger)8);
    (void)storage; (void)ctrl;
}

- (void)testReturnKey_customBracketConfig_parenthesis {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    UDCursorsController *ctrl;
    UDAutoIndenter *ind =
        [self _indenterWithText:@"(" cursor:1 storage:&storage textView:&tv ctrl:&ctrl];
    ind.languageConfiguration =
        [UDLanguageConfiguration configurationFromDictionary:@{
            @"brackets": @[@[@"(", @")"], @[@"{", @"}"]],
        }];
    XCTAssertTrue([ind handleReturnKey]);
    XCTAssertEqualObjects([storage.textModel getValue], @"(\n  ");
    (void)tv; (void)ctrl;
}

- (void)testReturnKey_tabIndentUnit {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    UDCursorsController *ctrl;
    UDAutoIndenter *ind =
        [self _indenterWithText:@"\t{" cursor:2 storage:&storage textView:&tv ctrl:&ctrl];
    ind.indentUnit = @"\t";
    XCTAssertTrue([ind handleReturnKey]);
    XCTAssertEqualObjects([storage.textModel getValue], @"\t{\n\t\t");
    (void)tv; (void)ctrl;
}

- (void)testReturnKey_openBraceWithTrailingSpaces_increasesIndent {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    UDCursorsController *ctrl;
    UDAutoIndenter *ind =
        [self _indenterWithText:@"{   " cursor:4 storage:&storage textView:&tv ctrl:&ctrl];
    XCTAssertTrue([ind handleReturnKey]);
    XCTAssertEqualObjects([storage.textModel getValue], @"{   \n  ");
    (void)tv; (void)ctrl;
}

// ---------------------------------------------------------------------------
// MARK: - handleTypedCharacter:
// ---------------------------------------------------------------------------

- (void)testTypedChar_noConfig_returnsNO {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    UDCursorsController *ctrl;
    UDAutoIndenter *ind =
        [self _indenterWithText:@"" cursor:0 storage:&storage textView:&tv ctrl:&ctrl];
    XCTAssertFalse([ind handleTypedCharacter:@"{"]);
    XCTAssertEqualObjects([storage.textModel getValue], @"");
    (void)tv; (void)ctrl;
}

- (void)testTypedChar_openBracket_insertsPair {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    UDCursorsController *ctrl;
    UDAutoIndenter *ind =
        [self _indenterWithText:@"" cursor:0 storage:&storage textView:&tv ctrl:&ctrl];
    ind.languageConfiguration =
        UDConfigWithPairs(@[@{@"open": @"{", @"close": @"}"}]);
    XCTAssertTrue([ind handleTypedCharacter:@"{"]);
    XCTAssertEqualObjects([storage.textModel getValue], @"{}");
    XCTAssertEqual(tv.selectedRange.location, (NSUInteger)1,
                   @"Cursor must be between open and close brackets");
    (void)storage; (void)ctrl;
}

- (void)testTypedChar_closeBracket_skipOver {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    UDCursorsController *ctrl;
    UDAutoIndenter *ind =
        [self _indenterWithText:@"{}" cursor:1 storage:&storage textView:&tv ctrl:&ctrl];
    ind.languageConfiguration =
        UDConfigWithPairs(@[@{@"open": @"{", @"close": @"}"}]);
    XCTAssertTrue([ind handleTypedCharacter:@"}"]);
    XCTAssertEqualObjects([storage.textModel getValue], @"{}");
    XCTAssertEqual(tv.selectedRange.location, (NSUInteger)2);
    (void)storage; (void)ctrl;
}

- (void)testTypedChar_withSelection_returnsNO {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    UDCursorsController *ctrl;
    UDAutoIndenter *ind =
        [self _indenterWithText:@"foo" cursor:0 storage:&storage textView:&tv ctrl:&ctrl];
    // Set a non-empty selection (covers all of "foo": line 1 col 1 → col 4).
    ctrl.selections = @[
        [NSValue ud_valueWithSelection:UDSelectionMake(1, 1, 1, 4)]
    ];
    ind.languageConfiguration =
        UDConfigWithPairs(@[@{@"open": @"{", @"close": @"}"}]);
    XCTAssertFalse([ind handleTypedCharacter:@"{"]);
    XCTAssertEqualObjects([storage.textModel getValue], @"foo",
                          @"Model must not change when selection is non-empty");
    (void)tv;
}

- (void)testTypedChar_autoCloseBefore_suppressedWhenCharNotInSet {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    UDCursorsController *ctrl;
    UDAutoIndenter *ind =
        [self _indenterWithText:@"a" cursor:0 storage:&storage textView:&tv ctrl:&ctrl];
    ind.languageConfiguration =
        UDConfigWithPairsAndBefore(@[@{@"open": @"{", @"close": @"}"}], @"}])");
    XCTAssertFalse([ind handleTypedCharacter:@"{"]);
    XCTAssertEqualObjects([storage.textModel getValue], @"a");
    (void)tv; (void)ctrl;
}

- (void)testTypedChar_autoCloseBefore_firesWhenCharInSet {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    UDCursorsController *ctrl;
    UDAutoIndenter *ind =
        [self _indenterWithText:@"}" cursor:0 storage:&storage textView:&tv ctrl:&ctrl];
    ind.languageConfiguration =
        UDConfigWithPairsAndBefore(@[@{@"open": @"{", @"close": @"}"}], @"}])");
    XCTAssertTrue([ind handleTypedCharacter:@"{"]);
    XCTAssertEqualObjects([storage.textModel getValue], @"{}}");
    XCTAssertEqual(tv.selectedRange.location, (NSUInteger)1);
    (void)storage; (void)ctrl;
}

- (void)testTypedChar_autoCloseBefore_firesAtEndOfDocument {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    UDCursorsController *ctrl;
    UDAutoIndenter *ind =
        [self _indenterWithText:@"" cursor:0 storage:&storage textView:&tv ctrl:&ctrl];
    ind.languageConfiguration =
        UDConfigWithPairsAndBefore(@[@{@"open": @"{", @"close": @"}"}], @"}])");
    XCTAssertTrue([ind handleTypedCharacter:@"{"]);
    XCTAssertEqualObjects([storage.textModel getValue], @"{}");
    XCTAssertEqual(tv.selectedRange.location, (NSUInteger)1);
    (void)storage; (void)ctrl;
}

// ---------------------------------------------------------------------------
// MARK: - handleShiftTabKey
// ---------------------------------------------------------------------------

- (void)testShiftTab_emptyDocument_returnsNO {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    UDCursorsController *ctrl;
    UDAutoIndenter *ind =
        [self _indenterWithText:@"" cursor:0 storage:&storage textView:&tv ctrl:&ctrl];
    XCTAssertFalse([ind handleShiftTabKey]);
    XCTAssertEqualObjects([storage.textModel getValue], @"");
    (void)tv; (void)ctrl;
}

- (void)testShiftTab_noLeadingWhitespace_returnsYES_noChange {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    UDCursorsController *ctrl;
    UDAutoIndenter *ind =
        [self _indenterWithText:@"hello" cursor:5 storage:&storage textView:&tv ctrl:&ctrl];
    XCTAssertTrue([ind handleShiftTabKey]);
    XCTAssertEqualObjects([storage.textModel getValue], @"hello");
    (void)tv; (void)ctrl;
}

- (void)testShiftTab_twoSpaceIndent_removesOneUnit {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    UDCursorsController *ctrl;
    UDAutoIndenter *ind =
        [self _indenterWithText:@"  hello" cursor:7 storage:&storage textView:&tv ctrl:&ctrl];
    XCTAssertTrue([ind handleShiftTabKey]);
    XCTAssertEqualObjects([storage.textModel getValue], @"hello");
    XCTAssertEqual(tv.selectedRange.location, (NSUInteger)5,
                   @"Cursor must shift back by 2 (the stripped spaces)");
    (void)storage; (void)ctrl;
}

- (void)testShiftTab_partialIndent_removesAllSpaces {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    UDCursorsController *ctrl;
    UDAutoIndenter *ind =
        [self _indenterWithText:@" hello" cursor:6 storage:&storage textView:&tv ctrl:&ctrl];
    XCTAssertTrue([ind handleShiftTabKey]);
    XCTAssertEqualObjects([storage.textModel getValue], @"hello");
    XCTAssertEqual(tv.selectedRange.location, (NSUInteger)5);
    (void)storage; (void)ctrl;
}

- (void)testShiftTab_fourSpaceIndent_removesOneUnit {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    UDCursorsController *ctrl;
    UDAutoIndenter *ind =
        [self _indenterWithText:@"    hello" cursor:9 storage:&storage textView:&tv ctrl:&ctrl];
    XCTAssertTrue([ind handleShiftTabKey]);
    XCTAssertEqualObjects([storage.textModel getValue], @"  hello");
    XCTAssertEqual(tv.selectedRange.location, (NSUInteger)7);
    (void)storage; (void)ctrl;
}

- (void)testShiftTab_tabIndent_removesOneTab {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    UDCursorsController *ctrl;
    UDAutoIndenter *ind =
        [self _indenterWithText:@"\thello" cursor:6 storage:&storage textView:&tv ctrl:&ctrl];
    XCTAssertTrue([ind handleShiftTabKey]);
    XCTAssertEqualObjects([storage.textModel getValue], @"hello");
    XCTAssertEqual(tv.selectedRange.location, (NSUInteger)5);
    (void)storage; (void)ctrl;
}

- (void)testShiftTab_cursorAtLineStart_clampsToLineStart {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    UDCursorsController *ctrl;
    UDAutoIndenter *ind =
        [self _indenterWithText:@"  hello" cursor:0 storage:&storage textView:&tv ctrl:&ctrl];
    XCTAssertTrue([ind handleShiftTabKey]);
    XCTAssertEqualObjects([storage.textModel getValue], @"hello");
    XCTAssertEqual(tv.selectedRange.location, (NSUInteger)0);
    (void)storage; (void)ctrl;
}

- (void)testShiftTab_multiLineSelection_removesFromEachLine {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    UDCursorsController *ctrl;
    UDAutoIndenter *ind =
        [self _indenterWithText:@"  foo\n  bar" cursor:0
                        storage:&storage textView:&tv ctrl:&ctrl];
    // Select the whole text (offsets 0–11): line 1 col 1 → line 2 col 6.
    UDTextModel *model = storage.textModel;
    UDPosition endPos = [model getPositionAt:11];
    ctrl.selections = @[
        [NSValue ud_valueWithSelection:UDSelectionMake(1, 1, endPos.line, endPos.column)]
    ];
    XCTAssertTrue([ind handleShiftTabKey]);
    XCTAssertEqualObjects([storage.textModel getValue], @"foo\nbar");
    // _syncTextViewCursor places the cursor at the selection's position end
    // (offset 7, end of "bar") with a collapsed range.
    XCTAssertEqual(tv.selectedRange.location, (NSUInteger)7);
    XCTAssertEqual(tv.selectedRange.length,   (NSUInteger)0);
    (void)storage;
}

- (void)testShiftTab_selectionEndsAtLineStart_doesNotDedentLastLine {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    UDCursorsController *ctrl;
    UDAutoIndenter *ind =
        [self _indenterWithText:@"  foo\n  bar" cursor:0
                        storage:&storage textView:&tv ctrl:&ctrl];
    // Select "  foo\n" (offsets 0–6): line 1 col 1 → line 2 col 1.
    ctrl.selections = @[
        [NSValue ud_valueWithSelection:UDSelectionMake(1, 1, 2, 1)]
    ];
    XCTAssertTrue([ind handleShiftTabKey]);
    XCTAssertEqualObjects([storage.textModel getValue], @"foo\n  bar");
    // Only the first line is de-indented (2 spaces stripped).
    // _syncTextViewCursor places cursor at position end of the selection
    // (offset 4 = start of "  bar" in the new doc) with a collapsed range.
    XCTAssertEqual(tv.selectedRange.location, (NSUInteger)4);
    XCTAssertEqual(tv.selectedRange.length,   (NSUInteger)0);
    (void)storage;
}

- (void)testShiftTab_customFourSpaceUnit_removesFourSpaces {
    UDTextModelTextStorage *storage;
    NSTextView *tv;
    UDCursorsController *ctrl;
    UDAutoIndenter *ind =
        [self _indenterWithText:@"    hello" cursor:9 storage:&storage textView:&tv ctrl:&ctrl];
    ind.indentUnit = @"    ";
    XCTAssertTrue([ind handleShiftTabKey]);
    XCTAssertEqualObjects([storage.textModel getValue], @"hello");
    XCTAssertEqual(tv.selectedRange.location, (NSUInteger)5);
    (void)storage; (void)ctrl;
}

@end
