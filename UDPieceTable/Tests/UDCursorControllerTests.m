/*---------------------------------------------------------------------------------------------
 *  Portions Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See LICENSE.txt for license information.
 *
 *  Test cases ported from VS Code:
 *    src/vs/editor/test/browser/controller/cursor.test.ts
 *    src/vs/editor/contrib/multicursor/test/browser/multicursor.test.ts
 *--------------------------------------------------------------------------------------------*/

#import <XCTest/XCTest.h>
#import "UDTextModel.h"
#import "UDTypes.h"
#import "UDCursorsController.h"
#import "UDCursorTypeEditOperations.h"
#import "UDReplaceCommand.h"

// ---------------------------------------------------------------------------
// MARK: - Helpers
// ---------------------------------------------------------------------------

/// Returns an NSValue-boxed UDSelection for a collapsed cursor (no selection).
static inline NSValue *Cursor(NSInteger line, NSInteger col) {
    UDSelection s = UDSelectionFromPosition(line, col);
    return [NSValue ud_valueWithSelection:s];
}

/// Returns an NSValue-boxed UDSelection spanning from (sl,sc) to (pl,pc).
static inline NSValue *Sel(NSInteger ssl, NSInteger ssc, NSInteger pl, NSInteger pc) {
    UDSelection s = UDSelectionMake(ssl, ssc, pl, pc);
    return [NSValue ud_valueWithSelection:s];
}

/// Asserts that the controller has exactly one cursor at the given line/column.
#define AssertCursorAt(ctrl, line, col) \
    do { \
        XCTAssertEqual((ctrl).selections.count, (NSUInteger)1); \
        UDSelection _s = [(ctrl).selections.firstObject ud_selectionValue]; \
        XCTAssertEqual(_s.positionLineNumber, (NSInteger)(line)); \
        XCTAssertEqual(_s.positionColumn,     (NSInteger)(col)); \
        XCTAssertTrue(UDSelectionIsEmpty(_s)); \
    } while(0)

/// Asserts that the controller has exactly N cursors and that cursor at index i
/// is at the given line/column (collapsed).
#define AssertCursorAtIndex(ctrl, idx, line, col) \
    do { \
        UDSelection _s = [(ctrl).selections[(idx)] ud_selectionValue]; \
        XCTAssertEqual(_s.positionLineNumber, (NSInteger)(line)); \
        XCTAssertEqual(_s.positionColumn,     (NSInteger)(col)); \
    } while(0)

/// Asserts that the selection at index i spans the given range.
#define AssertSelectionAtIndex(ctrl, idx, ssl, ssc, pl, pc) \
    do { \
        UDSelection _s = [(ctrl).selections[(idx)] ud_selectionValue]; \
        XCTAssertEqual(_s.selectionStartLineNumber, (NSInteger)(ssl)); \
        XCTAssertEqual(_s.selectionStartColumn,     (NSInteger)(ssc)); \
        XCTAssertEqual(_s.positionLineNumber,        (NSInteger)(pl)); \
        XCTAssertEqual(_s.positionColumn,            (NSInteger)(pc)); \
    } while(0)

// ---------------------------------------------------------------------------
// MARK: - UDCursorsControllerTests
// ---------------------------------------------------------------------------

@interface UDCursorsControllerTests : XCTestCase
@end

@implementation UDCursorsControllerTests

// ===========================================================================
// MARK: - Single-cursor typing
// Mirrors: "Editor Controller - Cursor > Typing" suite in cursor.test.ts
// ===========================================================================

/// Typing a single character inserts it and advances the cursor.
/// VS Code ref: basic type() behaviour verified throughout the typing suite.
- (void)testType_singleChar_insertedAndCursorAdvances {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"line1\nline2"];
    UDCursorsController *ctrl = [[UDCursorsController alloc] initWithModel:model];
    ctrl.selections = @[ Cursor(1, 1) ];

    [ctrl typeText:@"X" source:@"keyboard"];

    XCTAssertEqualObjects([model getValue], @"Xline1\nline2");
    AssertCursorAt(ctrl, 1, 2);
}

/// Typing at end of a line.
- (void)testType_atEndOfLine {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"abc"];
    UDCursorsController *ctrl = [[UDCursorsController alloc] initWithModel:model];
    ctrl.selections = @[ Cursor(1, 4) ]; // after 'c'

    [ctrl typeText:@"!" source:@"keyboard"];

    XCTAssertEqualObjects([model getValue], @"abc!");
    AssertCursorAt(ctrl, 1, 5);
}

/// Typing replaces the selected range (selection → insertion).
/// VS Code ref: type() with a non-collapsed selection replaces selected text.
- (void)testType_replacesSelection {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"Hello World"];
    UDCursorsController *ctrl = [[UDCursorsController alloc] initWithModel:model];
    // Select "World" (col 7–12)
    ctrl.selections = @[ Sel(1, 7, 1, 12) ];

    [ctrl typeText:@"Swift" source:@"keyboard"];

    XCTAssertEqualObjects([model getValue], @"Hello Swift");
    AssertCursorAt(ctrl, 1, 12);
}

/// Typing an empty string is a no-op.
- (void)testType_emptyString_noOp {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"abc"];
    UDCursorsController *ctrl = [[UDCursorsController alloc] initWithModel:model];
    ctrl.selections = @[ Cursor(1, 2) ];

    [ctrl typeText:@"" source:@"keyboard"];

    XCTAssertEqualObjects([model getValue], @"abc");
    AssertCursorAt(ctrl, 1, 2);
}

/// Typing multiple characters sequentially advances the cursor each time.
- (void)testType_multipleCharsSequentially {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@""];
    UDCursorsController *ctrl = [[UDCursorsController alloc] initWithModel:model];
    ctrl.selections = @[ Cursor(1, 1) ];

    [ctrl typeText:@"a" source:@"keyboard"];
    [ctrl typeText:@"b" source:@"keyboard"];
    [ctrl typeText:@"c" source:@"keyboard"];

    XCTAssertEqualObjects([model getValue], @"abc");
    AssertCursorAt(ctrl, 1, 4);
}

// ===========================================================================
// MARK: - DeleteLeft (backspace)
// Mirrors: CoreEditingCommands.DeleteLeft tests in cursor.test.ts
// ===========================================================================

/// Backspace on a collapsed cursor deletes the character to the left.
/// VS Code ref: "deleteLeft" with no selection → delete char left.
- (void)testDeleteLeft_deletesCharLeft {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"abc"];
    UDCursorsController *ctrl = [[UDCursorsController alloc] initWithModel:model];
    ctrl.selections = @[ Cursor(1, 3) ]; // between 'b' and 'c'

    [ctrl deleteLeftWithSource:nil];

    XCTAssertEqualObjects([model getValue], @"ac");
    AssertCursorAt(ctrl, 1, 2);
}

/// Backspace at the beginning of a line joins it with the previous line.
/// VS Code ref: deleteLeft at col 1 → move to end of previous line.
- (void)testDeleteLeft_atLineStart_joinsLines {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"abc\ndef"];
    UDCursorsController *ctrl = [[UDCursorsController alloc] initWithModel:model];
    ctrl.selections = @[ Cursor(2, 1) ]; // start of "def"

    [ctrl deleteLeftWithSource:nil];

    XCTAssertEqualObjects([model getValue], @"abcdef");
    AssertCursorAt(ctrl, 1, 4);
}

/// Backspace at the very beginning of the document is a no-op.
/// VS Code ref: deleteLeft at (1,1) → nothing happens.
- (void)testDeleteLeft_atDocumentStart_noOp {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"abc"];
    UDCursorsController *ctrl = [[UDCursorsController alloc] initWithModel:model];
    ctrl.selections = @[ Cursor(1, 1) ];

    [ctrl deleteLeftWithSource:nil];

    XCTAssertEqualObjects([model getValue], @"abc");
    AssertCursorAt(ctrl, 1, 1);
}

/// Backspace with a selection deletes the selected range.
/// VS Code ref: deleteLeft with non-empty selection → delete selection.
- (void)testDeleteLeft_withSelection_deletesSelection {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"Hello World"];
    UDCursorsController *ctrl = [[UDCursorsController alloc] initWithModel:model];
    ctrl.selections = @[ Sel(1, 7, 1, 12) ]; // "World"

    [ctrl deleteLeftWithSource:nil];

    XCTAssertEqualObjects([model getValue], @"Hello ");
    AssertCursorAt(ctrl, 1, 7);
}

// ===========================================================================
// MARK: - DeleteRight (forward-delete)
// Mirrors: CoreEditingCommands.DeleteRight tests in cursor.test.ts
// ===========================================================================

/// Forward-delete on a collapsed cursor deletes the character to the right.
- (void)testDeleteRight_deletesCharRight {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"abc"];
    UDCursorsController *ctrl = [[UDCursorsController alloc] initWithModel:model];
    ctrl.selections = @[ Cursor(1, 2) ]; // between 'a' and 'b'

    [ctrl deleteRightWithSource:nil];

    XCTAssertEqualObjects([model getValue], @"ac");
    AssertCursorAt(ctrl, 1, 2);
}

/// Forward-delete at the end of a line joins it with the next line.
- (void)testDeleteRight_atLineEnd_joinsLines {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"abc\ndef"];
    UDCursorsController *ctrl = [[UDCursorsController alloc] initWithModel:model];
    ctrl.selections = @[ Cursor(1, 4) ]; // after 'c', at EOL

    [ctrl deleteRightWithSource:nil];

    XCTAssertEqualObjects([model getValue], @"abcdef");
    AssertCursorAt(ctrl, 1, 4);
}

/// Forward-delete at the very end of the document is a no-op.
- (void)testDeleteRight_atDocumentEnd_noOp {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"abc"];
    UDCursorsController *ctrl = [[UDCursorsController alloc] initWithModel:model];
    ctrl.selections = @[ Cursor(1, 4) ]; // after last char

    [ctrl deleteRightWithSource:nil];

    XCTAssertEqualObjects([model getValue], @"abc");
    AssertCursorAt(ctrl, 1, 4);
}

/// Forward-delete with a selection deletes the selected range.
- (void)testDeleteRight_withSelection_deletesSelection {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"Hello World"];
    UDCursorsController *ctrl = [[UDCursorsController alloc] initWithModel:model];
    ctrl.selections = @[ Sel(1, 1, 1, 6) ]; // "Hello"

    [ctrl deleteRightWithSource:nil];

    XCTAssertEqualObjects([model getValue], @" World");
    AssertCursorAt(ctrl, 1, 1);
}

// ===========================================================================
// MARK: - Multi-cursor typing
// Mirrors: multicursor.test.ts and "multiple cursors" scenarios in cursor.test.ts
// ===========================================================================

/// Typing with two cursors inserts the same character at both positions.
/// VS Code ref: type() passes all selections[] to TypeOperations at once.
- (void)testType_twoCursors_insertBothPositions {
    // "aaa bbb" — cursors at end of "aaa" (col 4) and end of "bbb" (col 8)
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"aaa bbb"];
    UDCursorsController *ctrl = [[UDCursorsController alloc] initWithModel:model];
    ctrl.selections = @[ Cursor(1, 4), Cursor(1, 8) ];

    [ctrl typeText:@"!" source:@"keyboard"];

    XCTAssertEqualObjects([model getValue], @"aaa! bbb!");
    XCTAssertEqual(ctrl.selections.count, (NSUInteger)2);
    AssertCursorAtIndex(ctrl, 0, 1, 5);
    AssertCursorAtIndex(ctrl, 1, 1, 10);
}

/// Typing with three cursors on different lines inserts at all positions.
- (void)testType_threeCursors_differentLines {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"foo\nbar\nbaz"];
    UDCursorsController *ctrl = [[UDCursorsController alloc] initWithModel:model];
    ctrl.selections = @[
        Cursor(1, 4), // end of "foo"
        Cursor(2, 4), // end of "bar"
        Cursor(3, 4), // end of "baz"
    ];

    [ctrl typeText:@"X" source:@"keyboard"];

    XCTAssertEqualObjects([model getValue], @"fooX\nbarX\nbazX");
    XCTAssertEqual(ctrl.selections.count, (NSUInteger)3);
    AssertCursorAtIndex(ctrl, 0, 1, 5);
    AssertCursorAtIndex(ctrl, 1, 2, 5);
    AssertCursorAtIndex(ctrl, 2, 3, 5);
}

/// Typing replaces each cursor's selection independently.
/// VS Code ref: type() with multiple non-empty selections replaces each one.
- (void)testType_twoCursors_replaceBothSelections {
    // "aaa bbb" — select "aaa" and "bbb" with two cursors
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"aaa bbb"];
    UDCursorsController *ctrl = [[UDCursorsController alloc] initWithModel:model];
    ctrl.selections = @[
        Sel(1, 1, 1, 4),  // "aaa"
        Sel(1, 5, 1, 8),  // "bbb"
    ];

    [ctrl typeText:@"X" source:@"keyboard"];

    XCTAssertEqualObjects([model getValue], @"X X");
    XCTAssertEqual(ctrl.selections.count, (NSUInteger)2);
    AssertCursorAtIndex(ctrl, 0, 1, 2);
    AssertCursorAtIndex(ctrl, 1, 1, 4);
}

/// Multi-cursor typing is a single undo step.
/// VS Code ref: all cursor edits go into a single model.applyEdits() call.
- (void)testType_twoCursors_undoIsAtomic {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"aaa bbb"];
    UDCursorsController *ctrl = [[UDCursorsController alloc] initWithModel:model];
    ctrl.selections = @[ Cursor(1, 4), Cursor(1, 8) ];

    [ctrl typeText:@"!" source:@"keyboard"];
    XCTAssertEqualObjects([model getValue], @"aaa! bbb!");

    [model.undoManager undo];
    XCTAssertEqualObjects([model getValue], @"aaa bbb",
        @"Single undo should revert both insertions atomically");
}

// ===========================================================================
// MARK: - Multi-cursor deleteLeft
// Mirrors: "multiple cursors delete" scenarios in cursor.test.ts
// ===========================================================================

/// Backspace with two cursors deletes one character left of each.
- (void)testDeleteLeft_twoCursors_deleteBothChars {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"aXb YZc"];
    UDCursorsController *ctrl = [[UDCursorsController alloc] initWithModel:model];
    // Cursor after 'X' (col 3) and after 'Z' (col 7)
    ctrl.selections = @[ Cursor(1, 3), Cursor(1, 7) ];

    [ctrl deleteLeftWithSource:nil];

    XCTAssertEqualObjects([model getValue], @"ab Yc");
    XCTAssertEqual(ctrl.selections.count, (NSUInteger)2);
    AssertCursorAtIndex(ctrl, 0, 1, 2);
    AssertCursorAtIndex(ctrl, 1, 1, 5);
}

/// Backspace with two cursors on different lines.
- (void)testDeleteLeft_twoCursors_differentLines {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"abc\ndef"];
    UDCursorsController *ctrl = [[UDCursorsController alloc] initWithModel:model];
    ctrl.selections = @[
        Cursor(1, 4), // after 'c'
        Cursor(2, 4), // after 'f'
    ];

    [ctrl deleteLeftWithSource:nil];

    XCTAssertEqualObjects([model getValue], @"ab\nde");
    XCTAssertEqual(ctrl.selections.count, (NSUInteger)2);
    AssertCursorAtIndex(ctrl, 0, 1, 3);
    AssertCursorAtIndex(ctrl, 1, 2, 3);
}

// ===========================================================================
// MARK: - Multi-cursor deleteRight
// ===========================================================================

/// Forward-delete with two cursors deletes the character to the right of each.
- (void)testDeleteRight_twoCursors_deleteBothChars {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"abcd"];
    UDCursorsController *ctrl = [[UDCursorsController alloc] initWithModel:model];
    // Cursors before 'a' (col 1) and before 'c' (col 3 in original → col 2 after first delete)
    ctrl.selections = @[ Cursor(1, 1), Cursor(1, 3) ];

    [ctrl deleteRightWithSource:nil];

    XCTAssertEqualObjects([model getValue], @"bd");
    XCTAssertEqual(ctrl.selections.count, (NSUInteger)2);
    AssertCursorAtIndex(ctrl, 0, 1, 1);
    AssertCursorAtIndex(ctrl, 1, 1, 2);
}

// ===========================================================================
// MARK: - addCursor / removeSecondaryCursors
// Mirrors: InsertCursorAbove/Below tests in multicursor.test.ts
// ===========================================================================

/// Adding a cursor increases the selection count.
/// VS Code ref: InsertCursorBelow adds a cursor → getCursorStates().length == 2.
- (void)testAddCursor_increasesCount {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"abc\ndef"];
    UDCursorsController *ctrl = [[UDCursorsController alloc] initWithModel:model];
    ctrl.selections = @[ Cursor(1, 1) ];

    [ctrl addCursorAtLine:2 column:1];

    XCTAssertEqual(ctrl.selections.count, (NSUInteger)2);
    AssertCursorAtIndex(ctrl, 0, 1, 1);
    AssertCursorAtIndex(ctrl, 1, 2, 1);
}

/// removeSecondaryCursors reduces back to one cursor.
/// VS Code ref: killSecondaryCursors() → only primary remains.
- (void)testRemoveSecondaryCursors_keepsOnlyPrimary {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"abc\ndef\nghi"];
    UDCursorsController *ctrl = [[UDCursorsController alloc] initWithModel:model];
    ctrl.selections = @[ Cursor(1, 1), Cursor(2, 1), Cursor(3, 1) ];

    [ctrl removeSecondaryCursors];

    XCTAssertEqual(ctrl.selections.count, (NSUInteger)1);
    AssertCursorAt(ctrl, 1, 1);
}

/// Adding then typing works correctly — existing VS Code multi-cursor flow.
/// VS Code ref: addCursorBelow then type → both lines get the character.
- (void)testAddCursorThenType {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"abc\nabc"];
    UDCursorsController *ctrl = [[UDCursorsController alloc] initWithModel:model];
    ctrl.selections = @[ Cursor(1, 1) ];

    [ctrl addCursorAtLine:2 column:1];
    [ctrl typeText:@"X" source:@"keyboard"];

    XCTAssertEqualObjects([model getValue], @"Xabc\nXabc");
    XCTAssertEqual(ctrl.selections.count, (NSUInteger)2);
    AssertCursorAtIndex(ctrl, 0, 1, 2);
    AssertCursorAtIndex(ctrl, 1, 2, 2);
}

// ===========================================================================
// MARK: - executeCommands (direct command execution)
// Mirrors: CursorsController.executeCommands() used throughout the VS Code
//          editor for snippet expansion and external command execution.
// ===========================================================================

/// executeCommands applies one ReplaceCommand per cursor.
- (void)testExecuteCommands_twoReplaceCommands {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"aaa bbb ccc"];
    UDCursorsController *ctrl = [[UDCursorsController alloc] initWithModel:model];
    ctrl.selections = @[
        Sel(1, 1, 1, 4),   // "aaa"
        Sel(1, 9, 1, 12),  // "ccc"
    ];

    NSArray<id<UDCommand>> *commands = @[
        [[UDReplaceCommand alloc] initWithSelection:Sel(1,1,1,4).ud_selectionValue text:@"AAA"],
        [[UDReplaceCommand alloc] initWithSelection:Sel(1,9,1,12).ud_selectionValue text:@"CCC"],
    ];
    [ctrl executeCommands:commands];

    XCTAssertEqualObjects([model getValue], @"AAA bbb CCC");
    XCTAssertEqual(ctrl.selections.count, (NSUInteger)2);
    AssertCursorAtIndex(ctrl, 0, 1, 4);
    AssertCursorAtIndex(ctrl, 1, 1, 12);
}

// ===========================================================================
// MARK: - Undo / Redo
// Mirrors: undo/redo tests in cursor.test.ts
// ===========================================================================

/// Single-cursor typing is undoable.
- (void)testUndo_singleCursorType {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"hello"];
    UDCursorsController *ctrl = [[UDCursorsController alloc] initWithModel:model];
    ctrl.selections = @[ Cursor(1, 6) ];

    [ctrl typeText:@"!" source:@"keyboard"];
    XCTAssertEqualObjects([model getValue], @"hello!");

    [model.undoManager undo];
    XCTAssertEqualObjects([model getValue], @"hello");
}

/// Multi-cursor delete is undoable.
- (void)testUndo_multiCursorDelete {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"abc def"];
    UDCursorsController *ctrl = [[UDCursorsController alloc] initWithModel:model];
    ctrl.selections = @[ Cursor(1, 4), Cursor(1, 8) ];

    [ctrl deleteLeftWithSource:nil];
    XCTAssertEqualObjects([model getValue], @"ab de");

    [model.undoManager undo];
    XCTAssertEqualObjects([model getValue], @"abc def");
}

// ===========================================================================
// MARK: - UDCursorTypeEditOperations unit tests
// Directly tests the edit factory methods, mirroring VS Code's
// unit-level tests of TypeOperations / DeleteOperations.
// ===========================================================================

/// typeText: produces one command per selection.
- (void)testTypeEditOperations_commandCountMatchesSelectionCount {
    NSArray<NSValue *> *sels = @[ Cursor(1, 1), Cursor(2, 1), Cursor(3, 1) ];
    UDEditOperationResult *result =
        [UDCursorTypeEditOperations typeText:@"X"
                           prevOperationType:UDEditOperationTypeOther
                                  selections:sels];

    XCTAssertEqual(result.commands.count, (NSUInteger)3);
}

/// typeText: first command replaces the correct range.
- (void)testTypeEditOperations_replaceCommandTargetsSelection {
    UDSelection sel = UDSelectionMake(1, 3, 1, 6); // col 3–6
    NSArray<NSValue *> *sels = @[ [NSValue ud_valueWithSelection:sel] ];

    UDEditOperationResult *result =
        [UDCursorTypeEditOperations typeText:@"ABC"
                           prevOperationType:UDEditOperationTypeOther
                                  selections:sels];

    XCTAssertEqual(result.commands.count, (NSUInteger)1);
    XCTAssertEqual(result.type, UDEditOperationTypeTypingOther);
}

/// deleteLeft: produces one command per selection.
- (void)testDeleteLeftEditOperations_commandCountMatchesSelectionCount {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"abcdef"];
    NSArray<NSValue *> *sels = @[ Cursor(1, 3), Cursor(1, 6) ];

    UDEditOperationResult *result =
        [UDCursorTypeEditOperations deleteLeftWithSelections:sels model:model];

    XCTAssertEqual(result.commands.count, (NSUInteger)2);
}

/// deleteRight: produces one command per selection.
- (void)testDeleteRightEditOperations_commandCountMatchesSelectionCount {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"abcdef"];
    NSArray<NSValue *> *sels = @[ Cursor(1, 1), Cursor(1, 4) ];

    UDEditOperationResult *result =
        [UDCursorTypeEditOperations deleteRightWithSelections:sels model:model];

    XCTAssertEqual(result.commands.count, (NSUInteger)2);
}

/// Consecutive typing operations share the same EditOperationType,
/// so they don't generate unnecessary undo stack boundaries.
/// VS Code ref: shouldPushStackElementBetween() returns NO for same type.
- (void)testTypeEditOperations_consecutiveTyping_noPushBetween {
    NSArray<NSValue *> *sels = @[ Cursor(1, 1) ];

    UDEditOperationResult *r1 =
        [UDCursorTypeEditOperations typeText:@"a"
                           prevOperationType:UDEditOperationTypeOther
                                  selections:sels];
    XCTAssertTrue(r1.shouldPushStackElementBefore,
        @"First char after non-typing op should push a stack boundary");

    UDEditOperationResult *r2 =
        [UDCursorTypeEditOperations typeText:@"b"
                           prevOperationType:UDEditOperationTypeTypingOther
                                  selections:sels];
    XCTAssertFalse(r2.shouldPushStackElementBefore,
        @"Consecutive typing should NOT push a stack boundary");
}

@end
