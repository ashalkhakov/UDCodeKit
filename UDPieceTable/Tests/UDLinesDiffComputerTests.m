//
//  UDLinesDiffComputerTests.m
//
//  The diff, as VS Code's: its fixtures (src/vs/editor/test/node/diffing/
//  fixtures, each a folder's advanced.expected.diff.json, here Fixtures/
//  <folder>.diff.json) computed again and compared as its fixtures.test.ts
//  does, moves aside (not detected here).
//

#import <XCTest/XCTest.h>
#import "UDLinesDiffComputer.h"

@interface UDLinesDiffComputerTests : XCTestCase
@end

@implementation UDLinesDiffComputerTests

static NSString *UDLineRangeString(UDLineRange r) {
    return [NSString stringWithFormat:@"[%ld,%ld)", (long)r.startLineNumber, (long)r.endLineNumberExclusive];
}

/// fixtures.test.ts's formatRange: " EOL" when it ends at its line's end.
static NSString *UDRangeString(UDRange r, NSArray<NSString *> *lines) {
    BOOL toLastChar = r.endColumn == (NSInteger)lines[r.endLineNumber - 1].length + 1;
    return [NSString stringWithFormat:@"[%ld,%ld -> %ld,%ld%@]", (long)r.startLineNumber, (long)r.startColumn,
            (long)r.endLineNumber, (long)r.endColumn, toLastChar ? @" EOL" : @""];
}

static NSArray<NSString *> *UDLinesOf(NSString *content) {
    content = [[content stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"]
               stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
    return [content componentsSeparatedByString:@"\n"];
}

- (void)testVSCodesFixtures {
    NSBundle *bundle = [NSBundle bundleForClass:[self class]];
    NSArray<NSString *> *paths = [[bundle pathsForResourcesOfType:@"json" inDirectory:nil]
                                  sortedArrayUsingSelector:@selector(compare:)];
    NSMutableArray<NSString *> *fixtures = [NSMutableArray array];
    for (NSString *path in paths) {
        if ([path hasSuffix:@".diff.json"]) [fixtures addObject:path];
    }
    XCTAssertGreaterThanOrEqual(fixtures.count, 50u, @"the fixtures are in the bundle");

    NSUInteger passed = 0;
    for (NSString *path in fixtures) {
        NSString *name = [path.lastPathComponent stringByReplacingOccurrencesOfString:@".diff.json" withString:@""];
        NSDictionary *fixture = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:path] options:0 error:NULL];
        NSArray<NSString *> *original = UDLinesOf(fixture[@"original"][@"content"]);
        NSArray<NSString *> *modified = UDLinesOf(fixture[@"modified"][@"content"]);
        BOOL ignoreTrimWhitespace = [name containsString:@"trimws"];

        UDLinesDiff *diff = [UDLinesDiffComputer diffOfOriginalLines:original modifiedLines:modified
                                                ignoreTrimWhitespace:ignoreTrimWhitespace maxComputationTime:0];
        NSMutableArray *actual = [NSMutableArray array];
        for (UDDetailedLineRangeMapping *change in diff.changes) {
            NSMutableArray *inner = [NSMutableArray array];
            for (UDRangeMapping *mapping in change.innerChanges) {
                [inner addObject:@{ @"originalRange": UDRangeString(mapping.originalRange, original),
                                    @"modifiedRange": UDRangeString(mapping.modifiedRange, modified) }];
            }
            [actual addObject:@{ @"originalRange": UDLineRangeString(change.original),
                                 @"modifiedRange": UDLineRangeString(change.modified),
                                 @"innerChanges": inner }];
        }
        NSArray *expected = fixture[@"diffs"];
        if ([actual isEqualToArray:expected]) {
            passed++;
        } else {
            XCTFail(@"%@: %@\nexpected %@", name, actual, expected);
        }
    }
    XCTAssertEqual(passed, fixtures.count);
}

- (void)testEqualTextsHaveNoChanges {
    UDLinesDiff *diff = [UDLinesDiffComputer diffOfOriginalLines:@[ @"a", @"b" ] modifiedLines:@[ @"a", @"b" ]
                                            ignoreTrimWhitespace:NO maxComputationTime:5];
    XCTAssertEqual(diff.changes.count, 0u);
    XCTAssertFalse(diff.hitTimeout);
}

- (void)testALineChangedInsertedAndDeleted {
    UDLinesDiff *diff = [UDLinesDiffComputer diffOfOriginalLines:@[ @"one", @"two", @"three", @"four" ]
                                                   modifiedLines:@[ @"one", @"2", @"three", @"four", @"five" ]
                                            ignoreTrimWhitespace:NO maxComputationTime:5];
    XCTAssertEqual(diff.changes.count, 2u);
    UDDetailedLineRangeMapping *changed = diff.changes[0];
    XCTAssertEqual(changed.original.startLineNumber, 2);
    XCTAssertEqual(changed.original.endLineNumberExclusive, 3);
    XCTAssertEqual(changed.modified.startLineNumber, 2);
    XCTAssertEqual(changed.modified.endLineNumberExclusive, 3);
    UDDetailedLineRangeMapping *inserted = diff.changes[1];
    XCTAssertEqual(UDLineRangeLength(inserted.original), 0, @"nothing of the original");
    XCTAssertEqual(inserted.modified.startLineNumber, 5);
    XCTAssertEqual(inserted.modified.endLineNumberExclusive, 6);
}

@end
