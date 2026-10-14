//
//  UDEditorComplexityTests.m
//
//  The editor's hot paths cost what the edit, or what is on screen, costs —
//  not what the document costs. As UDComplexityTests does for the text
//  model, each test times the same work on two documents, one 8× the other,
//  and checks the time grows far less than 8×: work that rescans the document
//  grows ~8×; work proportional to the edit, or logarithmic in the document,
//  stays nearly flat. The bounds leave a wide margin, so only a change in
//  complexity trips them.
//
//  The documents nest, no list longer than 16: tree-sitter's own cost for an
//  edit grows with the length of the list it is in (it re-reduces the whole
//  repetition), so a flat list of N entries would time tree-sitter, not us.
//

#import <XCTest/XCTest.h>
#import <UDCodeKit/UDCodeKit.h>

static double UDTime(void (^block)(void)) {
    NSDate *start = [NSDate date];
    block();
    return -[start timeIntervalSinceNow];
}

/// Runs what the edits queued on the main queue (the highlighters' updates).
static void UDDrainMainQueue(void) {
    // The main queue runs in order: once a block queued now has run, so has
    // everything queued before it. Three rounds, for what those queue.
    for (int round = 0; round < 3; round++) {
        __block BOOL reached = NO;
        dispatch_async(dispatch_get_main_queue(), ^{ reached = YES; });
        while (!reached) CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.01, true);
    }
}

/// A JSON document of `entries` entries, one a line, in objects of at most
/// 16 members nested as deep as that takes.
static void UDAppendNestedJSON(NSMutableString *text, NSInteger entries, NSInteger *counter, NSInteger depth) {
    [text appendString:@"{\n"];
    if (entries <= 16) {
        for (NSInteger i = 0; i < entries; i++, (*counter)++) {
            [text appendFormat:@"  \"key%ld\": {\"value\": [%ld, true, null], \"name\": \"entry\"}%@\n",
                               (long)*counter, (long)*counter, i + 1 < entries ? @"," : @""];
        }
    } else {
        NSInteger per = (entries + 15) / 16, group = 0;
        for (NSInteger left = entries; left > 0; left -= per) {
            NSInteger count = MIN(left, per);
            [text appendFormat:@"\"group%ld_%ld\": ", (long)depth, (long)group++];
            UDAppendNestedJSON(text, count, counter, depth + 1);
            [text appendString:left > count ? @",\n" : @"\n"];
        }
    }
    [text appendString:@"}"];
}

static NSString *UDJSONDocument(NSInteger entries) {
    NSMutableString *text = [NSMutableString string];
    NSInteger counter = 0;
    UDAppendNestedJSON(text, entries, &counter, 0);
    [text appendString:@"\n"];
    return text;
}

@interface UDEditorComplexityTests : XCTestCase
@end

@implementation UDEditorComplexityTests

- (UDTextModelTextStorage *)highlightedStorageWithEntries:(NSInteger)entries {
    UDLanguageMode *json = [[UDLanguageModeRegistry sharedRegistry] modeForFileExtension:@"json"];
    UDTextModelTextStorage *storage = [[UDTextModelTextStorage alloc] initWithText:UDJSONDocument(entries)];
    storage.theme = [[TreeSitterTheme alloc] initWithMode:NO];
    [storage setLanguageFunc:json.languageFunc withHighlightsQuery:json.highlightsQuery ?: @""];
    UDDrainMainQueue();
    return storage;
}

- (BOOL)haveJSON {
    if ([[UDLanguageModeRegistry sharedRegistry] modeForFileExtension:@"json"].languageFunc) return YES;
    XCTFail(@"%@", @"the JSON grammar bundle did not load");
    return NO;
}

/// Undoing and redoing an edit near the top: the parse tree and the
/// highlights follow the change, not the document.
- (double)undoRedoInDocumentOf:(NSInteger)entries {
    UDTextModelTextStorage *storage = [self highlightedStorageWithEntries:entries];
    UDTextModel *model = storage.textModel;
    model.undoManager = [[NSUndoManager alloc] init];
    model.undoManager.groupsByEvent = NO;
    [model.undoManager beginUndoGrouping];
    [model applyEdits:@[[[UDTextModelEdit alloc] initWithRange:PTRangeMake(3, 5, 3, 5) text:@"x"]]];
    [model.undoManager endUndoGrouping];
    UDDrainMainQueue();
    return UDTime(^{
        for (NSInteger i = 0; i < 100; i++) {
            [model.undoManager undo];
            UDDrainMainQueue();
            [model.undoManager redo];
            UDDrainMainQueue();
        }
    });
}

- (void)testUndoAndRedoCostTheChange {
    if (![self haveJSON]) return;
    [self undoRedoInDocumentOf:500];
    double small = [self undoRedoInDocumentOf:2000];
    double large = [self undoRedoInDocumentOf:16000];
    XCTAssertLessThan(large / small, 3.0, @"8× the document made undo/redo %.1f× slower (%.3fs → %.3fs)", large / small, small, large);
}

/// Typing, then reading the attributes of a screenful where the typing is,
/// as layout does: the runs are built for the window read, not the document.
- (double)typeAndReadAttributesInDocumentOf:(NSInteger)entries {
    UDTextModelTextStorage *storage = [self highlightedStorageWithEntries:entries];
    NSUInteger middle = storage.length / 2;
    return UDTime(^{
        for (NSInteger i = 0; i < 100; i++) {
            [storage replaceCharactersInRange:NSMakeRange(middle, 0) withString:@" "];
            UDDrainMainQueue();
            NSUInteger at = middle - 1000;
            while (at < middle + 1000) {
                NSRange run;
                (void)[storage attributesAtIndex:at effectiveRange:&run];
                at = NSMaxRange(run);
            }
        }
    });
}

- (void)testAttributesCostTheWindowRead {
    if (![self haveJSON]) return;
    [self typeAndReadAttributesInDocumentOf:500];
    double small = [self typeAndReadAttributesInDocumentOf:2000];
    double large = [self typeAndReadAttributesInDocumentOf:16000];
    XCTAssertLessThan(large / small, 3.0, @"8× the document made typing and layout %.1f× slower (%.3fs → %.3fs)", large / small, small, large);
}

@end
