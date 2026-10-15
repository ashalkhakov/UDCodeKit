/*---------------------------------------------------------------------------------------------
 *  UDLanguageModeTests.m
 *
 *  Unit tests for UDLanguageMode and UDLanguageModeRegistry.
 *--------------------------------------------------------------------------------------------*/

#import <XCTest/XCTest.h>
#import "UDCodeTestCase.h"
#import <UDCodeKit/UDCodeKit.h>

@interface UDLanguageModeTests : UDCodeTestCase
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
     languageServerCommand:nil
    defaultNewDocumentText:@""
    languageConfiguration:[UDLanguageConfiguration emptyConfiguration]
               keyHandler:nil
               extension:nil];
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
     languageServerCommand:nil
    defaultNewDocumentText:@""
    languageConfiguration:[UDLanguageConfiguration emptyConfiguration]
               keyHandler:nil
               extension:nil];
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
     languageServerCommand:nil
    defaultNewDocumentText:@""
     languageConfiguration:[UDLanguageConfiguration emptyConfiguration]
                keyHandler:nil
               extension:nil];
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
     languageServerCommand:nil
    defaultNewDocumentText:@"{}"
     languageConfiguration:[UDLanguageConfiguration emptyConfiguration]
                keyHandler:nil
               extension:nil];
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
     languageServerCommand:nil
    defaultNewDocumentText:@""
     languageConfiguration:[UDLanguageConfiguration emptyConfiguration]
                keyHandler:nil
               extension:nil];
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
    XCTAssertTrue(html.languageFunc != NULL, @"HTML mode must have a tree-sitter grammar");
    XCTAssertNotNil(html.highlightsQuery);
}

- (void)testRegistryHasMarkdownMode {
    UDLanguageModeRegistry *reg = [UDLanguageModeRegistry sharedRegistry];
    UDLanguageMode *md = [reg modeForIdentifier:@"markdown"];
    XCTAssertEqualObjects(md.identifier, @"markdown");

    // this mode has a weird 2-level grammar... need to get back to it sometime
    //XCTAssertTrue(md.languageFunc != NULL, @"Markdown mode must have a tree-sitter grammar");
    //XCTAssertNotNil(md.highlightsQuery);
}

- (void)testRegistryHasXMLMode {
    UDLanguageModeRegistry *reg = [UDLanguageModeRegistry sharedRegistry];
    UDLanguageMode *xml = [reg modeForIdentifier:@"xml"];
    XCTAssertEqualObjects(xml.identifier, @"xml");
    XCTAssertEqualObjects(xml.lspLanguageID, @"xml");
    XCTAssertTrue(xml.languageFunc != NULL, @"XML mode must have a tree-sitter grammar");
    XCTAssertNotNil(xml.highlightsQuery);
}

- (void)testRegistryHasYAMLMode {
    UDLanguageModeRegistry *reg = [UDLanguageModeRegistry sharedRegistry];
    UDLanguageMode *yaml = [reg modeForIdentifier:@"yaml"];
    XCTAssertEqualObjects(yaml.identifier, @"yaml");
    XCTAssertEqualObjects(yaml.lspLanguageID, @"yaml");
    XCTAssertTrue(yaml.languageFunc != NULL, @"YAML mode must have a tree-sitter grammar");
    XCTAssertNotNil(yaml.highlightsQuery);
}

- (void)testRegistryHasCMode {
    UDLanguageModeRegistry *reg = [UDLanguageModeRegistry sharedRegistry];
    UDLanguageMode *c = [reg modeForIdentifier:@"c"];
    XCTAssertEqualObjects(c.identifier, @"c");
    XCTAssertEqualObjects(c.lspLanguageID, @"c");
    XCTAssertTrue(c.languageFunc != NULL, @"C mode must have a tree-sitter grammar");
    XCTAssertNotNil(c.highlightsQuery);
    //XCTAssertNotNil(c.indentsQuery);
}

- (void)testRegistryHasObjCMode {
    UDLanguageModeRegistry *reg = [UDLanguageModeRegistry sharedRegistry];
    UDLanguageMode *objc = [reg modeForIdentifier:@"objc"];
    XCTAssertEqualObjects(objc.identifier, @"objc");
    XCTAssertEqualObjects(objc.lspLanguageID, @"objective-c");
    XCTAssertTrue(objc.languageFunc != NULL, @"ObjC mode must have a tree-sitter grammar");
    XCTAssertNotNil(objc.highlightsQuery);
}

- (void)testRegistryHasBashMode {
    UDLanguageModeRegistry *reg = [UDLanguageModeRegistry sharedRegistry];
    UDLanguageMode *bash = [reg modeForIdentifier:@"bash"];
    XCTAssertEqualObjects(bash.identifier, @"bash");
    XCTAssertTrue(bash.languageFunc != NULL, @"Bash mode must have a tree-sitter grammar");
    XCTAssertNotNil(bash.highlightsQuery);
}

- (void)testRegistryHasMakeMode {
    UDLanguageModeRegistry *reg = [UDLanguageModeRegistry sharedRegistry];
    UDLanguageMode *make = [reg modeForIdentifier:@"make"];
    XCTAssertEqualObjects(make.identifier, @"make");
    XCTAssertTrue(make.languageFunc != NULL, @"Make mode must have a tree-sitter grammar");
    XCTAssertNotNil(make.highlightsQuery);
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

- (void)testLookupByExtension_xml {
    UDLanguageMode *mode =
        [[UDLanguageModeRegistry sharedRegistry] modeForFileExtension:@"xml"];
    XCTAssertEqualObjects(mode.identifier, @"xml");
}

- (void)testLookupByExtension_svg {
    UDLanguageMode *mode =
        [[UDLanguageModeRegistry sharedRegistry] modeForFileExtension:@"svg"];
    XCTAssertEqualObjects(mode.identifier, @"xml");
}

/// XHTML is XML (tag mirroring, LemMinX), and so are SVG, NORMA's models,
/// Interface Builder's files, schemas and the like; HTML keeps .html.
- (void)testLookupByExtension_xmlFamily {
    UDLanguageModeRegistry *reg = [UDLanguageModeRegistry sharedRegistry];
    for (NSString *ext in @[ @"xhtml", @"svg", @"orm", @"xsd", @"xib", @"storyboard", @"xaml", @"csproj", @"tmLanguage" ]) {
        XCTAssertEqualObjects([reg modeForFileExtension:ext].identifier, @"xml", @"%@", ext);
    }
    XCTAssertEqualObjects([reg modeForFileExtension:@"html"].identifier, @"html");
}

- (void)testLookupByExtension_plist {
    UDLanguageMode *mode =
        [[UDLanguageModeRegistry sharedRegistry] modeForFileExtension:@"plist"];
    XCTAssertEqualObjects(mode.identifier, @"xml");
}

- (void)testLookupByExtension_md {
    UDLanguageMode *mode =
        [[UDLanguageModeRegistry sharedRegistry] modeForFileExtension:@"md"];
    XCTAssertEqualObjects(mode.identifier, @"markdown");
}

- (void)testLookupByExtension_c {
    UDLanguageMode *mode =
        [[UDLanguageModeRegistry sharedRegistry] modeForFileExtension:@"c"];
    XCTAssertEqualObjects(mode.identifier, @"c");
}

- (void)testLookupByExtension_m_isObjC {
    UDLanguageMode *mode =
        [[UDLanguageModeRegistry sharedRegistry] modeForFileExtension:@"m"];
    XCTAssertEqualObjects(mode.identifier, @"objc");
}

- (void)testLookupByExtension_h_isObjC {
    UDLanguageMode *mode =
        [[UDLanguageModeRegistry sharedRegistry] modeForFileExtension:@"h"];
    XCTAssertEqualObjects(mode.identifier, @"objc");
}

- (void)testLookupByExtension_sh {
    UDLanguageMode *mode =
        [[UDLanguageModeRegistry sharedRegistry] modeForFileExtension:@"sh"];
    XCTAssertEqualObjects(mode.identifier, @"bash");
}

- (void)testLookupByExtension_mk {
    UDLanguageMode *mode =
        [[UDLanguageModeRegistry sharedRegistry] modeForFileExtension:@"mk"];
    XCTAssertEqualObjects(mode.identifier, @"make");
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

- (void)testLookupByURL_xmlFile {
    NSURL *url = [NSURL fileURLWithPath:@"/tmp/data.xml"];
    UDLanguageMode *mode =
        [[UDLanguageModeRegistry sharedRegistry] modeForFileURL:url];
    XCTAssertEqualObjects(mode.identifier, @"xml");
}

- (void)testLookupByURL_cFile {
    NSURL *url = [NSURL fileURLWithPath:@"/tmp/main.c"];
    UDLanguageMode *mode =
        [[UDLanguageModeRegistry sharedRegistry] modeForFileURL:url];
    XCTAssertEqualObjects(mode.identifier, @"c");
}

- (void)testLookupByURL_objcFile {
    NSURL *url = [NSURL fileURLWithPath:@"/tmp/MyClass.m"];
    UDLanguageMode *mode =
        [[UDLanguageModeRegistry sharedRegistry] modeForFileURL:url];
    XCTAssertEqualObjects(mode.identifier, @"objc");
}

- (void)testLookupByURL_headerFile {
    NSURL *url = [NSURL fileURLWithPath:@"/tmp/MyClass.h"];
    UDLanguageMode *mode =
        [[UDLanguageModeRegistry sharedRegistry] modeForFileURL:url];
    XCTAssertEqualObjects(mode.identifier, @"objc");
}

- (void)testLookupByURL_shellScript {
    NSURL *url = [NSURL fileURLWithPath:@"/tmp/build.sh"];
    UDLanguageMode *mode =
        [[UDLanguageModeRegistry sharedRegistry] modeForFileURL:url];
    XCTAssertEqualObjects(mode.identifier, @"bash");
}

- (void)testLookupByURL_makefileInclude {
    NSURL *url = [NSURL fileURLWithPath:@"/tmp/common.mk"];
    UDLanguageMode *mode =
        [[UDLanguageModeRegistry sharedRegistry] modeForFileURL:url];
    XCTAssertEqualObjects(mode.identifier, @"make");
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
     languageServerCommand:nil
    defaultNewDocumentText:@""
    languageConfiguration:[UDLanguageConfiguration emptyConfiguration]
               keyHandler:nil
               extension:nil];
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
     languageServerCommand:nil
    defaultNewDocumentText:@""
     languageConfiguration:[UDLanguageConfiguration emptyConfiguration]
                keyHandler:nil
               extension:nil];
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

- (void)testDocumentLanguageModeDetectedFromXMLURL {
    NSURL *url = [NSURL fileURLWithPath:@"/tmp/data.xml"];
    UDCodeDocument *doc = [[UDCodeDocument alloc] initWithText:@"" fileURL:url];
    XCTAssertEqualObjects(doc.languageMode.identifier, @"xml");
}

- (void)testDocumentLanguageModeDetectedFromCURL {
    NSURL *url = [NSURL fileURLWithPath:@"/tmp/main.c"];
    UDCodeDocument *doc = [[UDCodeDocument alloc] initWithText:@"" fileURL:url];
    XCTAssertEqualObjects(doc.languageMode.identifier, @"c");
}

- (void)testDocumentLanguageModeDetectedFromObjCURL {
    NSURL *url = [NSURL fileURLWithPath:@"/tmp/MyClass.m"];
    UDCodeDocument *doc = [[UDCodeDocument alloc] initWithText:@"" fileURL:url];
    XCTAssertEqualObjects(doc.languageMode.identifier, @"objc");
}

- (void)testDocumentLanguageModeDetectedFromShellURL {
    NSURL *url = [NSURL fileURLWithPath:@"/tmp/build.sh"];
    UDCodeDocument *doc = [[UDCodeDocument alloc] initWithText:@"" fileURL:url];
    XCTAssertEqualObjects(doc.languageMode.identifier, @"bash");
}

- (void)testDocumentLanguageModeIsPlaintextForNilURL {
    UDCodeDocument *doc = [[UDCodeDocument alloc] initWithText:@"hello" fileURL:nil];
    XCTAssertEqualObjects(doc.languageMode.identifier, @"plaintext");
}

- (void)testDocumentLanguageModeIsNonNilAlways {
    UDCodeDocument *doc = [[UDCodeDocument alloc] initWithText:@"" fileURL:nil];
    XCTAssertNotNil(doc.languageMode);
}

// ---------------------------------------------------------------------------
// MARK: - UDLanguageConfiguration
// ---------------------------------------------------------------------------

- (void)testEmptyConfigurationHasNilComments {
    UDLanguageConfiguration *cfg = [UDLanguageConfiguration emptyConfiguration];
    XCTAssertNil(cfg.lineCommentString);
    XCTAssertNil(cfg.blockCommentStart);
    XCTAssertNil(cfg.blockCommentEnd);
}

- (void)testEmptyConfigurationHasEmptyBrackets {
    UDLanguageConfiguration *cfg = [UDLanguageConfiguration emptyConfiguration];
    XCTAssertEqual(cfg.brackets.count, (NSUInteger)0);
    XCTAssertEqual(cfg.autoClosingPairs.count, (NSUInteger)0);
    XCTAssertEqual(cfg.surroundingPairs.count, (NSUInteger)0);
}

- (void)testConfigurationFromDictionaryParsesComments {
    NSDictionary *dict = @{
        @"comments": @{
            @"lineComment": @"//",
            @"blockComment": @[@"/*", @"*/"],
        }
    };
    UDLanguageConfiguration *cfg = [UDLanguageConfiguration configurationFromDictionary:dict];
    XCTAssertEqualObjects(cfg.lineCommentString, @"//");
    XCTAssertEqualObjects(cfg.blockCommentStart, @"/*");
    XCTAssertEqualObjects(cfg.blockCommentEnd,   @"*/");
}

- (void)testConfigurationFromDictionaryParsesBrackets {
    NSDictionary *dict = @{
        @"brackets": @[@[@"{", @"}"], @[@"[", @"]"], @[@"(", @")"]],
    };
    UDLanguageConfiguration *cfg = [UDLanguageConfiguration configurationFromDictionary:dict];
    XCTAssertEqual(cfg.brackets.count, (NSUInteger)3);
    XCTAssertEqualObjects(cfg.brackets[0], (@[@"{", @"}"]));
    XCTAssertEqualObjects(cfg.brackets[1], (@[@"[", @"]"]));
}

- (void)testConfigurationFromDictionaryParsesAutoClosingPairs {
    NSDictionary *dict = @{
        @"autoClosingPairs": @[
            @{@"open": @"{", @"close": @"}"},
            @{@"open": @"\"", @"close": @"\"", @"notIn": @[@"string"]},
        ]
    };
    UDLanguageConfiguration *cfg = [UDLanguageConfiguration configurationFromDictionary:dict];
    XCTAssertEqual(cfg.autoClosingPairs.count, (NSUInteger)2);
    XCTAssertEqualObjects(cfg.autoClosingPairs[0].open,  @"{");
    XCTAssertEqualObjects(cfg.autoClosingPairs[0].close, @"}");
    XCTAssertEqual(cfg.autoClosingPairs[0].notIn.count, (NSUInteger)0);
    XCTAssertEqualObjects(cfg.autoClosingPairs[1].notIn, (@[@"string"]));
}

- (void)testConfigurationFromDictionaryParsesFolding {
    NSDictionary *dict = @{
        @"folding": @{
            @"markers": @{
                @"start": @"^\\s*//\\s*#region\\b",
                @"end":   @"^\\s*//\\s*#endregion\\b",
            }
        }
    };
    UDLanguageConfiguration *cfg = [UDLanguageConfiguration configurationFromDictionary:dict];
    XCTAssertEqualObjects(cfg.foldingStartPattern, @"^\\s*//\\s*#region\\b");
    XCTAssertEqualObjects(cfg.foldingEndPattern,   @"^\\s*//\\s*#endregion\\b");
}

- (void)testConfigurationOpenBracketCharacters {
    NSDictionary *dict = @{
        @"brackets": @[@[@"{", @"}"], @[@"[", @"]"]]
    };
    UDLanguageConfiguration *cfg = [UDLanguageConfiguration configurationFromDictionary:dict];
    NSString *opens = [cfg openBracketCharacters];
    XCTAssertTrue([opens containsString:@"{"]);
    XCTAssertTrue([opens containsString:@"["]);
}

- (void)testConfigurationClosingBracketForOpen {
    NSDictionary *dict = @{
        @"brackets": @[@[@"{", @"}"], @[@"[", @"]"]]
    };
    UDLanguageConfiguration *cfg = [UDLanguageConfiguration configurationFromDictionary:dict];
    XCTAssertEqualObjects([cfg closingBracketForOpen:@"{"], @"}");
    XCTAssertEqualObjects([cfg closingBracketForOpen:@"["], @"]");
    XCTAssertNil([cfg closingBracketForOpen:@"("]);
}

- (void)testLanguageModeHasNonNilConfiguration {
    UDLanguageMode *mode = [[UDLanguageMode alloc]
        initWithIdentifier:@"test"
               displayName:@"Test"
            fileExtensions:@[@"tst"]
              languageFunc:NULL
           highlightsQuery:nil
              indentsQuery:nil
             lspLanguageID:nil
     languageServerCommand:nil
    defaultNewDocumentText:@""
     languageConfiguration:nil
                keyHandler:nil
               extension:nil];

    // nil config should be replaced by emptyConfiguration — never nil
    XCTAssertNotNil(mode.languageConfiguration);
}

- (void)testConfigurationFromNilDictIsEmpty {
    UDLanguageConfiguration *cfg = [UDLanguageConfiguration configurationFromDictionary:nil];
    XCTAssertNil(cfg.lineCommentString);
    XCTAssertEqual(cfg.brackets.count, (NSUInteger)0);
}

@end
