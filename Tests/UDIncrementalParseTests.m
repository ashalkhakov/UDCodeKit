//
//  UDIncrementalParseTests.m
//
//  Edits through the text storage, alone or several in one editing group,
//  leave the incrementally re-parsed tree exactly as a fresh parse of the
//  same text: every node with the same type and rows/columns (folding and
//  navigation read rows).
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

- (void)testEditedTreeMatchesAFreshParse {
    UDLanguageMode *json = [[UDLanguageModeRegistry sharedRegistry] modeForFileExtension:@"json"];
    if (json.languageFunc == NULL) {
        XCTFail(@"%@", @"the JSON grammar bundle did not load");
        return;
    }
    // Long enough that the parse reuses the nodes after the edits, which is
    // where wrong points would stay.
    NSMutableString *text = [NSMutableString stringWithString:@"{\n  \"a\": [1, 2],\n  \"b\": {\"c\": true},\n"];
    for (int i = 0; i < 200; i++) {
        [text appendFormat:@"  \"key%d\": {\"value\": [%d, %d, {\"deep\": \"text\"}]},\n", i, i, i + 1];
    }
    [text appendString:@"  \"end\": 0\n}\n"];
    UDTextModelTextStorage *storage = [[UDTextModelTextStorage alloc] initWithText:text];
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

    UDTextModelTextStorage *fresh = [[UDTextModelTextStorage alloc] initWithText:storage.string];
    [fresh setLanguageFunc:json.languageFunc withHighlightsQuery:json.highlightsQuery ?: @""];
    XCTAssertEqualObjects(UDPoints(storage.highlighter), UDPoints(fresh.highlighter),
                          @"the incrementally parsed tree should match a fresh parse of:\n%@", storage.string);
}

@end
