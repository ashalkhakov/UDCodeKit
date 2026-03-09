/*---------------------------------------------------------------------------------------------
 *  UDLanguageModeTests.m
 *
 *  Unit tests for UDLanguageMode and UDLanguageModeRegistry.
 *--------------------------------------------------------------------------------------------*/

#import <XCTest/XCTest.h>
#import "UDLanguageMode.h"
#import "UDLanguageModeRegistry.h"
#import "UDCodeDocument.h"

@interface UDLanguageModeTests : XCTestCase
@end

@implementation UDLanguageModeTests

// ---------------------------------------------------------------------------
// MARK: - UDLanguageMode basic properties
// ---------------------------------------------------------------------------

- (void)testLanguageModeStoresIdentifier {
    UDLanguageMode *mode = [[UDLanguageMode alloc]
        initWithIdentifier:@"test"
               displayName:@"Test"
            fileExtensions:@[@"tst"]
              languageFunc:NULL
           highlightsQuery:nil
              indentsQuery:nil
             lspLanguageID:nil
    defaultNewDocumentText:@""];
    XCTAssertEqualObjects(mode.identifier, @"test");
}

- (void)testLanguageModeStoresDisplayName {
    UDLanguageMode *mode = [[UDLanguageMode alloc]
        initWithIdentifier:@"test"
               displayName:@"Test Language"
            fileExtensions:@[@"tst"]
              languageFunc:NULL
           highlightsQuery:nil
              indentsQuery:nil
             lspLanguageID:nil
    defaultNewDocumentText:@""];
    XCTAssertEqualObjects(mode.displayName, @"Test Language");
}

- (void)testLanguageModeStoresFileExtensions {
    UDLanguageMode *mode = [[UDLanguageMode alloc]
        initWithIdentifier:@"test"
               displayName:@"Test"
            fileExtensions:@[@"foo", @"bar"]
              languageFunc:NULL
           highlightsQuery:nil
              indentsQuery:nil
             lspLanguageID:nil
    defaultNewDocumentText:@""];
    XCTAssertEqualObjects(mode.fileExtensions, (@[@"foo", @"bar"]));
}

- (void)testLanguageModeStoresLSPLanguageID {
    UDLanguageMode *mode = [[UDLanguageMode alloc]
        initWithIdentifier:@"json"
               displayName:@"JSON"
            fileExtensions:@[@"json"]
              languageFunc:NULL
           highlightsQuery:nil
              indentsQuery:nil
             lspLanguageID:@"json"
    defaultNewDocumentText:@"{}"];
    XCTAssertEqualObjects(mode.lspLanguageID, @"json");
}

- (void)testLanguageModeNilLanguageFuncForNoGrammar {
    UDLanguageMode *mode = [[UDLanguageMode alloc]
        initWithIdentifier:@"html"
               displayName:@"HTML"
            fileExtensions:@[@"html"]
              languageFunc:NULL
           highlightsQuery:nil
              indentsQuery:nil
             lspLanguageID:@"html"
    defaultNewDocumentText:@""];
    XCTAssertTrue(mode.languageFunc == NULL);
    XCTAssertNil(mode.highlightsQuery);
}

// ---------------------------------------------------------------------------
// MARK: - UDLanguageModeRegistry built-in modes
// ---------------------------------------------------------------------------

- (void)testRegistryHasBuiltinModes {
    UDLanguageModeRegistry *reg = [UDLanguageModeRegistry sharedRegistry];
    XCTAssertGreaterThan(reg.allModes.count, (NSUInteger)0);
}

- (void)testRegistryHasJSONMode {
    UDLanguageModeRegistry *reg = [UDLanguageModeRegistry sharedRegistry];
    UDLanguageMode *json = [reg modeForIdentifier:@"json"];
    XCTAssertEqualObjects(json.identifier, @"json");
    XCTAssertEqualObjects(json.lspLanguageID, @"json");
    XCTAssertTrue(json.languageFunc != NULL, @"JSON mode must have a tree-sitter grammar");
    XCTAssertNotNil(json.highlightsQuery);
}

- (void)testRegistryHasHTMLMode {
    UDLanguageModeRegistry *reg = [UDLanguageModeRegistry sharedRegistry];
    UDLanguageMode *html = [reg modeForIdentifier:@"html"];
    XCTAssertEqualObjects(html.identifier, @"html");
    XCTAssertEqualObjects(html.lspLanguageID, @"html");
}

- (void)testRegistryHasYAMLMode {
    UDLanguageModeRegistry *reg = [UDLanguageModeRegistry sharedRegistry];
    UDLanguageMode *yaml = [reg modeForIdentifier:@"yaml"];
    XCTAssertEqualObjects(yaml.identifier, @"yaml");
    XCTAssertEqualObjects(yaml.lspLanguageID, @"yaml");
}

- (void)testRegistryHasPlaintextFallback {
    UDLanguageModeRegistry *reg = [UDLanguageModeRegistry sharedRegistry];
    UDLanguageMode *plain = [reg modeForIdentifier:@"plaintext"];
    XCTAssertEqualObjects(plain.identifier, @"plaintext");
    XCTAssertNil(plain.lspLanguageID);
    XCTAssertTrue(plain.languageFunc == NULL);
}

// ---------------------------------------------------------------------------
// MARK: - UDLanguageModeRegistry lookup by extension
// ---------------------------------------------------------------------------

- (void)testLookupByExtension_json {
    UDLanguageMode *mode =
        [[UDLanguageModeRegistry sharedRegistry] modeForFileExtension:@"json"];
    XCTAssertEqualObjects(mode.identifier, @"json");
}

- (void)testLookupByExtension_html {
    UDLanguageMode *mode =
        [[UDLanguageModeRegistry sharedRegistry] modeForFileExtension:@"html"];
    XCTAssertEqualObjects(mode.identifier, @"html");
}

- (void)testLookupByExtension_htm {
    UDLanguageMode *mode =
        [[UDLanguageModeRegistry sharedRegistry] modeForFileExtension:@"htm"];
    XCTAssertEqualObjects(mode.identifier, @"html");
}

- (void)testLookupByExtension_yaml {
    UDLanguageMode *mode =
        [[UDLanguageModeRegistry sharedRegistry] modeForFileExtension:@"yaml"];
    XCTAssertEqualObjects(mode.identifier, @"yaml");
}

- (void)testLookupByExtension_yml {
    UDLanguageMode *mode =
        [[UDLanguageModeRegistry sharedRegistry] modeForFileExtension:@"yml"];
    XCTAssertEqualObjects(mode.identifier, @"yaml");
}

- (void)testLookupByExtension_unknownFallsBackToPlaintext {
    UDLanguageMode *mode =
        [[UDLanguageModeRegistry sharedRegistry] modeForFileExtension:@"xyz"];
    XCTAssertEqualObjects(mode.identifier, @"plaintext");
}

- (void)testLookupByExtension_caseInsensitive {
    UDLanguageMode *mode =
        [[UDLanguageModeRegistry sharedRegistry] modeForFileExtension:@"JSON"];
    XCTAssertEqualObjects(mode.identifier, @"json");
}

// ---------------------------------------------------------------------------
// MARK: - UDLanguageModeRegistry lookup by URL
// ---------------------------------------------------------------------------

- (void)testLookupByURL_jsonFile {
    NSURL *url = [NSURL fileURLWithPath:@"/tmp/data.json"];
    UDLanguageMode *mode =
        [[UDLanguageModeRegistry sharedRegistry] modeForFileURL:url];
    XCTAssertEqualObjects(mode.identifier, @"json");
}

- (void)testLookupByURL_htmlFile {
    NSURL *url = [NSURL fileURLWithPath:@"/tmp/index.html"];
    UDLanguageMode *mode =
        [[UDLanguageModeRegistry sharedRegistry] modeForFileURL:url];
    XCTAssertEqualObjects(mode.identifier, @"html");
}

- (void)testLookupByURL_yamlFile {
    NSURL *url = [NSURL fileURLWithPath:@"/tmp/config.yml"];
    UDLanguageMode *mode =
        [[UDLanguageModeRegistry sharedRegistry] modeForFileURL:url];
    XCTAssertEqualObjects(mode.identifier, @"yaml");
}

- (void)testLookupByURL_nilURLFallsBackToPlaintext {
    UDLanguageMode *mode =
        [[UDLanguageModeRegistry sharedRegistry] modeForFileURL:nil];
    XCTAssertEqualObjects(mode.identifier, @"plaintext");
}

- (void)testLookupByURL_unknownExtensionFallsBackToPlaintext {
    NSURL *url = [NSURL fileURLWithPath:@"/tmp/file.unknown"];
    UDLanguageMode *mode =
        [[UDLanguageModeRegistry sharedRegistry] modeForFileURL:url];
    XCTAssertEqualObjects(mode.identifier, @"plaintext");
}

// ---------------------------------------------------------------------------
// MARK: - Custom mode registration
// ---------------------------------------------------------------------------

- (void)testCustomModeCanBeRegistered {
    UDLanguageModeRegistry *reg = [UDLanguageModeRegistry sharedRegistry];
    UDLanguageMode *custom = [[UDLanguageMode alloc]
        initWithIdentifier:@"_test_custom_xyz"
               displayName:@"Test Custom"
            fileExtensions:@[@"_xyz_test"]
              languageFunc:NULL
           highlightsQuery:nil
              indentsQuery:nil
             lspLanguageID:nil
    defaultNewDocumentText:@""];
    [reg registerMode:custom];

    // The registry uses dispatch_barrier_async for writes and dispatch_sync for
    // reads; calling modeForIdentifier: here will naturally wait for the pending
    // barrier to complete, so no sleep is needed.
    UDLanguageMode *found = [reg modeForIdentifier:@"_test_custom_xyz"];
    XCTAssertEqualObjects(found.identifier, @"_test_custom_xyz");

    UDLanguageMode *byExt = [reg modeForFileExtension:@"_xyz_test"];
    XCTAssertEqualObjects(byExt.identifier, @"_test_custom_xyz");
}

- (void)testCustomModeAppearsInAllModes {
    UDLanguageModeRegistry *reg = [UDLanguageModeRegistry sharedRegistry];
    UDLanguageMode *custom = [[UDLanguageMode alloc]
        initWithIdentifier:@"_test_custom_abc"
               displayName:@"Test Custom ABC"
            fileExtensions:@[]
              languageFunc:NULL
           highlightsQuery:nil
              indentsQuery:nil
             lspLanguageID:nil
    defaultNewDocumentText:@""];
    [reg registerMode:custom];

    NSArray *all = reg.allModes;
    NSArray *ids = [all valueForKeyPath:@"identifier"];
    XCTAssertTrue([ids containsObject:@"_test_custom_abc"]);
}

// ---------------------------------------------------------------------------
// MARK: - UDCodeDocument.languageMode auto-detection
// ---------------------------------------------------------------------------

- (void)testDocumentLanguageModeDetectedFromJSONURL {
    NSURL *url = [NSURL fileURLWithPath:@"/tmp/data.json"];
    UDCodeDocument *doc = [[UDCodeDocument alloc] initWithText:@"{}" fileURL:url];
    XCTAssertEqualObjects(doc.languageMode.identifier, @"json");
}

- (void)testDocumentLanguageModeDetectedFromHTMLURL {
    NSURL *url = [NSURL fileURLWithPath:@"/tmp/index.html"];
    UDCodeDocument *doc = [[UDCodeDocument alloc] initWithText:@"" fileURL:url];
    XCTAssertEqualObjects(doc.languageMode.identifier, @"html");
}

- (void)testDocumentLanguageModeDetectedFromYAMLURL {
    NSURL *url = [NSURL fileURLWithPath:@"/tmp/config.yaml"];
    UDCodeDocument *doc = [[UDCodeDocument alloc] initWithText:@"" fileURL:url];
    XCTAssertEqualObjects(doc.languageMode.identifier, @"yaml");
}

- (void)testDocumentLanguageModeIsPlaintextForNilURL {
    UDCodeDocument *doc = [[UDCodeDocument alloc] initWithText:@"hello" fileURL:nil];
    XCTAssertEqualObjects(doc.languageMode.identifier, @"plaintext");
}

- (void)testDocumentLanguageModeIsNonNilAlways {
    UDCodeDocument *doc = [[UDCodeDocument alloc] initWithText:@"" fileURL:nil];
    XCTAssertNotNil(doc.languageMode);
}

@end
