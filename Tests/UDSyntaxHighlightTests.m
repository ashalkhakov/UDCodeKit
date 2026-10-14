//
//  UDSyntaxHighlightTests.m
//
//  The highlights the syntax highlighter keeps up to date edit by edit —
//  replacing only what the parse changed — are the highlights a fresh
//  highlight of the same text gives.
//

#import <XCTest/XCTest.h>
#import "UDCodeTestCase.h"
#import <UDCodeKit/UDCodeKit.h>

static void UDDrainMainQueue(void) {
    // The main queue runs in order: once a block queued now has run, so has
    // everything queued before it. Three rounds, for what those queue.
    for (int round = 0; round < 3; round++) {
        __block BOOL reached = NO;
        dispatch_async(dispatch_get_main_queue(), ^{ reached = YES; });
        while (!reached) [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
}

/// Every highlight decoration as "offset-offset class", sorted.
static NSArray<NSString *> *UDHighlights(UDTextModelTextStorage *storage) {
    UDTextModel *model = storage.textModel;
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    for (UDIntervalNode *node in [model decorationNodesInOffsetRange:0 end:[model getLength]]) {
        if (![node.owner isEqualToString:UDHighlightDecorationOwner]) continue;
        [out addObject:[NSString stringWithFormat:@"%08ld-%08ld %@", (long)node.start, (long)node.end, node.options.className]];
    }
    return [out sortedArrayUsingSelector:@selector(compare:)];
}

@interface UDSyntaxHighlightTests : UDCodeTestCase
@end

@implementation UDSyntaxHighlightTests

- (UDTextModelTextStorage *)storageWithText:(NSString *)text {
    UDLanguageMode *json = [[UDLanguageModeRegistry sharedRegistry] modeForFileExtension:@"json"];
    UDTextModelTextStorage *storage = [[UDTextModelTextStorage alloc] initWithText:text];
    [storage setLanguageFunc:json.languageFunc withHighlightsQuery:json.highlightsQuery ?: @""];
    UDDrainMainQueue();
    return storage;
}

- (void)assertHighlightsOf:(UDTextModelTextStorage *)storage areFresh:(NSString *)when {
    UDDrainMainQueue();
    NSArray *kept = UDHighlights(storage);
    NSArray *fresh = UDHighlights([self storageWithText:storage.string]);
    XCTAssertGreaterThan(fresh.count, 0u);
    XCTAssertEqualObjects(kept, fresh, @"%@: the highlights kept up to date should be a fresh highlight's", when);
}

/// idScript, through its bundle: the class each piece of a script gets.
- (void)testAnIdScriptIsHighlighted {
    UDLanguageMode *mode = [[UDLanguageModeRegistry sharedRegistry] modeForFileExtension:@"script"];
    if (!mode.languageFunc) {
        XCTFail(@"%@", @"the idScript grammar bundle did not load");
        return;
    }
    NSString *text = @"void lamp::flicker( float times ) {\n"
                     @"\twhile ( times > 0 ) { $lamp_1.setColor( '1 0.5 0' ); times--; }\n"
                     @"}\n";
    UDTextModelTextStorage *storage = [[UDTextModelTextStorage alloc] initWithText:text];
    [storage setLanguageFunc:mode.languageFunc withHighlightsQuery:mode.highlightsQuery ?: @""];
    UDDrainMainQueue();
    NSMutableDictionary<NSString *, NSString *> *classOf = [NSMutableDictionary dictionary];
    for (NSString *highlight in UDHighlights(storage)) {
        NSArray<NSString *> *parts = [highlight componentsSeparatedByString:@" "];
        NSArray<NSString *> *range = [parts[0] componentsSeparatedByString:@"-"];
        NSInteger start = range[0].integerValue, end = range[1].integerValue;
        classOf[[text substringWithRange:NSMakeRange((NSUInteger)start, (NSUInteger)(end - start))]] = parts[1];
    }
    XCTAssertEqualObjects(classOf[@"void"], @"type.builtin");
    XCTAssertEqualObjects(classOf[@"lamp"], @"type");
    XCTAssertEqualObjects(classOf[@"flicker"], @"function");
    XCTAssertEqualObjects(classOf[@"times"], @"variable.parameter");
    XCTAssertEqualObjects(classOf[@"while"], @"keyword.control");
    XCTAssertEqualObjects(classOf[@"lamp_1"], @"variable.builtin");
    XCTAssertEqualObjects(classOf[@"setColor"], @"function.method");
    XCTAssertEqualObjects(classOf[@"'1 0.5 0'"], @"constant");
}

- (void)testHighlightsFollowEditsUndoAndRedo {
    if (![[UDLanguageModeRegistry sharedRegistry] modeForFileExtension:@"json"].languageFunc) {
        XCTFail(@"%@", @"the JSON grammar bundle did not load");
        return;
    }
    NSMutableString *text = [NSMutableString stringWithString:@"{\n"];
    for (int i = 0; i < 300; i++) {
        [text appendFormat:@"  \"key%d\": {\"value\": [%d, true, null], \"name\": \"entry\"},\n", i, i];
    }
    [text appendString:@"  \"end\": 0\n}\n"];
    UDTextModelTextStorage *storage = [self storageWithText:text];
    UDTextModel *model = storage.textModel;
    model.undoManager = [[NSUndoManager alloc] init];
    model.undoManager.groupsByEvent = NO;

    // Typing through the storage: a string opened (everything after it
    // re-highlights) and closed again.
    [model.undoManager beginUndoGrouping];
    [storage replaceCharactersInRange:NSMakeRange(20, 0) withString:@"\""];
    [model.undoManager endUndoGrouping];
    [self assertHighlightsOf:storage areFresh:@"open a string"];
    [model.undoManager beginUndoGrouping];
    [storage replaceCharactersInRange:NSMakeRange(20, 1) withString:@""];
    [model.undoManager endUndoGrouping];
    [self assertHighlightsOf:storage areFresh:@"close it"];

    // Edits far apart in one call, as cursors make them: the text between
    // them keeps its highlights. They keep the JSON valid: in text with
    // errors tree-sitter's incremental parse need not give the tree a fresh
    // parse does (error recovery is not local), so the highlights need not
    // agree either.
    NSArray *calls = @[
        @[[[UDTextModelEdit alloc] initWithRange:PTRangeMake(3, 25, 3, 29) text:@"\"quoted\""],
          [[UDTextModelEdit alloc] initWithRange:PTRangeMake(290, 3, 290, 3) text:@"\"new\": false, "]],
        @[[[UDTextModelEdit alloc] initWithRange:PTRangeMake(10, 1, 12, 1) text:@""],
          [[UDTextModelEdit alloc] initWithRange:PTRangeMake(200, 24, 200, 27) text:@"1234"]],
    ];
    for (NSArray *edits in calls) {
        [model.undoManager beginUndoGrouping];
        [model applyEdits:edits];
        [model.undoManager endUndoGrouping];
        [self assertHighlightsOf:storage areFresh:@"edits far apart"];
    }
    while (model.undoManager.canUndo) {
        [model.undoManager undo];
        [self assertHighlightsOf:storage areFresh:@"undo"];
    }
    while (model.undoManager.canRedo) {
        [model.undoManager redo];
        [self assertHighlightsOf:storage areFresh:@"redo"];
    }
}

@end
