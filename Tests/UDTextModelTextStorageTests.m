/*---------------------------------------------------------------------------------------------
 *  UDTextModelTextStorageTests.m
 *
 *  Tests for the attribute-run cache in UDTextModelTextStorage, specifically
 *  the C-array binary search introduced to replace the NSArray<NSValue *>
 *  path in -attributesAtIndex:effectiveRange:.
 *
 *  These tests run in-process via BUNDLE_LOADER (AppKit is available).
 *--------------------------------------------------------------------------------------------*/

#import <XCTest/XCTest.h>
#import "UDTextModelTextStorage.h"
#import "UDTextModel.h"

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Build a UDModelDeltaDecoration for the given 1-based line/column range.
static UDModelDeltaDecoration *Deco(NSInteger sl, NSInteger sc,
                                    NSInteger el, NSInteger ec,
                                    NSString *cls) {
    UDRange r = UDRangeMake(sl, sc, el, ec);
    UDDecorationOptions *opts =
        [[UDDecorationOptions alloc] initWithClassName:cls userInfo:nil];
    return [[UDModelDeltaDecoration alloc] initWithRange:r options:opts];
}

// ---------------------------------------------------------------------------

@interface UDTextModelTextStorageTests : XCTestCase
@end

@implementation UDTextModelTextStorageTests

// MARK: - Helpers

/// Creates a UDTextModelTextStorage backed by the given text, with NO decorations.
- (UDTextModelTextStorage *)storageWithText:(NSString *)text {
    return [[UDTextModelTextStorage alloc] initWithText:text];
}

// MARK: - Empty document

- (void)testEmptyDocumentReturnsBaseAttrs {
    UDTextModelTextStorage *s = [self storageWithText:@""];
    NSRange outRange = NSMakeRange(NSNotFound, 0);
    NSDictionary *attrs = [s attributesAtIndex:0 effectiveRange:&outRange];
    XCTAssertNotNil(attrs);
    XCTAssertNotNil(attrs[NSFontAttributeName],
                    @"Base attributes must include a font");
    // outRange is undefined for an empty document — no assertion on it.
}

// MARK: - Single-run (no decorations)

- (void)testSingleRunCoversWholeDocument {
    NSString *text = @"hello world";
    UDTextModelTextStorage *s = [self storageWithText:text];
    NSUInteger len = text.length;

    NSRange r0, rMid, rLast;
    [s attributesAtIndex:0       effectiveRange:&r0];
    [s attributesAtIndex:len / 2 effectiveRange:&rMid];
    [s attributesAtIndex:len - 1 effectiveRange:&rLast];

    XCTAssertEqual(r0.location,    0U);
    XCTAssertEqual(r0.length,      len);
    XCTAssertEqualObjects(NSStringFromRange(r0),
                          NSStringFromRange(rMid),
                          @"All positions in a no-decoration document share one run");
    XCTAssertEqualObjects(NSStringFromRange(r0),
                          NSStringFromRange(rLast));
}

// MARK: - Multi-run (with decorations)

- (void)testMultiRunBinarySearchFindsCorrectRunForEachPosition {
    //  text:  "abcdefghij"  (10 chars, indices 0-9)
    //  decoration 1: chars [2, 5)  → className "kw"
    //  decoration 2: chars [7, 9)  → className "str"
    //
    //  Expected runs after rebuild:
    //    [0,2)  → base
    //    [2,5)  → "kw"
    //    [5,7)  → base
    //    [7,9)  → "str"
    //    [9,10) → base
    NSString *text = @"abcdefghij";
    UDTextModelTextStorage *s = [self storageWithText:text];
    UDTextModel *m = s.textModel;

    // Add decorations.  deltaDecorations uses 1-based line/column addressing.
    // "abcdefghij": col 3 = index 2, col 6 = index 5 (exclusive), so [2,5).
    [m deltaDecorations:nil
        newDecorations:@[ Deco(1, 3, 1, 6, @"kw") ]
                 owner:@"test"];
    [m deltaDecorations:nil
        newDecorations:@[ Deco(1, 8, 1, 10, @"str") ]
                 owner:@"test2"];

    [s applyDecorationHighlights];

    // Position 0 → first base run [0,2)
    NSRange r0;
    [s attributesAtIndex:0 effectiveRange:&r0];
    XCTAssertEqual(r0.location, 0U);
    XCTAssertEqual(r0.length,   2U, @"Base run before first decoration");

    // Position 2 → "kw" run [2,5)
    NSRange r2;
    [s attributesAtIndex:2 effectiveRange:&r2];
    XCTAssertEqual(r2.location, 2U);
    XCTAssertEqual(r2.length,   3U, @"'kw' decoration run");

    // Position 4 (inside kw run)
    NSRange r4;
    [s attributesAtIndex:4 effectiveRange:&r4];
    XCTAssertEqualObjects(NSStringFromRange(r2), NSStringFromRange(r4),
                          @"Positions inside a run report the same range");

    // Position 5 → second base run [5,7)
    NSRange r5;
    [s attributesAtIndex:5 effectiveRange:&r5];
    XCTAssertEqual(r5.location, 5U);
    XCTAssertEqual(r5.length,   2U, @"Base run between decorations");

    // Position 7 → "str" run [7,9)
    NSRange r7;
    [s attributesAtIndex:7 effectiveRange:&r7];
    XCTAssertEqual(r7.location, 7U);
    XCTAssertEqual(r7.length,   2U, @"'str' decoration run");

    // Position 9 → last base run [9,10)
    NSRange r9;
    [s attributesAtIndex:9 effectiveRange:&r9];
    XCTAssertEqual(r9.location, 9U);
    XCTAssertEqual(r9.length,   1U, @"Last base run after final decoration");
}

// MARK: - Cache invalidation

- (void)testCacheIsRebuiltAfterDecorationsChange {
    NSString *text = @"hello";
    UDTextModelTextStorage *s = [self storageWithText:text];

    // Before decoration: one run
    NSRange before;
    [s attributesAtIndex:0 effectiveRange:&before];
    XCTAssertEqual(before.length, text.length);

    // Add a decoration covering chars [1,3)
    [s.textModel deltaDecorations:nil
                   newDecorations:@[ Deco(1, 2, 1, 4, @"kw") ]
                            owner:@"test"];
    [s applyDecorationHighlights];

    // After decoration: position 0 should now be a shorter base run
    NSRange after;
    [s attributesAtIndex:0 effectiveRange:&after];
    XCTAssertLessThan(after.length, text.length,
                      @"Cache must be rebuilt after decoration change");
    XCTAssertEqual(after.location, 0U);
    XCTAssertEqual(after.length,   1U, @"Base run [0,1) before the decoration");
}

// MARK: - Out-of-range location

- (void)testOutOfRangeLocationReturnsBaseAttrs {
    UDTextModelTextStorage *s = [self storageWithText:@"hi"];
    NSRange outRange;
    NSDictionary *attrs = [s attributesAtIndex:100 effectiveRange:&outRange];
    XCTAssertNotNil(attrs);
    XCTAssertNotNil(attrs[NSFontAttributeName]);
}

@end
