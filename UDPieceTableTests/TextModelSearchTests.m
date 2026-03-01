// TextModelSearchTests.m
// Tests for the VS Code text-model search subsystem port.

#import <XCTest/XCTest.h>
#import "PieceTreeBase.h"
#import "TextModelSearch.h"

// MARK: - Helpers

/// Build a PTPieceTreeBase from a single string.
static PTPieceTreeBase *MakeTree(NSString *text) {
    NSMutableArray<NSNumber *> *lineStarts = [NSMutableArray arrayWithObject:@0];
    NSInteger len = (NSInteger)text.length;
    for (NSInteger i = 0; i < len; i++) {
        unichar c = [text characterAtIndex:(NSUInteger)i];
        if (c == '\r') {
            if (i + 1 < len && [text characterAtIndex:(NSUInteger)(i + 1)] == '\n') {
                [lineStarts addObject:@(i + 2)]; i++;
            } else {
                [lineStarts addObject:@(i + 1)];
            }
        } else if (c == '\n') {
            [lineStarts addObject:@(i + 1)];
        }
    }
    PTStringBuffer *buf = [[PTStringBuffer alloc] initWithBuffer:text lineStarts:lineStarts];
    return [[PTPieceTreeBase alloc] initWithChunks:@[buf] eol:@"\n" eolNormalized:YES];
}

/// Build a search range covering the entire document.
static PTRange FullRange(PTPieceTreeBase *tree) {
    NSInteger lineCount = [tree getLineCount];
    NSInteger lastLineLen = [tree getLineLength:lineCount];
    return PTRangeMake(1, 1, lineCount, lastLineLen + 1);
}

// MARK: - TextModelSearchTests

@interface TextModelSearchTests : XCTestCase
@end

@implementation TextModelSearchTests

// 1. Plain text, no word boundary — single match on one line.
- (void)testPlainTextSingleMatch {
    PTPieceTreeBase *tree = MakeTree(@"Hello World");
    PTSearchParams *params = [[PTSearchParams alloc] initWithSearchString:@"World"
                                                                  isRegex:NO
                                                                matchCase:YES
                                                           wordSeparators:nil];
    PTSearchData *data = [params parseSearchRequest];
    XCTAssertNotNil(data);
    NSArray<PTFindMatch *> *matches = [tree findMatchesLineByLine:FullRange(tree)
                                                       searchData:data
                                                   captureMatches:NO
                                                 limitResultCount:100];
    XCTAssertEqual(matches.count, (NSUInteger)1);
    XCTAssertEqual(matches[0].range.startLineNumber, 1);
    XCTAssertEqual(matches[0].range.startColumn, 7);
    XCTAssertEqual(matches[0].range.endColumn, 12);
    XCTAssertNil(matches[0].matches);
}

// 2. Plain text, case-insensitive — verify match found.
- (void)testPlainTextCaseInsensitive {
    PTPieceTreeBase *tree = MakeTree(@"Hello World");
    PTSearchParams *params = [[PTSearchParams alloc] initWithSearchString:@"hello"
                                                                  isRegex:NO
                                                                matchCase:NO
                                                           wordSeparators:nil];
    PTSearchData *data = [params parseSearchRequest];
    XCTAssertNotNil(data);
    NSArray<PTFindMatch *> *matches = [tree findMatchesLineByLine:FullRange(tree)
                                                       searchData:data
                                                   captureMatches:NO
                                                 limitResultCount:100];
    XCTAssertEqual(matches.count, (NSUInteger)1);
    XCTAssertEqual(matches[0].range.startColumn, 1);
    XCTAssertEqual(matches[0].range.endColumn, 6);
}

// 3. Plain text, whole word — verify non-word-boundary hit is excluded.
- (void)testPlainTextWholeWord {
    // "foo foobar foo" — "foo" as whole word should match at positions 1 and 11
    // "foobar" should NOT be matched
    PTPieceTreeBase *tree = MakeTree(@"foo foobar foo");
    NSString *separators = @" \t`~!@#$%^&*()-=+[{]}\\|;:'\",.<>/?";
    PTSearchParams *params = [[PTSearchParams alloc] initWithSearchString:@"foo"
                                                                  isRegex:NO
                                                                matchCase:YES
                                                           wordSeparators:separators];
    PTSearchData *data = [params parseSearchRequest];
    XCTAssertNotNil(data);
    NSArray<PTFindMatch *> *matches = [tree findMatchesLineByLine:FullRange(tree)
                                                       searchData:data
                                                   captureMatches:NO
                                                 limitResultCount:100];
    XCTAssertEqual(matches.count, (NSUInteger)2);
    XCTAssertEqual(matches[0].range.startColumn, 1);
    XCTAssertEqual(matches[1].range.startColumn, 12);
}

// 4. Regex, single line — e.g., \d+.
- (void)testRegexSingleLine {
    PTPieceTreeBase *tree = MakeTree(@"abc 123 def 456");
    PTSearchParams *params = [[PTSearchParams alloc] initWithSearchString:@"\\d+"
                                                                  isRegex:YES
                                                                matchCase:YES
                                                           wordSeparators:nil];
    PTSearchData *data = [params parseSearchRequest];
    XCTAssertNotNil(data);
    NSArray<PTFindMatch *> *matches = [tree findMatchesLineByLine:FullRange(tree)
                                                       searchData:data
                                                   captureMatches:NO
                                                 limitResultCount:100];
    XCTAssertEqual(matches.count, (NSUInteger)2);
    XCTAssertEqual(matches[0].range.startColumn, 5);
    XCTAssertEqual(matches[0].range.endColumn, 8);
    XCTAssertEqual(matches[1].range.startColumn, 13);
    XCTAssertEqual(matches[1].range.endColumn, 16);
}

// 5. Regex, multiline — pattern that crosses a line break.
- (void)testRegexMultiline {
    // Pattern "end\nstart" should match across lines
    PTPieceTreeBase *tree = MakeTree(@"line end\nstart line");
    PTSearchParams *params = [[PTSearchParams alloc] initWithSearchString:@"end\nstart"
                                                                  isRegex:YES
                                                                matchCase:YES
                                                           wordSeparators:nil];
    PTSearchData *data = [params parseSearchRequest];
    XCTAssertNotNil(data);
    NSArray<PTFindMatch *> *matches = [tree findMatchesLineByLine:FullRange(tree)
                                                       searchData:data
                                                   captureMatches:NO
                                                 limitResultCount:100];
    XCTAssertGreaterThanOrEqual(matches.count, (NSUInteger)1);
}

// 6. Search range limiting — PTRange that covers only part of the document.
- (void)testSearchRangeLimiting {
    PTPieceTreeBase *tree = MakeTree(@"abc\nabc\nabc");
    // Search only line 2
    PTRange range = PTRangeMake(2, 1, 2, 4);
    PTSearchParams *params = [[PTSearchParams alloc] initWithSearchString:@"abc"
                                                                  isRegex:NO
                                                                matchCase:YES
                                                           wordSeparators:nil];
    PTSearchData *data = [params parseSearchRequest];
    XCTAssertNotNil(data);
    NSArray<PTFindMatch *> *matches = [tree findMatchesLineByLine:range
                                                       searchData:data
                                                   captureMatches:NO
                                                 limitResultCount:100];
    XCTAssertEqual(matches.count, (NSUInteger)1);
    XCTAssertEqual(matches[0].range.startLineNumber, 2);
}

// 7. limitResultCount — verify early stop.
- (void)testLimitResultCount {
    PTPieceTreeBase *tree = MakeTree(@"a a a a a");
    PTSearchParams *params = [[PTSearchParams alloc] initWithSearchString:@"a"
                                                                  isRegex:NO
                                                                matchCase:YES
                                                           wordSeparators:nil];
    PTSearchData *data = [params parseSearchRequest];
    XCTAssertNotNil(data);
    NSArray<PTFindMatch *> *matches = [tree findMatchesLineByLine:FullRange(tree)
                                                       searchData:data
                                                   captureMatches:NO
                                                 limitResultCount:3];
    XCTAssertEqual(matches.count, (NSUInteger)3);
}

// 8. Multi-node document — built from multiple insertAtOffset: calls.
- (void)testMultiNodeDocument {
    // Start with empty tree, insert multiple chunks so we get > 1 node
    PTStringBuffer *empty = [[PTStringBuffer alloc] initWithBuffer:@"" lineStarts:@[@0]];
    PTPieceTreeBase *tree = [[PTPieceTreeBase alloc] initWithChunks:@[empty]
                                                                eol:@"\n"
                                                      eolNormalized:YES];
    [tree insertAtOffset:0 value:@"Hello " eolNormalized:YES];
    [tree insertAtOffset:6 value:@"World\n" eolNormalized:YES];
    [tree insertAtOffset:12 value:@"foo bar" eolNormalized:YES];

    PTSearchParams *params = [[PTSearchParams alloc] initWithSearchString:@"World"
                                                                  isRegex:NO
                                                                matchCase:YES
                                                           wordSeparators:nil];
    PTSearchData *data = [params parseSearchRequest];
    XCTAssertNotNil(data);
    NSArray<PTFindMatch *> *matches = [tree findMatchesLineByLine:FullRange(tree)
                                                       searchData:data
                                                   captureMatches:NO
                                                 limitResultCount:100];
    XCTAssertEqual(matches.count, (NSUInteger)1);
    XCTAssertEqual(matches[0].range.startLineNumber, 1);
    XCTAssertEqual(matches[0].range.startColumn, 7);
    XCTAssertEqual(matches[0].range.endColumn, 12);
}

// 9. Capture groups — regex with () groups, captureMatches:YES.
- (void)testCaptureGroups {
    PTPieceTreeBase *tree = MakeTree(@"2024-03-01");
    PTSearchParams *params = [[PTSearchParams alloc] initWithSearchString:@"(\\d{4})-(\\d{2})-(\\d{2})"
                                                                  isRegex:YES
                                                                matchCase:YES
                                                           wordSeparators:nil];
    PTSearchData *data = [params parseSearchRequest];
    XCTAssertNotNil(data);
    NSArray<PTFindMatch *> *matches = [tree findMatchesLineByLine:FullRange(tree)
                                                       searchData:data
                                                   captureMatches:YES
                                                 limitResultCount:100];
    XCTAssertEqual(matches.count, (NSUInteger)1);
    XCTAssertNotNil(matches[0].matches);
    // matches[0] = full match, [1] = year, [2] = month, [3] = day
    XCTAssertEqual(matches[0].matches.count, (NSUInteger)4);
    XCTAssertEqualObjects(matches[0].matches[0], @"2024-03-01");
    XCTAssertEqualObjects(matches[0].matches[1], @"2024");
    XCTAssertEqualObjects(matches[0].matches[2], @"03");
    XCTAssertEqualObjects(matches[0].matches[3], @"01");
}

// 10. Empty search string — parseSearchRequest must return nil.
- (void)testEmptySearchStringReturnsNil {
    PTSearchParams *params = [[PTSearchParams alloc] initWithSearchString:@""
                                                                  isRegex:NO
                                                                matchCase:YES
                                                           wordSeparators:nil];
    PTSearchData *data = [params parseSearchRequest];
    XCTAssertNil(data);
}

@end
