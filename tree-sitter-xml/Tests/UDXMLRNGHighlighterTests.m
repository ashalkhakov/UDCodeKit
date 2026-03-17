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
 *  A tiny RNG grammar that requires a <root> element containing one or
 *  more <item> elements each containing text:
 *
 *    <grammar xmlns="http://relaxng.org/ns/structure/1.0">
 *      <start>
 *        <element name="root">
 *          <oneOrMore>
 *            <element name="item"><text/></element>
 *          </oneOrMore>
 *        </element>
 *      </start>
 *    </grammar>
 *
 *  Valid:   <root><item>hello</item></root>
 *  Invalid: <wrong/>  (wrong root element name)
 *  Invalid child: <root><bad/></root>  (no <item> children — oneOrMore not satisfied)
 *--------------------------------------------------------------------------------------------*/

#import <XCTest/XCTest.h>
#import <tree_sitter/api.h>
#import "UDRNGValidator.h"
#import "UDTSRNGValidator.h"
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
//   <root> ::= (<item> text </item>)+
//
// Using oneOrMore (not zeroOrMore) so that libxml2 reports a mandatory-element-
// missing error when <root> has no valid <item> children.  The zeroOrMore
// variant hits a "extra content after zero matches" code path that relies on
// libxml2's best-error queue, which is silently discarded on some platforms.
static NSString * const kSchemaXML =
    @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
    @"<grammar xmlns=\"http://relaxng.org/ns/structure/1.0\">"
    @"  <start>"
    @"    <element name=\"root\">"
    @"      <oneOrMore>"
    @"        <element name=\"item\"><text/></element>"
    @"      </oneOrMore>"
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
    XCTAssert(doc.xmlDoc != NULL, @"Mirror doc should be built");

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
    XCTAssert(doc.xmlDoc != NULL, @"Mirror doc should be built");

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
    // <bad/> is not a valid child of <root> — the schema requires <item> (oneOrMore).
    UDXMLMirrorDoc *doc = [self _mirrorDocForXML:@"<root><bad/></root>"];
    XCTAssert(doc.xmlDoc != NULL);

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
    XCTAssert(doc.xmlDoc != NULL);

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

    XCTAssert(doc.xmlDoc != NULL);
    XCTAssert(doc.dirtyRoot != NULL,
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
    XCTAssert(doc.xmlDoc != NULL);
    xmlNodePtr dirtyRoot = doc.dirtyRoot;
    XCTAssert(dirtyRoot != NULL,
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
    XCTAssert(doc.xmlDoc != NULL);

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
    XCTAssert(doc.xmlDoc != NULL);
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
    XCTAssert(doc.xmlDoc != NULL);
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

// ---------------------------------------------------------------------------
// MARK: - Test class 3: UDTSRNGValidator (Clark's derivative-based validator)
// ---------------------------------------------------------------------------

/// Tests for the RELAX NG derivative validator that operates directly on
/// TSNode trees without going through libxml2's xmlDoc.
///
/// Schema used in most tests:
///   <grammar>
///     <start>
///       <element name="root">
///         <oneOrMore>
///           <element name="item"><text/></element>
///         </oneOrMore>
///       </element>
///     </start>
///   </grammar>
///
/// Valid:   <root><item>hello</item></root>
/// Invalid: <wrong/>                     — wrong root name
/// Invalid: <root/>                      — oneOrMore not satisfied
/// Invalid: <root><bad/></root>          — wrong child element name
@interface UDTSRNGValidatorTests : XCTestCase
@property (nonatomic, strong) NSURL             *schemaURL;
@property (nonatomic, strong) UDTSRNGValidator  *validator;
@end

@implementation UDTSRNGValidatorTests

static NSString * const kTSSchemaXML =
    @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
    @"<grammar xmlns=\"http://relaxng.org/ns/structure/1.0\">"
    @"  <start>"
    @"    <element name=\"root\">"
    @"      <oneOrMore>"
    @"        <element name=\"item\"><text/></element>"
    @"      </oneOrMore>"
    @"    </element>"
    @"  </start>"
    @"</grammar>";

// Schema with an optional attribute on <item>.
static NSString * const kTSSchemaWithAttr =
    @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
    @"<grammar xmlns=\"http://relaxng.org/ns/structure/1.0\">"
    @"  <start>"
    @"    <element name=\"root\">"
    @"      <oneOrMore>"
    @"        <element name=\"item\">"
    @"          <optional>"
    @"            <attribute name=\"id\"><text/></attribute>"
    @"          </optional>"
    @"          <text/>"
    @"        </element>"
    @"      </oneOrMore>"
    @"    </element>"
    @"  </start>"
    @"</grammar>";

// Schema with named define/ref (tests <ref> resolution and recursive grammars).
static NSString * const kTSSchemaWithRef =
    @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
    @"<grammar xmlns=\"http://relaxng.org/ns/structure/1.0\">"
    @"  <start><ref name=\"root\"/></start>"
    @"  <define name=\"root\">"
    @"    <element name=\"root\"><ref name=\"items\"/></element>"
    @"  </define>"
    @"  <define name=\"items\">"
    @"    <oneOrMore>"
    @"      <element name=\"item\"><text/></element>"
    @"    </oneOrMore>"
    @"  </define>"
    @"</grammar>";

- (void)setUp {
    [super setUp];
    NSURL *tmpDir = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    _schemaURL = [tmpDir URLByAppendingPathComponent:
                  [NSString stringWithFormat:@"test_ts_rng_%@.rng",
                   [[NSUUID UUID] UUIDString]]];
    NSError *writeError;
    BOOL ok = [kTSSchemaXML writeToURL:_schemaURL
                            atomically:YES
                              encoding:NSUTF8StringEncoding
                                 error:&writeError];
    XCTAssertTrue(ok, @"Failed to write schema: %@", writeError);

    _validator = [[UDTSRNGValidator alloc] init];
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

/// Validate @p xmlString and return diagnostics synchronously.
- (NSArray<UDDiagnosticItem *> *)_validateXML:(NSString *)xmlString
                                        cache:(NSMutableDictionary *)cache {
    TSTree *tree = ParseXML(xmlString);
    UDXMLGapBuffer *buf = [[UDXMLGapBuffer alloc] initWithString:xmlString];
    __block NSArray<UDDiagnosticItem *> *result = nil;
    [_validator validateTree:(const void *)tree
                   gapBuffer:buf
                       cache:cache
                  completion:^(NSArray<UDDiagnosticItem *> *diags) {
        result = diags;
    }];
    ts_tree_delete(tree);
    return result;
}

// ---------------------------------------------------------------------------
// MARK: - Basic valid / invalid documents
// ---------------------------------------------------------------------------

- (void)testTSRNG_validDocument_noErrors {
    NSMutableDictionary *cache = [NSMutableDictionary dictionary];
    NSArray *diags = [self _validateXML:@"<root><item>hello</item></root>"
                                  cache:cache];
    XCTAssertNotNil(diags);
    XCTAssertEqual(diags.count, (NSUInteger)0,
                   @"Valid document must produce no errors");
}

- (void)testTSRNG_multipleValidItems_noErrors {
    NSMutableDictionary *cache = [NSMutableDictionary dictionary];
    NSArray *diags = [self _validateXML:@"<root><item>a</item><item>b</item></root>"
                                  cache:cache];
    XCTAssertEqual(diags.count, (NSUInteger)0,
                   @"Multiple valid items must produce no errors");
}

- (void)testTSRNG_wrongRootElement_producesError {
    NSMutableDictionary *cache = [NSMutableDictionary dictionary];
    NSArray *diags = [self _validateXML:@"<wrong/>" cache:cache];
    XCTAssertGreaterThan(diags.count, (NSUInteger)0,
                         @"Wrong root element name must produce at least one error");
    for (UDDiagnosticItem *item in diags) {
        XCTAssertEqualObjects(item.source, UDDiagnosticSourceRNG);
        XCTAssertEqual(item.severity, UDDiagnosticSeverityError);
    }
}

- (void)testTSRNG_emptyRoot_producesError {
    // <root/> has no <item> children; oneOrMore constraint is violated.
    NSMutableDictionary *cache = [NSMutableDictionary dictionary];
    NSArray *diags = [self _validateXML:@"<root/>" cache:cache];
    XCTAssertGreaterThan(diags.count, (NSUInteger)0,
                         @"Empty <root/> violates oneOrMore — must produce errors");
}

- (void)testTSRNG_wrongChildElement_producesError {
    NSMutableDictionary *cache = [NSMutableDictionary dictionary];
    NSArray *diags = [self _validateXML:@"<root><bad/></root>" cache:cache];
    XCTAssertGreaterThan(diags.count, (NSUInteger)0,
                         @"Invalid child element must produce errors");
}

- (void)testTSRNG_validItemFollowedByInvalidChild_producesError {
    NSMutableDictionary *cache = [NSMutableDictionary dictionary];
    NSArray *diags = [self _validateXML:@"<root><item>ok</item><bad/></root>"
                                  cache:cache];
    XCTAssertGreaterThan(diags.count, (NSUInteger)0,
                         @"Invalid child after a valid item must produce errors");
}

- (void)testTSRNG_noSchemaLoaded_producesNoErrors {
    UDTSRNGValidator *v = [[UDTSRNGValidator alloc] init];
    TSTree *tree = ParseXML(@"<anything/>");
    UDXMLGapBuffer *buf = [[UDXMLGapBuffer alloc] initWithString:@"<anything/>"];
    NSMutableDictionary *cache = [NSMutableDictionary dictionary];
    __block NSArray<UDDiagnosticItem *> *diags = nil;
    [v validateTree:(const void *)tree gapBuffer:buf cache:cache
         completion:^(NSArray<UDDiagnosticItem *> *d) { diags = d; }];
    ts_tree_delete(tree);
    XCTAssertEqual(diags.count, (NSUInteger)0,
                   @"No schema loaded must produce empty diagnostics");
}

// ---------------------------------------------------------------------------
// MARK: - Diagnostic metadata
// ---------------------------------------------------------------------------

- (void)testTSRNG_diagnosticSource_isRNG {
    NSMutableDictionary *cache = [NSMutableDictionary dictionary];
    NSArray *diags = [self _validateXML:@"<wrong/>" cache:cache];
    for (UDDiagnosticItem *item in diags)
        XCTAssertEqualObjects(item.source, UDDiagnosticSourceRNG,
                              @"Source must be UDDiagnosticSourceRNG");
}

- (void)testTSRNG_diagnosticSeverity_isError {
    NSMutableDictionary *cache = [NSMutableDictionary dictionary];
    NSArray *diags = [self _validateXML:@"<wrong/>" cache:cache];
    for (UDDiagnosticItem *item in diags)
        XCTAssertEqual(item.severity, UDDiagnosticSeverityError);
}

- (void)testTSRNG_diagnosticLine_isPositive {
    NSMutableDictionary *cache = [NSMutableDictionary dictionary];
    NSArray *diags = [self _validateXML:@"<wrong/>" cache:cache];
    XCTAssertGreaterThan(diags.count, (NSUInteger)0);
    for (UDDiagnosticItem *item in diags)
        XCTAssertGreaterThan(item.line, (NSInteger)0,
                             @"Diagnostic line must be >= 1 (1-based)");
}

// ---------------------------------------------------------------------------
// MARK: - Incremental cache
// ---------------------------------------------------------------------------

- (void)testTSRNG_cachePopulatedAfterValidation {
    NSMutableDictionary *cache = [NSMutableDictionary dictionary];
    [self _validateXML:@"<root><item>hello</item></root>" cache:cache];
    XCTAssertGreaterThan(cache.count, (NSUInteger)0,
                         @"Cache must be non-empty after validating a valid document");
}

- (void)testTSRNG_secondCallWithSameXml_cacheDoesNotShrink {
    // Validate the same text twice: the cache must not shrink.
    NSMutableDictionary *cache = [NSMutableDictionary dictionary];
    NSString *xml = @"<root><item>hello</item></root>";
    [self _validateXML:xml cache:cache];
    NSUInteger sizeAfterFirst = cache.count;
    [self _validateXML:xml cache:cache];
    XCTAssertGreaterThanOrEqual(cache.count, sizeAfterFirst,
                                @"Cache must not shrink between identical calls");
}

- (void)testTSRNG_secondCallWithSameXml_stillNoErrors {
    NSMutableDictionary *cache = [NSMutableDictionary dictionary];
    NSString *xml = @"<root><item>hello</item></root>";
    NSArray *d1 = [self _validateXML:xml cache:cache];
    NSArray *d2 = [self _validateXML:xml cache:cache];
    XCTAssertEqual(d1.count, (NSUInteger)0);
    XCTAssertEqual(d2.count, (NSUInteger)0,
                   @"Second pass on unchanged document must also produce no errors");
}

// ---------------------------------------------------------------------------
// MARK: - Optional attribute schema
// ---------------------------------------------------------------------------

/// Load a one-off schema string into @p v; writes a temp file and returns it.
- (NSURL *)_loadSchemaString:(NSString *)schemaStr into:(UDTSRNGValidator *)v {
    NSURL *u = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
                URLByAppendingPathComponent:
                [NSString stringWithFormat:@"test_ts_%@.rng",
                 [[NSUUID UUID] UUIDString]]];
    [schemaStr writeToURL:u atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSError *e;
    XCTAssertTrue([v setSchemaURL:u error:&e], @"Schema load failed: %@", e);
    return u;
}

- (void)testTSRNG_optionalAttribute_present_noErrors {
    NSURL *u = [self _loadSchemaString:kTSSchemaWithAttr into:_validator];
    NSMutableDictionary *cache = [NSMutableDictionary dictionary];
    NSArray *diags = [self _validateXML:@"<root><item id=\"1\">hello</item></root>"
                                  cache:cache];
    [[NSFileManager defaultManager] removeItemAtURL:u error:nil];
    XCTAssertEqual(diags.count, (NSUInteger)0,
                   @"Optional attribute present must produce no errors");
}

- (void)testTSRNG_optionalAttribute_absent_noErrors {
    NSURL *u = [self _loadSchemaString:kTSSchemaWithAttr into:_validator];
    NSMutableDictionary *cache = [NSMutableDictionary dictionary];
    NSArray *diags = [self _validateXML:@"<root><item>hello</item></root>"
                                  cache:cache];
    [[NSFileManager defaultManager] removeItemAtURL:u error:nil];
    XCTAssertEqual(diags.count, (NSUInteger)0,
                   @"Absent optional attribute must also produce no errors");
}

// ---------------------------------------------------------------------------
// MARK: - Named define / ref patterns
// ---------------------------------------------------------------------------

- (void)testTSRNG_namedRef_validDocument_noErrors {
    NSURL *u = [self _loadSchemaString:kTSSchemaWithRef into:_validator];
    NSMutableDictionary *cache = [NSMutableDictionary dictionary];
    NSArray *diags = [self _validateXML:@"<root><item>hello</item></root>"
                                  cache:cache];
    [[NSFileManager defaultManager] removeItemAtURL:u error:nil];
    XCTAssertEqual(diags.count, (NSUInteger)0,
                   @"Document valid against ref-schema must produce no errors");
}

- (void)testTSRNG_namedRef_invalidDocument_producesErrors {
    NSURL *u = [self _loadSchemaString:kTSSchemaWithRef into:_validator];
    NSMutableDictionary *cache = [NSMutableDictionary dictionary];
    NSArray *diags = [self _validateXML:@"<root><wrong/></root>" cache:cache];
    [[NSFileManager defaultManager] removeItemAtURL:u error:nil];
    XCTAssertGreaterThan(diags.count, (NSUInteger)0,
                         @"Invalid child against ref-schema must produce errors");
}

@end

// ---------------------------------------------------------------------------
// MARK: - Test class 4: UDTSRNGValidator — <include> mechanism
// ---------------------------------------------------------------------------
///
/// Tests that the recursive <include> loading works correctly:
///
///  1. A grammar whose <start> element lives in an included file (not in the
///     root grammar) must load and validate correctly.
///
///  2. A grammar that uses the RNG override mechanism — defines inside the
///     <include> body replace the same-named defines in the included file —
///     must validate against the *overridden* schema, not the original.
///
///  3. Nested includes (grammar A includes grammar B which includes grammar C)
///     must be resolved fully.
///
/// Schema topology used in these tests
/// ------------------------------------
///
///  base.rng  (provides <start> and defines "root", "items"):
///    <grammar>
///      <start><ref name="root"/></start>
///      <define name="root">
///        <element name="root"><ref name="items"/></element>
///      </define>
///      <define name="items">
///        <oneOrMore><element name="item"><text/></element></oneOrMore>
///      </define>
///    </grammar>
///
///  override.rng  (includes base.rng but replaces "items" with "entry" elements):
///    <grammar>
///      <include href="base.rng">
///        <define name="items">
///          <oneOrMore><element name="entry"><text/></element></oneOrMore>
///        </define>
///      </include>
///    </grammar>
///
///  chain.rng  (includes override.rng, proving nested-include resolution):
///    <grammar>
///      <include href="override.rng"/>
///    </grammar>

@interface UDTSRNGValidatorIncludeTests : XCTestCase
@end

@implementation UDTSRNGValidatorIncludeTests {
    NSURL   *_tmpDir;
    NSURL   *_baseURL;
    NSURL   *_overrideURL;
    NSURL   *_chainURL;
}

// -----------------------------------------------------------------------
// MARK: - Set-up / tear-down
// -----------------------------------------------------------------------

- (void)setUp {
    [super setUp];
    NSString *uniq = [[NSUUID UUID] UUIDString];
    _tmpDir = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
               URLByAppendingPathComponent:
               [NSString stringWithFormat:@"UDTSRNGIncludeTests_%@", uniq]];
    [[NSFileManager defaultManager] createDirectoryAtURL:_tmpDir
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:nil];

    // base.rng — defines start + root + items (<item> elements)
    NSString *baseSchema =
        @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
        @"<grammar xmlns=\"http://relaxng.org/ns/structure/1.0\">"
        @"  <start><ref name=\"root\"/></start>"
        @"  <define name=\"root\">"
        @"    <element name=\"root\"><ref name=\"items\"/></element>"
        @"  </define>"
        @"  <define name=\"items\">"
        @"    <oneOrMore>"
        @"      <element name=\"item\"><text/></element>"
        @"    </oneOrMore>"
        @"  </define>"
        @"</grammar>";
    _baseURL = [_tmpDir URLByAppendingPathComponent:@"base.rng"];
    [baseSchema writeToURL:_baseURL atomically:YES
                  encoding:NSUTF8StringEncoding error:nil];

    // override.rng — includes base.rng, overrides "items" to require <entry>
    NSString *overrideSchema =
        @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
        @"<grammar xmlns=\"http://relaxng.org/ns/structure/1.0\">"
        @"  <include href=\"base.rng\">"
        @"    <define name=\"items\">"
        @"      <oneOrMore>"
        @"        <element name=\"entry\"><text/></element>"
        @"      </oneOrMore>"
        @"    </define>"
        @"  </include>"
        @"</grammar>";
    _overrideURL = [_tmpDir URLByAppendingPathComponent:@"override.rng"];
    [overrideSchema writeToURL:_overrideURL atomically:YES
                      encoding:NSUTF8StringEncoding error:nil];

    // chain.rng — includes override.rng (tests nested-include resolution)
    NSString *chainSchema =
        @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
        @"<grammar xmlns=\"http://relaxng.org/ns/structure/1.0\">"
        @"  <include href=\"override.rng\"/>"
        @"</grammar>";
    _chainURL = [_tmpDir URLByAppendingPathComponent:@"chain.rng"];
    [chainSchema writeToURL:_chainURL atomically:YES
                   encoding:NSUTF8StringEncoding error:nil];
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtURL:_tmpDir error:nil];
    [super tearDown];
}

// -----------------------------------------------------------------------
// MARK: - Helpers
// -----------------------------------------------------------------------

/// Returns a fresh UDTSRNGValidator loaded with the schema at @p url.
- (UDTSRNGValidator *)_validatorForURL:(NSURL *)url {
    UDTSRNGValidator *v = [[UDTSRNGValidator alloc] init];
    NSError *err;
    XCTAssertTrue([v setSchemaURL:url error:&err],
                  @"Schema load failed (%@): %@", url.lastPathComponent, err);
    return v;
}

/// Validate @p xmlString with @p v and return diagnostics synchronously.
- (NSArray<UDDiagnosticItem *> *)_validate:(NSString *)xmlString
                             withValidator:(UDTSRNGValidator *)v {
    TSTree *tree = ParseXML(xmlString);
    UDXMLGapBuffer *buf = [[UDXMLGapBuffer alloc] initWithString:xmlString];
    NSMutableDictionary *cache = [NSMutableDictionary dictionary];
    __block NSArray<UDDiagnosticItem *> *result = nil;
    [v validateTree:(const void *)tree gapBuffer:buf cache:cache
         completion:^(NSArray<UDDiagnosticItem *> *d) { result = d; }];
    ts_tree_delete(tree);
    return result;
}

// -----------------------------------------------------------------------
// MARK: - Test 1: start element lives only in included file
// -----------------------------------------------------------------------

- (void)testInclude_startFromIncludedFile_schemaLoads {
    // override.rng has no <start> of its own; it must import <start> from base.rng.
    UDTSRNGValidator *v = [self _validatorForURL:_overrideURL];
    XCTAssertNotNil(v, @"Validator must be non-nil after loading a schema with include");
}

- (void)testInclude_startFromIncludedFile_validDocument_noErrors {
    UDTSRNGValidator *v = [self _validatorForURL:_overrideURL];
    // override.rng expects <entry> elements (not <item>).
    NSArray *diags = [self _validate:@"<root><entry>hello</entry></root>"
                       withValidator:v];
    XCTAssertEqual(diags.count, (NSUInteger)0,
                   @"Document matching the overridden schema must be valid");
}

- (void)testInclude_startFromIncludedFile_originalDefine_isInvalid {
    UDTSRNGValidator *v = [self _validatorForURL:_overrideURL];
    // <item> is no longer valid — it was replaced by <entry> in the override.
    NSArray *diags = [self _validate:@"<root><item>hello</item></root>"
                       withValidator:v];
    XCTAssertGreaterThan(diags.count, (NSUInteger)0,
                         @"<item> replaced by <entry> in override — must produce errors");
}

// -----------------------------------------------------------------------
// MARK: - Test 2: base schema loaded directly still works
// -----------------------------------------------------------------------

- (void)testInclude_baseSchemaDirectly_validDocument_noErrors {
    UDTSRNGValidator *v = [self _validatorForURL:_baseURL];
    NSArray *diags = [self _validate:@"<root><item>hello</item></root>"
                       withValidator:v];
    XCTAssertEqual(diags.count, (NSUInteger)0,
                   @"Base schema loaded directly: <item> must still be valid");
}

- (void)testInclude_baseSchemaDirectly_wrongChild_producesError {
    UDTSRNGValidator *v = [self _validatorForURL:_baseURL];
    NSArray *diags = [self _validate:@"<root><entry>hello</entry></root>"
                       withValidator:v];
    XCTAssertGreaterThan(diags.count, (NSUInteger)0,
                         @"Base schema: <entry> is not valid — must produce errors");
}

// -----------------------------------------------------------------------
// MARK: - Test 3: nested include (chain.rng → override.rng → base.rng)
// -----------------------------------------------------------------------

- (void)testInclude_nestedInclude_schemaLoads {
    // chain.rng includes override.rng which includes base.rng.
    // All three levels must be processed correctly.
    UDTSRNGValidator *v = [self _validatorForURL:_chainURL];
    XCTAssertNotNil(v, @"Nested-include schema must load without error");
}

- (void)testInclude_nestedInclude_validDocument_noErrors {
    UDTSRNGValidator *v = [self _validatorForURL:_chainURL];
    // chain.rng inherits override.rng's schema: <entry> elements are required.
    NSArray *diags = [self _validate:@"<root><entry>hello</entry></root>"
                       withValidator:v];
    XCTAssertEqual(diags.count, (NSUInteger)0,
                   @"Nested-include chain: <entry> document must be valid");
}

- (void)testInclude_nestedInclude_invalidDocument_producesErrors {
    UDTSRNGValidator *v = [self _validatorForURL:_chainURL];
    NSArray *diags = [self _validate:@"<wrong/>" withValidator:v];
    XCTAssertGreaterThan(diags.count, (NSUInteger)0,
                         @"Nested-include chain: wrong root must produce errors");
}

@end
