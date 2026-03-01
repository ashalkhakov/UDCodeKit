// PieceTreeBaseTests.m
// Port of VS Code's piece tree tests
// Original: https://github.com/microsoft/vscode/blob/12bb8a5b9692bd72c7024ad88c1d0aa4fa72b48f/src/vs/editor/test/common/model/pieceTreeTextBuffer/pieceTreeTextBuffer.test.ts

#import <XCTest/XCTest.h>
#import "PieceTreeBase.h"

extern PTTreeNode *Sentinel(void);

// MARK: - Test helpers (mirrors of TS utility functions)

/// VS Code's splitLines: splits on \r\n, \r, or \n.
/// Each line INCLUDES its line-ending, except the last line.
/// e.g. "a\r\nb\nc" → ["a\r\n", "b\n", "c"]
static NSArray<NSString *> *SplitLines(NSString *str) {
    if (str.length == 0) { return @[@""]; }
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    NSInteger len = (NSInteger)str.length;
    NSInteger lineStart = 0;
    NSInteger i = 0;
    while (i < len) {
        unichar c = [str characterAtIndex:(NSUInteger)i];
        if (c == '\r') {
            // Check for \r\n
            if (i + 1 < len && [str characterAtIndex:(NSUInteger)(i + 1)] == '\n') {
                // Line includes \r\n
                [lines addObject:[str substringWithRange:NSMakeRange((NSUInteger)lineStart,
                                                                     (NSUInteger)(i + 2 - lineStart))]];
                i += 2;
            } else {
                // Line includes \r
                [lines addObject:[str substringWithRange:NSMakeRange((NSUInteger)lineStart,
                                                                     (NSUInteger)(i + 1 - lineStart))]];
                i += 1;
            }
            lineStart = i;
        } else if (c == '\n') {
            // Line includes \n
            [lines addObject:[str substringWithRange:NSMakeRange((NSUInteger)lineStart,
                                                                 (NSUInteger)(i + 1 - lineStart))]];
            i += 1;
            lineStart = i;
        } else {
            i++;
        }
    }
    // Last line (no line-ending)
    [lines addObject:[str substringFromIndex:(NSUInteger)lineStart]];
    return lines;
}

/// Trim a trailing line feed (\n, \r, or \r\n) from a string.
static NSString *TrimLineFeed(NSString *text) {
    NSInteger len = (NSInteger)text.length;
    if (len == 0) { return text; }
    unichar last = [text characterAtIndex:(NSUInteger)(len - 1)];
    if (len == 1) {
        return (last == '\n' || last == '\r') ? @"" : text;
    }
    if (last == '\n') {
        unichar prev = [text characterAtIndex:(NSUInteger)(len - 2)];
        return (prev == '\r') ? [text substringToIndex:(NSUInteger)(len - 2)] : [text substringToIndex:(NSUInteger)(len - 1)];
    }
    if (last == '\r') {
        return [text substringToIndex:(NSUInteger)(len - 1)];
    }
    return text;
}

/// Build a PTPieceTreeBase from an array of string chunks, optionally normalizing EOL to \n.
static PTPieceTreeBase *CreatePieceTree(NSArray<NSString *> *chunks, BOOL normalizeEOL) {
    NSMutableArray<PTStringBuffer *> *buffers = [NSMutableArray array];
    for (NSString *chunk in chunks) {
        if (chunk.length == 0) { continue; }
        NSMutableArray<NSNumber *> *lineStarts = [NSMutableArray arrayWithObject:@0];
        NSInteger len = (NSInteger)chunk.length;
        for (NSInteger i = 0; i < len; i++) {
            unichar c = [chunk characterAtIndex:(NSUInteger)i];
            if (c == '\r') {
                if (i + 1 < len && [chunk characterAtIndex:(NSUInteger)(i + 1)] == '\n') {
                    [lineStarts addObject:@(i + 2)]; i++;
                } else {
                    [lineStarts addObject:@(i + 1)];
                }
            } else if (c == '\n') {
                [lineStarts addObject:@(i + 1)];
            }
        }
        [buffers addObject:[[PTStringBuffer alloc] initWithBuffer:chunk lineStarts:lineStarts]];
    }
    NSString *eol = normalizeEOL ? @"\n" : @"\n";
    return [[PTPieceTreeBase alloc] initWithChunks:buffers eol:eol eolNormalized:normalizeEOL];
}

// MARK: - Tree invariant helpers

typedef struct { NSInteger size; NSInteger lfCnt; } PTNodeStats;

static NSInteger TreeDepth(PTTreeNode *n) {
    if (n == Sentinel()) { return 1; }
    NSInteger l = TreeDepth(n.left);
    NSInteger r = TreeDepth(n.right);
    // In a valid RB tree black-depths must match.
    assert(l == r);
    return (n.color == PTNodeColorBlack ? 1 : 0) + l;
}

static PTNodeStats AssertValidNode(PTTreeNode *n, XCTestCase *tc) {
    if (n == Sentinel()) { return (PTNodeStats){0, 0}; }
    PTTreeNode *l = n.left, *r = n.right;
    if (n.color == PTNodeColorRed) {
        XCTAssertEqual(l.color, PTNodeColorBlack, @"Red node must have black left child");
        XCTAssertEqual(r.color, PTNodeColorBlack, @"Red node must have black right child");
    }
    PTNodeStats leftStats = AssertValidNode(l, tc);
    XCTAssertEqual(leftStats.lfCnt, n.lfLeft,   @"lf_left mismatch");
    XCTAssertEqual(leftStats.size,  n.sizeLeft,  @"size_left mismatch");
    PTNodeStats rightStats = AssertValidNode(r, tc);
    return (PTNodeStats){
        n.sizeLeft + n.piece.length + rightStats.size,
        n.lfLeft   + n.piece.lineFeedCnt + rightStats.lfCnt
    };
}

static void AssertTreeInvariants(PTPieceTreeBase *T, XCTestCase *tc) {
    PTTreeNode *s = Sentinel();
    XCTAssertEqual(s.color, PTNodeColorBlack);
    XCTAssertEqual(s.parent, s);
    XCTAssertEqual(s.left,   s);
    XCTAssertEqual(s.right,  s);
    XCTAssertEqual(s.sizeLeft, (NSInteger)0);
    XCTAssertEqual(s.lfLeft,   (NSInteger)0);
    if (T.root == s) { return; }
    XCTAssertEqual(T.root.color, PTNodeColorBlack, @"Root must be black");
    NSInteger ld = TreeDepth(T.root.left);
    NSInteger rd = TreeDepth(T.root.right);
    XCTAssertEqual(ld, rd, @"Black-depth of left and right subtrees must match");
    AssertValidNode(T.root, tc);
}

/// Faithful port of VS Code's testLinesContent.
/// Uses SplitLines (which keeps line-endings) and getLineContent (which strips them).
static void TestLinesContent(NSString *str, PTPieceTreeBase *pt, XCTestCase *tc) {
    NSArray<NSString *> *lines = SplitLines(str);
    XCTAssertEqual([pt getLineCount], (NSInteger)lines.count,
                   @"getLineCount mismatch for: %@", str);
    XCTAssertEqualObjects([pt getLinesRawContent], str);
    for (NSInteger i = 0; i < (NSInteger)lines.count; i++) {
        NSString *lineWithEOL = lines[(NSUInteger)i];
        // getLineContent strips the EOL (returns just the text)
        NSString *lineNoEOL = TrimLineFeed(lineWithEOL);
        XCTAssertEqualObjects([pt getLineContent:i + 1], lineNoEOL,
                              @"getLineContent(%ld) mismatch", (long)(i + 1));

        // getValueInRange with the full line width (including EOL column)
        NSInteger endCol;
        if (i == (NSInteger)lines.count - 1) {
            endCol = (NSInteger)lineNoEOL.length + 1;
        } else {
            endCol = (NSInteger)lineNoEOL.length + 2;
        }
        NSString *rangeVal = [pt getValueInRange_startLine:i + 1
                                              startColumn:1
                                                  endLine:i + 1
                                                endColumn:endCol];
        XCTAssertEqualObjects(TrimLineFeed(rangeVal), lineNoEOL,
                              @"getValueInRange line %ld mismatch", (long)(i + 1));
    }
}

/// Faithful port of VS Code's testLineStarts.
/// Requires both getOffsetAt(line, col) AND getPositionAt(offset).
static void TestLineStarts(NSString *str, PTPieceTreeBase *pt, XCTestCase *tc) {
    // Build the expected array of line-start offsets by scanning for \r\n, \r, \n
    NSMutableArray<NSNumber *> *lineStarts = [NSMutableArray arrayWithObject:@0];
    NSInteger len = (NSInteger)str.length;
    NSInteger i = 0;
    while (i < len) {
        unichar c = [str characterAtIndex:(NSUInteger)i];
        if (c == '\r') {
            if (i + 1 < len && [str characterAtIndex:(NSUInteger)(i + 1)] == '\n') {
                [lineStarts addObject:@(i + 2)];
                i += 2;
            } else {
                [lineStarts addObject:@(i + 1)];
                i += 1;
            }
        } else if (c == '\n') {
            [lineStarts addObject:@(i + 1)];
            i += 1;
        } else {
            i++;
        }
    }

    // Forward check: getPositionAt(lineStart[i]) == (i+1, 1)  AND  getOffsetAt(i+1, 1) == lineStart[i]
    for (NSInteger idx = 0; idx < (NSInteger)lineStarts.count; idx++) {
        NSInteger offset = lineStarts[(NSUInteger)idx].integerValue;

        // getPositionAt(offset) should give line=idx+1, col=1
        PTPosition pos = [pt getPositionAt:offset];
        XCTAssertEqual(pos.line, idx + 1,
                       @"getPositionAt(%ld).line expected %ld got %ld",
                       (long)offset, (long)(idx + 1), (long)pos.line);
        XCTAssertEqual(pos.column, (NSInteger)1,
                       @"getPositionAt(%ld).column expected 1 got %ld",
                       (long)offset, (long)pos.column);

        // getOffsetAt(idx+1, 1) should give offset
        NSInteger got = [pt getOffsetAtLine:idx + 1 column:1];
        XCTAssertEqual(got, offset,
                       @"getOffsetAt(%ld, 1) expected %ld got %ld",
                       (long)(idx + 1), (long)offset, (long)got);
    }

    // Reverse check: for each lineStart > 0, getPositionAt(lineStart-1) roundtrips
    for (NSInteger idx = 1; idx < (NSInteger)lineStarts.count; idx++) {
        NSInteger offset = lineStarts[(NSUInteger)idx].integerValue - 1;
        PTPosition pos = [pt getPositionAt:offset];
        NSInteger roundtrip = [pt getOffsetAtLine:pos.line column:pos.column];
        XCTAssertEqual(roundtrip, offset,
                       @"roundtrip failed at offset %ld (line=%ld col=%ld → %ld)",
                       (long)offset, (long)pos.line, (long)pos.column, (long)roundtrip);
    }
}

// MARK: - Random helpers

static NSString * const kAlphabet = @"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ\r\n";

static NSString *RandomString(NSInteger len) {
    NSMutableString *s = [NSMutableString stringWithCapacity:(NSUInteger)len];
    NSInteger alphabetLen = (NSInteger)kAlphabet.length;
    for (NSInteger i = 0; i < len; i++) {
        NSInteger idx = arc4random_uniform((uint32_t)alphabetLen);
        [s appendFormat:@"%C", [kAlphabet characterAtIndex:(NSUInteger)idx]];
    }
    return [s copy];
}

static NSString *SubstringInsert(NSString *orig, NSInteger pos, NSString *insert) {
    NSMutableString *m = [orig mutableCopy];
    [m insertString:insert atIndex:(NSUInteger)pos];
    return [m copy];
}

static NSString *SubstringDelete(NSString *orig, NSInteger pos, NSInteger count) {
    NSMutableString *m = [orig mutableCopy];
    [m deleteCharactersInRange:NSMakeRange((NSUInteger)pos, (NSUInteger)count)];
    return [m copy];
}


// MARK: - XCTestCase

@interface PieceTreeBaseTests : XCTestCase
@end

@implementation PieceTreeBaseTests

// MARK: - inserts and deletes

- (void)testBasicInsertDelete {
    PTPieceTreeBase *pt = CreatePieceTree(@[@"This is a document with some text."], YES);
    [pt insertAtOffset:34 value:@"This is some more text to insert at offset 34." eolNormalized:YES];
    XCTAssertEqualObjects([pt getLinesRawContent],
        @"This is a document with some text.This is some more text to insert at offset 34.");
    [pt deleteAtOffset:42 count:5];
    XCTAssertEqualObjects([pt getLinesRawContent],
        @"This is a document with some text.This is more text to insert at offset 34.");
    AssertTreeInvariants(pt, self);
}

- (void)testMoreInserts {
    PTPieceTreeBase *pt = CreatePieceTree(@[@""], YES);
    [pt insertAtOffset:0 value:@"AAA" eolNormalized:YES];
    XCTAssertEqualObjects([pt getLinesRawContent], @"AAA");
    [pt insertAtOffset:0 value:@"BBB" eolNormalized:YES];
    XCTAssertEqualObjects([pt getLinesRawContent], @"BBBAAA");
    [pt insertAtOffset:6 value:@"CCC" eolNormalized:YES];
    XCTAssertEqualObjects([pt getLinesRawContent], @"BBBAAACCC");
    [pt insertAtOffset:5 value:@"DDD" eolNormalized:YES];
    XCTAssertEqualObjects([pt getLinesRawContent], @"BBBAADDDACCC");
    AssertTreeInvariants(pt, self);
}

- (void)testMoreDeletes {
    PTPieceTreeBase *pt = CreatePieceTree(@[@"012345678"], YES);
    [pt deleteAtOffset:8 count:1]; XCTAssertEqualObjects([pt getLinesRawContent], @"01234567");
    [pt deleteAtOffset:0 count:1]; XCTAssertEqualObjects([pt getLinesRawContent], @"1234567");
    [pt deleteAtOffset:5 count:1]; XCTAssertEqualObjects([pt getLinesRawContent], @"123457");
    [pt deleteAtOffset:5 count:1]; XCTAssertEqualObjects([pt getLinesRawContent], @"12345");
    [pt deleteAtOffset:0 count:5]; XCTAssertEqualObjects([pt getLinesRawContent], @"");
    AssertTreeInvariants(pt, self);
}

- (void)testRandomTest1 {
    NSString *str = @"";
    PTPieceTreeBase *pt = CreatePieceTree(@[@""], YES);
    str = SubstringInsert(str, 0,  @"ceLPHmFzvCtFeHkCBej ");
    [pt insertAtOffset:0  value:@"ceLPHmFzvCtFeHkCBej "  eolNormalized:YES];
    XCTAssertEqualObjects([pt getLinesRawContent], str);
    str = SubstringInsert(str, 8,  @"gDCEfNYiBUNkSwtvB K ");
    [pt insertAtOffset:8  value:@"gDCEfNYiBUNkSwtvB K "  eolNormalized:YES];
    XCTAssertEqualObjects([pt getLinesRawContent], str);
    str = SubstringInsert(str, 38, @"cyNcHxjNPPoehBJldLS ");
    [pt insertAtOffset:38 value:@"cyNcHxjNPPoehBJldLS " eolNormalized:YES];
    XCTAssertEqualObjects([pt getLinesRawContent], str);
    str = SubstringInsert(str, 59, @"ejMx\nOTgWlbpeDExjOk ");
    [pt insertAtOffset:59 value:@"ejMx\nOTgWlbpeDExjOk " eolNormalized:YES];
    XCTAssertEqualObjects([pt getLinesRawContent], str);
    AssertTreeInvariants(pt, self);
}

- (void)testRandomTest2 {
    NSString *str = @"";
    PTPieceTreeBase *pt = CreatePieceTree(@[@""], YES);
    str = SubstringInsert(str, 0,  @"VgPG "); [pt insertAtOffset:0  value:@"VgPG "  eolNormalized:YES];
    str = SubstringInsert(str, 2,  @"DdWF "); [pt insertAtOffset:2  value:@"DdWF "  eolNormalized:YES];
    str = SubstringInsert(str, 0,  @"hUJc "); [pt insertAtOffset:0  value:@"hUJc "  eolNormalized:YES];
    str = SubstringInsert(str, 8,  @"lQEq "); [pt insertAtOffset:8  value:@"lQEq "  eolNormalized:YES];
    str = SubstringInsert(str, 10, @"Gbtp "); [pt insertAtOffset:10 value:@"Gbtp "  eolNormalized:YES];
    XCTAssertEqualObjects([pt getLinesRawContent], str);
    AssertTreeInvariants(pt, self);
}

- (void)testRandomTest3 {
    NSString *str = @"";
    PTPieceTreeBase *pt = CreatePieceTree(@[@""], YES);
    str = SubstringInsert(str, 0,  @"gYSz"); [pt insertAtOffset:0  value:@"gYSz" eolNormalized:YES];
    str = SubstringInsert(str, 1,  @"mDQe"); [pt insertAtOffset:1  value:@"mDQe" eolNormalized:YES];
    str = SubstringInsert(str, 1,  @"DTMQ"); [pt insertAtOffset:1  value:@"DTMQ" eolNormalized:YES];
    str = SubstringInsert(str, 2,  @"GGZB"); [pt insertAtOffset:2  value:@"GGZB" eolNormalized:YES];
    str = SubstringInsert(str, 12, @"wXpq"); [pt insertAtOffset:12 value:@"wXpq" eolNormalized:YES];
    XCTAssertEqualObjects([pt getLinesRawContent], str);
}

- (void)testRandomDelete1 {
    NSString *str = @"";
    PTPieceTreeBase *pt = CreatePieceTree(@[@""], YES);
    str = SubstringInsert(str, 0, @"vfb"); [pt insertAtOffset:0 value:@"vfb" eolNormalized:YES];
    XCTAssertEqualObjects([pt getLinesRawContent], str);
    str = SubstringInsert(str, 0, @"zRq"); [pt insertAtOffset:0 value:@"zRq" eolNormalized:YES];
    XCTAssertEqualObjects([pt getLinesRawContent], str);
    str = SubstringDelete(str, 5, 1); [pt deleteAtOffset:5 count:1];
    XCTAssertEqualObjects([pt getLinesRawContent], str);
    str = SubstringInsert(str, 1, @"UNw"); [pt insertAtOffset:1 value:@"UNw" eolNormalized:YES];
    XCTAssertEqualObjects([pt getLinesRawContent], str);
    str = SubstringDelete(str, 4, 3); [pt deleteAtOffset:4 count:3];
    XCTAssertEqualObjects([pt getLinesRawContent], str);
    str = SubstringDelete(str, 1, 4); [pt deleteAtOffset:1 count:4];
    XCTAssertEqualObjects([pt getLinesRawContent], str);
    str = SubstringDelete(str, 0, 1); [pt deleteAtOffset:0 count:1];
    XCTAssertEqualObjects([pt getLinesRawContent], str);
    AssertTreeInvariants(pt, self);
}

- (void)testRandomDelete2 {
    NSString *str = @"";
    PTPieceTreeBase *pt = CreatePieceTree(@[@""], YES);
    str = SubstringInsert(str, 0, @"IDT"); [pt insertAtOffset:0 value:@"IDT" eolNormalized:YES];
    str = SubstringInsert(str, 3, @"wwA"); [pt insertAtOffset:3 value:@"wwA" eolNormalized:YES];
    str = SubstringInsert(str, 3, @"Gnr"); [pt insertAtOffset:3 value:@"Gnr" eolNormalized:YES];
    str = SubstringDelete(str, 6, 3); [pt deleteAtOffset:6 count:3];
    str = SubstringInsert(str, 4, @"eHp"); [pt insertAtOffset:4 value:@"eHp" eolNormalized:YES];
    str = SubstringInsert(str, 1, @"UAi"); [pt insertAtOffset:1 value:@"UAi" eolNormalized:YES];
    str = SubstringInsert(str, 2, @"FrR"); [pt insertAtOffset:2 value:@"FrR" eolNormalized:YES];
    str = SubstringDelete(str, 6, 7); [pt deleteAtOffset:6 count:7];
    str = SubstringDelete(str, 3, 5); [pt deleteAtOffset:3 count:5];
    XCTAssertEqualObjects([pt getLinesRawContent], str);
    AssertTreeInvariants(pt, self);
}

- (void)testRandomDelete3 {
    NSString *str = @"";
    PTPieceTreeBase *pt = CreatePieceTree(@[@""], YES);
    str = SubstringInsert(str, 0,  @"PqM");    [pt insertAtOffset:0  value:@"PqM"  eolNormalized:YES];
    str = SubstringDelete(str, 1,  2);          [pt deleteAtOffset:1  count:2];
    str = SubstringInsert(str, 1,  @"zLc");    [pt insertAtOffset:1  value:@"zLc"  eolNormalized:YES];
    str = SubstringInsert(str, 0,  @"MEX");    [pt insertAtOffset:0  value:@"MEX"  eolNormalized:YES];
    str = SubstringInsert(str, 0,  @"jZh");    [pt insertAtOffset:0  value:@"jZh"  eolNormalized:YES];
    str = SubstringInsert(str, 8,  @"GwQ");    [pt insertAtOffset:8  value:@"GwQ"  eolNormalized:YES];
    str = SubstringDelete(str, 5,  6);          [pt deleteAtOffset:5  count:6];
    str = SubstringInsert(str, 4,  @"ktw");    [pt insertAtOffset:4  value:@"ktw"  eolNormalized:YES];
    str = SubstringInsert(str, 5,  @"GVu");    [pt insertAtOffset:5  value:@"GVu"  eolNormalized:YES];
    str = SubstringInsert(str, 9,  @"jdm");    [pt insertAtOffset:9  value:@"jdm"  eolNormalized:YES];
    str = SubstringInsert(str, 15, @"na\n");   [pt insertAtOffset:15 value:@"na\n" eolNormalized:YES];
    str = SubstringDelete(str, 5,  8);          [pt deleteAtOffset:5  count:8];
    str = SubstringDelete(str, 3,  4);          [pt deleteAtOffset:3  count:4];
    XCTAssertEqualObjects([pt getLinesRawContent], str);
    AssertTreeInvariants(pt, self);
}

- (void)testRandomInsertDeleteCRBug1 {
    NSString *str = @"a";
    PTPieceTreeBase *pt = CreatePieceTree(@[@"a"], YES);
    str = SubstringDelete(str, 0, 1);            [pt deleteAtOffset:0 count:1];
    str = SubstringInsert(str, 0, @"\r\r\n\n"); [pt insertAtOffset:0 value:@"\r\r\n\n" eolNormalized:NO];
    str = SubstringDelete(str, 3, 1);            [pt deleteAtOffset:3 count:1];
    str = SubstringInsert(str, 2, @"\n\n\ra"); [pt insertAtOffset:2 value:@"\n\n\ra" eolNormalized:NO];
    str = SubstringDelete(str, 4, 3);            [pt deleteAtOffset:4 count:3];
    str = SubstringInsert(str, 2, @"\na\r\r"); [pt insertAtOffset:2 value:@"\na\r\r" eolNormalized:NO];
    str = SubstringInsert(str, 6, @"\ra\n\n"); [pt insertAtOffset:6 value:@"\ra\n\n" eolNormalized:NO];
    str = SubstringInsert(str, 0, @"aa\n\n");  [pt insertAtOffset:0 value:@"aa\n\n"  eolNormalized:NO];
    str = SubstringInsert(str, 5, @"\n\na\r"); [pt insertAtOffset:5 value:@"\n\na\r" eolNormalized:NO];
    XCTAssertEqualObjects([pt getLinesRawContent], str);
    AssertTreeInvariants(pt, self);
}

- (void)testRandomInsertDeleteCRBug2 {
    NSString *str = @"a";
    PTPieceTreeBase *pt = CreatePieceTree(@[@"a"], YES);
    str = SubstringInsert(str, 1,  @"\naa\r");   [pt insertAtOffset:1  value:@"\naa\r"   eolNormalized:NO];
    str = SubstringDelete(str, 0,  4);            [pt deleteAtOffset:0  count:4];
    str = SubstringInsert(str, 1,  @"\r\r\na"); [pt insertAtOffset:1  value:@"\r\r\na"  eolNormalized:NO];
    str = SubstringInsert(str, 2,  @"\n\r\ra"); [pt insertAtOffset:2  value:@"\n\r\ra"  eolNormalized:NO];
    str = SubstringDelete(str, 4,  1);            [pt deleteAtOffset:4  count:1];
    str = SubstringInsert(str, 8,  @"\r\n\r\r"); [pt insertAtOffset:8  value:@"\r\n\r\r" eolNormalized:NO];
    str = SubstringInsert(str, 7,  @"\n\n\na"); [pt insertAtOffset:7  value:@"\n\n\na"  eolNormalized:NO];
    str = SubstringInsert(str, 13, @"a\n\na");  [pt insertAtOffset:13 value:@"a\n\na"   eolNormalized:NO];
    str = SubstringDelete(str, 17, 3);            [pt deleteAtOffset:17 count:3];
    str = SubstringInsert(str, 2,  @"a\ra\n");  [pt insertAtOffset:2  value:@"a\ra\n"   eolNormalized:NO];
    XCTAssertEqualObjects([pt getLinesRawContent], str);
    AssertTreeInvariants(pt, self);
}

- (void)testRandomInsertDeleteCRBug3 {
    NSString *str = @"a";
    PTPieceTreeBase *pt = CreatePieceTree(@[@"a"], YES);
    str = SubstringInsert(str, 0,  @"\r\na\r");  [pt insertAtOffset:0  value:@"\r\na\r"  eolNormalized:NO];
    str = SubstringDelete(str, 2,  3);            [pt deleteAtOffset:2  count:3];
    str = SubstringInsert(str, 2,  @"a\r\n\r"); [pt insertAtOffset:2  value:@"a\r\n\r"  eolNormalized:NO];
    str = SubstringDelete(str, 4,  2);            [pt deleteAtOffset:4  count:2];
    str = SubstringInsert(str, 4,  @"a\n\r\n"); [pt insertAtOffset:4  value:@"a\n\r\n"  eolNormalized:NO];
    str = SubstringInsert(str, 1,  @"aa\n\r");  [pt insertAtOffset:1  value:@"aa\n\r"   eolNormalized:NO];
    str = SubstringInsert(str, 7,  @"\na\r\n"); [pt insertAtOffset:7  value:@"\na\r\n"  eolNormalized:NO];
    str = SubstringInsert(str, 5,  @"\n\na\r"); [pt insertAtOffset:5  value:@"\n\na\r"  eolNormalized:NO];
    str = SubstringInsert(str, 10, @"\r\r\n\r");[pt insertAtOffset:10 value:@"\r\r\n\r" eolNormalized:NO];
    XCTAssertEqualObjects([pt getLinesRawContent], str);
    str = SubstringDelete(str, 21, 3); [pt deleteAtOffset:21 count:3];
    XCTAssertEqualObjects([pt getLinesRawContent], str);
    AssertTreeInvariants(pt, self);
}

- (void)testRandomInsertDeleteCRBug4 {
    NSString *str = @"a";
    PTPieceTreeBase *pt = CreatePieceTree(@[@"a"], YES);
    str = SubstringDelete(str, 0, 1);            [pt deleteAtOffset:0 count:1];
    str = SubstringInsert(str, 0, @"\naaa");    [pt insertAtOffset:0 value:@"\naaa"   eolNormalized:NO];
    str = SubstringInsert(str, 2, @"\n\naa");   [pt insertAtOffset:2 value:@"\n\naa"  eolNormalized:NO];
    str = SubstringDelete(str, 1, 4);            [pt deleteAtOffset:1 count:4];
    str = SubstringDelete(str, 3, 1);            [pt deleteAtOffset:3 count:1];
    str = SubstringDelete(str, 1, 2);            [pt deleteAtOffset:1 count:2];
    str = SubstringDelete(str, 0, 1);            [pt deleteAtOffset:0 count:1];
    str = SubstringInsert(str, 0, @"a\n\n\r"); [pt insertAtOffset:0 value:@"a\n\n\r" eolNormalized:NO];
    str = SubstringInsert(str, 2, @"aa\r\n");  [pt insertAtOffset:2 value:@"aa\r\n"  eolNormalized:NO];
    str = SubstringInsert(str, 3, @"a\naa");   [pt insertAtOffset:3 value:@"a\naa"   eolNormalized:NO];
    XCTAssertEqualObjects([pt getLinesRawContent], str);
    AssertTreeInvariants(pt, self);
}

- (void)testRandomInsertDeleteCRBug5 {
    NSString *str = @"";
    PTPieceTreeBase *pt = CreatePieceTree(@[@""], YES);
    str = SubstringInsert(str, 0,  @"\n\n\n\r"); [pt insertAtOffset:0  value:@"\n\n\n\r" eolNormalized:NO];
    str = SubstringInsert(str, 1,  @"\n\n\n\r"); [pt insertAtOffset:1  value:@"\n\n\n\r" eolNormalized:NO];
    str = SubstringInsert(str, 2,  @"\n\r\r\r"); [pt insertAtOffset:2  value:@"\n\r\r\r" eolNormalized:NO];
    str = SubstringInsert(str, 8,  @"\n\r\n\r"); [pt insertAtOffset:8  value:@"\n\r\n\r" eolNormalized:NO];
    str = SubstringDelete(str, 5,  2);             [pt deleteAtOffset:5  count:2];
    str = SubstringInsert(str, 4,  @"\n\r\r\r"); [pt insertAtOffset:4  value:@"\n\r\r\r" eolNormalized:NO];
    str = SubstringInsert(str, 8,  @"\n\n\n\r"); [pt insertAtOffset:8  value:@"\n\n\n\r" eolNormalized:NO];
    str = SubstringDelete(str, 0,  7);             [pt deleteAtOffset:0  count:7];
    str = SubstringInsert(str, 1,  @"\r\n\r\r"); [pt insertAtOffset:1  value:@"\r\n\r\r" eolNormalized:NO];
    str = SubstringInsert(str, 15, @"\n\r\r\r"); [pt insertAtOffset:15 value:@"\n\r\r\r" eolNormalized:NO];
    XCTAssertEqualObjects([pt getLinesRawContent], str);
    AssertTreeInvariants(pt, self);
}

// MARK: - prefix sum for line feed

- (void)testPrefixSumBasic {
    PTPieceTreeBase *pt = CreatePieceTree(@[@"1\n2\n3\n4"], YES);
    XCTAssertEqual([pt getLineCount], (NSInteger)4);
    XCTAssertEqual([pt getOffsetAtLine:1 column:1], (NSInteger)0);
    XCTAssertEqual([pt getOffsetAtLine:1 column:2], (NSInteger)1);
    XCTAssertEqual([pt getOffsetAtLine:2 column:1], (NSInteger)2);
    XCTAssertEqual([pt getOffsetAtLine:2 column:2], (NSInteger)3);
    XCTAssertEqual([pt getOffsetAtLine:3 column:1], (NSInteger)4);
    XCTAssertEqual([pt getOffsetAtLine:3 column:2], (NSInteger)5);
    XCTAssertEqual([pt getOffsetAtLine:4 column:1], (NSInteger)6);
    AssertTreeInvariants(pt, self);
}

- (void)testPrefixSumAppend {
    PTPieceTreeBase *pt = CreatePieceTree(@[@"a\nb\nc\nde"], YES);
    [pt insertAtOffset:8 value:@"fh\ni\njk" eolNormalized:YES];
    XCTAssertEqual([pt getLineCount], (NSInteger)6);
    XCTAssertEqual([pt getOffsetAtLine:1 column:1], (NSInteger)0);
    AssertTreeInvariants(pt, self);
}

- (void)testPrefixSumInsert {
    PTPieceTreeBase *pt = CreatePieceTree(@[@"a\nb\nc\nde"], YES);
    [pt insertAtOffset:7 value:@"fh\ni\njk" eolNormalized:YES];
    XCTAssertEqual([pt getLineCount], (NSInteger)6);
    XCTAssertEqual([pt getOffsetAtLine:4 column:1], (NSInteger)6);
    XCTAssertEqual([pt getOffsetAtLine:4 column:2], (NSInteger)7);
    XCTAssertEqual([pt getOffsetAtLine:4 column:3], (NSInteger)8);
    XCTAssertEqual([pt getOffsetAtLine:4 column:4], (NSInteger)9);
    XCTAssertEqual([pt getOffsetAtLine:6 column:1], (NSInteger)12);
    XCTAssertEqual([pt getOffsetAtLine:6 column:2], (NSInteger)13);
    XCTAssertEqual([pt getOffsetAtLine:6 column:3], (NSInteger)14);
    AssertTreeInvariants(pt, self);
}

- (void)testPrefixSumDelete {
    PTPieceTreeBase *pt = CreatePieceTree(@[@"a\nb\nc\ndefh\ni\njk"], YES);
    [pt deleteAtOffset:7 count:2];
    XCTAssertEqualObjects([pt getLinesRawContent], @"a\nb\nc\ndh\ni\njk");
    XCTAssertEqual([pt getLineCount], (NSInteger)6);
    XCTAssertEqual([pt getOffsetAtLine:4 column:1], (NSInteger)6);
    XCTAssertEqual([pt getOffsetAtLine:4 column:2], (NSInteger)7);
    XCTAssertEqual([pt getOffsetAtLine:4 column:3], (NSInteger)8);
    XCTAssertEqual([pt getOffsetAtLine:5 column:1], (NSInteger)9);
    XCTAssertEqual([pt getOffsetAtLine:6 column:1], (NSInteger)11);
    XCTAssertEqual([pt getOffsetAtLine:6 column:2], (NSInteger)12);
    XCTAssertEqual([pt getOffsetAtLine:6 column:3], (NSInteger)13);
    AssertTreeInvariants(pt, self);
}

- (void)testPrefixSumAddDelete1 {
    PTPieceTreeBase *pt = CreatePieceTree(@[@"a\nb\nc\nde"], YES);
    [pt insertAtOffset:8 value:@"fh\ni\njk" eolNormalized:YES];
    [pt deleteAtOffset:7 count:2];
    XCTAssertEqualObjects([pt getLinesRawContent], @"a\nb\nc\ndh\ni\njk");
    XCTAssertEqual([pt getLineCount], (NSInteger)6);
    XCTAssertEqual([pt getOffsetAtLine:4 column:1], (NSInteger)6);
    XCTAssertEqual([pt getOffsetAtLine:5 column:1], (NSInteger)9);
    XCTAssertEqual([pt getOffsetAtLine:6 column:1], (NSInteger)11);
    AssertTreeInvariants(pt, self);
}

- (void)testInsertRandomBugPrefixSum1 {
    NSString *str = @"";
    PTPieceTreeBase *pt = CreatePieceTree(@[@""], YES);
    str = SubstringInsert(str, 0,  @" ZX \n Z\nZ\n YZ\nY\nZXX "); [pt insertAtOffset:0  value:@" ZX \n Z\nZ\n YZ\nY\nZXX " eolNormalized:YES];
    str = SubstringInsert(str, 14, @"X ZZ\nYZZYZXXY Y XY\n "); [pt insertAtOffset:14 value:@"X ZZ\nYZZYZXXY Y XY\n " eolNormalized:YES];
    XCTAssertEqualObjects([pt getLinesRawContent], str);
    TestLineStarts(str, pt, self);
    AssertTreeInvariants(pt, self);
}

- (void)testInsertRandomBugPrefixSum2 {
    NSString *str = @"";
    PTPieceTreeBase *pt = CreatePieceTree(@[@""], YES);
    str = SubstringInsert(str, 0, @"ZYZ\nYY XY\nX \nZ Y \nZ "); [pt insertAtOffset:0 value:@"ZYZ\nYY XY\nX \nZ Y \nZ " eolNormalized:YES];
    str = SubstringInsert(str, 3, @"XXY \n\nY Y YYY  ZYXY ");  [pt insertAtOffset:3 value:@"XXY \n\nY Y YYY  ZYXY "  eolNormalized:YES];
    XCTAssertEqualObjects([pt getLinesRawContent], str);
    TestLineStarts(str, pt, self);
    AssertTreeInvariants(pt, self);
}

- (void)testDeleteRandomBugLineFeedCnt {
    PTPieceTreeBase *pt = CreatePieceTree(@[@""], YES);
    [pt insertAtOffset:0   value:@"ba\na\nca\nba\ncbab\ncaa "    eolNormalized:YES];
    [pt insertAtOffset:13  value:@"cca\naabb\ncac\nccc\nab "     eolNormalized:YES];
    [pt deleteAtOffset:5   count:8];
    [pt deleteAtOffset:30  count:2];
    [pt insertAtOffset:24  value:@"cbbacccbac\nbaaab\n\nc "     eolNormalized:YES];
    [pt deleteAtOffset:29  count:3];
    [pt deleteAtOffset:23  count:9];
    [pt deleteAtOffset:21  count:5];
    [pt deleteAtOffset:30  count:3];
    [pt insertAtOffset:3   value:@"cb\nac\nc\n\nacc\nbb\nb\nc "   eolNormalized:YES];
    [pt deleteAtOffset:19  count:5];
    [pt insertAtOffset:18  value:@"\nbb\n\nacbc\ncbb\nc\nbb\n "  eolNormalized:YES];
    [pt insertAtOffset:65  value:@"cbccbac\nbc\n\nccabba\n "    eolNormalized:YES];
    [pt insertAtOffset:77  value:@"a\ncacb\n\nac\n\n\n\n\nabab " eolNormalized:YES];
    [pt deleteAtOffset:30  count:9];
    [pt insertAtOffset:45  value:@"b\n\nc\nba\n\nbbbba\n\naa\n "  eolNormalized:YES];
    [pt insertAtOffset:82  value:@"ab\nbb\ncabacab\ncbc\na "    eolNormalized:YES];
    [pt deleteAtOffset:123 count:9];
    [pt deleteAtOffset:71  count:2];
    [pt insertAtOffset:33  value:@"acaa\nacb\n\naa\n\nc\n\n\n\n " eolNormalized:YES];
    NSString *str = [pt getLinesRawContent];
    TestLineStarts(str, pt, self);
    AssertTreeInvariants(pt, self);
}

- (void)testDeleteRandomBugRBTree1 {
    NSString *str = @"";
    PTPieceTreeBase *pt = CreatePieceTree(@[@""], YES);
    str = SubstringInsert(str, 0,  @"YXXZ\n\nYY\n"); [pt insertAtOffset:0  value:@"YXXZ\n\nYY\n" eolNormalized:YES];
    str = SubstringDelete(str, 0,  5);                [pt deleteAtOffset:0  count:5];
    str = SubstringInsert(str, 0,  @"ZXYY\nX\nZ\n"); [pt insertAtOffset:0  value:@"ZXYY\nX\nZ\n" eolNormalized:YES];
    str = SubstringInsert(str, 10, @"\nXY\nYXYXY"); [pt insertAtOffset:10 value:@"\nXY\nYXYXY" eolNormalized:YES];
    TestLineStarts(str, pt, self);
    AssertTreeInvariants(pt, self);
}

- (void)testDeleteRandomBugRBTree2 {
    NSString *str = @"";
    PTPieceTreeBase *pt = CreatePieceTree(@[@""], YES);
    str = SubstringInsert(str, 0,  @"YXXZ\n\nYY\n"); [pt insertAtOffset:0  value:@"YXXZ\n\nYY\n" eolNormalized:YES];
    str = SubstringInsert(str, 0,  @"ZXYY\nX\nZ\n"); [pt insertAtOffset:0  value:@"ZXYY\nX\nZ\n" eolNormalized:YES];
    str = SubstringInsert(str, 10, @"\nXY\nYXYXY"); [pt insertAtOffset:10 value:@"\nXY\nYXYXY" eolNormalized:YES];
    str = SubstringInsert(str, 8,  @"YZXY\nZ\nYX"); [pt insertAtOffset:8  value:@"YZXY\nZ\nYX" eolNormalized:YES];
    str = SubstringInsert(str, 12, @"XX\nXXYXYZ"); [pt insertAtOffset:12 value:@"XX\nXXYXYZ"  eolNormalized:YES];
    str = SubstringDelete(str, 0,  4);               [pt deleteAtOffset:0  count:4];
    TestLineStarts(str, pt, self);
    AssertTreeInvariants(pt, self);
}

- (void)testDeleteRandomBugRBTree3 {
    NSString *str = @"";
    PTPieceTreeBase *pt = CreatePieceTree(@[@""], YES);
    str = SubstringInsert(str, 0,  @"YXXZ\n\nYY\n"); [pt insertAtOffset:0  value:@"YXXZ\n\nYY\n" eolNormalized:YES];
    str = SubstringDelete(str, 7,  2);                [pt deleteAtOffset:7  count:2];
    str = SubstringDelete(str, 6,  1);                [pt deleteAtOffset:6  count:1];
    str = SubstringDelete(str, 0,  5);                [pt deleteAtOffset:0  count:5];
    str = SubstringInsert(str, 0,  @"ZXYY\nX\nZ\n"); [pt insertAtOffset:0  value:@"ZXYY\nX\nZ\n" eolNormalized:YES];
    str = SubstringInsert(str, 10, @"\nXY\nYXYXY"); [pt insertAtOffset:10 value:@"\nXY\nYXYXY" eolNormalized:YES];
    str = SubstringInsert(str, 8,  @"YZXY\nZ\nYX"); [pt insertAtOffset:8  value:@"YZXY\nZ\nYX" eolNormalized:YES];
    str = SubstringInsert(str, 12, @"XX\nXXYXYZ"); [pt insertAtOffset:12 value:@"XX\nXXYXYZ"  eolNormalized:YES];
    str = SubstringDelete(str, 0,  4);               [pt deleteAtOffset:0  count:4];
    str = SubstringDelete(str, 30, 3);               [pt deleteAtOffset:30 count:3];
    TestLineStarts(str, pt, self);
    AssertTreeInvariants(pt, self);
}

// MARK: - offset → position

- (void)testOffsetToPositionBug1 {
    NSString *str = @"";
    PTPieceTreeBase *pt = CreatePieceTree(@[@""], YES);
    str = SubstringInsert(str, 0,  @"huuyYzUfKOENwGgZLqn "); [pt insertAtOffset:0  value:@"huuyYzUfKOENwGgZLqn " eolNormalized:YES];
    str = SubstringDelete(str, 18, 2);                         [pt deleteAtOffset:18 count:2];
    str = SubstringDelete(str, 3,  1);                         [pt deleteAtOffset:3  count:1];
    str = SubstringDelete(str, 12, 4);                         [pt deleteAtOffset:12 count:4];
    str = SubstringInsert(str, 3,  @"hMbnVEdTSdhLlPevXKF "); [pt insertAtOffset:3  value:@"hMbnVEdTSdhLlPevXKF " eolNormalized:YES];
    str = SubstringDelete(str, 22, 8);                         [pt deleteAtOffset:22 count:8];
    str = SubstringInsert(str, 4,  @"S umSnYrqOmOAV\nEbZJ ");[pt insertAtOffset:4  value:@"S umSnYrqOmOAV\nEbZJ " eolNormalized:YES];
    TestLineStarts(str, pt, self);
    AssertTreeInvariants(pt, self);
}

// MARK: - get text in range

- (void)testGetContentInRange {
    PTPieceTreeBase *pt = CreatePieceTree(@[@"a\nb\nc\nde"], YES);
    [pt insertAtOffset:8 value:@"fh\ni\njk" eolNormalized:YES];
    [pt deleteAtOffset:7 count:2];
    // "a\nb\nc\ndh\ni\njk"
    XCTAssertEqualObjects([pt getValueInRange_startLine:1 startColumn:1 endLine:1 endColumn:3], @"a\n");
    XCTAssertEqualObjects([pt getValueInRange_startLine:2 startColumn:1 endLine:2 endColumn:3], @"b\n");
    XCTAssertEqualObjects([pt getValueInRange_startLine:3 startColumn:1 endLine:3 endColumn:3], @"c\n");
    XCTAssertEqualObjects([pt getValueInRange_startLine:4 startColumn:1 endLine:4 endColumn:4], @"dh\n");
    XCTAssertEqualObjects([pt getValueInRange_startLine:5 startColumn:1 endLine:5 endColumn:3], @"i\n");
    XCTAssertEqualObjects([pt getValueInRange_startLine:6 startColumn:1 endLine:6 endColumn:3], @"jk");
    AssertTreeInvariants(pt, self);
}

- (void)testRandomValueInRange {
    NSString *str = @"";
    PTPieceTreeBase *pt = CreatePieceTree(@[@""], YES);
    str = SubstringInsert(str, 0,  @"ZXXY");   [pt insertAtOffset:0  value:@"ZXXY"   eolNormalized:YES];
    str = SubstringInsert(str, 1,  @"XZZY");   [pt insertAtOffset:1  value:@"XZZY"   eolNormalized:YES];
    str = SubstringInsert(str, 5,  @"\nX\n\n");[pt insertAtOffset:5  value:@"\nX\n\n" eolNormalized:YES];
    str = SubstringInsert(str, 3,  @"\nXX\n"); [pt insertAtOffset:3  value:@"\nXX\n"  eolNormalized:YES];
    str = SubstringInsert(str, 12, @"YYYX");   [pt insertAtOffset:12 value:@"YYYX"   eolNormalized:YES];
    TestLinesContent(str, pt, self);
    AssertTreeInvariants(pt, self);
}

- (void)testRandomValueInRangeException {
    NSString *str = @"";
    PTPieceTreeBase *pt = CreatePieceTree(@[@""], YES);
    str = SubstringInsert(str, 0, @"XZ\nZ"); [pt insertAtOffset:0 value:@"XZ\nZ" eolNormalized:YES];
    str = SubstringDelete(str, 0, 3);          [pt deleteAtOffset:0 count:3];
    str = SubstringDelete(str, 0, 1);          [pt deleteAtOffset:0 count:1];
    str = SubstringInsert(str, 0, @"ZYX\n"); [pt insertAtOffset:0 value:@"ZYX\n" eolNormalized:YES];
    str = SubstringDelete(str, 0, 4);          [pt deleteAtOffset:0 count:4];
    // Should not crash
    NSString *result = [pt getValueInRange_startLine:1 startColumn:1 endLine:1 endColumn:1];
    XCTAssertNotNil(result);
    AssertTreeInvariants(pt, self);
}

- (void)testRandomValueInRangeBug1 {
    NSString *str = @"";
    PTPieceTreeBase *pt = CreatePieceTree(@[@""], YES);
    str = SubstringInsert(str, 0,  @"huuyYzUfKOENwGgZLqn "); [pt insertAtOffset:0  value:@"huuyYzUfKOENwGgZLqn " eolNormalized:YES];
    str = SubstringDelete(str, 18, 2);                         [pt deleteAtOffset:18 count:2];
    str = SubstringDelete(str, 3,  1);                         [pt deleteAtOffset:3  count:1];
    str = SubstringDelete(str, 12, 4);                         [pt deleteAtOffset:12 count:4];
    str = SubstringInsert(str, 3,  @"hMbnVEdTSdhLlPevXKF "); [pt insertAtOffset:3  value:@"hMbnVEdTSdhLlPevXKF " eolNormalized:YES];
    str = SubstringDelete(str, 22, 8);                         [pt deleteAtOffset:22 count:8];
    str = SubstringInsert(str, 4,  @"S umSnYrqOmOAV\nEbZJ ");[pt insertAtOffset:4  value:@"S umSnYrqOmOAV\nEbZJ " eolNormalized:YES];
    TestLinesContent(str, pt, self);
    AssertTreeInvariants(pt, self);
}

- (void)testRandomValueInRangeBug2 {
    NSString *str = @"";
    PTPieceTreeBase *pt = CreatePieceTree(@[@""], YES);
    str = SubstringInsert(str, 0,  @"xfouRDZwdAHjVXJAMV\n "); [pt insertAtOffset:0  value:@"xfouRDZwdAHjVXJAMV\n " eolNormalized:YES];
    str = SubstringInsert(str, 16, @"dBGndxpFZBEAIKykYYx ");  [pt insertAtOffset:16 value:@"dBGndxpFZBEAIKykYYx "  eolNormalized:YES];
    str = SubstringDelete(str, 7,  6);   [pt deleteAtOffset:7  count:6];
    str = SubstringDelete(str, 9,  7);   [pt deleteAtOffset:9  count:7];
    str = SubstringDelete(str, 17, 6);   [pt deleteAtOffset:17 count:6];
    str = SubstringDelete(str, 0,  4);   [pt deleteAtOffset:0  count:4];
    str = SubstringInsert(str, 9,  @"qvEFXCNvVkWgvykahYt "); [pt insertAtOffset:9  value:@"qvEFXCNvVkWgvykahYt " eolNormalized:YES];
    str = SubstringDelete(str, 4,  6);   [pt deleteAtOffset:4  count:6];
    str = SubstringInsert(str, 11, @"OcSChUYT\nzPEBOpsGmR "); [pt insertAtOffset:11 value:@"OcSChUYT\nzPEBOpsGmR " eolNormalized:YES];
    str = SubstringInsert(str, 15, @"KJCozaXTvkE\nxnqAeTz "); [pt insertAtOffset:15 value:@"KJCozaXTvkE\nxnqAeTz " eolNormalized:YES];
    TestLinesContent(str, pt, self);
    AssertTreeInvariants(pt, self);
}

- (void)testGetLineContent {
    PTPieceTreeBase *pt = CreatePieceTree(@[@"1"], YES);
    XCTAssertEqualObjects([pt getLineRawContent:1], @"1");
    [pt insertAtOffset:1 value:@"2" eolNormalized:YES];
    XCTAssertEqualObjects([pt getLineRawContent:1], @"12");
    AssertTreeInvariants(pt, self);
}

- (void)testGetLineContentBasic {
    PTPieceTreeBase *pt = CreatePieceTree(@[@"1\n2\n3\n4"], YES);
    XCTAssertEqualObjects([pt getLineRawContent:1], @"1\n");
    XCTAssertEqualObjects([pt getLineRawContent:2], @"2\n");
    XCTAssertEqualObjects([pt getLineRawContent:3], @"3\n");
    XCTAssertEqualObjects([pt getLineRawContent:4], @"4");
    AssertTreeInvariants(pt, self);
}

- (void)testGetLineContentAfterInsertsDeletes {
    PTPieceTreeBase *pt = CreatePieceTree(@[@"a\nb\nc\nde"], YES);
    [pt insertAtOffset:8 value:@"fh\ni\njk" eolNormalized:YES];
    [pt deleteAtOffset:7 count:2];
    XCTAssertEqualObjects([pt getLineRawContent:1], @"a\n");
    XCTAssertEqualObjects([pt getLineRawContent:2], @"b\n");
    XCTAssertEqualObjects([pt getLineRawContent:3], @"c\n");
    XCTAssertEqualObjects([pt getLineRawContent:4], @"dh\n");
    XCTAssertEqualObjects([pt getLineRawContent:5], @"i\n");
    XCTAssertEqualObjects([pt getLineRawContent:6], @"jk");
    AssertTreeInvariants(pt, self);
}

- (void)testRandomLinesContent1 {
    NSString *str = @"";
    PTPieceTreeBase *pt = CreatePieceTree(@[@""], YES);
    str = SubstringInsert(str, 0, @"J eNnDzQpnlWyjmUu\ny "); [pt insertAtOffset:0 value:@"J eNnDzQpnlWyjmUu\ny " eolNormalized:YES];
    str = SubstringInsert(str, 0, @"QPEeRAQmRwlJqtZSWhQ "); [pt insertAtOffset:0 value:@"QPEeRAQmRwlJqtZSWhQ " eolNormalized:YES];
    str = SubstringDelete(str, 5, 1);                          [pt deleteAtOffset:5 count:1];
    TestLinesContent(str, pt, self);
    AssertTreeInvariants(pt, self);
}

- (void)testRandomLinesContent2 {
    NSString *str = @"";
    PTPieceTreeBase *pt = CreatePieceTree(@[@""], YES);
    str = SubstringInsert(str, 0,  @"DZoQ tglPCRHMltejRI ");   [pt insertAtOffset:0  value:@"DZoQ tglPCRHMltejRI "  eolNormalized:YES];
    str = SubstringInsert(str, 10, @"JRXiyYqJ qqdcmbfkKX ");   [pt insertAtOffset:10 value:@"JRXiyYqJ qqdcmbfkKX "  eolNormalized:YES];
    str = SubstringDelete(str, 16, 3);                           [pt deleteAtOffset:16 count:3];
    str = SubstringDelete(str, 25, 1);                           [pt deleteAtOffset:25 count:1];
    str = SubstringInsert(str, 18, @"vH\nNlvfqQJPm\nSFkhMc "); [pt insertAtOffset:18 value:@"vH\nNlvfqQJPm\nSFkhMc " eolNormalized:YES];
    TestLinesContent(str, pt, self);
    AssertTreeInvariants(pt, self);
}

// MARK: - CRLF tests

- (void)testCRLFDeleteCR1 {
    PTPieceTreeBase *pt = CreatePieceTree(@[@""], NO);
    [pt insertAtOffset:0 value:@"a\r\nb" eolNormalized:NO];
    [pt deleteAtOffset:0 count:2];
    XCTAssertEqual([pt getLineCount], (NSInteger)2);
    AssertTreeInvariants(pt, self);
}

- (void)testCRLFDeleteCR2 {
    PTPieceTreeBase *pt = CreatePieceTree(@[@""], NO);
    [pt insertAtOffset:0 value:@"a\r\nb" eolNormalized:NO];
    [pt deleteAtOffset:2 count:2];
    XCTAssertEqual([pt getLineCount], (NSInteger)2);
    AssertTreeInvariants(pt, self);
}

- (void)testCRLFRandomBug1 {
    NSString *str = @"";
    PTPieceTreeBase *pt = CreatePieceTree(@[@""], NO);
    str = SubstringInsert(str, 0, @"\n\n\r\r"); [pt insertAtOffset:0 value:@"\n\n\r\r" eolNormalized:NO];
    str = SubstringInsert(str, 1, @"\r\n\r\n"); [pt insertAtOffset:1 value:@"\r\n\r\n" eolNormalized:NO];
    str = SubstringDelete(str, 5, 3);            [pt deleteAtOffset:5 count:3];
    str = SubstringDelete(str, 2, 3);            [pt deleteAtOffset:2 count:3];
    XCTAssertEqual([pt getLineCount], (NSInteger)SplitLines(str).count);
    AssertTreeInvariants(pt, self);
}

- (void)testCRLFRandomBug2 {
    NSString *str = @"";
    PTPieceTreeBase *pt = CreatePieceTree(@[@""], NO);
    str = SubstringInsert(str, 0, @"\n\r\n\r"); [pt insertAtOffset:0 value:@"\n\r\n\r" eolNormalized:NO];
    str = SubstringInsert(str, 2, @"\n\r\r\r"); [pt insertAtOffset:2 value:@"\n\r\r\r" eolNormalized:NO];
    str = SubstringDelete(str, 4, 1);            [pt deleteAtOffset:4 count:1];
    XCTAssertEqual([pt getLineCount], (NSInteger)SplitLines(str).count);
    AssertTreeInvariants(pt, self);
}

- (void)testCRLFRandomBug3 {
    NSString *str = @"";
    PTPieceTreeBase *pt = CreatePieceTree(@[@""], NO);
    str = SubstringInsert(str, 0, @"\n\n\n\r"); [pt insertAtOffset:0 value:@"\n\n\n\r" eolNormalized:NO];
    str = SubstringDelete(str, 2, 2);            [pt deleteAtOffset:2 count:2];
    str = SubstringDelete(str, 0, 2);            [pt deleteAtOffset:0 count:2];
    str = SubstringInsert(str, 0, @"\r\r\r\r"); [pt insertAtOffset:0 value:@"\r\r\r\r" eolNormalized:NO];
    str = SubstringInsert(str, 2, @"\r\n\r\r"); [pt insertAtOffset:2 value:@"\r\n\r\r" eolNormalized:NO];
    str = SubstringInsert(str, 3, @"\r\r\r\n"); [pt insertAtOffset:3 value:@"\r\r\r\n" eolNormalized:NO];
    XCTAssertEqual([pt getLineCount], (NSInteger)SplitLines(str).count);
    AssertTreeInvariants(pt, self);
}

- (void)testCRLFRandomBug4 {
    NSString *str = @"";
    PTPieceTreeBase *pt = CreatePieceTree(@[@""], NO);
    str = SubstringInsert(str, 0, @"\n\n\n\n"); [pt insertAtOffset:0 value:@"\n\n\n\n" eolNormalized:NO];
    str = SubstringDelete(str, 3, 1);            [pt deleteAtOffset:3 count:1];
    str = SubstringInsert(str, 1, @"\r\r\r\r"); [pt insertAtOffset:1 value:@"\r\r\r\r" eolNormalized:NO];
    str = SubstringInsert(str, 6, @"\r\n\n\r"); [pt insertAtOffset:6 value:@"\r\n\n\r" eolNormalized:NO];
    str = SubstringDelete(str, 5, 3);            [pt deleteAtOffset:5 count:3];
    TestLinesContent(str, pt, self);
    AssertTreeInvariants(pt, self);
}

- (void)testCRLFRandomBug5 {
    NSString *str = @"";
    PTPieceTreeBase *pt = CreatePieceTree(@[@""], NO);
    str = SubstringInsert(str, 0,  @"\n\n\n\n"); [pt insertAtOffset:0  value:@"\n\n\n\n" eolNormalized:NO];
    str = SubstringDelete(str, 3,  1);            [pt deleteAtOffset:3  count:1];
    str = SubstringInsert(str, 0,  @"\n\r\r\n"); [pt insertAtOffset:0  value:@"\n\r\r\n" eolNormalized:NO];
    str = SubstringInsert(str, 4,  @"\n\r\r\n"); [pt insertAtOffset:4  value:@"\n\r\r\n" eolNormalized:NO];
    str = SubstringDelete(str, 4,  3);            [pt deleteAtOffset:4  count:3];
    str = SubstringInsert(str, 5,  @"\r\r\n\r"); [pt insertAtOffset:5  value:@"\r\r\n\r" eolNormalized:NO];
    str = SubstringInsert(str, 12, @"\n\n\n\r"); [pt insertAtOffset:12 value:@"\n\n\n\r" eolNormalized:NO];
    str = SubstringInsert(str, 5,  @"\r\r\r\n"); [pt insertAtOffset:5  value:@"\r\r\r\n" eolNormalized:NO];
    str = SubstringInsert(str, 20, @"\n\n\r\n"); [pt insertAtOffset:20 value:@"\n\n\r\n" eolNormalized:NO];
    TestLinesContent(str, pt, self);
    AssertTreeInvariants(pt, self);
}

- (void)testCRLFRandomBug6 {
    NSString *str = @"";
    PTPieceTreeBase *pt = CreatePieceTree(@[@""], NO);
    str = SubstringInsert(str, 0, @"\n\r\r\n"); [pt insertAtOffset:0 value:@"\n\r\r\n" eolNormalized:NO];
    str = SubstringInsert(str, 4, @"\r\n\n\r"); [pt insertAtOffset:4 value:@"\r\n\n\r" eolNormalized:NO];
    str = SubstringInsert(str, 3, @"\r\n\n\n"); [pt insertAtOffset:3 value:@"\r\n\n\n" eolNormalized:NO];
    str = SubstringDelete(str, 4, 8);            [pt deleteAtOffset:4 count:8];
    str = SubstringInsert(str, 4, @"\r\n\n\r"); [pt insertAtOffset:4 value:@"\r\n\n\r" eolNormalized:NO];
    str = SubstringInsert(str, 0, @"\r\n\n\r"); [pt insertAtOffset:0 value:@"\r\n\n\r" eolNormalized:NO];
    str = SubstringDelete(str, 4, 0);            [pt deleteAtOffset:4 count:0];
    str = SubstringDelete(str, 8, 4);            [pt deleteAtOffset:8 count:4];
    TestLinesContent(str, pt, self);
    AssertTreeInvariants(pt, self);
}

- (void)testCRLFRandomBug7 {
    NSString *str = @"";
    PTPieceTreeBase *pt = CreatePieceTree(@[@""], NO);
    str = SubstringInsert(str, 0,  @"\r\r\n\n"); [pt insertAtOffset:0  value:@"\r\r\n\n" eolNormalized:NO];
    str = SubstringInsert(str, 4,  @"\r\n\n\r"); [pt insertAtOffset:4  value:@"\r\n\n\r" eolNormalized:NO];
    str = SubstringInsert(str, 7,  @"\n\r\r\r"); [pt insertAtOffset:7  value:@"\n\r\r\r" eolNormalized:NO];
    str = SubstringInsert(str, 11, @"\n\n\r\n"); [pt insertAtOffset:11 value:@"\n\n\r\n" eolNormalized:NO];
    TestLinesContent(str, pt, self);
    AssertTreeInvariants(pt, self);
}

- (void)testCRLFRandomBug8 {
    NSString *str = @"";
    PTPieceTreeBase *pt = CreatePieceTree(@[@""], NO);
    str = SubstringInsert(str, 0, @"\r\n\n\r"); [pt insertAtOffset:0 value:@"\r\n\n\r" eolNormalized:NO];
    str = SubstringDelete(str, 1, 0);            [pt deleteAtOffset:1 count:0];
    str = SubstringInsert(str, 3, @"\n\n\n\r"); [pt insertAtOffset:3 value:@"\n\n\n\r" eolNormalized:NO];
    str = SubstringInsert(str, 7, @"\n\n\r\n"); [pt insertAtOffset:7 value:@"\n\n\r\n" eolNormalized:NO];
    TestLinesContent(str, pt, self);
    AssertTreeInvariants(pt, self);
}

- (void)testCRLFRandomBug9 {
    NSString *str = @"";
    PTPieceTreeBase *pt = CreatePieceTree(@[@""], NO);
    str = SubstringInsert(str, 0, @"\n\n\n\n"); [pt insertAtOffset:0 value:@"\n\n\n\n" eolNormalized:NO];
    str = SubstringInsert(str, 3, @"\n\r\n\r"); [pt insertAtOffset:3 value:@"\n\r\n\r" eolNormalized:NO];
    str = SubstringInsert(str, 2, @"\n\r\n\n"); [pt insertAtOffset:2 value:@"\n\r\n\n" eolNormalized:NO];
    str = SubstringInsert(str, 0, @"\n\n\r\r"); [pt insertAtOffset:0 value:@"\n\n\r\r" eolNormalized:NO];
    str = SubstringInsert(str, 3, @"\r\r\r\r"); [pt insertAtOffset:3 value:@"\r\r\r\r" eolNormalized:NO];
    str = SubstringInsert(str, 3, @"\n\n\r\r"); [pt insertAtOffset:3 value:@"\n\n\r\r" eolNormalized:NO];
    TestLinesContent(str, pt, self);
    AssertTreeInvariants(pt, self);
}

- (void)testCRLFRandomBug10 {
    NSString *str = @"";
    PTPieceTreeBase *pt = CreatePieceTree(@[@""], NO);
    str = SubstringInsert(str, 0, @"qneW"); [pt insertAtOffset:0 value:@"qneW" eolNormalized:NO];
    str = SubstringInsert(str, 0, @"YhIl"); [pt insertAtOffset:0 value:@"YhIl" eolNormalized:NO];
    str = SubstringInsert(str, 0, @"qdsm"); [pt insertAtOffset:0 value:@"qdsm" eolNormalized:NO];
    str = SubstringDelete(str, 7, 0);        [pt deleteAtOffset:7 count:0];
    str = SubstringInsert(str, 12, @"iiPv");[pt insertAtOffset:12 value:@"iiPv" eolNormalized:NO];
    str = SubstringInsert(str, 9, @"V\rSA");[pt insertAtOffset:9  value:@"V\rSA" eolNormalized:NO];
    TestLinesContent(str, pt, self);
    AssertTreeInvariants(pt, self);
}

// MARK: - centralized lineStarts with CRLF

- (void)testCentralizedCRLFDeleteCR1 {
    PTPieceTreeBase *pt = CreatePieceTree(@[@"a\r\nb"], NO);
    [pt deleteAtOffset:2 count:2];
    XCTAssertEqual([pt getLineCount], (NSInteger)2);
    AssertTreeInvariants(pt, self);
}

- (void)testCentralizedCRLFDeleteCR2 {
    PTPieceTreeBase *pt = CreatePieceTree(@[@"a\r\nb"], YES);
    [pt deleteAtOffset:0 count:2];
    XCTAssertEqual([pt getLineCount], (NSInteger)2);
    AssertTreeInvariants(pt, self);
}

- (void)testCentralizedCRLFRandomBug1 {
    NSString *str = @"\n\n\r\r";
    PTPieceTreeBase *pt = CreatePieceTree(@[@"\n\n\r\r"], NO);
    str = SubstringInsert(str, 1, @"\r\n\r\n"); [pt insertAtOffset:1 value:@"\r\n\r\n" eolNormalized:NO];
    str = SubstringDelete(str, 5, 3);            [pt deleteAtOffset:5 count:3];
    str = SubstringDelete(str, 2, 3);            [pt deleteAtOffset:2 count:3];
    XCTAssertEqual([pt getLineCount], (NSInteger)SplitLines(str).count);
    AssertTreeInvariants(pt, self);
}

- (void)testCentralizedCRLFRandomBug2 {
    NSString *str = @"\n\r\n\r";
    PTPieceTreeBase *pt = CreatePieceTree(@[@"\n\r\n\r"], NO);
    str = SubstringInsert(str, 2, @"\n\r\r\r"); [pt insertAtOffset:2 value:@"\n\r\r\r" eolNormalized:NO];
    str = SubstringDelete(str, 4, 1);            [pt deleteAtOffset:4 count:1];
    XCTAssertEqual([pt getLineCount], (NSInteger)SplitLines(str).count);
    AssertTreeInvariants(pt, self);
}

- (void)testCentralizedCRLFRandomBug3 {
    NSString *str = @"\n\n\n\r";
    PTPieceTreeBase *pt = CreatePieceTree(@[@"\n\n\n\r"], NO);
    str = SubstringDelete(str, 2, 2);            [pt deleteAtOffset:2 count:2];
    str = SubstringDelete(str, 0, 2);            [pt deleteAtOffset:0 count:2];
    str = SubstringInsert(str, 0, @"\r\r\r\r"); [pt insertAtOffset:0 value:@"\r\r\r\r" eolNormalized:NO];
    str = SubstringInsert(str, 2, @"\r\n\r\r"); [pt insertAtOffset:2 value:@"\r\n\r\r" eolNormalized:NO];
    str = SubstringInsert(str, 3, @"\r\r\r\n"); [pt insertAtOffset:3 value:@"\r\r\r\n" eolNormalized:NO];
    XCTAssertEqual([pt getLineCount], (NSInteger)SplitLines(str).count);
    AssertTreeInvariants(pt, self);
}

- (void)testCentralizedCRLFRandomBug4 {
    NSString *str = @"\n\n\n\n";
    PTPieceTreeBase *pt = CreatePieceTree(@[@"\n\n\n\n"], NO);
    str = SubstringDelete(str, 3, 1);            [pt deleteAtOffset:3 count:1];
    str = SubstringInsert(str, 1, @"\r\r\r\r"); [pt insertAtOffset:1 value:@"\r\r\r\r" eolNormalized:NO];
    str = SubstringInsert(str, 6, @"\r\n\n\r"); [pt insertAtOffset:6 value:@"\r\n\n\r" eolNormalized:NO];
    str = SubstringDelete(str, 5, 3);            [pt deleteAtOffset:5 count:3];
    TestLinesContent(str, pt, self);
    AssertTreeInvariants(pt, self);
}

- (void)testCentralizedCRLFRandomBug5 {
    NSString *str = @"\n\n\n\n";
    PTPieceTreeBase *pt = CreatePieceTree(@[@"\n\n\n\n"], NO);
    str = SubstringDelete(str, 3,  1);            [pt deleteAtOffset:3  count:1];
    str = SubstringInsert(str, 0,  @"\n\r\r\n"); [pt insertAtOffset:0  value:@"\n\r\r\n" eolNormalized:NO];
    str = SubstringInsert(str, 4,  @"\n\r\r\n"); [pt insertAtOffset:4  value:@"\n\r\r\n" eolNormalized:NO];
    str = SubstringDelete(str, 4,  3);            [pt deleteAtOffset:4  count:3];
    str = SubstringInsert(str, 5,  @"\r\r\n\r"); [pt insertAtOffset:5  value:@"\r\r\n\r" eolNormalized:NO];
    str = SubstringInsert(str, 12, @"\n\n\n\r"); [pt insertAtOffset:12 value:@"\n\n\n\r" eolNormalized:NO];
    str = SubstringInsert(str, 5,  @"\r\r\r\n"); [pt insertAtOffset:5  value:@"\r\r\r\n" eolNormalized:NO];
    str = SubstringInsert(str, 20, @"\n\n\r\n"); [pt insertAtOffset:20 value:@"\n\n\r\n" eolNormalized:NO];
    TestLinesContent(str, pt, self);
    AssertTreeInvariants(pt, self);
}

- (void)testCentralizedCRLFRandomBug6 {
    NSString *str = @"\n\r\r\n";
    PTPieceTreeBase *pt = CreatePieceTree(@[@"\n\r\r\n"], NO);
    str = SubstringInsert(str, 4, @"\r\n\n\r"); [pt insertAtOffset:4 value:@"\r\n\n\r" eolNormalized:NO];
    str = SubstringInsert(str, 3, @"\r\n\n\n"); [pt insertAtOffset:3 value:@"\r\n\n\n" eolNormalized:NO];
    str = SubstringDelete(str, 4, 8);            [pt deleteAtOffset:4 count:8];
    str = SubstringInsert(str, 4, @"\r\n\n\r"); [pt insertAtOffset:4 value:@"\r\n\n\r" eolNormalized:NO];
    str = SubstringInsert(str, 0, @"\r\n\n\r"); [pt insertAtOffset:0 value:@"\r\n\n\r" eolNormalized:NO];
    str = SubstringDelete(str, 4, 0);            [pt deleteAtOffset:4 count:0];
    str = SubstringDelete(str, 8, 4);            [pt deleteAtOffset:8 count:4];
    TestLinesContent(str, pt, self);
    AssertTreeInvariants(pt, self);
}

- (void)testCentralizedCRLFRandomBug7 {
    NSString *str = @"\r\n\n\r";
    PTPieceTreeBase *pt = CreatePieceTree(@[@"\r\n\n\r"], NO);
    str = SubstringDelete(str, 1, 0);            [pt deleteAtOffset:1 count:0];
    str = SubstringInsert(str, 3, @"\n\n\n\r"); [pt insertAtOffset:3 value:@"\n\n\n\r" eolNormalized:NO];
    str = SubstringInsert(str, 7, @"\n\n\r\n"); [pt insertAtOffset:7 value:@"\n\n\r\n" eolNormalized:NO];
    TestLinesContent(str, pt, self);
    AssertTreeInvariants(pt, self);
}

- (void)testCentralizedCRLFRandomBug8 {
    NSString *str = @"\r\r\n\n";
    PTPieceTreeBase *pt = CreatePieceTree(@[@"\r\r\n\n"], NO);
    str = SubstringInsert(str, 4,  @"\r\n\n\r"); [pt insertAtOffset:4  value:@"\r\n\n\r" eolNormalized:NO];
    str = SubstringInsert(str, 7,  @"\n\r\r\r"); [pt insertAtOffset:7  value:@"\n\r\r\r" eolNormalized:NO];
    str = SubstringInsert(str, 11, @"\n\n\r\n"); [pt insertAtOffset:11 value:@"\n\n\r\n" eolNormalized:NO];
    TestLinesContent(str, pt, self);
    AssertTreeInvariants(pt, self);
}

- (void)testCentralizedCRLFRandomBug9 {
    NSString *str = @"qneW";
    PTPieceTreeBase *pt = CreatePieceTree(@[@"qneW"], NO);
    str = SubstringInsert(str, 0,  @"YhIl"); [pt insertAtOffset:0  value:@"YhIl" eolNormalized:NO];
    str = SubstringInsert(str, 0,  @"qdsm"); [pt insertAtOffset:0  value:@"qdsm" eolNormalized:NO];
    str = SubstringDelete(str, 7,  0);        [pt deleteAtOffset:7  count:0];
    str = SubstringInsert(str, 12, @"iiPv"); [pt insertAtOffset:12 value:@"iiPv" eolNormalized:NO];
    str = SubstringInsert(str, 9,  @"V\rSA");[pt insertAtOffset:9  value:@"V\rSA" eolNormalized:NO];
    TestLinesContent(str, pt, self);
    AssertTreeInvariants(pt, self);
}

- (void)testCentralizedCRLFRandomBug10 {
    NSString *str = @"\n\n\n\n";
    PTPieceTreeBase *pt = CreatePieceTree(@[@"\n\n\n\n"], NO);
    str = SubstringInsert(str, 3, @"\n\r\n\r"); [pt insertAtOffset:3 value:@"\n\r\n\r" eolNormalized:NO];
    str = SubstringInsert(str, 2, @"\n\r\n\n"); [pt insertAtOffset:2 value:@"\n\r\n\n" eolNormalized:NO];
    str = SubstringInsert(str, 0, @"\n\n\r\r"); [pt insertAtOffset:0 value:@"\n\n\r\r" eolNormalized:NO];
    str = SubstringInsert(str, 3, @"\r\r\r\r"); [pt insertAtOffset:3 value:@"\r\r\r\r" eolNormalized:NO];
    str = SubstringInsert(str, 3, @"\n\n\r\r"); [pt insertAtOffset:3 value:@"\n\n\r\r" eolNormalized:NO];
    TestLinesContent(str, pt, self);
    AssertTreeInvariants(pt, self);
}

- (void)testCentralizedCRLFChunkBug1 {
    PTPieceTreeBase *pt = CreatePieceTree(@[@"\n\r\r\n\n\n\r\n\r"], NO);
    NSString *str = @"\n\r\r\n\n\n\r\n\r";
    str = SubstringDelete(str, 0, 2);            [pt deleteAtOffset:0 count:2];
    str = SubstringInsert(str, 1, @"\r\r\n\n"); [pt insertAtOffset:1 value:@"\r\r\n\n" eolNormalized:NO];
    str = SubstringInsert(str, 7, @"\r\r\r\r"); [pt insertAtOffset:7 value:@"\r\r\r\r" eolNormalized:NO];
    XCTAssertEqualObjects([pt getLinesRawContent], str);
    TestLineStarts(str, pt, self);
    AssertTreeInvariants(pt, self);
}

- (void)testCentralizedCRLFChunkBug2 {
    PTPieceTreeBase *pt = CreatePieceTree(@[@"\n\r\n\n\n\r\n\r\n\r\r\n\n\n\r\r\n\r\n"], NO);
    NSString *str = @"\n\r\n\n\n\r\n\r\n\r\r\n\n\n\r\r\n\r\n";
    str = SubstringInsert(str, 16, @"\r\n\r\r"); [pt insertAtOffset:16 value:@"\r\n\r\r" eolNormalized:NO];
    str = SubstringInsert(str, 13, @"\n\n\r\r"); [pt insertAtOffset:13 value:@"\n\n\r\r" eolNormalized:NO];
    str = SubstringInsert(str, 19, @"\n\n\r\n"); [pt insertAtOffset:19 value:@"\n\n\r\n" eolNormalized:NO];
    str = SubstringDelete(str, 5,  0);            [pt deleteAtOffset:5  count:0];
    str = SubstringDelete(str, 11, 2);            [pt deleteAtOffset:11 count:2];
    XCTAssertEqualObjects([pt getLinesRawContent], str);
    TestLineStarts(str, pt, self);
    AssertTreeInvariants(pt, self);
}

- (void)testCentralizedCRLFChunkBug3 {
    PTPieceTreeBase *pt = CreatePieceTree(@[@"\r\n\n\n\n\n\n\r\n"], NO);
    NSString *str = @"\r\n\n\n\n\n\n\r\n";
    str = SubstringInsert(str, 4,  @"\n\n\r\n\r\r\n\n\r"); [pt insertAtOffset:4  value:@"\n\n\r\n\r\r\n\n\r" eolNormalized:NO];
    str = SubstringDelete(str, 4,  4);                      [pt deleteAtOffset:4  count:4];
    str = SubstringInsert(str, 11, @"\r\n\r\n\n\r\r\n\n"); [pt insertAtOffset:11 value:@"\r\n\r\n\n\r\r\n\n" eolNormalized:NO];
    str = SubstringDelete(str, 1,  2);                      [pt deleteAtOffset:1  count:2];
    XCTAssertEqualObjects([pt getLinesRawContent], str);
    TestLineStarts(str, pt, self);
    AssertTreeInvariants(pt, self);
}

- (void)testCentralizedCRLFChunkBug4 {
    PTPieceTreeBase *pt = CreatePieceTree(@[@"\n\r\n\r"], NO);
    NSString *str = @"\n\r\n\r";
    str = SubstringInsert(str, 4, @"\n\n\r\n"); [pt insertAtOffset:4 value:@"\n\n\r\n" eolNormalized:NO];
    str = SubstringInsert(str, 3, @"\r\n\n\n"); [pt insertAtOffset:3 value:@"\r\n\n\n" eolNormalized:NO];
    XCTAssertEqualObjects([pt getLinesRawContent], str);
    TestLineStarts(str, pt, self);
    AssertTreeInvariants(pt, self);
}

// MARK: - random is unsupervised

- (void)testSplittingLargeChangeBuffer {
    NSString *str = @"";
    PTPieceTreeBase *pt = CreatePieceTree(@[@""], NO);
    str = SubstringInsert(str, 0,  @"WUZ\nXVZY\n");  [pt insertAtOffset:0  value:@"WUZ\nXVZY\n"  eolNormalized:NO];
    str = SubstringInsert(str, 8,  @"\r\r\nZXUWVW"); [pt insertAtOffset:8  value:@"\r\r\nZXUWVW"  eolNormalized:NO];
    str = SubstringDelete(str, 10, 7);                [pt deleteAtOffset:10 count:7];
    str = SubstringDelete(str, 10, 1);                [pt deleteAtOffset:10 count:1];
    str = SubstringInsert(str, 4,  @"VX\r\r\nWZVZ"); [pt insertAtOffset:4  value:@"VX\r\r\nWZVZ" eolNormalized:NO];
    str = SubstringDelete(str, 11, 3);                [pt deleteAtOffset:11 count:3];
    str = SubstringDelete(str, 12, 4);                [pt deleteAtOffset:12 count:4];
    str = SubstringDelete(str, 8,  0);                [pt deleteAtOffset:8  count:0];
    str = SubstringDelete(str, 10, 2);                [pt deleteAtOffset:10 count:2];
    str = SubstringInsert(str, 0,  @"VZXXZYZX\r");   [pt insertAtOffset:0  value:@"VZXXZYZX\r"   eolNormalized:NO];
    XCTAssertEqualObjects([pt getLinesRawContent], str);
    TestLineStarts(str, pt, self);
    TestLinesContent(str, pt, self);
    AssertTreeInvariants(pt, self);
}

- (void)testRandomInsertDelete {
    NSString *str = @"";
    PTPieceTreeBase *pt = CreatePieceTree(@[@""], NO);
    for (NSInteger i = 0; i < 1000; i++) {
        if ((double)arc4random() / UINT32_MAX < 0.6) {
            NSString *text = RandomString(100);
            NSInteger pos = (NSInteger)(arc4random_uniform((uint32_t)((NSInteger)str.length + 1)));
            [pt insertAtOffset:pos value:text eolNormalized:NO];
            str = SubstringInsert(str, pos, text);
        } else {
            if (str.length == 0) { continue; }
            NSInteger pos = (NSInteger)arc4random_uniform((uint32_t)str.length);
            NSInteger len = MIN((NSInteger)str.length - pos, (NSInteger)arc4random_uniform(10));
            [pt deleteAtOffset:pos count:len];
            str = SubstringDelete(str, pos, len);
        }
    }
    XCTAssertEqualObjects([pt getLinesRawContent], str);
    TestLineStarts(str, pt, self);
    TestLinesContent(str, pt, self);
    AssertTreeInvariants(pt, self);
}

- (void)testRandomChunks {
    NSMutableArray<NSString *> *chunks = [NSMutableArray array];
    for (NSInteger i = 0; i < 5; i++) { [chunks addObject:RandomString(1000)]; }
    PTPieceTreeBase *pt = CreatePieceTree(chunks, NO);
    NSString *str = [chunks componentsJoinedByString:@""];
    for (NSInteger i = 0; i < 1000; i++) {
        if ((double)arc4random() / UINT32_MAX < 0.6) {
            NSString *text = RandomString(100);
            NSInteger pos = (NSInteger)(arc4random_uniform((uint32_t)((NSInteger)str.length + 1)));
            [pt insertAtOffset:pos value:text eolNormalized:NO];
            str = SubstringInsert(str, pos, text);
        } else {
            if (str.length == 0) { continue; }
            NSInteger pos = (NSInteger)arc4random_uniform((uint32_t)str.length);
            NSInteger len = MIN((NSInteger)str.length - pos, (NSInteger)arc4random_uniform(10));
            [pt deleteAtOffset:pos count:len];
            str = SubstringDelete(str, pos, len);
        }
    }
    XCTAssertEqualObjects([pt getLinesRawContent], str);
    TestLineStarts(str, pt, self);
    TestLinesContent(str, pt, self);
    AssertTreeInvariants(pt, self);
}

- (void)testRandomChunks2 {
    NSMutableArray<NSString *> *chunks = [NSMutableArray arrayWithObject:RandomString(1000)];
    PTPieceTreeBase *pt = CreatePieceTree(chunks, NO);
    NSString *str = [chunks componentsJoinedByString:@""];
    for (NSInteger i = 0; i < 50; i++) {
        if ((double)arc4random() / UINT32_MAX < 0.6) {
            NSString *text = RandomString(30);
            NSInteger pos = (NSInteger)(arc4random_uniform((uint32_t)((NSInteger)str.length + 1)));
            [pt insertAtOffset:pos value:text eolNormalized:NO];
            str = SubstringInsert(str, pos, text);
        } else {
            if (str.length == 0) { continue; }
            NSInteger pos = (NSInteger)arc4random_uniform((uint32_t)str.length);
            NSInteger len = MIN((NSInteger)str.length - pos, (NSInteger)arc4random_uniform(10));
            [pt deleteAtOffset:pos count:len];
            str = SubstringDelete(str, pos, len);
        }
        TestLinesContent(str, pt, self);
    }
    XCTAssertEqualObjects([pt getLinesRawContent], str);
    TestLineStarts(str, pt, self);
    TestLinesContent(str, pt, self);
    AssertTreeInvariants(pt, self);
}

// MARK: - buffer API: equal

- (void)testEqual {
    PTPieceTreeBase *a = CreatePieceTree(@[@"abc"], YES);
    PTPieceTreeBase *b = CreatePieceTree(@[@"ab", @"c"], YES);
    PTPieceTreeBase *c = CreatePieceTree(@[@"abd"], YES);
    PTPieceTreeBase *d = CreatePieceTree(@[@"abcd"], YES);
    XCTAssertTrue([a isEqualTo:b]);
    XCTAssertFalse([a isEqualTo:c]);
    XCTAssertFalse([a isEqualTo:d]);
}

- (void)testEqualWithMoreChunks {
    PTPieceTreeBase *a = CreatePieceTree(@[@"ab", @"cd", @"e"], YES);
    PTPieceTreeBase *b = CreatePieceTree(@[@"ab", @"c", @"de"], YES);
    XCTAssertTrue([a isEqualTo:b]);
}

- (void)testEqual2EmptyBuffer {
    PTPieceTreeBase *a = CreatePieceTree(@[@""], YES);
    PTPieceTreeBase *b = CreatePieceTree(@[@""], YES);
    XCTAssertTrue([a isEqualTo:b]);
}

- (void)testEqual3EmptyBuffer {
    PTPieceTreeBase *a = CreatePieceTree(@[@"a"], YES);
    PTPieceTreeBase *b = CreatePieceTree(@[@""], YES);
    XCTAssertFalse([a isEqualTo:b]);
}

// MARK: - search offset cache / EOL normalization

- (void)testRenderWhitespaceException {
    NSString *str = @"class Name{\n\t\n\t\t\tget() {\n\n\t\t\t}\n\t\t}";
    PTPieceTreeBase *pt = CreatePieceTree(@[@"class Name{\n\t\n\t\t\tget() {\n\n\t\t\t}\n\t\t}"], YES);

    str = SubstringInsert(str, 12, @"s"); [pt insertAtOffset:12 value:@"s" eolNormalized:YES];
    str = SubstringInsert(str, 13, @"e"); [pt insertAtOffset:13 value:@"e" eolNormalized:YES];
    str = SubstringInsert(str, 14, @"t"); [pt insertAtOffset:14 value:@"t" eolNormalized:YES];
    str = SubstringInsert(str, 15, @"()"); [pt insertAtOffset:15 value:@"()" eolNormalized:YES];
    str = SubstringDelete(str, 16, 1);     [pt deleteAtOffset:16 count:1];
    str = SubstringInsert(str, 17, @"()"); [pt insertAtOffset:17 value:@"()" eolNormalized:YES];
    str = SubstringDelete(str, 18, 1);     [pt deleteAtOffset:18 count:1];
    str = SubstringInsert(str, 18, @"}");  [pt insertAtOffset:18 value:@"}"  eolNormalized:YES];
    str = SubstringInsert(str, 12, @"\n"); [pt insertAtOffset:12 value:@"\n" eolNormalized:YES];
    str = SubstringDelete(str, 12, 1);     [pt deleteAtOffset:12 count:1];
    str = SubstringDelete(str, 18, 1);     [pt deleteAtOffset:18 count:1];
    str = SubstringInsert(str, 18, @"}");  [pt insertAtOffset:18 value:@"}"  eolNormalized:YES];
    str = SubstringDelete(str, 17, 2);     [pt deleteAtOffset:17 count:2];
    str = SubstringDelete(str, 16, 1);     [pt deleteAtOffset:16 count:1];
    str = SubstringInsert(str, 16, @")");  [pt insertAtOffset:16 value:@")"  eolNormalized:YES];
    str = SubstringDelete(str, 15, 2);     [pt deleteAtOffset:15 count:2];
    XCTAssertEqualObjects([pt getLinesRawContent], str);
}

- (void)testEOLNormalized1 {
    NSString *str = @"abc";
    PTPieceTreeBase *pt = CreatePieceTree(@[@"abc"], YES);
    str = [str stringByAppendingString:@"def\nabc"];
    [pt insertAtOffset:3 value:@"def\nabc" eolNormalized:YES];
    TestLineStarts(str, pt, self);
    TestLinesContent(str, pt, self);
    AssertTreeInvariants(pt, self);
}

- (void)testEOLNormalized2 {
    NSString *str = @"abc\n";
    PTPieceTreeBase *pt = CreatePieceTree(@[@"abc\n"], YES);
    str = [str stringByAppendingString:@"def\nabc"];
    [pt insertAtOffset:4 value:@"def\nabc" eolNormalized:YES];
    TestLineStarts(str, pt, self);
    TestLinesContent(str, pt, self);
    AssertTreeInvariants(pt, self);
}

- (void)testEOLNormalized3 {
    NSString *str = @"abc\n";
    PTPieceTreeBase *pt = CreatePieceTree(@[@"abc\n"], YES);
    str = SubstringInsert(str, 2, @"def\nabc");
    [pt insertAtOffset:2 value:@"def\nabc" eolNormalized:YES];
    TestLineStarts(str, pt, self);
    TestLinesContent(str, pt, self);
    AssertTreeInvariants(pt, self);
}

- (void)testEOLNormalized4 {
    NSString *str = @"abc\n";
    PTPieceTreeBase *pt = CreatePieceTree(@[@"abc\n"], YES);
    str = SubstringInsert(str, 3, @"def\nabc");
    [pt insertAtOffset:3 value:@"def\nabc" eolNormalized:YES];
    TestLineStarts(str, pt, self);
    TestLinesContent(str, pt, self);
    AssertTreeInvariants(pt, self);
}

@end
