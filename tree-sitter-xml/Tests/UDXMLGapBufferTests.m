/*---------------------------------------------------------------------------------------------
 *  UDXMLGapBufferTests.m
 *
 *  Unit tests for UDXMLGapBuffer — verifies that the gap buffer correctly
 *  tracks document text through incremental edits and produces accurate snapshots.
 *--------------------------------------------------------------------------------------------*/

#import <XCTest/XCTest.h>
#import "UDXMLGapBuffer.h"

@interface UDXMLGapBufferTests : XCTestCase
@end

@implementation UDXMLGapBufferTests

// ---------------------------------------------------------------------------
// MARK: - Initialisation
// ---------------------------------------------------------------------------

- (void)testInitEmpty {
    UDXMLGapBuffer *buf = [[UDXMLGapBuffer alloc] initWithString:@""];
    XCTAssertEqual(buf.length, (NSUInteger)0);
    XCTAssertEqualObjects([buf snapshotString], @"");
}

- (void)testInitWithContent {
    NSString *content = @"Hello, World!";
    UDXMLGapBuffer *buf = [[UDXMLGapBuffer alloc] initWithString:content];
    XCTAssertEqual(buf.length, content.length);
    XCTAssertEqualObjects([buf snapshotString], content);
}

// ---------------------------------------------------------------------------
// MARK: - Pure insertion
// ---------------------------------------------------------------------------

- (void)testInsertAtStart {
    UDXMLGapBuffer *buf = [[UDXMLGapBuffer alloc] initWithString:@"World"];
    [buf replaceCharactersInRange:NSMakeRange(0, 0) withString:@"Hello, "];
    XCTAssertEqualObjects([buf snapshotString], @"Hello, World");
}

- (void)testInsertAtEnd {
    UDXMLGapBuffer *buf = [[UDXMLGapBuffer alloc] initWithString:@"Hello"];
    [buf replaceCharactersInRange:NSMakeRange(5, 0) withString:@", World"];
    XCTAssertEqualObjects([buf snapshotString], @"Hello, World");
}

- (void)testInsertInMiddle {
    UDXMLGapBuffer *buf = [[UDXMLGapBuffer alloc] initWithString:@"Hello World"];
    [buf replaceCharactersInRange:NSMakeRange(5, 0) withString:@","];
    XCTAssertEqualObjects([buf snapshotString], @"Hello, World");
}

// ---------------------------------------------------------------------------
// MARK: - Pure deletion
// ---------------------------------------------------------------------------

- (void)testDeleteAtStart {
    UDXMLGapBuffer *buf = [[UDXMLGapBuffer alloc] initWithString:@"XXHello"];
    [buf replaceCharactersInRange:NSMakeRange(0, 2) withString:@""];
    XCTAssertEqualObjects([buf snapshotString], @"Hello");
}

- (void)testDeleteAtEnd {
    UDXMLGapBuffer *buf = [[UDXMLGapBuffer alloc] initWithString:@"HelloXX"];
    [buf replaceCharactersInRange:NSMakeRange(5, 2) withString:@""];
    XCTAssertEqualObjects([buf snapshotString], @"Hello");
}

- (void)testDeleteInMiddle {
    UDXMLGapBuffer *buf = [[UDXMLGapBuffer alloc] initWithString:@"Hello--World"];
    [buf replaceCharactersInRange:NSMakeRange(5, 2) withString:@""];
    XCTAssertEqualObjects([buf snapshotString], @"HelloWorld");
}

- (void)testDeleteAll {
    UDXMLGapBuffer *buf = [[UDXMLGapBuffer alloc] initWithString:@"Hello"];
    [buf replaceCharactersInRange:NSMakeRange(0, 5) withString:@""];
    XCTAssertEqual(buf.length, (NSUInteger)0);
    XCTAssertEqualObjects([buf snapshotString], @"");
}

// ---------------------------------------------------------------------------
// MARK: - Replace (delete + insert)
// ---------------------------------------------------------------------------

- (void)testReplaceAtStart {
    UDXMLGapBuffer *buf = [[UDXMLGapBuffer alloc] initWithString:@"Greetings, World"];
    [buf replaceCharactersInRange:NSMakeRange(0, 9) withString:@"Hello"];
    XCTAssertEqualObjects([buf snapshotString], @"Hello, World");
}

- (void)testReplaceAtEnd {
    UDXMLGapBuffer *buf = [[UDXMLGapBuffer alloc] initWithString:@"Hello, Earth"];
    [buf replaceCharactersInRange:NSMakeRange(7, 5) withString:@"World"];
    XCTAssertEqualObjects([buf snapshotString], @"Hello, World");
}

- (void)testReplaceInMiddle {
    UDXMLGapBuffer *buf = [[UDXMLGapBuffer alloc] initWithString:@"foo BAD bar"];
    [buf replaceCharactersInRange:NSMakeRange(4, 3) withString:@"GOOD"];
    XCTAssertEqualObjects([buf snapshotString], @"foo GOOD bar");
}

- (void)testReplaceAll {
    UDXMLGapBuffer *buf = [[UDXMLGapBuffer alloc] initWithString:@"old content"];
    [buf replaceCharactersInRange:NSMakeRange(0, 11) withString:@"new content"];
    XCTAssertEqualObjects([buf snapshotString], @"new content");
}

// ---------------------------------------------------------------------------
// MARK: - Sequential edits (simulates typing)
// ---------------------------------------------------------------------------

- (void)testSequentialInserts {
    // Simulate typing "<root/>" one character at a time.
    UDXMLGapBuffer *buf = [[UDXMLGapBuffer alloc] initWithString:@""];
    NSString *typed = @"<root/>";
    for (NSUInteger i = 0; i < typed.length; i++) {
        NSString *ch = [typed substringWithRange:NSMakeRange(i, 1)];
        [buf replaceCharactersInRange:NSMakeRange(i, 0) withString:ch];
    }
    XCTAssertEqualObjects([buf snapshotString], @"<root/>");
}

- (void)testEditsFarApart {
    // Edit at the start, then far at the end — exercises gap movement.
    UDXMLGapBuffer *buf = [[UDXMLGapBuffer alloc] initWithString:@"<a></a>"];
    // Replace '<a>' with '<b>'.
    [buf replaceCharactersInRange:NSMakeRange(1, 1) withString:@"b"];
    XCTAssertEqualObjects([buf snapshotString], @"<b></a>");
    // Replace '</a>' with '</b>'.
    NSString *snap = [buf snapshotString];
    NSRange endTag = [snap rangeOfString:@"</a>"];
    XCTAssertNotEqual(endTag.location, NSNotFound);
    [buf replaceCharactersInRange:NSMakeRange(endTag.location + 2, 1) withString:@"b"];
    XCTAssertEqualObjects([buf snapshotString], @"<b></b>");
}

- (void)testMultipleEditsAlternatingEnds {
    // Edit alternately near start and end to exercise maximal gap movement.
    UDXMLGapBuffer *buf = [[UDXMLGapBuffer alloc] initWithString:@"ABCDE"];
    [buf replaceCharactersInRange:NSMakeRange(0, 0) withString:@"["];   // "[ABCDE"
    [buf replaceCharactersInRange:NSMakeRange(buf.length, 0) withString:@"]"]; // "[ABCDE]"
    [buf replaceCharactersInRange:NSMakeRange(1, 0) withString:@"+"]; // "[+ABCDE]"
    [buf replaceCharactersInRange:NSMakeRange(buf.length - 1, 0) withString:@"-"]; // "[+ABCDE-]"
    XCTAssertEqualObjects([buf snapshotString], @"[+ABCDE-]");
}

// ---------------------------------------------------------------------------
// MARK: - Large replacement (forces buffer growth)
// ---------------------------------------------------------------------------

- (void)testLargeInsertForcesGrowth {
    // Start with a short string; insert a very long replacement to force the
    // gap buffer to allocate more capacity.
    UDXMLGapBuffer *buf = [[UDXMLGapBuffer alloc] initWithString:@"AB"];
    NSMutableString *big = [NSMutableString stringWithCapacity:1024];
    for (int i = 0; i < 512; i++) [big appendString:@"X"];
    [buf replaceCharactersInRange:NSMakeRange(1, 0) withString:big];
    NSString *expected = [@"A" stringByAppendingString:[big stringByAppendingString:@"B"]];
    XCTAssertEqual(buf.length, expected.length);
    XCTAssertEqualObjects([buf snapshotString], expected);
}

// ---------------------------------------------------------------------------
// MARK: - Unicode (multi-byte / surrogate pairs)
// ---------------------------------------------------------------------------

- (void)testUnicodeCharacters {
    // U+1F600 GRINNING FACE is a surrogate pair in UTF-16 (2 unichars).
    NSString *emoji = @"\U0001F600";
    XCTAssertEqual(emoji.length, (NSUInteger)2, @"emoji should be 2 UTF-16 code units");

    UDXMLGapBuffer *buf = [[UDXMLGapBuffer alloc] initWithString:@"A B"];
    [buf replaceCharactersInRange:NSMakeRange(1, 1) withString:emoji];
    NSString *expected = [@"A" stringByAppendingString:[emoji stringByAppendingString:@"B"]];
    XCTAssertEqual(buf.length, expected.length);
    XCTAssertEqualObjects([buf snapshotString], expected);
}

// ---------------------------------------------------------------------------
// MARK: - Snapshot is independent copy
// ---------------------------------------------------------------------------

- (void)testSnapshotIsIndependentCopy {
    UDXMLGapBuffer *buf = [[UDXMLGapBuffer alloc] initWithString:@"Hello"];
    NSString *snapshot1 = [buf snapshotString];
    [buf replaceCharactersInRange:NSMakeRange(0, 5) withString:@"World"];
    NSString *snapshot2 = [buf snapshotString];
    // snapshot1 must still hold the original text.
    XCTAssertEqualObjects(snapshot1, @"Hello");
    XCTAssertEqualObjects(snapshot2, @"World");
}

// ---------------------------------------------------------------------------
// MARK: - Length tracking
// ---------------------------------------------------------------------------

- (void)testLengthAfterEdits {
    UDXMLGapBuffer *buf = [[UDXMLGapBuffer alloc] initWithString:@"ABCDE"];
    XCTAssertEqual(buf.length, (NSUInteger)5);
    [buf replaceCharactersInRange:NSMakeRange(2, 2) withString:@"XYZ"]; // delete 2, insert 3 → +1
    XCTAssertEqual(buf.length, (NSUInteger)6);
    [buf replaceCharactersInRange:NSMakeRange(0, 6) withString:@""]; // delete all → 0
    XCTAssertEqual(buf.length, (NSUInteger)0);
}

@end
