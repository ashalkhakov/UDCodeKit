//
//  UDMarkdownPreviewTests.m
//
//  Markdown's Preview, in the editor's tab: the mode renders its text
//  (headings, emphasis, links against the file, lists, tables), the editor
//  shows it in place of the text and follows the text's edits, and Find and
//  going to a line bring the text back. A mode without a preview has none.
//

#import <XCTest/XCTest.h>
#import "UDCodeTestCase.h"
#import <UDCodeKit/UDCodeKit.h>

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
