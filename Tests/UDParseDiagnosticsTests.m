//
//  UDParseDiagnosticsTests.m
//
//  The parse errors an editor session keeps up to date edit by edit — the
//  error highlighters walking only what changed, the collector reading their
//  decorations — are the ones a fresh session on the same text finds.
//

#import <XCTest/XCTest.h>
#import "UDCodeTestCase.h"
#import <UDCodeKit/UDCodeKit.h>

/// Runs what the edits left for the run loop's next turn (the highlighters'
/// updates): a marker scheduled after them has run once they have. Three
/// rounds, for what those schedule. Each pass of the run loop is told not to
/// wait: it runs what is due.
static void UDDrainMainQueue(void) {
    for (int round = 0; round < 3; round++) {
        NSMutableArray *reached = [NSMutableArray array];
        [reached performSelector:@selector(addObject:) withObject:@YES afterDelay:0];
        while (reached.count == 0) [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate date]];
    }
}

static NSArray<NSString *> *UDParseErrors(UDEditorSession *session) {
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    for (UDDiagnosticItem *item in session.document.diagnosticStore.allDiagnostics) {
        if (![item.source isEqualToString:UDDiagnosticSourceParser]) continue;
        [out addObject:[NSString stringWithFormat:@"%ld:%ld %@", (long)item.line, (long)item.column, item.message]];
    }
    return out;
}

@interface UDParseDiagnosticsTests : UDCodeTestCase
@end

@implementation UDParseDiagnosticsTests

- (UDEditorSession *)sessionWithText:(NSString *)text {
    UDCodeDocument *document = [[UDCodeDocument alloc] initWithText:text fileURL:[NSURL fileURLWithPath:@"/tmp/errors.json"]];
    UDEditorSession *session = [[UDEditorSession alloc] initWithDocument:document];
    [session activateWithTheme:nil];
    UDDrainMainQueue();
    return session;
}

- (void)assertErrorsOf:(UDEditorSession *)session areFresh:(NSString *)when expectingSome:(BOOL)some {
    UDDrainMainQueue();
    NSArray *kept = UDParseErrors(session);
    NSArray *fresh = UDParseErrors([self sessionWithText:[session.document.textModel getValue]]);
    XCTAssertEqual(fresh.count > 0, some, @"%@: %@", when, fresh);
    XCTAssertEqualObjects(kept, fresh, @"%@: the errors kept up to date should be a fresh session's", when);
}

- (void)testParseErrorsFollowEditsUndoAndRedo {
    if (![[UDLanguageModeRegistry sharedRegistry] modeForFileExtension:@"json"].languageFunc) {
        XCTFail(@"%@", @"the JSON grammar bundle did not load");
        return;
    }
    NSMutableString *text = [NSMutableString stringWithString:@"{\n"];
    for (int i = 0; i < 100; i++) {
        [text appendFormat:@"  \"key%d\": {\"value\": [%d, true, null]},\n", i, i];
    }
    [text appendString:@"  \"end\": 0\n}\n"];
    UDEditorSession *session = [self sessionWithText:text];
    UDTextModel *model = session.document.textModel;
    model.undoManager = [[NSUndoManager alloc] init];
    model.undoManager.groupsByEvent = NO;
    [self assertErrorsOf:session areFresh:@"valid" expectingSome:NO];

    // An array's comma goes: an error there.
    NSArray *steps = @[
        @[@[[[UDTextModelEdit alloc] initWithRange:PTRangeMake(20, 25, 20, 26) text:@""]], @YES, @"a comma deleted"],
        // Another, far away, while the first stays.
        @[@[[[UDTextModelEdit alloc] initWithRange:PTRangeMake(80, 25, 80, 25) text:@" 7"]], @YES, @"a value without a comma"],
        // Typing elsewhere, in a string: the errors stay where they are.
        @[@[[[UDTextModelEdit alloc] initWithRange:PTRangeMake(50, 6, 50, 6) text:@"abc"]], @YES, @"typing between them"],
        // Lines inserted above both: they move down.
        @[@[[[UDTextModelEdit alloc] initWithRange:PTRangeMake(2, 1, 2, 1) text:@"  \"new\": 1,\n  \"newer\": 2,\n"]], @YES, @"lines above"],
        // A bracket opened and never closed: recovery reaches far.
        @[@[[[UDTextModelEdit alloc] initWithRange:PTRangeMake(40, 13, 40, 13) text:@"["]], @YES, @"an open bracket"],
        @[@[[[UDTextModelEdit alloc] initWithRange:PTRangeMake(40, 13, 40, 14) text:@""]], @YES, @"closed again"],
        @[@[[[UDTextModelEdit alloc] initWithRange:PTRangeMake(60, 3, 60, 3) text:@"{"]], @YES, @"a brace in a key"],
        @[@[[[UDTextModelEdit alloc] initWithRange:PTRangeMake(60, 3, 60, 4) text:@""]], @YES, @"the brace gone"],
        // Both fixed in one call.
        @[@[[[UDTextModelEdit alloc] initWithRange:PTRangeMake(22, 25, 22, 25) text:@","],
            [[UDTextModelEdit alloc] initWithRange:PTRangeMake(82, 25, 82, 27) text:@""]], @NO, @"both fixed"],
    ];
    for (NSArray *step in steps) {
        [model.undoManager beginUndoGrouping];
        [model applyEdits:step[0]];
        [model.undoManager endUndoGrouping];
        [self assertErrorsOf:session areFresh:step[2] expectingSome:[step[1] boolValue]];
    }
    for (NSInteger i = (NSInteger)steps.count - 1; i >= 0; i--) {
        [model.undoManager undo];
        BOOL some = i > 0;
        [self assertErrorsOf:session areFresh:[NSString stringWithFormat:@"undoing %@", steps[(NSUInteger)i][2]] expectingSome:some];
    }
    XCTAssertEqualObjects([model getValue], text);
    for (NSArray *step in steps) {
        [model.undoManager redo];
        [self assertErrorsOf:session areFresh:[@"redoing " stringByAppendingString:step[2]] expectingSome:[step[1] boolValue]];
    }
}

@end
