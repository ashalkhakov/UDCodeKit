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
    XCTAssertEqualObjects([model getValue], @"HelloWorld!");
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

// MARK: - EOL

- (void)testGetEOL_default_lf {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"line1\nline2"];
    XCTAssertEqualObjects([model getEOL], @"\n");
}

- (void)testGetEOL_crlf {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"line1\r\nline2"];
    XCTAssertEqualObjects([model getEOL], @"\r\n");
}

- (void)testGetEOL_cr {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"line1\rline2"];
    XCTAssertEqualObjects([model getEOL], @"\r");
}

- (void)testGetEOL_noLineEnding_defaultsToLF {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"single line"];
    XCTAssertEqualObjects([model getEOL], @"\n");
}

- (void)testSetEOL_convertsToLF {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"a\r\nb\r\nc"];
    [model setEOL:@"\n"];
    XCTAssertEqualObjects([model getEOL], @"\n");
    // After normalizing the content must be intact
    XCTAssertEqual([model getLineCount], (NSInteger)3);
    XCTAssertEqualObjects([model getLineContent:1], @"a");
    XCTAssertEqualObjects([model getLineContent:2], @"b");
    XCTAssertEqualObjects([model getLineContent:3], @"c");
}

- (void)testSetEOL_convertsToCRLF {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"a\nb\nc"];
    [model setEOL:@"\r\n"];
    XCTAssertEqualObjects([model getEOL], @"\r\n");
    XCTAssertEqual([model getLineCount], (NSInteger)3);
}

// MARK: - findNextMatch / findPreviousMatch

- (void)testFindNextMatch_basic {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"foo bar foo"];
    UDPosition start = {1, 1};
    UDFindMatch *m = [model findNextMatch:@"foo"
                                  isRegex:NO
                                matchCase:YES
                           wordSeparators:nil
                                     from:start];
    XCTAssertNotNil(m);
    XCTAssertEqual(m.range.startColumn, (NSInteger)1);
}

- (void)testFindNextMatch_fromMiddle {
    // Starting after the first match should find the second.
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"foo bar foo"];
    UDPosition start = {1, 4}; // after "foo"
    UDFindMatch *m = [model findNextMatch:@"foo"
                                  isRegex:NO
                                matchCase:YES
                           wordSeparators:nil
                                     from:start];
    XCTAssertNotNil(m);
    XCTAssertEqual(m.range.startColumn, (NSInteger)9);
}

- (void)testFindNextMatch_wrapsAround {
    // Starting after the last match should wrap to the first.
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"foo bar foo"];
    UDPosition start = {1, 10}; // after the second "foo"
    UDFindMatch *m = [model findNextMatch:@"foo"
                                  isRegex:NO
                                matchCase:YES
                           wordSeparators:nil
                                     from:start];
    XCTAssertNotNil(m);
    XCTAssertEqual(m.range.startColumn, (NSInteger)1);
}

- (void)testFindNextMatch_noMatch {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"hello world"];
    UDPosition start = {1, 1};
    UDFindMatch *m = [model findNextMatch:@"xyz"
                                  isRegex:NO
                                matchCase:YES
                           wordSeparators:nil
                                     from:start];
    XCTAssertNil(m);
}

- (void)testFindPreviousMatch_basic {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"foo bar foo"];
    // Position is after both matches — previous should be second "foo"
    UDPosition start = {1, 12};
    UDFindMatch *m = [model findPreviousMatch:@"foo"
                                      isRegex:NO
                                    matchCase:YES
                               wordSeparators:nil
                                         from:start];
    XCTAssertNotNil(m);
    XCTAssertEqual(m.range.startColumn, (NSInteger)9);
}

- (void)testFindPreviousMatch_wrapsAround {
    // Position is before all matches — wrap to last match in document.
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"foo bar foo"];
    UDPosition start = {1, 1};
    UDFindMatch *m = [model findPreviousMatch:@"foo"
                                      isRegex:NO
                                    matchCase:YES
                               wordSeparators:nil
                                         from:start];
    XCTAssertNotNil(m);
    XCTAssertEqual(m.range.startColumn, (NSInteger)9);
}

- (void)testFindPreviousMatch_noMatch {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"hello world"];
    UDPosition start = {1, 6};
    UDFindMatch *m = [model findPreviousMatch:@"xyz"
                                      isRegex:NO
                                    matchCase:YES
                               wordSeparators:nil
                                         from:start];
    XCTAssertNil(m);
}

// MARK: - decorationsInRange

- (void)testDecorationsInRange_findsOverlapping {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"Hello World"];
    UDDecorationOptions *opts = [[UDDecorationOptions alloc] initWithClassName:@"x"
                                                                      userInfo:nil];
    // "Hello" [col 1..6)
    UDModelDeltaDecoration *d1 =
        [[UDModelDeltaDecoration alloc] initWithRange:PTRangeMake(1, 1, 1, 6) options:opts];
    // "World" [col 7..12)
    UDModelDeltaDecoration *d2 =
        [[UDModelDeltaDecoration alloc] initWithRange:PTRangeMake(1, 7, 1, 12) options:opts];

    NSArray<NSString *> *ids =
        [model deltaDecorations:nil newDecorations:@[d1, d2]];

    // Query the range covering all of "Hello" [col 1..6)
    NSArray<NSString *> *found = [model decorationsInRange:PTRangeMake(1, 1, 1, 6)];
    XCTAssertEqual(found.count, (NSUInteger)1);
    XCTAssertEqualObjects(found[0], ids[0]);
}

- (void)testDecorationsInRange_emptyWhenNoneOverlap {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"Hello World"];
    UDDecorationOptions *opts = [[UDDecorationOptions alloc] initWithClassName:@"x"
                                                                      userInfo:nil];
    UDModelDeltaDecoration *d =
        [[UDModelDeltaDecoration alloc] initWithRange:PTRangeMake(1, 7, 1, 12) options:opts];
    [model deltaDecorations:nil newDecorations:@[d]];

    // Query a range that doesn't overlap [col 1..2)
    NSArray<NSString *> *found = [model decorationsInRange:PTRangeMake(1, 1, 1, 2)];
    XCTAssertEqual(found.count, (NSUInteger)0);
}

- (void)testDecorationsInRange_multipleOverlapping {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"Hello World"];
    UDDecorationOptions *opts = [[UDDecorationOptions alloc] initWithClassName:@"x"
                                                                      userInfo:nil];
    UDModelDeltaDecoration *d1 =
        [[UDModelDeltaDecoration alloc] initWithRange:PTRangeMake(1, 1, 1, 6) options:opts];
    UDModelDeltaDecoration *d2 =
        [[UDModelDeltaDecoration alloc] initWithRange:PTRangeMake(1, 3, 1, 9) options:opts];
    [model deltaDecorations:nil newDecorations:@[d1, d2]];

    // Both overlap [1,1..1,7)
    NSArray<NSString *> *found = [model decorationsInRange:PTRangeMake(1, 1, 1, 7)];
    XCTAssertEqual(found.count, (NSUInteger)2);
}

// MARK: - TrackedRangeStickiness

- (void)testStickiness_neverGrows_insertAtStart {
    // NeverGrowsWhenTypingAtEdges: insertion at the start of the range pushes it right.
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"Hello World"];
    UDDecorationOptions *opts = [[UDDecorationOptions alloc] initWithClassName:@"x"
                                                                      userInfo:nil];
    UDModelDeltaDecoration *delta =
        [[UDModelDeltaDecoration alloc] initWithRange:PTRangeMake(1, 7, 1, 12) options:opts];
    delta.stickiness = UDTrackedRangeNeverGrowsWhenTypingAtEdges;
    NSArray<NSString *> *ids = [model deltaDecorations:nil newDecorations:@[delta]];

    // Insert 3 chars exactly at col 7 (the start of the decoration)
    UDTextModelEdit *edit = [[UDTextModelEdit alloc] initWithRange:PTRangeMake(1, 7, 1, 7)
                                                              text:@"XXX"];
    [model applyEdits:@[edit]];

    // With NeverGrows: start is pushed right by 3 → col 10, end shifts to col 15
    UDRange r = [model rangeForDecoration:ids[0]];
    XCTAssertEqual(r.startColumn, (NSInteger)10);
    XCTAssertEqual(r.endColumn,   (NSInteger)15);
}

- (void)testStickiness_alwaysGrows_insertAtStart {
    // AlwaysGrowsWhenTypingAtEdges: insertion at the start expands the range leftward.
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"Hello World"];
    UDDecorationOptions *opts = [[UDDecorationOptions alloc] initWithClassName:@"x"
                                                                      userInfo:nil];
    UDModelDeltaDecoration *delta =
        [[UDModelDeltaDecoration alloc] initWithRange:PTRangeMake(1, 7, 1, 12) options:opts];
    delta.stickiness = UDTrackedRangeAlwaysGrowsWhenTypingAtEdges;
    NSArray<NSString *> *ids = [model deltaDecorations:nil newDecorations:@[delta]];

    // Insert 3 chars exactly at col 7
    UDTextModelEdit *edit = [[UDTextModelEdit alloc] initWithRange:PTRangeMake(1, 7, 1, 7)
                                                              text:@"XXX"];
    [model applyEdits:@[edit]];

    // With AlwaysGrows: start absorbs insert → stays at col 7, end shifts to col 15
    UDRange r = [model rangeForDecoration:ids[0]];
    XCTAssertEqual(r.startColumn, (NSInteger)7);
    XCTAssertEqual(r.endColumn,   (NSInteger)15);
}

- (void)testStickiness_alwaysGrows_insertAtEnd {
    // AlwaysGrowsWhenTypingAtEdges: insertion at the end expands the range rightward.
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"Hello World"];
    UDDecorationOptions *opts = [[UDDecorationOptions alloc] initWithClassName:@"x"
                                                                      userInfo:nil];
    UDModelDeltaDecoration *delta =
        [[UDModelDeltaDecoration alloc] initWithRange:PTRangeMake(1, 7, 1, 12) options:opts];
    delta.stickiness = UDTrackedRangeAlwaysGrowsWhenTypingAtEdges;
    NSArray<NSString *> *ids = [model deltaDecorations:nil newDecorations:@[delta]];

    // Insert 3 chars at col 12 (the end of the decoration)
    UDTextModelEdit *edit = [[UDTextModelEdit alloc] initWithRange:PTRangeMake(1, 12, 1, 12)
                                                              text:@"XXX"];
    [model applyEdits:@[edit]];

    // With AlwaysGrows: end grows right → col 15, start unchanged at col 7
    UDRange r = [model rangeForDecoration:ids[0]];
    XCTAssertEqual(r.startColumn, (NSInteger)7);
    XCTAssertEqual(r.endColumn,   (NSInteger)15);
}

- (void)testStickiness_neverGrows_insertAtEnd {
    // NeverGrowsWhenTypingAtEdges: insertion at the end does not expand the range.
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"Hello World"];
    UDDecorationOptions *opts = [[UDDecorationOptions alloc] initWithClassName:@"x"
                                                                      userInfo:nil];
    UDModelDeltaDecoration *delta =
        [[UDModelDeltaDecoration alloc] initWithRange:PTRangeMake(1, 7, 1, 12) options:opts];
    delta.stickiness = UDTrackedRangeNeverGrowsWhenTypingAtEdges;
    NSArray<NSString *> *ids = [model deltaDecorations:nil newDecorations:@[delta]];

    // Insert 3 chars at col 12
    UDTextModelEdit *edit = [[UDTextModelEdit alloc] initWithRange:PTRangeMake(1, 12, 1, 12)
                                                              text:@"XXX"];
    [model applyEdits:@[edit]];

    // With NeverGrows: end stays at col 12, start stays at col 7
    UDRange r = [model rangeForDecoration:ids[0]];
    XCTAssertEqual(r.startColumn, (NSInteger)7);
    XCTAssertEqual(r.endColumn,   (NSInteger)12);
}

// MARK: - nodesInRange binary-search correctness

/// Helper: create a decoration covering [startOff, endOff) (0-based offsets).
- (UDModelDeltaDecoration *)_decorationFrom:(NSUInteger)startOff
                                         to:(NSUInteger)endOff
                                  inModel:(UDTextModel *)model {
    UDDecorationOptions *opts =
        [[UDDecorationOptions alloc] initWithClassName:@"t" userInfo:nil];
    UDPosition sp = [model getPositionAt:(NSInteger)startOff];
    UDPosition ep = [model getPositionAt:(NSInteger)endOff];
    return [[UDModelDeltaDecoration alloc]
                initWithRange:PTRangeMake(sp.line, sp.column, ep.line, ep.column)
                      options:opts];
}

- (void)testNodesInOffsetRange_noDecorations {
    UDTextModel *m = [[UDTextModel alloc] initWithText:@"Hello World"];
    NSArray *nodes = [m decorationNodesInOffsetRange:0 end:5];
    XCTAssertEqual(nodes.count, (NSUInteger)0);
}

- (void)testNodesInOffsetRange_queryBeforeAllNodes {
    // Single decoration covering offsets [6, 11).  Query [0, 5) should return nothing.
    UDTextModel *m = [[UDTextModel alloc] initWithText:@"Hello World"];
    UDModelDeltaDecoration *d = [self _decorationFrom:6 to:11 inModel:m];
    [m deltaDecorations:nil newDecorations:@[d]];

    NSArray *nodes = [m decorationNodesInOffsetRange:0 end:5];
    XCTAssertEqual(nodes.count, (NSUInteger)0);
}

- (void)testNodesInOffsetRange_queryAfterAllNodes {
    // Single decoration covering [0, 5).  Query [6, 11) should return nothing.
    UDTextModel *m = [[UDTextModel alloc] initWithText:@"Hello World"];
    UDModelDeltaDecoration *d = [self _decorationFrom:0 to:5 inModel:m];
    [m deltaDecorations:nil newDecorations:@[d]];

    NSArray *nodes = [m decorationNodesInOffsetRange:6 end:11];
    XCTAssertEqual(nodes.count, (NSUInteger)0);
}

- (void)testNodesInOffsetRange_exactBoundaryMatch {
    // Decoration [3, 7).  Query [3, 7) should return it.
    UDTextModel *m = [[UDTextModel alloc] initWithText:@"Hello World"];
    UDModelDeltaDecoration *d = [self _decorationFrom:3 to:7 inModel:m];
    [m deltaDecorations:nil newDecorations:@[d]];

    NSArray *nodes = [m decorationNodesInOffsetRange:3 end:7];
    XCTAssertEqual(nodes.count, (NSUInteger)1);
}

- (void)testNodesInOffsetRange_queryEndEqualsNodeStart {
    // Decoration [5, 8).  Query [2, 5) must NOT include it (open interval at right end).
    UDTextModel *m = [[UDTextModel alloc] initWithText:@"Hello World"];
    UDModelDeltaDecoration *d = [self _decorationFrom:5 to:8 inModel:m];
    [m deltaDecorations:nil newDecorations:@[d]];

    NSArray *nodes = [m decorationNodesInOffsetRange:2 end:5];
    XCTAssertEqual(nodes.count, (NSUInteger)0);
}

- (void)testNodesInOffsetRange_queryStartEqualsNodeEnd {
    // Decoration [2, 5).  Query [5, 8) must NOT include it.
    UDTextModel *m = [[UDTextModel alloc] initWithText:@"Hello World"];
    UDModelDeltaDecoration *d = [self _decorationFrom:2 to:5 inModel:m];
    [m deltaDecorations:nil newDecorations:@[d]];

    NSArray *nodes = [m decorationNodesInOffsetRange:5 end:8];
    XCTAssertEqual(nodes.count, (NSUInteger)0);
}

- (void)testNodesInOffsetRange_manyNonOverlapping {
    // 100 sequential non-overlapping tokens: token i covers [i*3, i*3+2).
    // Verify that only the token(s) actually overlapping the query range
    // are returned, not all 100.
    NSInteger tokenCount = 100;
    NSMutableString *text = [NSMutableString string];
    for (NSInteger i = 0; i < tokenCount; i++) { [text appendString:@"ab "]; }
    UDTextModel *m = [[UDTextModel alloc] initWithText:text];

    NSMutableArray *decors = [NSMutableArray arrayWithCapacity:tokenCount];
    for (NSInteger i = 0; i < tokenCount; i++) {
        [decors addObject:[self _decorationFrom:(NSUInteger)(i * 3)
                                             to:(NSUInteger)(i * 3 + 2)
                                        inModel:m]];
    }
    [m deltaDecorations:nil newDecorations:decors];

    // Query the 50th token's range (offsets [150, 152)).
    NSArray *nodes = [m decorationNodesInOffsetRange:150 end:152];
    XCTAssertEqual(nodes.count, (NSUInteger)1);

    // Query an inter-token gap (offsets [152, 153) — the space between tokens 50 and 51).
    nodes = [m decorationNodesInOffsetRange:152 end:153];
    XCTAssertEqual(nodes.count, (NSUInteger)0);
}

- (void)testNodesInOffsetRange_largeCountPerformance {
    // Performance smoke-test: 10,000 non-overlapping tokens.  A correct O(log N + k)
    // query should complete in well under 1 second for any single-character position.
    NSInteger tokenCount = 10000;
    NSMutableString *text = [NSMutableString stringWithCapacity:(NSUInteger)tokenCount * 3];
    for (NSInteger i = 0; i < tokenCount; i++) { [text appendString:@"ab "]; }
    UDTextModel *m = [[UDTextModel alloc] initWithText:text];

    NSMutableArray *decors = [NSMutableArray arrayWithCapacity:(NSUInteger)tokenCount];
    for (NSInteger i = 0; i < tokenCount; i++) {
        [decors addObject:[self _decorationFrom:(NSUInteger)(i * 3)
                                             to:(NSUInteger)(i * 3 + 2)
                                        inModel:m]];
    }
    [m deltaDecorations:nil newDecorations:decors];

    // Query positions spread across the whole document.
    // Each query should be O(log N), not O(N), so 1000 queries should be fast.
    [self measureBlock:^{
        for (NSInteger q = 0; q < 1000; q++) {
            NSInteger pos = (q * 30) % (tokenCount * 3 - 1);
            (void)[m decorationNodesInOffsetRange:pos end:pos + 1];
        }
    }];
}

@end
