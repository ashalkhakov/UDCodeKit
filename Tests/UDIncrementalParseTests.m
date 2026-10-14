//
//  UDIncrementalParseTests.m
//
//  Edits through the text storage, alone or several in one editing group,
//  and edits, undo and redo on the text model, leave the incrementally
//  re-parsed tree exactly as a fresh parse of the same text: every node with
//  the same type and rows/columns (folding and navigation read rows).
//

#import <XCTest/XCTest.h>
#import <tree_sitter/api.h>
#import <UDCodeKit/UDCodeKit.h>

@interface UDIncrementalParseTests : XCTestCase
@end

@implementation UDIncrementalParseTests

static void UDCollectPoints(TSNode node, NSMutableArray<NSString *> *out) {
    TSPoint s = ts_node_start_point(node), e = ts_node_end_point(node);
    [out addObject:[NSString stringWithFormat:@"%s %u:%u-%u:%u", ts_node_type(node), s.row, s.column, e.row, e.column]];
    uint32_t n = ts_node_child_count(node);
    for (uint32_t i = 0; i < n; i++) {
        UDCollectPoints(ts_node_child(node, i), out);
    }
}

static NSArray<NSString *> *UDPoints(UDTreeSitterHighlighter *highlighter) {
    NSMutableArray *points = [NSMutableArray array];
    UDCollectPoints(ts_tree_root_node((const TSTree *)highlighter.currentParseTree), points);
    return points;
}

static UDLanguageMode *UDJSONMode(void) {
    return [[UDLanguageModeRegistry sharedRegistry] modeForFileExtension:@"json"];
}

/// Long enough that the parse reuses the nodes after the edits, which is
/// where wrong points would stay.
static NSString *UDLongJSON(void) {
    NSMutableString *text = [NSMutableString stringWithString:@"{\n  \"a\": [1, 2],\n  \"b\": {\"c\": true},\n"];
    for (int i = 0; i < 200; i++) {
        [text appendFormat:@"  \"key%d\": {\"value\": [%d, %d, {\"deep\": \"text\"}]},\n", i, i, i + 1];
    }
    [text appendString:@"  \"end\": 0\n}\n"];
    return text;
}

- (void)assertTreeOf:(UDTextModelTextStorage *)storage matchesAFreshParse:(NSString *)when {
    UDLanguageMode *json = UDJSONMode();
    UDTextModelTextStorage *fresh = [[UDTextModelTextStorage alloc] initWithText:storage.string];
    [fresh setLanguageFunc:json.languageFunc withHighlightsQuery:json.highlightsQuery ?: @""];
    XCTAssertEqualObjects(UDPoints(storage.highlighter), UDPoints(fresh.highlighter),
                          @"%@: the incrementally parsed tree should match a fresh parse of:\n%@", when, storage.string);
}

- (void)testEditedTreeMatchesAFreshParse {
    UDLanguageMode *json = UDJSONMode();
    if (json.languageFunc == NULL) {
        XCTFail(@"%@", @"the JSON grammar bundle did not load");
        return;
    }
    UDTextModelTextStorage *storage = [[UDTextModelTextStorage alloc] initWithText:UDLongJSON()];
    [storage setLanguageFunc:json.languageFunc withHighlightsQuery:json.highlightsQuery ?: @""];

    // Lines inserted above, a line deleted, an edit inside a line, and two
    // edits in one editing group.
    NSArray<NSArray *> *steps = @[
        @[@0, @0, @"\n\n"],
        @[@4, @0, @"\"z\": null,\n  "],
        @[@3, @1, @""],
    ];
    for (NSArray *step in steps) {
        [storage beginEditing];
        [storage replaceCharactersInRange:NSMakeRange([step[0] unsignedIntegerValue], [step[1] unsignedIntegerValue]) withString:step[2]];
        [storage endEditing];
    }
    [storage beginEditing];
    [storage replaceCharactersInRange:NSMakeRange(storage.length - 2, 1) withString:@"\n"];
    [storage replaceCharactersInRange:NSMakeRange(2, 0) withString:@"\n"];
    [storage endEditing];
    [self assertTreeOf:storage matchesAFreshParse:@"storage edits"];
}

/// Edits made on the model — several in one call, as cursors make them —
/// and undoing and redoing them reach the tree through the model's content
/// changes, without a fresh parse.
- (void)testModelEditsUndoAndRedoMatchAFreshParse {
    UDLanguageMode *json = UDJSONMode();
    if (json.languageFunc == NULL) {
        XCTFail(@"%@", @"the JSON grammar bundle did not load");
        return;
    }
    UDTextModelTextStorage *storage = [[UDTextModelTextStorage alloc] initWithText:UDLongJSON()];
    [storage setLanguageFunc:json.languageFunc withHighlightsQuery:json.highlightsQuery ?: @""];
    UDTextModel *model = storage.textModel;
    model.undoManager = [[NSUndoManager alloc] init];
    model.undoManager.groupsByEvent = NO;

    NSArray<NSArray<UDTextModelEdit *> *> *calls = @[
        @[[[UDTextModelEdit alloc] initWithRange:PTRangeMake(2, 3, 2, 6) text:@"\"x\": [\n  true\n],\n  \"a"],
          [[UDTextModelEdit alloc] initWithRange:PTRangeMake(40, 1, 41, 1) text:@""],
          [[UDTextModelEdit alloc] initWithRange:PTRangeMake(120, 5, 120, 5) text:@"\n\n"]],
        @[[[UDTextModelEdit alloc] initWithRange:PTRangeMake(1, 2, 1, 2) text:@"\n  \"first\": {},"]],
    ];
    for (NSArray<UDTextModelEdit *> *edits in calls) {
        [model.undoManager beginUndoGrouping];
        [model applyEdits:edits];
        [model.undoManager endUndoGrouping];
        [self assertTreeOf:storage matchesAFreshParse:@"model edits"];
    }
    while (model.undoManager.canUndo) {
        [model.undoManager undo];
        [self assertTreeOf:storage matchesAFreshParse:@"undo"];
    }
    XCTAssertEqualObjects(storage.string, UDLongJSON());
    while (model.undoManager.canRedo) {
        [model.undoManager redo];
        [self assertTreeOf:storage matchesAFreshParse:@"redo"];
    }
}

/// Undo tells the layout managers what it changed — not everything from
/// the change to the end of the document.
- (void)testUndoMarksOnlyWhatItChanged {
    UDTextModelTextStorage *storage = [[UDTextModelTextStorage alloc] initWithText:UDLongJSON()];
    UDTextModel *model = storage.textModel;
    model.undoManager = [[NSUndoManager alloc] init];
    model.undoManager.groupsByEvent = NO;
    [model.undoManager beginUndoGrouping];
    [model applyEdits:@[[[UDTextModelEdit alloc] initWithRange:PTRangeMake(3, 3, 3, 6) text:@"replaced"],
                        [[UDTextModelEdit alloc] initWithRange:PTRangeMake(5, 1, 5, 1) text:@"\n"]]];
    [model.undoManager endUndoGrouping];

    __block NSRange edited = NSMakeRange(NSNotFound, 0);
    __block NSInteger delta = 0;
    id token = [[NSNotificationCenter defaultCenter] addObserverForName:NSTextStorageDidProcessEditingNotification object:storage queue:nil usingBlock:^(NSNotification *note) {
        edited = storage.editedRange;
        delta = storage.changeInLength;
    }];
    [model.undoManager undo];
    [[NSNotificationCenter defaultCenter] removeObserver:token];

    XCTAssertNotEqual(edited.location, (NSUInteger)NSNotFound, @"undo edits the storage");
    XCTAssertLessThan(edited.length, 200u, @"undo marked %@ of a %lu-character document", NSStringFromRange(edited), (unsigned long)storage.length);
    XCTAssertEqual(delta, -6);
    XCTAssertEqualObjects(storage.string, UDLongJSON());
}

@end
