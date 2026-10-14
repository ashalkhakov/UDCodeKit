//
//  UDFoldingTests.m
//
//  Folding answers for the lines asked about — walking only the tree over
//  them — what a walk of the whole tree finds; folds follow edits and go
//  when their region does.
//

#import <XCTest/XCTest.h>
#import <tree_sitter/api.h>
#import <UDCodeKit/UDCodeKit.h>

/// The reference: every node in the tree, as the folding controller once
/// walked them — lines where a multi-line object or array opens.
static void UDCollectFoldable(TSNode node, NSMutableIndexSet *out) {
    uint32_t n = ts_node_child_count(node);
    const char *type = ts_node_type(node);
    if (ts_node_end_point(node).row > ts_node_start_point(node).row && n >= 2 &&
        (!strcmp(type, "object") || !strcmp(type, "array")) &&
        ts_node_start_byte(ts_node_child(node, n - 1)) > ts_node_end_byte(ts_node_child(node, 0))) {
        [out addIndex:ts_node_start_point(ts_node_child(node, 0)).row + 1];
    }
    for (uint32_t i = 0; i < n; i++) UDCollectFoldable(ts_node_child(node, i), out);
}

@interface UDFoldingTests : XCTestCase
@end

@implementation UDFoldingTests

- (UDTextModelTextStorage *)storageWithText:(NSString *)text {
    UDLanguageMode *json = [[UDLanguageModeRegistry sharedRegistry] modeForFileExtension:@"json"];
    UDTextModelTextStorage *storage = [[UDTextModelTextStorage alloc] initWithText:text];
    [storage setLanguageFunc:json.languageFunc withHighlightsQuery:json.highlightsQuery ?: @""];
    return storage;
}

- (NSString *)document {
    NSMutableString *text = [NSMutableString stringWithString:@"{\n"];
    for (int i = 0; i < 60; i++) {
        if (i % 3 == 0) [text appendFormat:@"  \"key%d\": {\n    \"list\": [\n      %d,\n      true\n    ], \"x\": [1, 2]\n  },\n", i, i];
        else [text appendFormat:@"  \"key%d\": {\"value\": [%d, true]},\n", i, i];
    }
    [text appendString:@"  \"end\": 0\n}\n"];
    return text;
}

- (void)testFoldableLinesMatchAWalkOfTheWholeTree {
    if (![[UDLanguageModeRegistry sharedRegistry] modeForFileExtension:@"json"].languageFunc) {
        XCTFail(@"%@", @"the JSON grammar bundle did not load");
        return;
    }
    UDTextModelTextStorage *storage = [self storageWithText:[self document]];
    UDFoldingController *folding = [[UDFoldingController alloc] initWithTextView:[[NSTextView alloc] init]
                                                                      textStorage:storage
                                                                      highlighter:storage.highlighter];
    NSMutableIndexSet *all = [NSMutableIndexSet indexSet];
    UDCollectFoldable(ts_tree_root_node((const TSTree *)storage.highlighter.currentParseTree), all);
    NSUInteger lines = (NSUInteger)[storage.textModel getLineCount];
    XCTAssertGreaterThan(all.count, 20u);
    XCTAssertEqualObjects([folding foldableLinesInRange:NSMakeRange(1, lines)], all);
    for (NSUInteger first = 1; first <= lines; first += 7) {
        for (NSUInteger count = 1; count <= 40; count += 13) {
            NSIndexSet *expected = [all indexesInRange:NSMakeRange(first, count) options:0 passingTest:^BOOL(NSUInteger i, BOOL *stop) { return YES; }];
            XCTAssertEqualObjects([folding foldableLinesInRange:NSMakeRange(first, count)], expected,
                                  @"lines %lu to %lu", (unsigned long)first, (unsigned long)(first + count - 1));
        }
    }
}

- (void)testFoldsFollowEditsAndGoWithTheirRegion {
    if (![[UDLanguageModeRegistry sharedRegistry] modeForFileExtension:@"json"].languageFunc) {
        XCTFail(@"%@", @"the JSON grammar bundle did not load");
        return;
    }
    UDTextModelTextStorage *storage = [self storageWithText:[self document]];
    UDTextModel *model = storage.textModel;
    UDFoldingController *folding = [[UDFoldingController alloc] initWithTextView:[[NSTextView alloc] init]
                                                                      textStorage:storage
                                                                      highlighter:storage.highlighter];
    NSRange everything = NSMakeRange(1, (NSUInteger)[model getLineCount] + 10);

    // key0's object opens on line 2 and its list on line 3 (lines 2-7);
    // key1 and key2 take a line each; key3's object opens on line 10.
    [folding toggleFoldAtLine:3];
    [folding toggleFoldAtLine:10];
    NSMutableIndexSet *expected = [NSMutableIndexSet indexSetWithIndex:3];
    [expected addIndex:10];
    XCTAssertEqualObjects([folding foldedLinesInRange:everything], expected);

    // Lines inserted above both: the folds move down with their regions.
    [storage replaceCharactersInRange:NSMakeRange(2, 0) withString:@"  \"a\": 1,\n  \"b\": 2,\n"];
    [folding update];
    expected = [NSMutableIndexSet indexSetWithIndex:5];
    [expected addIndex:12];
    XCTAssertEqualObjects([folding foldedLinesInRange:everything], expected);

    // The second fold's object loses its closing brace: its region is gone,
    // and so is the fold; the first stays.
    NSInteger closing = [model getOffsetAt:17 column:3];
    XCTAssertEqualObjects([model getValueInRange:PTRangeMake(17, 3, 17, 4)], @"}");
    [storage replaceCharactersInRange:NSMakeRange((NSUInteger)closing, 1) withString:@""];
    [folding update];
    XCTAssertEqualObjects([folding foldedLinesInRange:everything], [NSIndexSet indexSetWithIndex:5]);

    // Unfolding.
    [folding toggleFoldAtLine:5];
    XCTAssertEqual([folding foldedLinesInRange:everything].count, 0u);
}

@end
