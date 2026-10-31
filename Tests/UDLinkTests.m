//
//  UDLinkTests.m
//
//  The text's links, VS Code's: the addresses any text has (its
//  LinkComputer: a C comment's, say), each mode's own besides (HTML's path
//  attributes, Markdown's), a link's hover saying what ⌘-click does, and a
//  link to a place in the file (a heading, an id) taking the caret there.
//

#import <XCTest/XCTest.h>
#import "UDCodeTestCase.h"
#import <UDCodeKit/UDCodeKit.h>

/// A link delegate that keeps what it is asked.
@interface UDOpenedLinks : NSObject <UDCodeEditorLinkDelegate>
@property (nonatomic, strong) NSMutableArray<NSString *> *opened;
@end

@implementation UDOpenedLinks
- (BOOL)codeEditor:(UDCodeEditorViewController *)editor openLink:(NSURL *)url editing:(BOOL)editing {
    if (!_opened) _opened = [NSMutableArray array];
    [_opened addObject:[NSString stringWithFormat:@"%@%@", url.absoluteString, editing ? @" editing" : @""]];
    return YES;
}
@end

@interface UDLinkTests : UDCodeTestCase
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) UDCodeEditorViewController *editor;
@end

@implementation UDLinkTests

- (void)tearDown {
    [_window orderOut:nil];
    _window = nil;
}

- (void)openText:(NSString *)text mode:(UDLanguageMode *)mode file:(NSString *)path {
    _editor = [[UDCodeEditorViewController alloc] initWithTextStorage:[[UDTextModelTextStorage alloc] initWithText:text]];
    [_editor configureForLanguageMode:mode];
    _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 900, 600)
                                          styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable
                                            backing:NSBackingStoreBuffered
                                              defer:NO];
    _window.releasedWhenClosed = NO;
    _window.contentView = _editor.view;
    [_window makeKeyAndOrderFront:nil];
    [_window makeFirstResponder:_editor.textView];
    _editor.previewBaseURL = [NSURL fileURLWithPath:path];
}

/// "text url" of each link, in order.
static NSArray<NSString *> *UDFound(NSArray<NSDictionary *> *links, NSString *text) {
    NSMutableArray<NSString *> *found = [NSMutableArray array];
    for (NSDictionary *link in links) {
        NSString *url = [UDCodeTestCase tmpURLsWrittenAsUnix:[link[UDLinkURLKey] absoluteString]];
        [found addObject:[NSString stringWithFormat:@"%@ %@", [text substringWithRange:[link[UDLinkRangeKey] rangeValue]], url]];
    }
    return found;
}

- (void)testAnyTextsAddressesAreLinks {
    NSString *text = @"// see https://example.com/a/b?q=1, (http://x.org/p) and <file:///tmp/f.txt>.\n"
                     @"/* ftp://no.org HTTPS://Up.org/x; [https://e.com/] */\n";
    // (lowercase: GNUstep's NSURL writes HTTPS: as Https:)
    XCTAssertEqualObjects([UDFound([UDLinkComputer linksInText:text], text) valueForKey:@"lowercaseString"],
                          (@[ @"https://example.com/a/b?q=1 https://example.com/a/b?q=1",
                              @"http://x.org/p http://x.org/p",
                              @"file:///tmp/f.txt file:///tmp/f.txt",
                              @"https://up.org/x https://up.org/x",
                              @"https://e.com/ https://e.com/" ]),
                          @"as VS Code's LinkComputer finds them");
}

/// A C comment's address: underlined, its hover says ⌘-click, followed.
- (void)testACommentsAddressIsFollowed {
    UDLanguageMode *c = [[UDLanguageModeRegistry sharedRegistry] modeForIdentifier:@"c"];
    NSString *text = @"/* See https://example.com/spec for it. */\nint x;\n";
    [self openText:text mode:c file:@"/tmp/src/x.c"];
    UDOpenedLinks *links = [[UDOpenedLinks alloc] init];
    _editor.linkDelegate = links;
    NSTextView *view = _editor.textView;
    NSUInteger at = [text rangeOfString:@"example"].location;
    XCTAssertNotNil([view.textStorage attribute:NSUnderlineStyleAttributeName atIndex:at effectiveRange:NULL]);

    NSString *hover = nil;
    for (UDIntervalNode *node in [((UDTextModelTextStorage *)view.textStorage).textModel decorationNodesInOffsetRange:(NSInteger)at end:(NSInteger)at + 1]) {
        if ([node.owner isEqualToString:UDLinkDecorationOwner]) hover = node.options.hoverMessage;
    }
    XCTAssertEqualObjects(hover, @"Follow link (⌘-click)");

    [UDCodeTestCase clickTextView:view atIndex:at command:YES];
    XCTAssertEqualObjects(links.opened, (@[ @"https://example.com/spec editing" ]));
}

- (void)testHTMLsPathAttributesAreLinks {
    UDLanguageMode *html = [[UDLanguageModeRegistry sharedRegistry] modeForIdentifier:@"html"];
    XCTAssertNotNil(html, @"the HTML bundle loaded");
    NSURL *file = [NSURL fileURLWithPath:@"/tmp/site/index.html"];
    NSString *text = @"<html>\n<link rel=\"stylesheet\" href=\"css/a.css\">\n"
                     @"<body><a href=\"#part\">here</a> <a href='../up.html?x=1#y'>up</a>\n"
                     @"  <img src=p.png> <a href=\"javascript:go()\">no</a> <a href=\"mailto:a@b.c\">no</a>\n"
                     @"  <p id=\"part\">it</p> <a href=\"https://example.com/\">web</a> <a title=\"t.html\">no</a>\n"
                     @"</body></html>\n";
    XCTAssertEqualObjects(UDFound([html linksInText:text baseURL:file], text),
                          (@[ @"css/a.css file:///tmp/site/css/a.css",
                              @"#part file:///tmp/site/index.html#5,9",
                              @"../up.html?x=1#y file:///tmp/up.html",
                              @"p.png file:///tmp/site/p.png",
                              @"https://example.com/ https://example.com/" ]),
                          @"as VS Code's HTML finds them: an id's, its place");

    NSString *based = @"<head><base href=\"https://example.com/docs/\"></head><a href=\"x.html\">x</a>\n";
    XCTAssertEqualObjects(UDFound([html linksInText:based baseURL:file], based),
                          (@[ @"x.html https://example.com/docs/x.html" ]), @"against <base href>");
}

/// [a](#heading): its line, as VS Code's Markdown has it; ⌘-click, the
/// caret there.
- (void)testAHeadingOfThisFileIsItsLine {
    UDLanguageMode *markdown = [[UDLanguageModeRegistry sharedRegistry] modeForIdentifier:@"markdown"];
    if (!markdown.hasPreview) {
        XCTFail(@"%@", @"the Markdown bundle did not load");
        return;
    }
    NSURL *file = [NSURL fileURLWithPath:@"/tmp/notes/README.md"];
    NSString *text = @"# Top\n\nSee [start](#getting-started), [top](README.md#top), [no](#nowhere).\n\n"
                     @"## Getting *Started*\n\nhere\n";
    XCTAssertEqualObjects(UDFound([markdown linksInText:text baseURL:file], text),
                          (@[ @"#getting-started file:///tmp/notes/README.md#L5",
                              @"README.md#top file:///tmp/notes/README.md#L1",
                              @"#nowhere file:///tmp/notes/README.md#nowhere" ]));

    [self openText:text mode:markdown file:file.path];
    UDOpenedLinks *links = [[UDOpenedLinks alloc] init];
    _editor.linkDelegate = links;
    [UDCodeTestCase clickTextView:_editor.textView atIndex:[text rangeOfString:@"#getting"].location + 2 command:YES];
    XCTAssertNil(links.opened, @"this file's: not another's to open");
    XCTAssertEqual(_editor.textView.selectedRange.location, [text rangeOfString:@"## Getting"].location);
    XCTAssertEqual(_editor.textView.selectedRange.length, 0u);
}

@end
