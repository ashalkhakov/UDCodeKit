/*---------------------------------------------------------------------------------------------
 *  UDXMLSchematronTests.m
 *
 *  Tests for UDSchematronValidator.  Exercises full-document Schematron validation
 *  against a minimal Schematron schema written to a temporary file.
 *
 *  Schema used in these tests
 *  --------------------------
 *  Requires that every <item> element has a non-empty @id attribute:
 *
 *    <sch:schema xmlns:sch="http://purl.oclc.org/dsdl/schematron">
 *      <sch:pattern>
 *        <sch:rule context="item">
 *          <sch:assert test="@id">
 *            Every item must have an id attribute.
 *          </sch:assert>
 *        </sch:rule>
 *      </sch:pattern>
 *    </sch:schema>
 *
 *  Valid:   <root><item id="1">hello</item></root>
 *  Invalid: <root><item>hello</item></root>   (missing @id)
 *--------------------------------------------------------------------------------------------*/

#import <XCTest/XCTest.h>
#import <tree_sitter/api.h>
#import "UDSchematronValidator.h"
#import "UDXMLMirrorDoc.h"
#import "UDXMLGapBuffer.h"
#import "UDDiagnosticItem.h"

// UDDiagnosticSourceSchematron is defined in UDSchematronValidator.m
// (also compiled into the test target).
extern NSString * const UDDiagnosticSourceSchematron;

// ---------------------------------------------------------------------------
// MARK: - Tree-sitter XML parse helper
// ---------------------------------------------------------------------------

extern const TSLanguage *tree_sitter_xml(void);

static TSTree *ParseXMLSch(NSString *text) {
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
// MARK: - UDXMLSchematronTests
// ---------------------------------------------------------------------------

@interface UDXMLSchematronTests : XCTestCase
@property (nonatomic, strong) NSURL                  *schemaURL;
@property (nonatomic, strong) UDSchematronValidator  *validator;
@end

@implementation UDXMLSchematronTests

/// Minimal Schematron schema: every <item> must carry an @id attribute.
static NSString * const kSchematronXML =
    @"<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
    @"<sch:schema xmlns:sch=\"http://purl.oclc.org/dsdl/schematron\">"
    @"  <sch:pattern>"
    @"    <sch:rule context=\"item\">"
    @"      <sch:assert test=\"@id\">Every item must have an id attribute.</sch:assert>"
    @"    </sch:rule>"
    @"  </sch:pattern>"
    @"</sch:schema>";

- (void)setUp {
    [super setUp];
    NSURL *tmpDir = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    _schemaURL = [tmpDir URLByAppendingPathComponent:
                  [NSString stringWithFormat:@"test_sch_%@.sch",
                   [[NSUUID UUID] UUIDString]]];
    NSError *writeError;
    BOOL ok = [kSchematronXML writeToURL:_schemaURL
                              atomically:YES
                                encoding:NSUTF8StringEncoding
                                   error:&writeError];
    XCTAssertTrue(ok, @"Failed to write Schematron schema: %@", writeError);

    _validator = [[UDSchematronValidator alloc] init];
    NSError *schemaError;
    XCTAssertTrue([_validator setSchemaURL:_schemaURL error:&schemaError],
                  @"Schematron schema load failed: %@", schemaError);
}

- (void)tearDown {
    [_validator clearSchema];
    _validator = nil;
    [[NSFileManager defaultManager] removeItemAtURL:_schemaURL error:nil];
    _schemaURL = nil;
    [super tearDown];
}

/// Build a UDXMLMirrorDoc from the given XML string (same pattern as RNG tests).
- (UDXMLMirrorDoc *)_mirrorDocForXML:(NSString *)xmlString {
    UDXMLGapBuffer *buf = [[UDXMLGapBuffer alloc] initWithString:xmlString];
    TSTree *tree = ParseXMLSch(xmlString);
    UDXMLMirrorDoc *doc = [[UDXMLMirrorDoc alloc] init];
    [doc applyTree:tree changedRanges:nil gapBuffer:buf];
    ts_tree_delete(tree);
    return doc;
}

// ---------------------------------------------------------------------------
// MARK: - Tests
// ---------------------------------------------------------------------------

- (void)testSchematronValidation_validDocument_producesNoErrors {
    // Every <item> has an @id — schema is satisfied.
    UDXMLMirrorDoc *doc = [self _mirrorDocForXML:
                           @"<root><item id=\"1\">hello</item></root>"];
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
                   @"Document satisfying all assertions should produce no errors");
}

- (void)testSchematronValidation_missingAttribute_producesError {
    // <item> is missing @id — the assert fires.
    UDXMLMirrorDoc *doc = [self _mirrorDocForXML:
                           @"<root><item>hello</item></root>"];
    XCTAssert(doc.xmlDoc != NULL);

    __block NSArray<UDDiagnosticItem *> *diagnostics = nil;
    [_validator validateDoc:doc.xmlDoc
                  lineIndex:NULL
                  lineCount:0
                 completion:^(NSArray<UDDiagnosticItem *> *items) {
        diagnostics = items;
    }];
    XCTAssertNotNil(diagnostics);
    XCTAssertGreaterThan(diagnostics.count, (NSUInteger)0,
                         @"Missing @id should trigger a Schematron assertion failure");
    for (UDDiagnosticItem *item in diagnostics) {
        XCTAssertEqualObjects(item.source, UDDiagnosticSourceSchematron);
        XCTAssertEqual(item.severity, UDDiagnosticSeverityError);
    }
}

- (void)testSchematronValidation_multipleViolations_producesMultipleErrors {
    // Two <item> elements both missing @id.
    UDXMLMirrorDoc *doc = [self _mirrorDocForXML:
                           @"<root><item>hello</item><item>world</item></root>"];
    XCTAssert(doc.xmlDoc != NULL);

    __block NSArray<UDDiagnosticItem *> *diagnostics = nil;
    [_validator validateDoc:doc.xmlDoc
                  lineIndex:NULL
                  lineCount:0
                 completion:^(NSArray<UDDiagnosticItem *> *items) {
        diagnostics = items;
    }];
    XCTAssertGreaterThanOrEqual(diagnostics.count, (NSUInteger)2,
                                @"Two items without @id should produce at least two errors");
}

- (void)testSchematronValidation_partialViolation_producesOneError {
    // First <item> has @id; second does not.
    UDXMLMirrorDoc *doc = [self _mirrorDocForXML:
                           @"<root><item id=\"1\">hello</item><item>world</item></root>"];
    XCTAssert(doc.xmlDoc != NULL);

    __block NSArray<UDDiagnosticItem *> *diagnostics = nil;
    [_validator validateDoc:doc.xmlDoc
                  lineIndex:NULL
                  lineCount:0
                 completion:^(NSArray<UDDiagnosticItem *> *items) {
        diagnostics = items;
    }];
    XCTAssertEqual(diagnostics.count, (NSUInteger)1,
                   @"Only one item is missing @id — expect exactly one error");
}

- (void)testSchematronValidation_noSchema_producesNoErrors {
    // With no schema loaded the validator is a no-op and returns an empty array.
    UDSchematronValidator *noSchemaValidator = [[UDSchematronValidator alloc] init];
    UDXMLMirrorDoc *doc = [self _mirrorDocForXML:@"<anything/>"];

    __block NSArray<UDDiagnosticItem *> *diagnostics = nil;
    [noSchemaValidator validateDoc:doc.xmlDoc
                         lineIndex:NULL
                         lineCount:0
                        completion:^(NSArray<UDDiagnosticItem *> *items) {
        diagnostics = items;
    }];
    XCTAssertNotNil(diagnostics);
    XCTAssertEqual(diagnostics.count, (NSUInteger)0,
                   @"No schema loaded — expect no diagnostics");
}

- (void)testSchematronValidation_diagnosticSourceIsSchematron {
    // Verify the source tag so the diagnostic store can partition by producer.
    UDXMLMirrorDoc *doc = [self _mirrorDocForXML:@"<root><item>no-id</item></root>"];

    __block NSArray<UDDiagnosticItem *> *diagnostics = nil;
    [_validator validateDoc:doc.xmlDoc
                  lineIndex:NULL
                  lineCount:0
                 completion:^(NSArray<UDDiagnosticItem *> *items) {
        diagnostics = items;
    }];
    XCTAssertGreaterThan(diagnostics.count, (NSUInteger)0);
    XCTAssertEqualObjects(diagnostics.firstObject.source, UDDiagnosticSourceSchematron);
}

@end
