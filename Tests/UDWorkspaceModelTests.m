/*---------------------------------------------------------------------------------------------
 *  UDWorkspaceModelTests.m
 *
 *  Unit tests for the UDWorkspaceModel model class.
 *  Tests run in-process via BUNDLE_LOADER — no AppKit required.
 *--------------------------------------------------------------------------------------------*/

#import <XCTest/XCTest.h>
#import "UDCodeTestCase.h"
#import "UDWorkspaceModel.h"

@interface UDWorkspaceModelTests : UDCodeTestCase
@end

@implementation UDWorkspaceModelTests

// ---------------------------------------------------------------------------
// MARK: - Initial state
// ---------------------------------------------------------------------------

- (void)testInitHasNoDocuments {
    UDWorkspaceModel *model = [[UDWorkspaceModel alloc] init];
    XCTAssertEqual(model.documents.count, (NSUInteger)0);
}

// ---------------------------------------------------------------------------
// MARK: - addDocumentWithText:fileURL:
// ---------------------------------------------------------------------------

- (void)testAddDocumentWithTextCreatesDocument {
    UDWorkspaceModel *model = [[UDWorkspaceModel alloc] init];
    UDCodeDocument *doc = [model addDocumentWithText:@"hello" fileURL:nil];
    XCTAssertNotNil(doc);
    XCTAssertEqual(model.documents.count, (NSUInteger)1);
    XCTAssertEqualObjects([doc.textModel getValue], @"hello");
}

- (void)testAddDocumentWithFileURLDeduplicates {
    NSURL *url = [NSURL fileURLWithPath:@"/tmp/foo.json"];
    UDWorkspaceModel *model = [[UDWorkspaceModel alloc] init];

    UDCodeDocument *first  = [model addDocumentWithText:@"a" fileURL:url];
    UDCodeDocument *second = [model addDocumentWithText:@"b" fileURL:url];

    XCTAssertEqual(first, second, @"should return existing document for same URL");
    XCTAssertEqual(model.documents.count, (NSUInteger)1);
}

- (void)testAddDocumentWithNilFileURLAllowsMultipleUnnamed {
    UDWorkspaceModel *model = [[UDWorkspaceModel alloc] init];
    UDCodeDocument *a = [model addDocumentWithText:@"a" fileURL:nil];
    UDCodeDocument *b = [model addDocumentWithText:@"b" fileURL:nil];
    XCTAssertNotEqual(a, b, @"nil-URL documents are never de-duplicated");
    XCTAssertEqual(model.documents.count, (NSUInteger)2);
}

// ---------------------------------------------------------------------------
// MARK: - addDocumentFromURL:error:
// ---------------------------------------------------------------------------

- (void)testAddDocumentFromURLLoadsContent {
    NSURL *url = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
                     URLByAppendingPathComponent:@"ud_ws_test.json"];
    [@"{}" writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:nil];

    UDWorkspaceModel *model = [[UDWorkspaceModel alloc] init];
    NSError *err = nil;
    UDCodeDocument *doc = [model addDocumentFromURL:url error:&err];

    XCTAssertNil(err);
    XCTAssertNotNil(doc);
    XCTAssertEqualObjects([doc.textModel getValue], @"{}");
    XCTAssertEqual(model.documents.count, (NSUInteger)1);

    [[NSFileManager defaultManager] removeItemAtURL:url error:nil];
}

- (void)testAddDocumentFromURLReturnsExistingForDuplicateURL {
    NSURL *url = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
                     URLByAppendingPathComponent:@"ud_ws_test2.json"];
    [@"{}" writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:nil];

    UDWorkspaceModel *model = [[UDWorkspaceModel alloc] init];
    UDCodeDocument *first  = [model addDocumentFromURL:url error:nil];
    UDCodeDocument *second = [model addDocumentFromURL:url error:nil];

    XCTAssertEqual(first, second);
    XCTAssertEqual(model.documents.count, (NSUInteger)1);

    [[NSFileManager defaultManager] removeItemAtURL:url error:nil];
}

- (void)testAddDocumentFromURL_failsForMissingFile {
    NSURL *url = [NSURL fileURLWithPath:@"/nonexistent/missing.json"];
    UDWorkspaceModel *model = [[UDWorkspaceModel alloc] init];
    NSError *err = nil;
    UDCodeDocument *doc = [model addDocumentFromURL:url error:&err];
    XCTAssertNil(doc);
    XCTAssertNotNil(err);
    XCTAssertEqual(model.documents.count, (NSUInteger)0);
}

// ---------------------------------------------------------------------------
// MARK: - removeDocument:
// ---------------------------------------------------------------------------

- (void)testRemoveDocument {
    UDWorkspaceModel *model = [[UDWorkspaceModel alloc] init];
    UDCodeDocument *doc = [model addDocumentWithText:@"x" fileURL:nil];
    [model removeDocument:doc];
    XCTAssertEqual(model.documents.count, (NSUInteger)0);
}

- (void)testRemoveDocumentNoopForAbsentDocument {
    UDWorkspaceModel *model = [[UDWorkspaceModel alloc] init];
    UDCodeDocument *other = [[UDCodeDocument alloc] initWithText:@"z" fileURL:nil];
    XCTAssertNoThrow([model removeDocument:other]);
    XCTAssertEqual(model.documents.count, (NSUInteger)0);
}

// ---------------------------------------------------------------------------
// MARK: - documentForFileURL:
// ---------------------------------------------------------------------------

- (void)testDocumentForFileURL_findsDocument {
    NSURL *url = [NSURL fileURLWithPath:@"/tmp/bar.json"];
    UDWorkspaceModel *model = [[UDWorkspaceModel alloc] init];
    UDCodeDocument *doc = [model addDocumentWithText:@"" fileURL:url];
    XCTAssertEqual([model documentForFileURL:url], doc);
}

- (void)testDocumentForFileURL_returnsNilWhenNotFound {
    UDWorkspaceModel *model = [[UDWorkspaceModel alloc] init];
    NSURL *url = [NSURL fileURLWithPath:@"/tmp/notopen.json"];
    XCTAssertNil([model documentForFileURL:url]);
}

// ---------------------------------------------------------------------------
// MARK: - Serialisation
// ---------------------------------------------------------------------------

- (void)testSerializeDeserializeRoundTrip {
    // Create two temp files.
    NSURL *url1 = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
                      URLByAppendingPathComponent:@"a.json"];
    NSURL *url2 = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
                      URLByAppendingPathComponent:@"b.json"];
    [@"{}" writeToURL:url1 atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [@"[]" writeToURL:url2 atomically:YES encoding:NSUTF8StringEncoding error:nil];

    // Build a workspace, serialise it.
    UDWorkspaceModel *original = [[UDWorkspaceModel alloc] init];
    [original addDocumentFromURL:url1 error:nil];
    [original addDocumentFromURL:url2 error:nil];

    NSError *err = nil;
    NSData *data = [original serializeToDataWithError:&err];
    XCTAssertNil(err);
    XCTAssertNotNil(data);

    // Deserialise and verify.
    UDWorkspaceModel *restored = [UDWorkspaceModel workspaceModelFromData:data error:&err];
    XCTAssertNil(err);
    XCTAssertNotNil(restored);
    XCTAssertEqual(restored.documents.count, (NSUInteger)2);
    XCTAssertEqualObjects(restored.documents[0].fileURL, url1);
    XCTAssertEqualObjects(restored.documents[1].fileURL, url2);

    [[NSFileManager defaultManager] removeItemAtURL:url1 error:nil];
    [[NSFileManager defaultManager] removeItemAtURL:url2 error:nil];
}

- (void)testSerializeOmitsUnsavedDocuments {
    UDWorkspaceModel *model = [[UDWorkspaceModel alloc] init];
    [model addDocumentWithText:@"scratch" fileURL:nil]; // no URL — should be omitted
    NSURL *url = [NSURL fileURLWithPath:@"/tmp/saved.json"];
    [model addDocumentWithText:@"saved" fileURL:url];

    NSData *data = [model serializeToDataWithError:nil];
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSArray *files = obj[@"openFiles"];
    XCTAssertEqual(files.count, (NSUInteger)1);
    XCTAssertEqualObjects(files[0][@"path"], @"/tmp/saved.json");
}

- (void)testDeserializeMalformedDataReturnsNil {
    NSData *garbage = [@"not json" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *err = nil;
    UDWorkspaceModel *model = [UDWorkspaceModel workspaceModelFromData:garbage error:&err];
    XCTAssertNil(model);
    XCTAssertNotNil(err);
}

// ---------------------------------------------------------------------------
// MARK: - UDWorkspaceModelDidChangeNotification
// ---------------------------------------------------------------------------

- (void)testChangeNotificationPostedOnAdd {
    UDWorkspaceModel *model = [[UDWorkspaceModel alloc] init];
    XCTestExpectation *exp = [self expectationWithDescription:@"change notification"];
    // A block observer is removed by its token (removeObserver:self would
    // leave it behind, and a later test's model at the same address would
    // fulfil this expectation again).
    id observer = [[NSNotificationCenter defaultCenter]
        addObserverForName:UDWorkspaceModelDidChangeNotification
                    object:model
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *n) { [exp fulfill]; }];

    [model addDocumentWithText:@"x" fileURL:nil];

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:observer];
}

- (void)testChangeNotificationPostedOnRemove {
    UDWorkspaceModel *model = [[UDWorkspaceModel alloc] init];
    UDCodeDocument *doc = [model addDocumentWithText:@"y" fileURL:nil];

    XCTestExpectation *exp = [self expectationWithDescription:@"remove notification"];
    // A block observer is removed by its token (removeObserver:self would
    // leave it behind, and a later test's model at the same address would
    // fulfil this expectation again).
    id observer = [[NSNotificationCenter defaultCenter]
        addObserverForName:UDWorkspaceModelDidChangeNotification
                    object:model
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *n) { [exp fulfill]; }];

    [model removeDocument:doc];

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:observer];
}

@end
