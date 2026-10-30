//
//  UDMarkdownPreviewTests.m
//
//  Markdown's Preview, in the editor's tab: the mode renders its text
//  (headings, emphasis, links against the file, lists, tables), the editor
//  shows it in place of the text and follows the text's edits, and Find and
//  going to a line bring the text back; its links are followed (a heading
//  of its own, another file through the link delegate, read or ⌘ edited). A
//  mode without a preview has none.
//

#import <XCTest/XCTest.h>
#import "UDCodeTestCase.h"
#import <UDCodeKit/UDCodeKit.h>

/// A link delegate that keeps what it is asked.
@interface UDLinkRecorder : NSObject <UDCodeEditorLinkDelegate>
@property (nonatomic, strong) NSMutableArray<NSString *> *followed;
@end

@implementation UDLinkRecorder
- (BOOL)codeEditor:(UDCodeEditorViewController *)editor openLink:(NSURL *)url editing:(BOOL)editing {
    if (!_followed) _followed = [NSMutableArray array];
    [_followed addObject:[NSString stringWithFormat:@"%@%@", url.lastPathComponent, editing ? @" editing" : @""]];
    return YES;
}
@end

@interface UDMarkdownPreviewTests : UDCodeTestCase
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) UDCodeEditorViewController *editor;
@property (nonatomic, strong) UDTextModelTextStorage *storage;
@property (nonatomic, strong) UDLanguageMode *markdown;
@end

@implementation UDMarkdownPreviewTests

- (void)setUp {
    [super setUp];
    _markdown = [[UDLanguageModeRegistry sharedRegistry] modeForIdentifier:@"markdown"];
}

- (void)tearDown {
    [_window orderOut:nil];
    _window = nil;
}

- (void)openText:(NSString *)text mode:(UDLanguageMode *)mode {
    _storage = [[UDTextModelTextStorage alloc] initWithText:text];
    _editor = [[UDCodeEditorViewController alloc] initWithTextStorage:_storage];
    [_editor configureForLanguageMode:mode];
    _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 900, 600)
                                          styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable
                                            backing:NSBackingStoreBuffered
                                              defer:NO];
    _window.releasedWhenClosed = NO;
    _window.contentView = _editor.view;
    [_window orderFront:nil];
    [_window makeFirstResponder:_editor.textView];
}

- (void)testMarkdownRendersAsItReads {
    XCTAssertTrue(_markdown.hasPreview, @"Markdown's bundle renders it");
    NSURL *file = [NSURL fileURLWithPath:@"/tmp/notes/README.md"];
    NSAttributedString *preview =
        [_markdown previewOfText:@"# Title\n\nSome **bold** and a [link](other.md).\n\n- one\n- [x] done\n\n"
                                  @"| a | b |\n|---|--:|\n| 1 | 2 |\n"
                         baseURL:file];
    NSString *text = preview.string;
    XCTAssertTrue([text hasPrefix:@"Title\n"], @"the heading, without its marker: %@", text);
    XCTAssertTrue([text containsString:@"Some bold and a link."], @"%@", text);
    XCTAssertTrue([text containsString:@"•\tone"], @"%@", text);
    XCTAssertTrue([text containsString:@"☑\tdone"], @"%@", text);
    XCTAssertTrue([text containsString:@"\ta\tb\n\t1\t2"], @"%@", text);

    NSFont *heading = [preview attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL];
    NSFont *body = [preview attribute:NSFontAttributeName atIndex:[text rangeOfString:@"Some"].location effectiveRange:NULL];
    XCTAssertGreaterThan(heading.pointSize, body.pointSize);
    NSFont *bold = [preview attribute:NSFontAttributeName atIndex:[text rangeOfString:@"bold"].location effectiveRange:NULL];
    XCTAssertTrue([[NSFontManager sharedFontManager] traitsOfFont:bold] & NSBoldFontMask);
    NSURL *link = [preview attribute:NSLinkAttributeName atIndex:[text rangeOfString:@"link"].location effectiveRange:NULL];
    XCTAssertEqualObjects(link.path, @"/tmp/notes/other.md", @"a relative link, against the file");
    XCTAssertEqualObjects([preview attribute:UDPreviewAnchorAttributeName atIndex:0 effectiveRange:NULL], @"title");
}

- (void)testHeadingsHaveGitHubsAnchors {
    NSAttributedString *preview = [_markdown previewOfText:@"# Getting Started!\n\n## Notes\n\n## Notes\n" baseURL:nil];
    NSMutableArray<NSString *> *anchors = [NSMutableArray array];
    NSRange range = NSMakeRange(0, 0);
    for (NSUInteger at = 0; at < preview.length; at = NSMaxRange(range)) {
        id value = [preview attribute:UDPreviewAnchorAttributeName atIndex:at effectiveRange:&range];
        if (value) [anchors addObject:value];
    }
    XCTAssertEqualObjects(anchors, (@[ @"getting-started", @"notes", @"notes-1" ]));
}

- (void)testLinksAreFollowed {
    if (!_markdown.hasPreview) {
        XCTFail(@"%@", @"the Markdown bundle did not load");
        return;
    }
    NSMutableString *text = [NSMutableString stringWithString:@"# Top\n\nSee [below](#far-down) and [other](other.md#part).\n\n"];
    for (int i = 0; i < 200; i++) [text appendFormat:@"Paragraph %d.\n\n", i];
    [text appendString:@"## Far down\n\nthe end\n"];
    [self openText:text mode:_markdown];
    UDLinkRecorder *recorder = [[UDLinkRecorder alloc] init];
    _editor.linkDelegate = recorder;
    _editor.previewBaseURL = [NSURL fileURLWithPath:@"/tmp/notes/README.md"];
    _editor.showsPreview = YES;
    NSTextView *preview = _editor.previewTextView;

    // its own heading: scrolled to, in the preview
    NSUInteger far = [preview.string rangeOfString:@"Far down"].location;
    XCTAssertFalse(NSLocationInRange(far, [preview.layoutManager characterRangeForGlyphRange:
        [preview.layoutManager glyphRangeForBoundingRect:preview.visibleRect inTextContainer:preview.textContainer]
                                                                            actualGlyphRange:NULL]));
    [_editor followPreviewLink:[NSURL URLWithString:@"README.md#far-down" relativeToURL:_editor.previewBaseURL] editing:NO];
    NSRange visible = [preview.layoutManager characterRangeForGlyphRange:
        [preview.layoutManager glyphRangeForBoundingRect:preview.visibleRect inTextContainer:preview.textContainer]
                                                        actualGlyphRange:NULL];
    XCTAssertTrue(NSLocationInRange(far, visible), @"scrolled to its heading");
    XCTAssertTrue(_editor.showsPreview);
    XCTAssertFalse([_editor revealPreviewAnchor:@"nowhere"]);
    XCTAssertNil(recorder.followed, @"its own: not the delegate's");

    // another file: the delegate's, read or edited
    NSURL *other = [NSURL URLWithString:@"other.md#part" relativeToURL:_editor.previewBaseURL];
    [_editor followPreviewLink:other editing:NO];
    [_editor followPreviewLink:other editing:YES];
    XCTAssertEqualObjects(recorder.followed, (@[ @"other.md", @"other.md editing" ]));

    // the link as clicked: to the delegate
    NSUInteger link = [preview.string rangeOfString:@"other"].location;
    XCTAssertTrue([preview.delegate textView:preview clickedOnLink:[preview.textStorage attribute:NSLinkAttributeName atIndex:link effectiveRange:NULL]
                                     atIndex:link]);
    XCTAssertEqualObjects(recorder.followed.lastObject, @"other.md");
    NSString *tip = [preview.textStorage attribute:NSToolTipAttributeName atIndex:link effectiveRange:NULL];
    XCTAssertTrue([tip containsString:@"⌘-click to edit"], @"%@", tip);

    // ⌘ on its own: its text, to edit
    [_editor followPreviewLink:[NSURL URLWithString:@"README.md#far-down" relativeToURL:_editor.previewBaseURL] editing:YES];
    XCTAssertFalse(_editor.showsPreview);
    XCTAssertEqualObjects(_window.firstResponder, _editor.textView);
}

- (void)testPlainTextHasNoPreview {
    UDLanguageMode *c = [[UDLanguageModeRegistry sharedRegistry] modeForIdentifier:@"c"];
    XCTAssertFalse(c.hasPreview);
    [self openText:@"int x;\n" mode:c];
    XCTAssertFalse(_editor.canShowPreview);
    _editor.showsPreview = YES;
    XCTAssertFalse(_editor.showsPreview, @"nothing to show");
}

- (void)testThePreviewTakesTheTextsPlaceInTheTab {
    if (!_markdown.hasPreview) {
        XCTFail(@"%@", @"the Markdown bundle did not load");
        return;
    }
    [self openText:@"# Notes\n\nfirst\n" mode:_markdown];
    XCTAssertTrue(_editor.canShowPreview);
    __block NSUInteger posted = 0;
    id observer = [[NSNotificationCenter defaultCenter] addObserverForName:UDCodeEditorPreviewDidChangeNotification
                                                                    object:_editor queue:nil
                                                                usingBlock:^(NSNotification *note) { posted++; }];

    [_editor togglePreview:nil];
    XCTAssertTrue(_editor.showsPreview);
    XCTAssertEqual(posted, 1u);
    NSTextView *preview = _editor.previewTextView;
    XCTAssertFalse([preview.enclosingScrollView isHidden]);
    XCTAssertFalse(preview.isEditable);
    XCTAssertTrue([_editor.textView.enclosingScrollView isHiddenOrHasHiddenAncestor], @"the text is behind it");
    XCTAssertEqualObjects(_window.firstResponder, preview, @"the focus goes with it");
    XCTAssertEqualObjects(preview.string, @"Notes\nfirst");

    // an edit (another tab's, say): the preview follows, a moment later
    [_storage replaceCharactersInRange:NSMakeRange(_storage.length, 0) withString:@"second *line*\n"];
    UDRunUntil([preview.string containsString:@"second line"], 2.0);
    XCTAssertEqualObjects(preview.string, @"Notes\nfirst second line");

    [_editor togglePreview:nil];
    XCTAssertFalse(_editor.showsPreview);
    XCTAssertEqual(posted, 2u);
    XCTAssertTrue([preview.enclosingScrollView isHidden]);
    XCTAssertFalse([_editor.textView.enclosingScrollView isHiddenOrHasHiddenAncestor]);
    XCTAssertEqualObjects(_window.firstResponder, _editor.textView);
    [[NSNotificationCenter defaultCenter] removeObserver:observer];
}

- (void)testFindAndGoingToALineBringTheTextBack {
    if (!_markdown.hasPreview) {
        XCTFail(@"%@", @"the Markdown bundle did not load");
        return;
    }
    [self openText:@"# Notes\n\nfirst\nsecond\n" mode:_markdown];
    _editor.showsPreview = YES;
    [_editor showFindBarReplacing:NO];
    XCTAssertFalse(_editor.showsPreview, @"Find is the text's");
    XCTAssertTrue(_editor.isFindBarVisible);

    _editor.showsPreview = YES;
    [_editor selectLine:3];
    XCTAssertFalse(_editor.showsPreview, @"an issue's line, say");
    XCTAssertEqualObjects([_storage.string substringWithRange:_editor.textView.selectedRange], @"first");
}

- (void)testTheMenuItemSaysWhatItDoes {
    [self openText:@"text\n" mode:_markdown];
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"" action:@selector(togglePreview:) keyEquivalent:@""];
    XCTAssertEqual([_editor validateMenuItem:item], _markdown.hasPreview);
    XCTAssertEqualObjects(item.title, @"Show Preview");
    _editor.showsPreview = YES;
    [_editor validateMenuItem:item];
    XCTAssertEqualObjects(item.title, _markdown.hasPreview ? @"Hide Preview" : @"Show Preview");
}

@end
