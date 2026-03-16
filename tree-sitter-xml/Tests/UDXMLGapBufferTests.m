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

// ---------------------------------------------------------------------------
// MARK: - UTF-8 slice (utf8DataFromByte:toByte:intoBuffer:)
// ---------------------------------------------------------------------------

// Convenience: call utf8DataFromByte:toByte:intoBuffer: and return the UTF-8 string.
// byte offsets = char offset × 2  (tree-sitter convention).
static NSString *sliceString(UDXMLGapBuffer *buf, NSMutableData *scratch,
                              NSUInteger start, NSUInteger end) {
    [buf utf8DataFromByte:(uint32_t)(start * 2)
                   toByte:(uint32_t)(end   * 2)
               intoBuffer:scratch];
    if (!scratch || scratch.length == 0) return @"";
    // Length - 1 to exclude the null terminator.
    return [[NSString alloc] initWithBytes:scratch.bytes length:scratch.length - 1
                                  encoding:NSUTF8StringEncoding] ?: @"";
}

- (void)testUTF8SliceFullRange {
    NSMutableData *b = [NSMutableData data];
    UDXMLGapBuffer *buf = [[UDXMLGapBuffer alloc] initWithString:@"Hello"];
    XCTAssertEqualObjects(sliceString(buf, b, 0, 5), @"Hello");
}

- (void)testUTF8SlicePrefix {
    NSMutableData *b = [NSMutableData data];
    UDXMLGapBuffer *buf = [[UDXMLGapBuffer alloc] initWithString:@"Hello, World!"];
    XCTAssertEqualObjects(sliceString(buf, b, 0, 5), @"Hello");
}

- (void)testUTF8SliceSuffix {
    NSMutableData *b = [NSMutableData data];
    UDXMLGapBuffer *buf = [[UDXMLGapBuffer alloc] initWithString:@"Hello, World!"];
    // "World!" starts at char index 7
    XCTAssertEqualObjects(sliceString(buf, b, 7, 13), @"World!");
}

- (void)testUTF8SliceMiddle {
    NSMutableData *b = [NSMutableData data];
    UDXMLGapBuffer *buf = [[UDXMLGapBuffer alloc] initWithString:@"<root/>"];
    // Slice char[1..5) = "root"
    XCTAssertEqualObjects(sliceString(buf, b, 1, 5), @"root");
}

- (void)testUTF8SliceEmptyRangeReturnsNul {
    NSMutableData *b = [NSMutableData data];
    UDXMLGapBuffer *buf = [[UDXMLGapBuffer alloc] initWithString:@"Hello"];
    [buf utf8DataFromByte:4 toByte:4 intoBuffer:b]; // startByte == endByte
    XCTAssertEqual(b.length, (NSUInteger)1, @"empty range should return single NUL byte");
    XCTAssertEqual(((const char *)b.bytes)[0], '\0');
}

- (void)testUTF8SliceBufferIsReused {
    // Verify that the same NSMutableData object is reused (not a new allocation).
    NSMutableData *b = [NSMutableData dataWithCapacity:64];
    UDXMLGapBuffer *buf = [[UDXMLGapBuffer alloc] initWithString:@"abcde"];
    [buf utf8DataFromByte:0 toByte:4 intoBuffer:b]; // "ab"
    NSMutableData *first = b;
    [buf utf8DataFromByte:4 toByte:8 intoBuffer:b]; // "cd"
    XCTAssertEqual(first, b, @"same buffer object must be reused");
    NSString *second = [[NSString alloc] initWithBytes:b.bytes length:b.length - 1
                                              encoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(second, @"cd");
}

- (void)testUTF8SliceSpansGap {
    NSMutableData *b = [NSMutableData data];
    // After insertions the gap is somewhere inside the buffer.
    // Slicing across the gap boundary must still yield correct text.
    UDXMLGapBuffer *buf = [[UDXMLGapBuffer alloc] initWithString:@"abcde"];
    // Insert "XY" at position 2 → "abXYcde", gap is now somewhere in the middle
    [buf replaceCharactersInRange:NSMakeRange(2, 0) withString:@"XY"];
    // Slice the whole text
    XCTAssertEqualObjects(sliceString(buf, b, 0, 7), @"abXYcde");
    // Slice crossing the original gap position
    XCTAssertEqualObjects(sliceString(buf, b, 1, 5), @"bXYc");
}

- (void)testUTF8SliceAfterDeletion {
    NSMutableData *b = [NSMutableData data];
    UDXMLGapBuffer *buf = [[UDXMLGapBuffer alloc] initWithString:@"Hello, World!"];
    [buf replaceCharactersInRange:NSMakeRange(5, 7) withString:@""]; // → "Hello!"
    XCTAssertEqualObjects(sliceString(buf, b, 0, 6), @"Hello!");
}

- (void)testUTF8SliceNullTerminated {
    NSMutableData *b = [NSMutableData data];
    // The buffer must include a null terminator so callers can pass .bytes to libxml2.
    UDXMLGapBuffer *buf = [[UDXMLGapBuffer alloc] initWithString:@"root"];
    [buf utf8DataFromByte:0 toByte:(uint32_t)(4 * 2) intoBuffer:b];
    XCTAssertGreaterThan(b.length, (NSUInteger)4, @"data must include NUL");
    XCTAssertEqual(((const char *)b.bytes)[b.length - 1], '\0', @"last byte must be NUL");
}

- (void)testUTF8SliceUnicodeAscii {
    NSMutableData *b = [NSMutableData data];
    // ASCII text: UTF-8 == UTF-16 (byte-for-byte same for 0x00-0x7F)
    UDXMLGapBuffer *buf = [[UDXMLGapBuffer alloc] initWithString:@"<tag attr=\"val\"/>"];
    // Slice out the attribute name "attr"
    XCTAssertEqualObjects(sliceString(buf, b, 5, 9), @"attr");
}

- (void)testUTF8SliceMultibyteUnicode {
    NSMutableData *b = [NSMutableData data];
    // U+00E9 é is 2 bytes in UTF-8 (0xC3 0xA9) but 1 UTF-16 code unit.
    NSString *content = @"caf\u00E9";  // "café", 4 UTF-16 code units
    UDXMLGapBuffer *buf = [[UDXMLGapBuffer alloc] initWithString:content];
    // Slice char[3..4) = "é"
    [buf utf8DataFromByte:6 toByte:8 intoBuffer:b]; // char 3 → byte 6, char 4 → byte 8
    XCTAssertGreaterThanOrEqual(b.length, (NSUInteger)3, @"é is 2 UTF-8 bytes + NUL");
    NSString *sliced = [[NSString alloc] initWithBytes:b.bytes length:b.length - 1
                                              encoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(sliced, @"\u00E9");
}

- (void)testUTF8SliceSurrogatePair {
    NSMutableData *b = [NSMutableData data];
    // U+1F600 GRINNING FACE: 2 UTF-16 code units (surrogate pair), 4 UTF-8 bytes.
    NSString *emoji = @"\U0001F600";
    UDXMLGapBuffer *buf = [[UDXMLGapBuffer alloc] initWithString:[@"A" stringByAppendingString:emoji]];
    // char[0..1) = "A"; char[1..3) = emoji (2 UTF-16 units)
    XCTAssertEqualObjects(sliceString(buf, b, 0, 1), @"A");
    [buf utf8DataFromByte:2 toByte:6 intoBuffer:b]; // char 1→byte 2, char 3→byte 6
    XCTAssertGreaterThanOrEqual(b.length, (NSUInteger)5, @"emoji is 4 UTF-8 bytes + NUL");
    NSString *slicedEmoji = [[NSString alloc] initWithBytes:b.bytes
                                                     length:b.length - 1
                                                   encoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(slicedEmoji, emoji);
}

@end
