//
//  UDDiffEditorTests.m
//
//  The diff editor, VS Code's side by side: its diff, its lines' and
//  characters' backgrounds (its views' own, not the text's), blank space
//  that aligns the lines that correspond, scrolling together, going from
//  change to change, the original read-only; computed again after an edit.
//

#import <XCTest/XCTest.h>
#import "UDCodeTestCase.h"
#import <UDCodeKit/UDCodeKit.h>

@interface UDDiffEditorTests : UDCodeTestCase
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) UDDiffEditorViewController *diffEditor;
@property (nonatomic, strong) UDTextModelTextStorage *original;
@property (nonatomic, strong) UDTextModelTextStorage *modified;
@end

@implementation UDDiffEditorTests

- (void)tearDown {
    [_window orderOut:nil];
    _window = nil;
    _diffEditor = nil;
}

- (void)openOriginal:(NSString *)original modified:(NSString *)modified {
    _original = [[UDTextModelTextStorage alloc] initWithText:original];
    _modified = [[UDTextModelTextStorage alloc] initWithText:modified];
    _diffEditor = [[UDDiffEditorViewController alloc] initWithOriginalTextStorage:_original modifiedTextStorage:_modified];
    _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1000, 500)
                                          styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable
                                            backing:NSBackingStoreBuffered
                                              defer:NO];
    _window.releasedWhenClosed = NO;
    _window.contentView = _diffEditor.view;
    [_window makeKeyAndOrderFront:nil];
    [_window makeFirstResponder:_diffEditor.modifiedEditor.textView];
    [_diffEditor computeDiff];
}

/// "[start,end)->[start,end)" of each change.
- (NSArray<NSString *> *)changes {
    NSMutableArray *changes = [NSMutableArray array];
    for (UDDetailedLineRangeMapping *c in _diffEditor.diff.changes) {
        [changes addObject:[NSString stringWithFormat:@"[%ld,%ld)->[%ld,%ld)",
                            (long)c.original.startLineNumber, (long)c.original.endLineNumberExclusive,
                            (long)c.modified.startLineNumber, (long)c.modified.endLineNumberExclusive]];
    }
    return changes;
}

/// The top of the line fragment of @a text's first character, in the view.
static CGFloat UDTopOfText(NSTextView *view, NSString *text) {
    NSUInteger index = [view.string rangeOfString:text].location;
    NSLayoutManager *lm = view.layoutManager;
    NSUInteger glyph = [lm glyphRangeForCharacterRange:NSMakeRange(index, 1) actualCharacterRange:NULL].location;
    return NSMinY([(UDDiagnosticTextView *)view textRectOfLineFragmentForGlyphAtIndex:glyph]);
}

- (void)testItsDiffAndTheBlankSpaceThatAlignsIt {
    [self openOriginal:@"one\ntwo\nthree\nfour\n" modified:@"one\n2\nthree\nx\ny\nfour\n"];
    XCTAssertEqualObjects([self changes], (@[ @"[2,3)->[2,3)", @"[4,4)->[4,6)" ]));

    UDDiagnosticTextView *original = _diffEditor.originalEditor.textView, *modified = _diffEditor.modifiedEditor.textView;
    CGFloat lineHeight = original.lineHeight;
    XCTAssertEqualObjects(modified.viewZones, @{}, @"the longer side: none");
    XCTAssertEqual(original.viewZones.count, 1u);
    XCTAssertEqualWithAccuracy([original.viewZones[@3] doubleValue], 2 * lineHeight, 0.5, @"after three, the two lines inserted");
    XCTAssertEqualWithAccuracy(UDTopOfText(original, @"four"), UDTopOfText(modified, @"four"), 0.5, @"side by side");
    XCTAssertEqualWithAccuracy(UDTopOfText(original, @"three"), UDTopOfText(modified, @"three"), 0.5);
}

- (void)testTheDiffIsTheViewsOwnNotTheTexts {
    [self openOriginal:@"alpha\nbeta\n" modified:@"alpha\nbeta gamma\n"];
    XCTAssertEqual(_diffEditor.diff.changes.count, 1u);
    // another tab of the modified text
    UDCodeEditorViewController *other = [[UDCodeEditorViewController alloc] initWithTextStorage:_modified];
    (void)other.view;
    NSUInteger gamma = [_modified.string rangeOfString:@"gamma"].location;
    XCTAssertNil([_modified attribute:NSBackgroundColorAttributeName atIndex:gamma effectiveRange:NULL], @"not in the text's attributes");
    XCTAssertEqualObjects(other.textView.viewZones, @{});
}

- (void)testAnEditIsDiffedAgain {
    [self openOriginal:@"a\nb\nc\n" modified:@"a\nb\nc\n"];
    XCTAssertEqual(_diffEditor.diff.changes.count, 0u);
    [_modified replaceCharactersInRange:NSMakeRange(2, 1) withString:@"B"];
    UDRunUntil(_diffEditor.diff.changes.count == 1, 2.0);
    XCTAssertEqualObjects([self changes], (@[ @"[2,3)->[2,3)" ]));
}

- (void)testGoingFromChangeToChange {
    [self openOriginal:@"1\n2\n3\n4\n5\n6\n" modified:@"1\nb\n3\n4\ne\n6\n"];
    NSTextView *modified = _diffEditor.modifiedEditor.textView;
    [modified setSelectedRange:NSMakeRange(0, 0)];
    [_diffEditor goToNextChange:nil];
    XCTAssertEqual(modified.selectedRange.location, [modified.string rangeOfString:@"b"].location);
    [_diffEditor goToNextChange:nil];
    XCTAssertEqual(modified.selectedRange.location, [modified.string rangeOfString:@"e"].location);
    [_diffEditor goToNextChange:nil];
    XCTAssertEqual(modified.selectedRange.location, [modified.string rangeOfString:@"b"].location, @"round to the first");
    [_diffEditor goToPreviousChange:nil];
    XCTAssertEqual(modified.selectedRange.location, [modified.string rangeOfString:@"e"].location, @"and back to the last");
}

- (void)testTheOriginalIsReadOnly {
    [self openOriginal:@"kept\n" modified:@"kept\n"];
    UDDiagnosticTextView *original = _diffEditor.originalEditor.textView;
    XCTAssertFalse(original.isEditable);
    [_window makeFirstResponder:original];
    [original setSelectedRange:NSMakeRange(0, 0)];
    [original insertText:@"x" replacementRange:NSMakeRange(NSNotFound, 0)];
    [original deleteForward:nil];
    XCTAssertEqualObjects(_original.string, @"kept\n");
    XCTAssertEqual(_diffEditor.activeEditor, _diffEditor.originalEditor, @"the one with the focus");
}

- (void)testTheyScrollTogether {
    NSMutableString *text = [NSMutableString string];
    for (int i = 0; i < 200; i++) [text appendFormat:@"line %d\n", i];
    [self openOriginal:text modified:[text stringByReplacingOccurrencesOfString:@"line 100\n" withString:@"changed\n"]];
    NSScrollView *modified = _diffEditor.modifiedEditor.textView.enclosingScrollView;
    NSScrollView *original = _diffEditor.originalEditor.textView.enclosingScrollView;
    [modified.contentView scrollToPoint:NSMakePoint(0, 600)];
    [modified reflectScrolledClipView:modified.contentView];
    XCTAssertEqualWithAccuracy(original.contentView.bounds.origin.y, 600, 0.5);
}

@end
