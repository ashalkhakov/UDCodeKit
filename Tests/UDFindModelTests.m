//
//  UDFindModelTests.m
//
//  The find model keeps its matches up to date edit by edit — searching only
//  the lines an edit touched — and they are the matches a fresh search of
//  the text finds; navigation, ranks, and replacing.
//

#import <XCTest/XCTest.h>
#import <UDCodeKit/UDCodeKit.h>

typedef struct { uint64_t state; } UDRandom;
static NSInteger UDRandomBelow(UDRandom *r, NSInteger bound) {
    r->state = r->state * 6364136223846793005ULL + 1442695040888963407ULL;
    return (NSInteger)((r->state >> 33) % (uint64_t)MAX(bound, 1));
}

/// The kept matches as "start-end".
static NSArray<NSString *> *UDKept(UDFindModel *find) {
    NSMutableArray *out = [NSMutableArray array];
    for (UDIntervalNode *node in [find matchNodes]) {
        [out addObject:[NSString stringWithFormat:@"%ld-%ld", (long)node.start, (long)node.end]];
    }
    return out;
}

/// What a fresh find model on the same text, with the same query, keeps.
static NSArray<NSString *> *UDFresh(UDFindModel *find) {
    UDTextModel *copy = [[UDTextModel alloc] initWithText:[find.textModel getValue]];
    UDFindModel *fresh = [[UDFindModel alloc] initWithTextModel:copy];
    fresh.isRegex = find.isRegex;
    fresh.matchCase = find.matchCase;
    fresh.wholeWord = find.wholeWord;
    fresh.searchString = find.searchString;
    return UDKept(fresh);
}

@interface UDFindModelTests : XCTestCase
@end

@implementation UDFindModelTests

- (void)testKeptMatchesAreAFreshSearchsThroughEditsAndUndo {
    NSArray<NSArray *> *queries = @[
        @[@"foo", @NO, @NO, @NO],
        @[@"Foo", @NO, @YES, @NO],
        @[@"foo", @NO, @NO, @YES],
        @[@"f[o0]+\\d?", @YES, @NO, @NO],
        @[@"o", @NO, @NO, @NO],
    ];
    NSArray *inserts = @[@"", @"foo", @"Foo bar", @"\nfoofoo\n", @"o", @"f", @"x foo2 ", @"\r\n"];
    for (NSArray *query in queries) {
        for (uint64_t seed = 1; seed <= 10; seed++) {
            UDRandom random = { seed };
            NSMutableString *text = [NSMutableString string];
            for (NSInteger i = 0; i < 40; i++) [text appendFormat:@"line %ld foo bar Foo food fo%ld\n", (long)i, (long)i];
            UDTextModel *model = [[UDTextModel alloc] initWithText:text];
            model.undoManager = [[NSUndoManager alloc] init];
            model.undoManager.groupsByEvent = NO;
            UDFindModel *find = [[UDFindModel alloc] initWithTextModel:model];
            find.isRegex = [query[1] boolValue];
            find.matchCase = [query[2] boolValue];
            find.wholeWord = [query[3] boolValue];
            find.searchString = query[0];
            XCTAssertGreaterThan(find.matchCount, 0u);
            XCTAssertEqualObjects(UDKept(find), UDFresh(find));

            for (NSInteger round = 0; round < 12; round++) {
                NSInteger lines = [model getLineCount];
                NSMutableIndexSet *chosen = [NSMutableIndexSet indexSet];
                NSInteger count = 1 + UDRandomBelow(&random, 3);
                while ((NSInteger)chosen.count < count) [chosen addIndex:(NSUInteger)(1 + UDRandomBelow(&random, lines))];
                NSMutableArray *edits = [NSMutableArray array];
                [chosen enumerateIndexesUsingBlock:^(NSUInteger line, BOOL *stop) {
                    NSInteger max = [model getLineMaxColumn:(NSInteger)line];
                    NSInteger c1 = 1 + UDRandomBelow(&random, max);
                    NSInteger c2 = MIN(max, c1 + UDRandomBelow(&random, 5));
                    [edits addObject:[[UDTextModelEdit alloc] initWithRange:PTRangeMake((NSInteger)line, c1, (NSInteger)line, c2)
                                                                        text:inserts[(NSUInteger)UDRandomBelow(&random, (NSInteger)inserts.count)]]];
                }];
                [model.undoManager beginUndoGrouping];
                [model applyEdits:edits];
                [model.undoManager endUndoGrouping];
                NSArray *kept = UDKept(find), *fresh = UDFresh(find);
                if (![kept isEqualToArray:fresh]) {
                    NSMutableArray *extra = [kept mutableCopy]; [extra removeObjectsInArray:fresh];
                    NSMutableArray *missing = [fresh mutableCopy]; [missing removeObjectsInArray:kept];
                    XCTFail(@"%@ seed %llu round %ld: kept also %@, missing %@", query[0], seed, (long)round, extra, missing);
                    return;
                }
                XCTAssertEqual(find.matchCount, kept.count);
            }
            while (model.undoManager.canUndo) {
                [model.undoManager undo];
                XCTAssertEqualObjects(UDKept(find), UDFresh(find), @"%@ seed %llu: undo", query[0], seed);
            }
            XCTAssertEqualObjects([model getValue], text);
        }
    }
}

- (void)testNavigationAndRanks {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"a foo\nb foo foo\nc\nfoo\n"];
    UDFindModel *find = [[UDFindModel alloc] initWithTextModel:model];
    find.searchString = @"foo";
    XCTAssertEqual(find.matchCount, 4u);
    // Offsets: "a foo\n" 2-5; "b foo foo\n" 8-11, 12-15; "c\n"; "foo" 18-21.
    UDFindMatch *m = [find matchFrom:0];
    XCTAssertEqual([model getOffsetAt:m.range.startLineNumber column:m.range.startColumn], 2);
    m = [find matchFrom:9];
    XCTAssertEqual([model getOffsetAt:m.range.startLineNumber column:m.range.startColumn], 12);
    m = [find matchFrom:19];                       // wraps to the top
    XCTAssertEqual([model getOffsetAt:m.range.startLineNumber column:m.range.startColumn], 2);
    m = [find matchBefore:12];
    XCTAssertEqual([model getOffsetAt:m.range.startLineNumber column:m.range.startColumn], 8);
    m = [find matchBefore:2];                      // wraps to the bottom
    XCTAssertEqual([model getOffsetAt:m.range.startLineNumber column:m.range.startColumn], 18);
    XCTAssertEqual([find indexOfMatchFrom:2 to:5], 1u);
    XCTAssertEqual([find indexOfMatchFrom:12 to:15], 3u);
    XCTAssertEqual([find indexOfMatchFrom:18 to:21], 4u);
    XCTAssertEqual([find indexOfMatchFrom:3 to:5], 0u, @"not a match");
}

- (void)testReplacingWithGroupsAndReplaceAllIsOneUndoStep {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"key1 = 10\nkey2 = 20\nother\nkey3 = 30\n"];
    model.undoManager = [[NSUndoManager alloc] init];
    model.undoManager.groupsByEvent = NO;
    UDFindModel *find = [[UDFindModel alloc] initWithTextModel:model];
    find.isRegex = YES;
    find.searchString = @"^(key\\d) = (\\d+)$";
    find.replaceString = @"$2 -> $1 $$\\t";
    XCTAssertEqual(find.matchCount, 3u);

    XCTAssertEqual([find replaceMatchFrom:0 to:4], NSNotFound, @"not a whole match");
    [model.undoManager beginUndoGrouping];
    NSInteger end = [find replaceMatchFrom:0 to:9];
    [model.undoManager endUndoGrouping];
    NSString *first = @"10 -> key1 $\t";
    XCTAssertEqual(end, (NSInteger)first.length);
    XCTAssertEqualObjects([model getLineContent:1], first);
    XCTAssertEqual(find.matchCount, 2u);

    find.replaceString = @"[$&] $1";
    [model.undoManager beginUndoGrouping];
    XCTAssertEqual([find replaceAll], 2u);
    [model.undoManager endUndoGrouping];
    XCTAssertEqualObjects([model getValue], ([NSString stringWithFormat:@"%@\n[key2 = 20] key2\nother\n[key3 = 30] key3\n", first]));
    XCTAssertEqual(find.matchCount, 0u);
    [model.undoManager undo];
    XCTAssertEqualObjects([model getValue], ([NSString stringWithFormat:@"%@\nkey2 = 20\nother\nkey3 = 30\n", first]),
                          @"Replace All undoes in one step");
    XCTAssertEqual(find.matchCount, 2u);
}

- (void)testAnInvalidRegexFindsNothing {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"a(b\n"];
    UDFindModel *find = [[UDFindModel alloc] initWithTextModel:model];
    find.isRegex = YES;
    find.searchString = @"a(";
    XCTAssertFalse(find.isValid);
    XCTAssertEqual(find.matchCount, 0u);
    XCTAssertNil([find matchFrom:0]);
    find.isRegex = NO;
    XCTAssertTrue(find.isValid);
    XCTAssertEqual(find.matchCount, 1u);
}

@end
