// UDAnnotatedStringTests.m
// Tests for the NSMutableAttributedString-backed UDAnnotatedString.

#import <XCTest/XCTest.h>
#import "UDAnnotatedString.h"

@interface UDAnnotatedStringTests : XCTestCase
@end

@implementation UDAnnotatedStringTests

// MARK: - Basic annotation

- (void)testSetAndGetAnnotation {
    UDAnnotatedString *as = [[UDAnnotatedString alloc] initWithString:@"Hello World"];
    [as setAnnotation:@"emphasis" forRange:NSMakeRange(0, 5)]; // "Hello"

    NSArray *annotations = [as allAnnotations];
    XCTAssertEqual(annotations.count, (NSUInteger)1);
    NSDictionary *entry = annotations[0];
    XCTAssertEqualObjects(entry[@"annotation"], @"emphasis");
    NSRange r = [entry[@"range"] rangeValue];
    XCTAssertEqual(r.location, (NSUInteger)0);
    XCTAssertEqual(r.length,   (NSUInteger)5);
}

- (void)testSetAnnotationNil_removesAnnotation {
    UDAnnotatedString *as = [[UDAnnotatedString alloc] initWithString:@"Hello World"];
    [as setAnnotation:@"emphasis" forRange:NSMakeRange(0, 5)];
    [as setAnnotation:nil forRange:NSMakeRange(0, 5)];

    XCTAssertEqual([as allAnnotations].count, (NSUInteger)0);
}

- (void)testRemoveAnnotationsInRange {
    UDAnnotatedString *as = [[UDAnnotatedString alloc] initWithString:@"Hello World"];
    [as setAnnotation:@"emphasis" forRange:NSMakeRange(0, 11)]; // full string
    [as removeAnnotationsInRange:NSMakeRange(0, 5)];            // remove "Hello"

    NSArray *annotations = [as allAnnotations];
    // The remaining "World" part [5..11) should still be annotated.
    XCTAssertEqual(annotations.count, (NSUInteger)1);
    NSRange r = [annotations[0][@"range"] rangeValue];
    XCTAssertEqual(r.location, (NSUInteger)5);
    XCTAssertEqual(r.length,   (NSUInteger)6); // " World"
}

// MARK: - annotationsIntersectingRange

- (void)testAnnotationsIntersectingRange_partial {
    UDAnnotatedString *as = [[UDAnnotatedString alloc] initWithString:@"Hello World"];
    [as setAnnotation:@"a1" forRange:NSMakeRange(0, 5)];   // "Hello"
    [as setAnnotation:@"a2" forRange:NSMakeRange(6, 5)];   // "World"

    // Query a range that overlaps only "Hello"
    NSArray *found = [as annotationsIntersectingRange:NSMakeRange(0, 3)];
    XCTAssertEqual(found.count, (NSUInteger)1);
    XCTAssertEqualObjects(found[0][@"annotation"], @"a1");
}

- (void)testAnnotationsIntersectingRange_both {
    UDAnnotatedString *as = [[UDAnnotatedString alloc] initWithString:@"Hello World"];
    [as setAnnotation:@"a1" forRange:NSMakeRange(0, 5)];
    [as setAnnotation:@"a2" forRange:NSMakeRange(6, 5)];

    // Query spanning both words
    NSArray *found = [as annotationsIntersectingRange:NSMakeRange(3, 6)];
    XCTAssertEqual(found.count, (NSUInteger)2);
}

- (void)testAnnotationsIntersectingRange_none {
    UDAnnotatedString *as = [[UDAnnotatedString alloc] initWithString:@"Hello World"];
    [as setAnnotation:@"a1" forRange:NSMakeRange(6, 5)];

    NSArray *found = [as annotationsIntersectingRange:NSMakeRange(0, 4)];
    XCTAssertEqual(found.count, (NSUInteger)0);
}

// MARK: - applyEditDeleteRange:insertText:

- (void)testApplyEdit_insertion_shiftsAnnotation {
    UDAnnotatedString *as = [[UDAnnotatedString alloc] initWithString:@"Hello World"];
    [as setAnnotation:@"emphasis" forRange:NSMakeRange(6, 5)]; // "World" at [6..11)

    // Insert "Beautiful " at offset 6 (before "World")
    [as applyEditDeleteRange:NSMakeRange(6, 0) insertText:@"Beautiful "];

    NSArray *annotations = [as allAnnotations];
    // "World" should now be at [16..21) — shifted by 10
    XCTAssertEqual(annotations.count, (NSUInteger)1);
    NSRange r = [annotations[0][@"range"] rangeValue];
    XCTAssertEqual(r.location, (NSUInteger)16);
    XCTAssertEqual(r.length,   (NSUInteger)5);
    XCTAssertEqualObjects(annotations[0][@"annotation"], @"emphasis");
}

- (void)testApplyEdit_deletion_removesAnnotatedChars {
    UDAnnotatedString *as = [[UDAnnotatedString alloc] initWithString:@"Hello World"];
    [as setAnnotation:@"emphasis" forRange:NSMakeRange(0, 11)]; // whole string

    // Delete "Hello " (first 6 chars)
    [as applyEditDeleteRange:NSMakeRange(0, 6) insertText:@""];

    // Only "World" [0..5) remains, still annotated
    NSArray *annotations = [as allAnnotations];
    XCTAssertEqual(annotations.count, (NSUInteger)1);
    NSRange r = [annotations[0][@"range"] rangeValue];
    XCTAssertEqual(r.location, (NSUInteger)0);
    XCTAssertEqual(r.length,   (NSUInteger)5);
}

- (void)testApplyEdit_insertedTextIsUnannotated {
    UDAnnotatedString *as = [[UDAnnotatedString alloc] initWithString:@"HelloWorld"];
    [as setAnnotation:@"bold" forRange:NSMakeRange(0, 10)]; // whole string

    // Insert " " at offset 5 (between "Hello" and "World")
    [as applyEditDeleteRange:NSMakeRange(5, 0) insertText:@" "];

    // The inserted space should NOT be annotated
    NSArray *found = [as annotationsIntersectingRange:NSMakeRange(5, 1)];
    XCTAssertEqual(found.count, (NSUInteger)0);

    // But "Hello" and "World" parts should still be annotated
    NSArray *allAnnotations = [as allAnnotations];
    // NSAttributedString will likely produce 2 runs: [0,5) and [6,5)
    XCTAssertGreaterThanOrEqual(allAnnotations.count, (NSUInteger)1);
}

- (void)testApplyEdit_replacement_updatesRanges {
    UDAnnotatedString *as = [[UDAnnotatedString alloc] initWithString:@"Hello World"];
    [as setAnnotation:@"emphasis" forRange:NSMakeRange(6, 5)]; // "World"

    // Replace "Hello " (first 6 chars) with "Hi "
    [as applyEditDeleteRange:NSMakeRange(0, 6) insertText:@"Hi "];

    // "World" annotation should now start at 3 (= 0 + "Hi ".length)
    NSArray *annotations = [as allAnnotations];
    XCTAssertEqual(annotations.count, (NSUInteger)1);
    NSRange r = [annotations[0][@"range"] rangeValue];
    XCTAssertEqual(r.location, (NSUInteger)3);
    XCTAssertEqual(r.length,   (NSUInteger)5);
}

// MARK: - string property

- (void)testStringProperty {
    UDAnnotatedString *as = [[UDAnnotatedString alloc] initWithString:@"Hello"];
    XCTAssertEqualObjects(as.string, @"Hello");
    [as applyEditDeleteRange:NSMakeRange(5, 0) insertText:@" World"];
    XCTAssertEqualObjects(as.string, @"Hello World");
}

@end
