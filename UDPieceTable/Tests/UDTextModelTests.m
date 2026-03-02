// UDTextModelTests.m
// Tests for the VS Code TextModel port (UDTextModel).

#import <XCTest/XCTest.h>
#import "UDTextModel.h"

@interface UDTextModelTests : XCTestCase
@end

@implementation UDTextModelTests

// MARK: - Initialisation

- (void)testInitWithEmptyText {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@""];
    XCTAssertEqualObjects([model getValue], @"");
    XCTAssertEqual([model getLineCount], (NSInteger)1);
    XCTAssertEqual([model getLength],    (NSInteger)0);
}

- (void)testInitWithSingleLine {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"Hello, World!"];
    XCTAssertEqualObjects([model getValue], @"Hello, World!");
    XCTAssertEqual([model getLineCount], (NSInteger)1);
    XCTAssertEqual([model getLength],    (NSInteger)13);
}

- (void)testInitWithMultipleLines {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"line1\nline2\nline3"];
    XCTAssertEqual([model getLineCount], (NSInteger)3);
    XCTAssertEqualObjects([model getLineContent:1], @"line1");
    XCTAssertEqualObjects([model getLineContent:2], @"line2");
    XCTAssertEqualObjects([model getLineContent:3], @"line3");
}

// MARK: - getValueInRange

- (void)testGetValueInRange_singleLine {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"Hello, World!"];
    NSString *val = [model getValueInRange:PTRangeMake(1, 1, 1, 6)];
    XCTAssertEqualObjects(val, @"Hello");
}

- (void)testGetValueInRange_multiLine {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"abc\ndef\nghi"];
    // From line 1 col 2 to line 2 col 3 → "bc\nde"
    NSString *val = [model getValueInRange:PTRangeMake(1, 2, 2, 3)];
    XCTAssertEqualObjects(val, @"bc\nde");
}

// MARK: - getPositionAt / getOffsetAt

- (void)testPositionRoundTrip {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"abc\ndef"];
    // offset 0 → (1,1)
    UDPosition p = [model getPositionAt:0];
    XCTAssertEqual(p.line,   (NSInteger)1);
    XCTAssertEqual(p.column, (NSInteger)1);
    // offset 4 → (2,1) (after the \n)
    p = [model getPositionAt:4];
    XCTAssertEqual(p.line,   (NSInteger)2);
    XCTAssertEqual(p.column, (NSInteger)1);
    // round-trip
    NSInteger off = [model getOffsetAt:2 column:2];
    XCTAssertEqual(off, (NSInteger)5); // "d" is at offset 4; col 2 = offset 5
}

// MARK: - applyEdits: insert

- (void)testApplyEdits_insert {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"Hello World"];
    // Insert ", beautiful" between "Hello" and " World"
    UDRange insertRange = PTRangeMake(1, 6, 1, 6); // collapsed range at col 6
    UDTextModelEdit *edit = [[UDTextModelEdit alloc] initWithRange:insertRange
                                                              text:@", beautiful"];
    [model applyEdits:@[edit]];
    XCTAssertEqualObjects([model getValue], @"Hello, beautiful World");
}

// MARK: - applyEdits: delete

- (void)testApplyEdits_delete {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"Hello, World!"];
    // Delete ", " (cols 6-8 on line 1 → range [1,6),[1,8))
    UDTextModelEdit *edit = [[UDTextModelEdit alloc] initWithRange:PTRangeMake(1, 6, 1, 8)
                                                              text:@""];
    [model applyEdits:@[edit]];
    XCTAssertEqualObjects([model getValue], @"Hello World!");
}

// MARK: - applyEdits: replace

- (void)testApplyEdits_replace {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"Hello World"];
    UDTextModelEdit *edit = [[UDTextModelEdit alloc] initWithRange:PTRangeMake(1, 7, 1, 12)
                                                              text:@"Swift"];
    [model applyEdits:@[edit]];
    XCTAssertEqualObjects([model getValue], @"Hello Swift");
}

// MARK: - applyEdits: multiple edits

- (void)testApplyEdits_multipleEdits {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"aaa bbb ccc"];
    // Replace "aaa" with "AAA" and "ccc" with "CCC" simultaneously.
    UDTextModelEdit *e1 = [[UDTextModelEdit alloc] initWithRange:PTRangeMake(1, 1, 1, 4)
                                                            text:@"AAA"];
    UDTextModelEdit *e2 = [[UDTextModelEdit alloc] initWithRange:PTRangeMake(1, 9, 1, 12)
                                                            text:@"CCC"];
    [model applyEdits:@[e1, e2]];
    XCTAssertEqualObjects([model getValue], @"AAA bbb CCC");
}

// MARK: - Undo

- (void)testUndo_singleEdit {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"Hello World"];
    UDTextModelEdit *edit = [[UDTextModelEdit alloc] initWithRange:PTRangeMake(1, 7, 1, 12)
                                                              text:@"Swift"];
    [model applyEdits:@[edit]];
    XCTAssertEqualObjects([model getValue], @"Hello Swift");

    [model.undoManager undo];
    XCTAssertEqualObjects([model getValue], @"Hello World");
}

- (void)testRedo_singleEdit {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"Hello World"];
    UDTextModelEdit *edit = [[UDTextModelEdit alloc] initWithRange:PTRangeMake(1, 7, 1, 12)
                                                              text:@"Swift"];
    [model applyEdits:@[edit]];
    [model.undoManager undo];
    XCTAssertEqualObjects([model getValue], @"Hello World");

    [model.undoManager redo];
    XCTAssertEqualObjects([model getValue], @"Hello Swift");
}

- (void)testUndo_multipleEdits {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"Hello World"];
    UDTextModelEdit *e1 = [[UDTextModelEdit alloc] initWithRange:PTRangeMake(1, 1, 1, 6)
                                                            text:@"Hi"];
    UDTextModelEdit *e2 = [[UDTextModelEdit alloc] initWithRange:PTRangeMake(1, 7, 1, 12)
                                                            text:@"Earth"];
    [model applyEdits:@[e1, e2]];
    XCTAssertEqualObjects([model getValue], @"Hi Earth");

    [model.undoManager undo];
    XCTAssertEqualObjects([model getValue], @"Hello World");
}

// MARK: - Decorations

- (void)testDeltaDecorations_add {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"Hello World"];
    UDDecorationOptions *opts = [[UDDecorationOptions alloc] initWithClassName:@"highlight"
                                                                      userInfo:@"my-info"];
    UDModelDeltaDecoration *delta =
        [[UDModelDeltaDecoration alloc] initWithRange:PTRangeMake(1, 1, 1, 6)
                                              options:opts];
    NSArray<NSString *> *ids = [model deltaDecorations:nil newDecorations:@[delta]];
    XCTAssertEqual(ids.count, (NSUInteger)1);

    UDRange r = [model rangeForDecoration:ids[0]];
    XCTAssertEqual(r.startLineNumber, (NSInteger)1);
    XCTAssertEqual(r.startColumn,     (NSInteger)1);
    XCTAssertEqual(r.endLineNumber,   (NSInteger)1);
    XCTAssertEqual(r.endColumn,       (NSInteger)6);
}

- (void)testDeltaDecorations_options {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"Hello World"];
    UDDecorationOptions *opts = [[UDDecorationOptions alloc] initWithClassName:@"error"
                                                                      userInfo:@{@"msg": @"oops"}];
    UDModelDeltaDecoration *delta =
        [[UDModelDeltaDecoration alloc] initWithRange:PTRangeMake(1, 7, 1, 12)
                                              options:opts];
    NSArray<NSString *> *ids = [model deltaDecorations:nil newDecorations:@[delta]];
    UDDecorationOptions *returned = [model optionsForDecoration:ids[0]];
    XCTAssertEqualObjects(returned.className, @"error");
    XCTAssertEqualObjects(returned.userInfo[@"msg"], @"oops");
}

- (void)testDeltaDecorations_remove {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"Hello World"];
    UDDecorationOptions *opts = [[UDDecorationOptions alloc] initWithClassName:@"x"
                                                                      userInfo:nil];
    UDModelDeltaDecoration *delta =
        [[UDModelDeltaDecoration alloc] initWithRange:PTRangeMake(1, 1, 1, 6)
                                              options:opts];
    NSArray<NSString *> *ids = [model deltaDecorations:nil newDecorations:@[delta]];
    // Now remove it.
    NSArray<NSString *> *newIds = [model deltaDecorations:ids newDecorations:@[]];
    XCTAssertEqual(newIds.count, (NSUInteger)0);
    XCTAssertNil([model optionsForDecoration:ids[0]]);
    // rangeForDecoration: returns an all-zero sentinel for unknown IDs.
    UDRange r = [model rangeForDecoration:ids[0]];
    XCTAssertEqual(r.startLineNumber, (NSInteger)0);
    XCTAssertEqual(r.startColumn,     (NSInteger)0);
}

- (void)testDecoration_rangeTrackedAfterInsertBefore {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"Hello World"];
    UDDecorationOptions *opts = [[UDDecorationOptions alloc] initWithClassName:@"x"
                                                                      userInfo:nil];
    // Decorate "World" (cols 7-12)
    UDModelDeltaDecoration *delta =
        [[UDModelDeltaDecoration alloc] initWithRange:PTRangeMake(1, 7, 1, 12)
                                              options:opts];
    NSArray<NSString *> *ids = [model deltaDecorations:nil newDecorations:@[delta]];

    // Insert "Beautiful " before "World" (at col 7)
    UDTextModelEdit *edit = [[UDTextModelEdit alloc] initWithRange:PTRangeMake(1, 7, 1, 7)
                                                              text:@"Beautiful "];
    [model applyEdits:@[edit]];

    // "World" decoration should have shifted by 10 chars.
    UDRange r = [model rangeForDecoration:ids[0]];
    XCTAssertEqual(r.startColumn, (NSInteger)17); // 7 + 10
    XCTAssertEqual(r.endColumn,   (NSInteger)22); // 12 + 10
}

- (void)testDecoration_rangeTrackedAfterDeleteBefore {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"Hello World"];
    UDDecorationOptions *opts = [[UDDecorationOptions alloc] initWithClassName:@"x"
                                                                      userInfo:nil];
    // Decorate "World" (cols 7-12)
    UDModelDeltaDecoration *delta =
        [[UDModelDeltaDecoration alloc] initWithRange:PTRangeMake(1, 7, 1, 12)
                                              options:opts];
    NSArray<NSString *> *ids = [model deltaDecorations:nil newDecorations:@[delta]];

    // Delete "Hello " (cols 1-7)
    UDTextModelEdit *edit = [[UDTextModelEdit alloc] initWithRange:PTRangeMake(1, 1, 1, 7)
                                                              text:@""];
    [model applyEdits:@[edit]];

    // "World" decoration should have shifted back by 6 chars to col 1-6.
    UDRange r = [model rangeForDecoration:ids[0]];
    XCTAssertEqual(r.startColumn, (NSInteger)1);
    XCTAssertEqual(r.endColumn,   (NSInteger)6);
}

// MARK: - Decoration owners

- (void)testOwner_addWithOwner {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"Hello World"];
    UDDecorationOptions *opts = [[UDDecorationOptions alloc] initWithClassName:@"highlight"
                                                                      userInfo:nil];
    UDModelDeltaDecoration *delta =
        [[UDModelDeltaDecoration alloc] initWithRange:PTRangeMake(1, 1, 1, 6)
                                              options:opts];
    NSArray<NSString *> *ids = [model deltaDecorations:nil
                                        newDecorations:@[delta]
                                                 owner:@"syntax"];
    XCTAssertEqual(ids.count, (NSUInteger)1);

    UDRange r = [model rangeForDecoration:ids[0]];
    XCTAssertEqual(r.startColumn, (NSInteger)1);
    XCTAssertEqual(r.endColumn,   (NSInteger)6);
}

- (void)testOwner_isolation_cannotRemoveForeignDecoration {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"Hello World"];
    UDDecorationOptions *opts = [[UDDecorationOptions alloc] initWithClassName:@"x"
                                                                      userInfo:nil];

    // ownerA adds a decoration
    UDModelDeltaDecoration *d =
        [[UDModelDeltaDecoration alloc] initWithRange:PTRangeMake(1, 1, 1, 6)
                                              options:opts];
    NSArray<NSString *> *idsA = [model deltaDecorations:nil
                                         newDecorations:@[d]
                                                  owner:@"ownerA"];

    // ownerB tries to remove ownerA's ID — should be silently ignored
    [model deltaDecorations:idsA newDecorations:@[] owner:@"ownerB"];

    // ownerA's decoration is still present
    XCTAssertNotNil([model optionsForDecoration:idsA[0]]);
}

- (void)testOwner_canRemoveOwnDecoration {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"Hello World"];
    UDDecorationOptions *opts = [[UDDecorationOptions alloc] initWithClassName:@"x"
                                                                      userInfo:nil];
    UDModelDeltaDecoration *d =
        [[UDModelDeltaDecoration alloc] initWithRange:PTRangeMake(1, 1, 1, 6)
                                              options:opts];
    NSArray<NSString *> *ids = [model deltaDecorations:nil
                                        newDecorations:@[d]
                                                 owner:@"ownerA"];

    // Same owner removes it
    [model deltaDecorations:ids newDecorations:@[] owner:@"ownerA"];
    XCTAssertNil([model optionsForDecoration:ids[0]]);
}

- (void)testOwner_differentOwnersCoexist {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"Hello World"];
    UDDecorationOptions *opts = [[UDDecorationOptions alloc] initWithClassName:@"x"
                                                                      userInfo:nil];

    UDModelDeltaDecoration *dA =
        [[UDModelDeltaDecoration alloc] initWithRange:PTRangeMake(1, 1, 1, 6)
                                              options:opts];
    UDModelDeltaDecoration *dB =
        [[UDModelDeltaDecoration alloc] initWithRange:PTRangeMake(1, 7, 1, 12)
                                              options:opts];
    NSArray<NSString *> *idsA = [model deltaDecorations:nil
                                         newDecorations:@[dA]
                                                  owner:@"ownerA"];
    NSArray<NSString *> *idsB = [model deltaDecorations:nil
                                         newDecorations:@[dB]
                                                  owner:@"ownerB"];

    // Both decorations exist independently
    XCTAssertNotNil([model optionsForDecoration:idsA[0]]);
    XCTAssertNotNil([model optionsForDecoration:idsB[0]]);
}

- (void)testDecorationsForOwner {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"Hello World"];
    UDDecorationOptions *opts = [[UDDecorationOptions alloc] initWithClassName:@"x"
                                                                      userInfo:nil];

    UDModelDeltaDecoration *d1 =
        [[UDModelDeltaDecoration alloc] initWithRange:PTRangeMake(1, 1, 1, 3)
                                              options:opts];
    UDModelDeltaDecoration *d2 =
        [[UDModelDeltaDecoration alloc] initWithRange:PTRangeMake(1, 4, 1, 6)
                                              options:opts];
    UDModelDeltaDecoration *d3 =
        [[UDModelDeltaDecoration alloc] initWithRange:PTRangeMake(1, 7, 1, 12)
                                              options:opts];

    NSArray<NSString *> *idsA = [model deltaDecorations:nil
                                         newDecorations:@[d1, d2]
                                                  owner:@"ownerA"];
    [model deltaDecorations:nil newDecorations:@[d3] owner:@"ownerB"];

    NSArray<NSString *> *forA = [model decorationsForOwner:@"ownerA"];
    XCTAssertEqual(forA.count, (NSUInteger)2);
    NSSet<NSString *> *forASet = [NSSet setWithArray:forA];
    XCTAssertTrue([forASet containsObject:idsA[0]]);
    XCTAssertTrue([forASet containsObject:idsA[1]]);

    NSArray<NSString *> *forB = [model decorationsForOwner:@"ownerB"];
    XCTAssertEqual(forB.count, (NSUInteger)1);
}

- (void)testDecorationsForOwner_nil {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"Hello World"];
    UDDecorationOptions *opts = [[UDDecorationOptions alloc] initWithClassName:@"x"
                                                                      userInfo:nil];

    UDModelDeltaDecoration *d =
        [[UDModelDeltaDecoration alloc] initWithRange:PTRangeMake(1, 1, 1, 6)
                                              options:opts];
    // Anonymous owner (nil)
    NSArray<NSString *> *anonIds = [model deltaDecorations:nil newDecorations:@[d]];

    NSArray<NSString *> *forNil = [model decorationsForOwner:nil];
    XCTAssertEqual(forNil.count, (NSUInteger)1);
    XCTAssertEqualObjects(forNil[0], anonIds[0]);
}



- (void)testChangeNotificationIsPosted {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"Hello"];
    __block BOOL received = NO;
    id observer = [[NSNotificationCenter defaultCenter]
                   addObserverForName:UDTextModelDidChangeNotification
                               object:model
                                queue:nil
                           usingBlock:^(NSNotification *note) {
        received = YES;
        XCTAssertNotNil(note.userInfo[@"edits"]);
    }];
    UDTextModelEdit *edit = [[UDTextModelEdit alloc] initWithRange:PTRangeMake(1, 6, 1, 6)
                                                              text:@" World"];
    [model applyEdits:@[edit]];
    [[NSNotificationCenter defaultCenter] removeObserver:observer];
    XCTAssertTrue(received);
}

// MARK: - Search

- (void)testFindMatches_simple {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"foo bar foo"];
    NSArray<UDFindMatch *> *matches = [model findMatches:@"foo"
                                                 isRegex:NO
                                               matchCase:YES
                                          wordSeparators:nil
                                        limitResultCount:100];
    XCTAssertEqual(matches.count, (NSUInteger)2);
    XCTAssertEqual(matches[0].range.startColumn, (NSInteger)1);
    XCTAssertEqual(matches[1].range.startColumn, (NSInteger)9);
}

- (void)testFindMatches_regex {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"abc 123 def 456"];
    NSArray<UDFindMatch *> *matches = [model findMatches:@"\\d+"
                                                 isRegex:YES
                                               matchCase:NO
                                          wordSeparators:nil
                                        limitResultCount:100];
    XCTAssertEqual(matches.count, (NSUInteger)2);
}

- (void)testFindMatches_noResults {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"Hello World"];
    NSArray<UDFindMatch *> *matches = [model findMatches:@"xyz"
                                                 isRegex:NO
                                               matchCase:YES
                                          wordSeparators:nil
                                        limitResultCount:100];
    XCTAssertEqual(matches.count, (NSUInteger)0);
}

@end
