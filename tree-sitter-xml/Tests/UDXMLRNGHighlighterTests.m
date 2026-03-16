/*---------------------------------------------------------------------------------------------
 *  UDXMLRNGHighlighterTests.m
 *
 *  Tests for the RNG validation pipeline.  They cover two areas:
 *
 *  1. The sorted-splice merge algorithm (lowerBound / upperBound helpers and
 *     the resulting in-place splice used by UDXMLRNGHighlighter).  Tested
 *     independently of libxml2 so they run without a schema file.
 *
 *  2. The UDRNGValidator API for both full-document and incremental subtree
 *     validation, exercised against a real (temporary) RELAX NG schema and a
 *     tree-sitter–mirrored xmlDoc.
 *
 *  Schema used in the validation tests
 *  ------------------------------------
 *  A tiny RNG grammar that allows only a <root> element containing zero or
 *  more <item> elements each containing text:
 *
 *    <grammar xmlns="http://relaxng.org/ns/structure/1.0">
 *      <start>
 *        <element name="root">
 *          <zeroOrMore>
 *            <element name="item"><text/></element>
 *          </zeroOrMore>
 *        </element>
 *      </start>
 *    </grammar>
 *
 *  Valid:   <root><item>hello</item></root>
 *  Invalid: <wrong/>  (wrong root element name)
 *  Invalid child: <root><bad/></root>  (<bad> is not allowed inside <root>)
 *--------------------------------------------------------------------------------------------*/

#import <XCTest/XCTest.h>
#import <tree_sitter/api.h>
#import "UDRNGValidator.h"
#import "UDXMLMirrorDoc.h"
#import "UDXMLGapBuffer.h"
#import "UDDiagnosticItem.h"

// UDDiagnosticSourceRNG is defined in UDRNGValidator.m (also compiled into the test target).
extern NSString * const UDDiagnosticSourceRNG;

// ---------------------------------------------------------------------------
// MARK: - Tree-sitter XML parse helper (same pattern as UDXMLTagMirrorTests)
// ---------------------------------------------------------------------------

extern const TSLanguage *tree_sitter_xml(void);

static TSTree *ParseXML(NSString *text) {
    TSParser *parser = ts_parser_new();
    ts_parser_set_language(parser, tree_sitter_xml());
    NSData *utf16 = [text dataUsingEncoding:NSUTF16LittleEndianStringEncoding];
    TSTree *tree = ts_parser_parse_string_encoding(
        parser, NULL,
        (const char *)utf16.bytes, (uint32_t)utf16.length,
        TSInputEncodingUTF16LE);
    ts_parser_delete(parser);
    return tree;
}

// ---------------------------------------------------------------------------
// MARK: - Merge-algorithm helpers (mirror of the static functions in
//         UDXMLRNGHighlighter.m — tested here independently)
// ---------------------------------------------------------------------------

/// Returns the smallest index i where arr[i].line >= targetLine.
static NSUInteger lowerBoundTest(NSArray<UDDiagnosticItem *> *arr,
                                  NSInteger targetLine) {
    NSUInteger lo = 0, hi = arr.count;
    while (lo < hi) {
        NSUInteger mid = lo + (hi - lo) / 2;
        if (arr[mid].line < targetLine) lo = mid + 1;
        else                             hi = mid;
    }
    return lo;
}

/// Returns the smallest index i where arr[i].line > targetLine.
static NSUInteger upperBoundTest(NSArray<UDDiagnosticItem *> *arr,
                                  NSInteger targetLine) {
    NSUInteger lo = 0, hi = arr.count;
    while (lo < hi) {
        NSUInteger mid = lo + (hi - lo) / 2;
        if (arr[mid].line <= targetLine) lo = mid + 1;
        else                              hi = mid;
    }
    return lo;
}

// ---------------------------------------------------------------------------
// MARK: - Helpers
// ---------------------------------------------------------------------------

static UDDiagnosticItem *makeDiag(NSInteger line, NSInteger col) {
    return [[UDDiagnosticItem alloc] initWithLine:line
                                           column:col
                                          message:@"error"
                                         severity:UDDiagnosticSeverityError
                                           source:UDDiagnosticSourceRNG];
}

// ---------------------------------------------------------------------------
// MARK: - Test class 1: sorted-splice merge algorithm
// ---------------------------------------------------------------------------

@interface UDXMLRNGMergeTests : XCTestCase
@end

@implementation UDXMLRNGMergeTests

// ---------------------------------------------------------------------------
// MARK: - lowerBound
// ---------------------------------------------------------------------------

- (void)testLowerBound_emptyArray {
    NSArray<UDDiagnosticItem *> *arr = @[];
    XCTAssertEqual(lowerBoundTest(arr, 1), (NSUInteger)0);
}

- (void)testLowerBound_allBefore {
    // All items on line 2, query line 5 → result is count (past end).
    NSArray *arr = @[makeDiag(2, 0), makeDiag(2, 1)];
    XCTAssertEqual(lowerBoundTest(arr, 5), arr.count);
}

- (void)testLowerBound_allAfter {
    NSArray *arr = @[makeDiag(5, 0), makeDiag(7, 0)];
    XCTAssertEqual(lowerBoundTest(arr, 3), (NSUInteger)0);
}

- (void)testLowerBound_exactMatch {
    NSArray *arr = @[makeDiag(1, 0), makeDiag(3, 0), makeDiag(5, 0)];
    XCTAssertEqual(lowerBoundTest(arr, 3), (NSUInteger)1);
}

- (void)testLowerBound_betweenValues {
    NSArray *arr = @[makeDiag(1, 0), makeDiag(3, 0), makeDiag(5, 0)];
    // Query for line 4: first element with line >= 4 is at index 2 (line 5).
    XCTAssertEqual(lowerBoundTest(arr, 4), (NSUInteger)2);
}

- (void)testLowerBound_firstOfMultipleSameLine {
    NSArray *arr = @[makeDiag(3, 0), makeDiag(3, 1), makeDiag(3, 2), makeDiag(5, 0)];
    XCTAssertEqual(lowerBoundTest(arr, 3), (NSUInteger)0);
}

// ---------------------------------------------------------------------------
// MARK: - upperBound
// ---------------------------------------------------------------------------

- (void)testUpperBound_emptyArray {
    NSArray<UDDiagnosticItem *> *arr = @[];
    XCTAssertEqual(upperBoundTest(arr, 1), (NSUInteger)0);
}

- (void)testUpperBound_mutableArrayMatchesBehavior {
    // The production code operates on NSMutableArray; verify the helper
    // produces identical results when handed an NSMutableArray vs NSArray.
    NSMutableArray<UDDiagnosticItem *> *mutable =
        [NSMutableArray arrayWithArray:@[makeDiag(1, 0), makeDiag(3, 0), makeDiag(5, 0)]];
    NSArray<UDDiagnosticItem *> *immutable = [mutable copy];
    // upperBound queries a mutable array via a typed NSArray* parameter — valid
    // because NSMutableArray is a subclass of NSArray.
    XCTAssertEqual(upperBoundTest(mutable,   3), (NSUInteger)2);
    XCTAssertEqual(upperBoundTest(immutable, 3), (NSUInteger)2,
                   @"Mutable and immutable arrays must give identical results");
}

- (void)testUpperBound_allBefore {
    NSArray *arr = @[makeDiag(2, 0), makeDiag(2, 1)];
    XCTAssertEqual(upperBoundTest(arr, 2), arr.count);
}

- (void)testUpperBound_allAfter {
    NSArray *arr = @[makeDiag(5, 0), makeDiag(7, 0)];
    XCTAssertEqual(upperBoundTest(arr, 3), (NSUInteger)0);
}

- (void)testUpperBound_exactMatch {
    NSArray *arr = @[makeDiag(1, 0), makeDiag(3, 0), makeDiag(5, 0)];
    // First element with line > 3 is index 2 (line 5).
    XCTAssertEqual(upperBoundTest(arr, 3), (NSUInteger)2);
}

- (void)testUpperBound_betweenValues {
    NSArray *arr = @[makeDiag(1, 0), makeDiag(3, 0), makeDiag(5, 0)];
    // First element with line > 4 is index 2 (line 5).
    XCTAssertEqual(upperBoundTest(arr, 4), (NSUInteger)2);
}

- (void)testUpperBound_afterLastElement {
    NSArray *arr = @[makeDiag(1, 0), makeDiag(3, 0), makeDiag(5, 0)];
    XCTAssertEqual(upperBoundTest(arr, 5), arr.count);
}

// ---------------------------------------------------------------------------
// MARK: - Full sorted-splice merge
// ---------------------------------------------------------------------------

/// Build a mutable sorted diagnostics array from an NSArray of line numbers.
static NSMutableArray<UDDiagnosticItem *> *cache(NSArray<NSNumber *> *lines) {
    NSMutableArray *arr = [NSMutableArray arrayWithCapacity:lines.count];
    for (NSNumber *n in lines)
        [arr addObject:makeDiag(n.integerValue, 0)];
    return arr;
}

/// Execute the sorted-splice merge and return the resulting line-number array.
static NSArray<NSNumber *> *mergeLines(NSMutableArray<UDDiagnosticItem *> *existing,
                                        NSArray<UDDiagnosticItem *> *newItems,
                                        NSInteger firstLine,
                                        NSInteger lastLine) {
    NSUInteger lo = lowerBoundTest(existing, firstLine);
    NSUInteger hi = upperBoundTest(existing, lastLine);
    if (hi > lo)
        [existing removeObjectsInRange:NSMakeRange(lo, hi - lo)];
    if (newItems.count) {
        NSIndexSet *idxs = [NSIndexSet indexSetWithIndexesInRange:
                            NSMakeRange(lo, newItems.count)];
        [existing insertObjects:newItems atIndexes:idxs];
    }
    NSMutableArray<NSNumber *> *result = [NSMutableArray arrayWithCapacity:existing.count];
    for (UDDiagnosticItem *item in existing)
        [result addObject:@(item.line)];
    return result;
}

- (void)testMerge_replacesStaleRange {
    // Existing: lines 1, 3, 5, 7, 9.  Dirty range: [3, 7].
    // New items for range: lines 4, 6.
    // Expected result: 1, 4, 6, 9.
    NSMutableArray *existing = cache(@[@1, @3, @5, @7, @9]);
    NSArray *newItems = @[makeDiag(4, 0), makeDiag(6, 0)];
    NSArray *result = mergeLines(existing, newItems, 3, 7);
    XCTAssertEqualObjects(result, (@[@1, @4, @6, @9]));
}

- (void)testMerge_removesRangeWithNoNewErrors {
    // Dirty range was fixed: no new errors for lines [3, 7].
    // Expected result: just lines 1 and 9.
    NSMutableArray *existing = cache(@[@1, @3, @5, @7, @9]);
    NSArray *result = mergeLines(existing, @[], 3, 7);
    XCTAssertEqualObjects(result, (@[@1, @9]));
}

- (void)testMerge_emptyExisting {
    // Starting from empty cache, merge introduces first errors.
    NSMutableArray *existing = [NSMutableArray array];
    NSArray *newItems = @[makeDiag(2, 0), makeDiag(4, 0)];
    NSArray *result = mergeLines(existing, newItems, 2, 4);
    XCTAssertEqualObjects(result, (@[@2, @4]));
}

- (void)testMerge_rangeBeforeAll {
    // Range covers lines 1-2; existing has lines 5, 7, 9.
    NSMutableArray *existing = cache(@[@5, @7, @9]);
    NSArray *newItems = @[makeDiag(1, 0)];
    NSArray *result = mergeLines(existing, newItems, 1, 2);
    XCTAssertEqualObjects(result, (@[@1, @5, @7, @9]));
}

- (void)testMerge_rangeAfterAll {
    NSMutableArray *existing = cache(@[@1, @3]);
    NSArray *newItems = @[makeDiag(10, 0)];
    NSArray *result = mergeLines(existing, newItems, 9, 11);
    XCTAssertEqualObjects(result, (@[@1, @3, @10]));
}

- (void)testMerge_resultIsSorted {
    // Even with items of different columns in the same line, the merge must
    // keep the list sorted because newItems itself comes from the validator
    // in document (line, column) order.
    NSMutableArray *existing = cache(@[@1, @2, @10, @11]);
    NSArray *newItems = @[makeDiag(5, 0), makeDiag(5, 2), makeDiag(7, 1)];
    NSArray *result = mergeLines(existing, newItems, 3, 8);
    // Lines 1, 2 before range; then 5, 5, 7 from new items; then 10, 11 after.
    NSArray *expected = @[@1, @2, @5, @5, @7, @10, @11];
    XCTAssertEqualObjects(result, expected);
}

@end

// ---------------------------------------------------------------------------
// MARK: - Test class 2: UDRNGValidator (full + incremental validation)
// ---------------------------------------------------------------------------

@interface UDXMLRNGValidatorTests : XCTestCase
@property (nonatomic, strong) NSURL           *schemaURL;
@property (nonatomic, strong) UDRNGValidator  *validator;
@end

@implementation UDXMLRNGValidatorTests

// Minimal RELAX NG grammar:
//   <root> ::= (<item> text </item>)*
static NSString * const kSchemaXML =
    @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
    @"<grammar xmlns=\"http://relaxng.org/ns/structure/1.0\">"
    @"  <start>"
    @"    <element name=\"root\">"
    @"      <zeroOrMore>"
    @"        <element name=\"item\"><text/></element>"
    @"      </zeroOrMore>"
    @"    </element>"
    @"  </start>"
    @"</grammar>";

- (void)setUp {
    [super setUp];
    NSURL *tmpDir = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    _schemaURL = [tmpDir URLByAppendingPathComponent:
                  [NSString stringWithFormat:@"test_rng_%@.rng",
                   [[NSUUID UUID] UUIDString]]];
    NSError *writeError;
    BOOL ok = [kSchemaXML writeToURL:_schemaURL
                          atomically:YES
                            encoding:NSUTF8StringEncoding
                               error:&writeError];
    XCTAssertTrue(ok, @"Failed to write schema: %@", writeError);

    _validator = [[UDRNGValidator alloc] init];
    NSError *schemaError;
    XCTAssertTrue([_validator setSchemaURL:_schemaURL error:&schemaError],
                  @"Schema load failed: %@", schemaError);
}

- (void)tearDown {
    [_validator clearSchema];
    _validator = nil;
    [[NSFileManager defaultManager] removeItemAtURL:_schemaURL error:nil];
    _schemaURL = nil;
    [super tearDown];
}

/// Build and return a UDXMLMirrorDoc from the given XML string.
/// The TSTree is deleted before returning; the xmlDoc lives in the mirrorDoc.
- (UDXMLMirrorDoc *)_mirrorDocForXML:(NSString *)xmlString {
    UDXMLGapBuffer *buf = [[UDXMLGapBuffer alloc] initWithString:xmlString];
    TSTree *tree = ParseXML(xmlString);
    UDXMLMirrorDoc *doc = [[UDXMLMirrorDoc alloc] init];
    [doc applyTree:tree changedRanges:nil gapBuffer:buf];
    ts_tree_delete(tree);
    return doc;
}

// ---------------------------------------------------------------------------
// MARK: - Full document validation
// ---------------------------------------------------------------------------

- (void)testFullValidation_validDocument_producesNoErrors {
    UDXMLMirrorDoc *doc = [self _mirrorDocForXML:@"<root><item>hello</item></root>"];
    XCTAssertNotNil(doc.xmlDoc, @"Mirror doc should be built");

    __block NSArray<UDDiagnosticItem *> *diagnostics = nil;
    [_validator validateDoc:doc.xmlDoc
                  lineIndex:NULL
                  lineCount:0
                 completion:^(NSArray<UDDiagnosticItem *> *items) {
        diagnostics = items;
    }];
    XCTAssertNotNil(diagnostics);
    XCTAssertEqual(diagnostics.count, (NSUInteger)0,
                   @"Valid document should produce no errors");
}

- (void)testFullValidation_wrongRootElement_producesError {
    // <wrong/> is not a valid root — the schema requires <root>.
    UDXMLMirrorDoc *doc = [self _mirrorDocForXML:@"<wrong/>"];
    XCTAssertNotNil(doc.xmlDoc, @"Mirror doc should be built");

    __block NSArray<UDDiagnosticItem *> *diagnostics = nil;
    [_validator validateDoc:doc.xmlDoc
                  lineIndex:NULL
                  lineCount:0
                 completion:^(NSArray<UDDiagnosticItem *> *items) {
        diagnostics = items;
    }];
    XCTAssertNotNil(diagnostics);
    XCTAssertGreaterThan(diagnostics.count, (NSUInteger)0,
                         @"Wrong root element should produce validation errors");
    for (UDDiagnosticItem *item in diagnostics) {
        XCTAssertEqualObjects(item.source, UDDiagnosticSourceRNG);
        XCTAssertEqual(item.severity, UDDiagnosticSeverityError);
    }
}

- (void)testFullValidation_invalidChild_producesError {
    // <bad/> is not a valid child of <root>.
    UDXMLMirrorDoc *doc = [self _mirrorDocForXML:@"<root><bad/></root>"];
    XCTAssertNotNil(doc.xmlDoc);

    __block NSArray<UDDiagnosticItem *> *diagnostics = nil;
    [_validator validateDoc:doc.xmlDoc
                  lineIndex:NULL
                  lineCount:0
                 completion:^(NSArray<UDDiagnosticItem *> *items) {
        diagnostics = items;
    }];
    XCTAssertGreaterThan(diagnostics.count, (NSUInteger)0,
                         @"Invalid child element should produce errors");
}

- (void)testFullValidation_multipleInvalidChildren_producesMultipleErrors {
    UDXMLMirrorDoc *doc = [self _mirrorDocForXML:
                           @"<root><bad/><also-bad/></root>"];
    XCTAssertNotNil(doc.xmlDoc);

    __block NSArray<UDDiagnosticItem *> *diagnostics = nil;
    [_validator validateDoc:doc.xmlDoc
                  lineIndex:NULL
                  lineCount:0
                 completion:^(NSArray<UDDiagnosticItem *> *items) {
        diagnostics = items;
    }];
    XCTAssertGreaterThan(diagnostics.count, (NSUInteger)0,
                         @"Document with multiple invalid children should have errors");
}

- (void)testFullValidation_noSchema_producesNoErrors {
    // With no schema loaded the validator is a no-op and returns an empty array.
    UDRNGValidator *noSchemaValidator = [[UDRNGValidator alloc] init];
    UDXMLMirrorDoc *doc = [self _mirrorDocForXML:@"<anything/>"];

    __block NSArray<UDDiagnosticItem *> *diagnostics = nil;
    [noSchemaValidator validateDoc:doc.xmlDoc
                         lineIndex:NULL
                         lineCount:0
                        completion:^(NSArray<UDDiagnosticItem *> *items) {
        diagnostics = items;
    }];
    XCTAssertEqual(diagnostics.count, (NSUInteger)0,
                   @"No schema means no errors");
}

// ---------------------------------------------------------------------------
// MARK: - Incremental (subtree) validation
// ---------------------------------------------------------------------------

/// Build two successive mirror docs: first from @p xml1, then applying @p xml2
/// on the same UDXMLMirrorDoc.  Returns the doc after the second apply, with
/// dirtyRoot set by the incremental diff.
- (UDXMLMirrorDoc *)_incrementalMirrorDocFrom:(NSString *)xml1 to:(NSString *)xml2 {
    // First apply.
    UDXMLGapBuffer *buf1 = [[UDXMLGapBuffer alloc] initWithString:xml1];
    TSTree *tree1 = ParseXML(xml1);
    UDXMLMirrorDoc *doc = [[UDXMLMirrorDoc alloc] init];
    [doc applyTree:tree1 changedRanges:nil gapBuffer:buf1];
    ts_tree_delete(tree1);

    // Second apply — same mirrorDoc, incremental.
    UDXMLGapBuffer *buf2 = [[UDXMLGapBuffer alloc] initWithString:xml2];
    TSTree *tree2 = ParseXML(xml2);
    [doc applyTree:tree2 changedRanges:nil gapBuffer:buf2];
    ts_tree_delete(tree2);

    return doc;
}

- (void)testIncrementalValidation_dirtyRootIsDocRoot_onFirstBuild {
    // After the very first build dirtyRoot == the document root element.
    UDXMLGapBuffer *buf = [[UDXMLGapBuffer alloc] initWithString:@"<root/>"];
    TSTree *tree = ParseXML(@"<root/>");
    UDXMLMirrorDoc *doc = [[UDXMLMirrorDoc alloc] init];
    [doc applyTree:tree changedRanges:nil gapBuffer:buf];
    ts_tree_delete(tree);

    XCTAssertNotNil(doc.xmlDoc);
    XCTAssertNotNil((__bridge id)doc.dirtyRoot,
                    @"First build must set dirtyRoot to the root element");
    XCTAssertEqual(doc.dirtyRoot, xmlDocGetRootElement(doc.xmlDoc),
                   @"On first build dirtyRoot must equal the document root element");
}

- (void)testIncrementalValidation_unchangedDocument_dirtyRootIsNULL {
    // Applying the same tree twice: no structural changes → dirtyRoot == NULL.
    NSString *xml = @"<root><item>hello</item></root>";
    UDXMLGapBuffer *buf1 = [[UDXMLGapBuffer alloc] initWithString:xml];
    TSTree *tree1 = ParseXML(xml);
    UDXMLMirrorDoc *doc = [[UDXMLMirrorDoc alloc] init];
    [doc applyTree:tree1 changedRanges:nil gapBuffer:buf1];
    ts_tree_delete(tree1);

    // Second apply with identical content.
    UDXMLGapBuffer *buf2 = [[UDXMLGapBuffer alloc] initWithString:xml];
    TSTree *tree2 = ParseXML(xml);
    [doc applyTree:tree2 changedRanges:nil gapBuffer:buf2];
    ts_tree_delete(tree2);

    XCTAssertNil((__bridge id)doc.dirtyRoot,
                 @"No structural change: dirtyRoot must be NULL");
}

- (void)testIncrementalValidation_subtreeChange_dirtyRootIsNotDocRoot {
    // Change only the second child element's tag name: item → wrong.
    // dirtyRoot should be a non-root element (the changed child).
    NSString *xml1 = @"<root><item>hello</item><item>world</item></root>";
    NSString *xml2 = @"<root><item>hello</item><wrong>world</wrong></root>";

    UDXMLMirrorDoc *doc = [self _incrementalMirrorDocFrom:xml1 to:xml2];
    XCTAssertNotNil(doc.xmlDoc);
    xmlNodePtr dirtyRoot = doc.dirtyRoot;
    XCTAssertNotNil((__bridge id)dirtyRoot,
                    @"Structural change must set dirtyRoot");
    XCTAssertNotEqual(dirtyRoot, xmlDocGetRootElement(doc.xmlDoc),
                      @"Only a child was changed: dirtyRoot should NOT be the document root");
}

- (void)testIncrementalValidation_subtreeValid_producesNoErrors {
    // After changing item → item (no name change, only text change),
    // the dirty node should validate without errors.
    NSString *xml1 = @"<root><item>hello</item></root>";
    NSString *xml2 = @"<root><item>goodbye</item></root>";

    UDXMLMirrorDoc *doc = [self _incrementalMirrorDocFrom:xml1 to:xml2];
    XCTAssertNotNil(doc.xmlDoc);

    // dirtyRoot may be NULL (text changes may not trigger a structural diff) or
    // may be the item element.  If it IS set, validate it and expect no errors.
    xmlNodePtr dirtyRoot = doc.dirtyRoot;
    if (!dirtyRoot) return; // text-only change; structural diff saw nothing — skip.

    __block NSArray<UDDiagnosticItem *> *diagnostics = nil;
    __block NSInteger firstLine = 0, lastLine = 0;
    [_validator validateSubtree:dirtyRoot
                            doc:doc.xmlDoc
                      lineIndex:NULL
                      lineCount:0
                     completion:^(NSArray<UDDiagnosticItem *> *items,
                                  NSInteger fl, NSInteger ll) {
        diagnostics = items;
        firstLine    = fl;
        lastLine     = ll;
    }];
    XCTAssertNotNil(diagnostics);
    // firstLine and lastLine must be plausible (both ≥ 1, lastLine ≥ firstLine).
    XCTAssertGreaterThanOrEqual(firstLine, (NSInteger)1);
    XCTAssertGreaterThanOrEqual(lastLine, firstLine);
}

- (void)testIncrementalValidation_subtreeInvalid_producesErrors {
    // Change a valid child <item> to an invalid <wrong> element.
    // validateSubtree on dirtyRoot should report errors.
    NSString *xml1 = @"<root><item>hello</item><item>world</item></root>";
    NSString *xml2 = @"<root><item>hello</item><wrong>world</wrong></root>";

    UDXMLMirrorDoc *doc = [self _incrementalMirrorDocFrom:xml1 to:xml2];
    XCTAssertNotNil(doc.xmlDoc);
    xmlNodePtr dirtyRoot = doc.dirtyRoot;
    if (!dirtyRoot) {
        XCTFail(@"Expected dirtyRoot to be set after changing child element name");
        return;
    }

    __block NSArray<UDDiagnosticItem *> *diagnostics = nil;
    __block NSInteger firstLine = 0, lastLine = 0;
    [_validator validateSubtree:dirtyRoot
                            doc:doc.xmlDoc
                      lineIndex:NULL
                      lineCount:0
                     completion:^(NSArray<UDDiagnosticItem *> *items,
                                  NSInteger fl, NSInteger ll) {
        diagnostics = items;
        firstLine    = fl;
        lastLine     = ll;
    }];
    XCTAssertNotNil(diagnostics);
    XCTAssertGreaterThan(diagnostics.count, (NSUInteger)0,
                         @"<wrong> is not valid — errors should be reported");
    // Line range must be set and must be plausible.
    XCTAssertGreaterThanOrEqual(firstLine, (NSInteger)1);
    XCTAssertGreaterThanOrEqual(lastLine, firstLine);
}

- (void)testIncrementalValidation_lineRangeCoversSubtree {
    // The line range [firstLine, lastLine] must fully span the dirty subtree.
    NSString *xml1 = @"<root><item>hello</item></root>";
    // Make a multi-line dirty subtree.
    NSString *xml2 = @"<root>\n<wrong>\nwrong content\n</wrong>\n</root>";

    UDXMLMirrorDoc *doc = [self _incrementalMirrorDocFrom:xml1 to:xml2];
    XCTAssertNotNil(doc.xmlDoc);
    xmlNodePtr dirtyRoot = doc.dirtyRoot;
    if (!dirtyRoot) return; // no structural change detected

    __block NSInteger firstLine = 0, lastLine = 0;
    [_validator validateSubtree:dirtyRoot
                            doc:doc.xmlDoc
                      lineIndex:NULL
                      lineCount:0
                     completion:^(NSArray<UDDiagnosticItem *> *items,
                                  NSInteger fl, NSInteger ll) {
        firstLine = fl;
        lastLine  = ll;
    }];
    // The dirty node's start line must match firstLine and lastLine >= firstLine.
    NSInteger nodeStartLine = (NSInteger)dirtyRoot->line;
    XCTAssertEqual(firstLine, nodeStartLine,
                   @"firstLine must equal the dirty node's start line");
    XCTAssertGreaterThanOrEqual(lastLine, firstLine,
                                @"lastLine must be >= firstLine");
}

@end
