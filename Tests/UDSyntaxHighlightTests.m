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


/// Markdown's markup gets the theme's styles, a capture's dotted name falling
/// back to a shorter one ("markup.link.url" has its own, "markup.link.label"
/// is "markup.link"'s).
- (void)testMarkdownMarkupIsStyled {
    UDLanguageMode *md = [[UDLanguageModeRegistry sharedRegistry] modeForIdentifier:@"markdown"];
    if (!md.languageFunc) {
        XCTFail(@"%@", @"the Markdown grammar bundle did not load");
        return;
    }
    NSString *text = @"# Title\n\nSome **bold**, *em* and `code`, a [link](http://x.y).\n";
    UDTextModelTextStorage *storage = [[UDTextModelTextStorage alloc] initWithText:text];
    TreeSitterTheme *theme = [[TreeSitterTheme alloc] initWithMode:NO];
    storage.theme = theme;
    [storage setLanguageFunc:md.languageFunc withHighlightsQuery:md.highlightsQuery];
    UDDrainMainQueue();

    NSArray<NSString *> *highlights = UDHighlights(storage);
    NSString *(^span)(NSString *, NSString *) = ^NSString *(NSString *of, NSString *name) {
        NSRange r = [text rangeOfString:of];
        return [NSString stringWithFormat:@"%08lu-%08lu %@", (unsigned long)r.location, (unsigned long)NSMaxRange(r), name];
    };
    XCTAssertTrue([highlights containsObject:span(@"# Title", @"markup.heading")], @"%@", highlights);
    XCTAssertTrue([highlights containsObject:span(@"**bold**", @"markup.bold")], @"%@", highlights);
    XCTAssertTrue([highlights containsObject:span(@"*em*", @"markup.italic")], @"%@", highlights);
    XCTAssertTrue([highlights containsObject:span(@"`code`", @"markup.raw")], @"%@", highlights);
    XCTAssertTrue([highlights containsObject:span(@"link", @"markup.link.label")], @"%@", highlights);
    XCTAssertTrue([highlights containsObject:span(@"http://x.y", @"markup.link.url")], @"%@", highlights);

    NSFontTraitMask (^traits)(NSString *) = ^NSFontTraitMask(NSString *of) {
        NSFont *font = [storage attribute:NSFontAttributeName atIndex:[text rangeOfString:of].location + 2 effectiveRange:NULL];
        return [[NSFontManager sharedFontManager] traitsOfFont:font];
    };
    XCTAssertTrue(traits(@"# Title") & NSBoldFontMask);
    XCTAssertTrue(traits(@"**bold**") & NSBoldFontMask);
    XCTAssertTrue(traits(@"*em*") & NSItalicFontMask);
    NSUInteger url = [text rangeOfString:@"http://x.y"].location;
    XCTAssertNotNil([storage attribute:NSUnderlineStyleAttributeName atIndex:url effectiveRange:NULL]);
    NSUInteger label = [text rangeOfString:@"link"].location;
    XCTAssertEqualObjects([storage attribute:NSForegroundColorAttributeName atIndex:label effectiveRange:NULL],
                          [theme styleAttributesForName:@"markup.link"][NSForegroundColorAttributeName]);
}

@end
