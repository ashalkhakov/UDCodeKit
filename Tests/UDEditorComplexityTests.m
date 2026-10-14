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
#import "UDCodeTestCase.h"
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
        while (!reached) [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
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

@interface UDEditorComplexityTests : UDCodeTestCase
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

/// Typing in a document with a syntax error near the top, through an editor
/// session: the error highlighters walk what changed — and only subtrees
/// holding an error — and the parse diagnostics come from their decorations,
/// so the typing costs the edit, not the parse tree.
- (double)typeWithAnErrorInDocumentOf:(NSInteger)entries {
    NSMutableString *text = [UDJSONDocument(entries) mutableCopy];
    NSRange comma = [text rangeOfString:@", true"];
    [text deleteCharactersInRange:NSMakeRange(comma.location, 1)];   // the first entry's comma
    UDCodeDocument *document = [[UDCodeDocument alloc] initWithText:text fileURL:[NSURL fileURLWithPath:@"/tmp/typing.json"]];
    UDEditorSession *session = [[UDEditorSession alloc] initWithDocument:document];
    [session activateWithTheme:[[TreeSitterTheme alloc] initWithMode:NO]];
    UDDrainMainQueue();
    XCTAssertGreaterThan(document.diagnosticStore.allDiagnostics.count, 0u, @"the document has an error");
    UDTextModelTextStorage *storage = session.textStorage;
    NSUInteger middle = [text rangeOfString:@"\"entry\"" options:0 range:NSMakeRange(text.length / 2, text.length / 2)].location + 2;
    return UDTime(^{
        for (NSInteger i = 0; i < 100; i++) {
            [storage replaceCharactersInRange:NSMakeRange(middle, 0) withString:@"x"];
            UDDrainMainQueue();
        }
    });
}

- (void)testTypingWithAnErrorCostsTheEdit {
    if (![self haveJSON]) return;
    [self typeWithAnErrorInDocumentOf:500];
    double small = [self typeWithAnErrorInDocumentOf:2000];
    double large = [self typeWithAnErrorInDocumentOf:16000];
    XCTAssertLessThan(large / small, 3.0, @"8× the document made typing %.1f× slower (%.3fs → %.3fs)", large / small, small, large);
}

/// Typing with a fold open, then asking what the gutter asks for a
/// screenful: the folding controller walks the tree over those lines, and
/// checks only the folds an edit touched.
- (double)typeWithFoldsInDocumentOf:(NSInteger)entries {
    UDTextModelTextStorage *storage = [self highlightedStorageWithEntries:entries];
    UDFoldingController *folding = [[UDFoldingController alloc] initWithTextView:[[NSTextView alloc] init]
                                                                      textStorage:storage
                                                                      highlighter:storage.highlighter];
    UDTextModel *model = storage.textModel;
    NSInteger lines = [model getLineCount];
    [folding toggleFoldAtLine:lines / 3];
    [folding toggleFoldAtLine:2 * lines / 3];
    NSUInteger middle = (NSUInteger)[model getOffsetAt:lines / 2 column:5];
    NSRange screen = NSMakeRange((NSUInteger)(lines / 2 - 30), 60);
    return UDTime(^{
        for (NSInteger i = 0; i < 100; i++) {
            [storage replaceCharactersInRange:NSMakeRange(middle, 0) withString:@"x"];
            UDDrainMainQueue();
            [folding update];
            (void)[folding foldableLinesInRange:screen];
            (void)[folding foldedLinesInRange:screen];
        }
    });
}

- (void)testFoldingCostsTheLinesShown {
    if (![self haveJSON]) return;
    [self typeWithFoldsInDocumentOf:500];
    double small = [self typeWithFoldsInDocumentOf:2000];
    double large = [self typeWithFoldsInDocumentOf:16000];
    XCTAssertLessThan(large / small, 3.0, @"8× the document made typing with folds %.1f× slower (%.3fs → %.3fs)", large / small, small, large);
}

/// Drawing a screenful in the middle of the document, as the editor's text
/// view does it (its background draws the diagnostics' labels): it costs the
/// lines drawn, not every decoration in the document.
- (double)drawInDocumentOf:(NSInteger)entries {
    UDTextModelTextStorage *storage = [self highlightedStorageWithEntries:entries];
    UDDiagnosticTextView *textView = [[UDDiagnosticTextView alloc] initWithFrame:NSMakeRect(0, 0, 600, 400)];
    NSLayoutManager *layoutManager = textView.layoutManager;
    [layoutManager.textStorage removeLayoutManager:layoutManager];
    [storage addLayoutManager:layoutManager];
    textView.textModel = storage.textModel;
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 600, 400)];
    scrollView.documentView = textView;
#ifdef __APPLE__
    [textView scrollRangeToVisible:NSMakeRange(storage.length / 2, 0)];
    NSRect visible = textView.visibleRect;
    NSBitmapImageRep *bitmap = [textView bitmapImageRepForCachingDisplayInRect:visible];
    [textView cacheDisplayInRect:visible toBitmapImageRep:bitmap];
    return UDTime(^{
        for (NSInteger i = 0; i < 50; i++) {
            [textView cacheDisplayInRect:visible toBitmapImageRep:bitmap];
        }
    });
#else
    // GNUstep draws a view only in a window: its -cacheDisplayInRect:...
    // reads the window back rather than drawing.
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 600, 400)
                                                   styleMask:NSWindowStyleMaskBorderless
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.releasedWhenClosed = NO;
    window.contentView = scrollView;
    [textView scrollRangeToVisible:NSMakeRange(storage.length / 2, 0)];
    NSRect visible = textView.visibleRect;
    [textView displayRect:visible];
    return UDTime(^{
        for (NSInteger i = 0; i < 50; i++) {
            [textView displayRect:visible];
        }
    });
#endif
}

- (void)testDrawingCostsTheLinesDrawn {
    if (![self haveJSON]) return;
#ifdef __APPLE__
    NSInteger entries = 2000;
#else
    // GNUstep lays the whole text out before it draws any of it, in time
    // quadratic in the text (GSLayoutManager runs its debug checks in
    // release builds): smaller documents, 8x apart all the same.
    NSInteger entries = 500;
#endif
    [self drawInDocumentOf:entries / 4];
    double small = [self drawInDocumentOf:entries];
    double large = [self drawInDocumentOf:entries * 8];
    XCTAssertLessThan(large / small, 3.0, @"8× the document made drawing %.1f× slower (%.3fs → %.3fs)", large / small, small, large);
}

/// Typing while a search is open, with a match on every line: the find
/// model searches the lines the edit touched again, not the text.
- (double)typeWhileFindingInDocumentOf:(NSInteger)entries {
    UDTextModelTextStorage *storage = [self highlightedStorageWithEntries:entries];
    UDFindModel *find = [[UDFindModel alloc] initWithTextModel:storage.textModel];
    find.searchString = @"value";
    XCTAssertGreaterThan(find.matchCount, (NSUInteger)MIN(entries, 19999) - 1);
    // Inside a string, so the text stays valid JSON: typing elsewhere would
    // time tree-sitter's error recovery.
    NSString *text = storage.string;
    NSUInteger middle = [text rangeOfString:@"\"entry\"" options:0 range:NSMakeRange(text.length / 2, text.length / 2)].location + 2;
    return UDTime(^{
        for (NSInteger i = 0; i < 100; i++) {
            [storage replaceCharactersInRange:NSMakeRange(middle, 0) withString:@"v"];
            UDDrainMainQueue();
        }
    });
}

- (void)testTypingWhileFindingCostsTheEdit {
    if (![self haveJSON]) return;
    [self typeWhileFindingInDocumentOf:500];
    double small = [self typeWhileFindingInDocumentOf:2000];
    double large = [self typeWhileFindingInDocumentOf:16000];
    XCTAssertLessThan(large / small, 3.0, @"8× the document made typing while finding %.1f× slower (%.3fs → %.3fs)", large / small, small, large);
}

@end
