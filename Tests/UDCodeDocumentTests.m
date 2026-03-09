/*---------------------------------------------------------------------------------------------
 *  UDCodeDocumentTests.m
 *
 *  Unit tests for the UDCodeDocument model class.
 *  Tests run in-process via BUNDLE_LOADER — no AppKit required.
 *--------------------------------------------------------------------------------------------*/

#import <XCTest/XCTest.h>
#import "UDCodeDocument.h"

@interface UDCodeDocumentTests : XCTestCase
@end

@implementation UDCodeDocumentTests

// ---------------------------------------------------------------------------
// MARK: - Initialisation
// ---------------------------------------------------------------------------

- (void)testInitSetsDisplayNameFromFileURL {
    NSURL *url = [NSURL fileURLWithPath:@"/tmp/foo.json"];
    UDCodeDocument *doc = [[UDCodeDocument alloc] initWithText:@"" fileURL:url];
    XCTAssertEqualObjects(doc.displayName, @"foo.json");
}

- (void)testInitWithNilFileURLUsesUntitled {
    UDCodeDocument *doc = [[UDCodeDocument alloc] initWithText:@"hello" fileURL:nil];
    XCTAssertEqualObjects(doc.displayName, @"Untitled");
    XCTAssertNil(doc.fileURL);
}

- (void)testInitStoresTextInModel {
    UDCodeDocument *doc = [[UDCodeDocument alloc] initWithText:@"hello world" fileURL:nil];
    XCTAssertEqualObjects([doc.textModel getValue], @"hello world");
}

- (void)testInitNotModified {
    UDCodeDocument *doc = [[UDCodeDocument alloc] initWithText:@"x" fileURL:nil];
    XCTAssertFalse(doc.isModified);
}

- (void)testInitCreatesDiagnosticStore {
    UDCodeDocument *doc = [[UDCodeDocument alloc] initWithText:@"" fileURL:nil];
    XCTAssertNotNil(doc.diagnosticStore);
}

// ---------------------------------------------------------------------------
// MARK: - Modified flag
// ---------------------------------------------------------------------------

- (void)testModifiedFlagRaisedAfterTextEdit {
    UDCodeDocument *doc = [[UDCodeDocument alloc] initWithText:@"abc" fileURL:nil];
    XCTAssertFalse(doc.isModified, @"should start clean");

    // Apply an edit via the underlying text model.
    UDRange r = PTRangeMake(1, 1, 1, 4); // replace all "abc"
    [doc.textModel applyEdits:@[[[UDTextModelEdit alloc] initWithRange:r text:@"xyz"]]];

    // The UDTextModelDidChangeNotification is synchronous in tests.
    XCTAssertTrue(doc.isModified, @"should be dirty after edit");
}

// ---------------------------------------------------------------------------
// MARK: - documentFromURL:error:
// ---------------------------------------------------------------------------

- (void)testDocumentFromURL_readsFileContent {
    // Write a temp file, then read it back.
    NSURL *url = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
                     URLByAppendingPathComponent:@"ud_test_doc.json"];
    NSString *content = @"{\"key\": 1}";
    XCTAssertTrue([content writeToURL:url atomically:YES
                             encoding:NSUTF8StringEncoding error:nil]);

    NSError *err = nil;
    UDCodeDocument *doc = [UDCodeDocument documentFromURL:url error:&err];
    XCTAssertNil(err);
    XCTAssertNotNil(doc);
    XCTAssertEqualObjects([doc.textModel getValue], content);
    XCTAssertEqualObjects(doc.fileURL, url);
    XCTAssertEqualObjects(doc.displayName, @"ud_test_doc.json");

    [[NSFileManager defaultManager] removeItemAtURL:url error:nil];
}

- (void)testDocumentFromURL_returnsNilForMissingFile {
    NSURL *url = [NSURL fileURLWithPath:@"/nonexistent/path/missing.json"];
    NSError *err = nil;
    UDCodeDocument *doc = [UDCodeDocument documentFromURL:url error:&err];
    XCTAssertNil(doc);
    XCTAssertNotNil(err);
}

// ---------------------------------------------------------------------------
// MARK: - saveToURL:error:
// ---------------------------------------------------------------------------

- (void)testSaveToURL_writesCurrentText {
    UDCodeDocument *doc = [[UDCodeDocument alloc] initWithText:@"saved content" fileURL:nil];
    NSURL *url = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
                     URLByAppendingPathComponent:@"ud_test_save.json"];

    NSError *err = nil;
    BOOL ok = [doc saveToURL:url error:&err];
    XCTAssertTrue(ok);
    XCTAssertNil(err);

    NSString *read = [NSString stringWithContentsOfURL:url
                                              encoding:NSUTF8StringEncoding
                                                 error:nil];
    XCTAssertEqualObjects(read, @"saved content");
    [[NSFileManager defaultManager] removeItemAtURL:url error:nil];
}

- (void)testSaveToURL_clearsModifiedFlag {
    UDCodeDocument *doc = [[UDCodeDocument alloc] initWithText:@"data" fileURL:nil];

    // Make it dirty.
    UDRange r = PTRangeMake(1, 1, 1, 5);
    [doc.textModel applyEdits:@[[[UDTextModelEdit alloc] initWithRange:r text:@"data2"]]];
    XCTAssertTrue(doc.isModified);

    NSURL *url = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
                     URLByAppendingPathComponent:@"ud_test_save2.json"];
    [doc saveToURL:url error:nil];
    XCTAssertFalse(doc.isModified, @"modified flag should clear after save");
    [[NSFileManager defaultManager] removeItemAtURL:url error:nil];
}

// ---------------------------------------------------------------------------
// MARK: - Notification
// ---------------------------------------------------------------------------

- (void)testTextDidChangeNotificationPosted {
    UDCodeDocument *doc = [[UDCodeDocument alloc] initWithText:@"hi" fileURL:nil];
    XCTestExpectation *exp = [self expectationWithDescription:@"text-changed notification"];

    [[NSNotificationCenter defaultCenter]
        addObserverForName:UDCodeDocumentTextDidChangeNotification
                    object:doc
                     queue:[NSOperationQueue mainQueue]
                usingBlock:^(NSNotification *n) {
        [exp fulfill];
    }];

    UDRange r = PTRangeMake(1, 1, 1, 3);
    [doc.textModel applyEdits:@[[[UDTextModelEdit alloc] initWithRange:r text:@"bye"]]];

    [self waitForExpectationsWithTimeout:1.0 handler:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
