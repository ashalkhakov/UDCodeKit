//
//  UDWorkspaceWindowTests.m
//
//  The workspace window, driven in-process: its XIB (navigator, editor tabs,
//  inspector), the panes keeping their widths and hiding and showing, what
//  is remembered, and the tabs, the files navigator and the inspector
//  following each other.
//

#import <XCTest/XCTest.h>
#import "UDCodeTestCase.h"
#import <UDCodeKit/UDCodeKit.h>
#import "UDDocument.h"
#import "UDDocumentWindowController.h"

static NSString * const UDSavedPanes = @"UDPaneSplit UDCode Workspace";

@interface UDDocumentWindowController (Testing)
@property (nonatomic, strong) UDPaneSplitController  *paneSplit;
@property (nonatomic, strong) UDEditorTabsController *editorTabs;
@property (nonatomic, weak) NSSegmentedControl *navigatorControl;
@property (nonatomic, weak) NSTabView          *navigatorTabView;
@property (nonatomic, weak) NSTableView        *filesTable;
@property (nonatomic, weak) NSView             *issuesHost;
@property (nonatomic, weak) NSTextField        *inspectorName;
@property (nonatomic, weak) NSTextField        *inspectorLanguage;
@property (nonatomic, weak) NSTextField        *inspectorLines;
- (IBAction)toggleNavigator:(id)sender;
- (IBAction)toggleInspector:(id)sender;
- (IBAction)showIssuesNavigator:(id)sender;
- (IBAction)closeEditorTab:(id)sender;
- (BOOL)codeEditor:(UDCodeEditorViewController *)editor openLink:(NSURL *)url editing:(BOOL)editing;
@end

@interface UDWorkspaceWindowTests : UDCodeTestCase
@property (nonatomic, strong) UDWorkspace *workspace;
@property (nonatomic, strong) UDDocumentWindowController *controller;
@end

@implementation UDWorkspaceWindowTests

- (void)setUp {
    [super setUp];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:UDSavedPanes];
    [self openWorkspace];
}

- (void)tearDown {
    [_controller close];
    [_workspace close];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:UDSavedPanes];
}

- (void)openWorkspace {
    _workspace = [[UDWorkspace alloc] init];
    [_workspace makeWindowControllers];
    _controller = (UDDocumentWindowController *)_workspace.windowControllers.firstObject;
    [_controller.window setFrame:NSMakeRect(0, 0, 1200, 760) display:NO];
    [_controller showWindow:nil];
}

- (NSView *)pane:(NSInteger)i {
    return _controller.paneSplit.splitView.subviews[(NSUInteger)i];
}

- (void)testTheWindowLoadsFromItsXIB {
    for (NSString *outlet in @[@"paneSplit", @"editorTabs", @"navigatorControl", @"navigatorTabView", @"filesTable",
                               @"issuesHost", @"inspectorName", @"inspectorLanguage", @"inspectorLines"]) {
        XCTAssertNotNil([_controller valueForKey:outlet], @"%@ is connected in UDDocumentWindowController.xib", outlet);
    }
    XCTAssertEqual(_controller.paneSplit.splitView.subviews.count, 3u);
    XCTAssertNotNil(_controller.editorTabs.tabBar);
    XCTAssertNotNil(_controller.editorTabs.tabView);
    XCTAssertEqual(_controller.issuesHost.subviews.count, 1u, @"the issues navigator fills its host");
    XCTAssertEqual(_controller.editorTabs.items.count, 1u, @"a new workspace opens one tab");
}

- (void)testSidePanesKeepTheirWidthsAndHide {
    XCTAssertEqualWithAccuracy(NSWidth([self pane:0].frame), 240, 1);
    XCTAssertEqualWithAccuracy(NSWidth([self pane:2].frame), 260, 1);

    // A wider window: the editors take it. As wide as the screen lets it be:
    // Windows keeps a window within its screen (CI's is 1024 wide).
    [_controller.window setFrame:NSMakeRect(0, 0, 900, 760) display:NO];
    CGFloat editors = NSWidth([self pane:1].frame);
    CGFloat wider = MIN(1400, NSWidth([NSScreen mainScreen].frame));
    [_controller.window setFrame:NSMakeRect(0, 0, wider, 760) display:NO];
    XCTAssertEqualWithAccuracy(NSWidth([self pane:0].frame), 240, 1);
    XCTAssertEqualWithAccuracy(NSWidth([self pane:2].frame), 260, 1);
    XCTAssertEqualWithAccuracy(NSWidth([self pane:1].frame), editors + (wider - 900), 2);

    // The navigator hidden: its room goes to the editors; shown again, at its width.
    editors = NSWidth([self pane:1].frame);
    [_controller toggleNavigator:nil];
    XCTAssertTrue([[self pane:0] isHidden]);
    XCTAssertGreaterThan(NSWidth([self pane:1].frame), editors + 200);
    XCTAssertEqualWithAccuracy(NSMinX([self pane:1].frame), 0, 1);
    [_controller toggleNavigator:nil];
    XCTAssertFalse([[self pane:0] isHidden]);
    XCTAssertEqualWithAccuracy(NSWidth([self pane:0].frame), 240, 1);

    // The panes never squeeze the editors below their minimum.
    [_controller.window setFrame:NSMakeRect(0, 0, 720, 760) display:NO];
    XCTAssertGreaterThanOrEqual(NSWidth([self pane:1].frame), 319);

    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"" action:@selector(toggleInspector:) keyEquivalent:@""];
    [_controller validateMenuItem:item];
    XCTAssertEqualObjects(item.title, @"Hide Inspector");
}

- (void)testPaneVisibilityIsRemembered {
    [_controller toggleInspector:nil];
    XCTAssertTrue([[self pane:2] isHidden]);
    [_controller close];
    [_workspace close];

    [self openWorkspace];
    XCTAssertTrue([[self pane:2] isHidden], @"a new window remembers the hidden inspector");
    XCTAssertFalse([[self pane:0] isHidden]);
    [_controller toggleInspector:nil];
    XCTAssertEqualWithAccuracy(NSWidth([self pane:2].frame), 260, 1);
}

- (void)testTabsTheFilesNavigatorAndTheInspectorFollowEachOther {
    UDEditorTabsController *tabs = _controller.editorTabs;
    [_controller addEditorTab:nil];
    [_controller addEditorTab:nil];
    XCTAssertEqual(tabs.items.count, 3u);
    XCTAssertEqual(tabs.tabBar.items.count, 3u);
    XCTAssertEqual(tabs.tabView.numberOfTabViewItems, 3);
    XCTAssertEqual(_controller.filesTable.numberOfRows, 3);
    XCTAssertEqual(tabs.selectedItem, tabs.items.lastObject, @"a new tab is selected");
    XCTAssertEqual(_controller.filesTable.selectedRow, 2);

    // Choosing a file selects its tab, and the inspector shows it.
    [_controller.filesTable selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    XCTAssertEqual(tabs.selectedItem, tabs.items.firstObject);
    XCTAssertEqualObjects(_controller.inspectorLanguage.stringValue, @"JSON");

    // Typing marks the tab dirty.
    UDCodeEditorViewController *editor = (UDCodeEditorViewController *)[tabs viewControllerForItem:tabs.selectedItem];
    XCTAssertFalse(tabs.selectedItem.dirty);
    editor.textView.selectedRange = NSMakeRange(0, 0);
    [editor.textView insertText:@"x"];
    XCTAssertTrue(tabs.selectedItem.dirty);

    // An untouched tab closes without asking; its file leaves the navigator.
    [tabs selectItem:tabs.items.lastObject];
    [_controller closeEditorTab:nil];
    XCTAssertEqual(tabs.items.count, 2u);
    XCTAssertEqual(_controller.filesTable.numberOfRows, 2);
    XCTAssertEqual(tabs.selectedItem, tabs.items.lastObject, @"the neighbour is selected");
}

- (void)testAFileOpenTwiceSharesItsText {
    NSURL *url = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:@"twice.json"];
    [@"{\"a\": 1}\n" writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [_controller openURLInNewTab:url];
    [_controller openURLInNewTab:url];
    UDEditorTabsController *tabs = _controller.editorTabs;
    XCTAssertEqual(tabs.items.count, 3u);
    XCTAssertEqual(_controller.filesTable.numberOfRows, 2, @"one file, two tabs");
    UDCodeEditorViewController *first = (UDCodeEditorViewController *)[tabs viewControllerForItem:tabs.items[1]];
    UDCodeEditorViewController *second = (UDCodeEditorViewController *)[tabs viewControllerForItem:tabs.items[2]];
    XCTAssertEqual(first.textView.textStorage, second.textView.textStorage);
    first.textView.selectedRange = NSMakeRange(0, 0);
    [first.textView insertText:@" "];
    XCTAssertEqualObjects(second.textView.string, @" {\"a\": 1}\n");
    XCTAssertTrue(tabs.items[1].dirty && tabs.items[2].dirty);
}

/// A Markdown file's preview links to another: a click reads it (its tab,
/// in Preview, at the heading), ⌘-click edits it (the same tab, its text).
- (void)testAPreviewsLinkOpensTheOtherFileToReadOrEdit {
    if (![[UDLanguageModeRegistry sharedRegistry] modeForIdentifier:@"markdown"].hasPreview) {
        XCTFail(@"%@", @"the Markdown bundle did not load");
        return;
    }
    NSURL *folder = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
                     URLByAppendingPathComponent:[@"UDLinks-" stringByAppendingString:[NSUUID UUID].UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:NULL];
    NSURL *a = [folder URLByAppendingPathComponent:@"a.md"], *b = [folder URLByAppendingPathComponent:@"b.md"];
    [@"# A\n\nSee [b](b.md#two).\n" writeToURL:a atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    NSMutableString *bText = [NSMutableString stringWithString:@"# One\n\n"];
    for (int i = 0; i < 200; i++) [bText appendFormat:@"Paragraph %d.\n\n", i];
    [bText appendString:@"## Two\n\nhere\n"];
    [bText writeToURL:b atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    NSData *png = [NSData dataWithBytes:"\x89PNG\r\n\x1a\n\0\0\0\0" length:12];
    [png writeToURL:[folder URLByAppendingPathComponent:@"pic.png"] atomically:YES];

    UDEditorTabsController *tabs = _controller.editorTabs;
    [_controller openURLInNewTab:a];
    UDCodeEditorViewController *aEditor = (UDCodeEditorViewController *)[tabs viewControllerForItem:tabs.selectedItem];
    aEditor.showsPreview = YES;
    NSUInteger count = tabs.items.count;

    [aEditor followPreviewLink:[NSURL URLWithString:@"b.md#two" relativeToURL:a] editing:NO];
    XCTAssertEqual(tabs.items.count, count + 1, @"b in a tab of its own");
    UDCodeEditorViewController *bEditor = (UDCodeEditorViewController *)[tabs viewControllerForItem:tabs.selectedItem];
    XCTAssertEqualObjects(((UDCodeDocument *)tabs.selectedItem.representedObject).fileURL.lastPathComponent, @"b.md");
    XCTAssertTrue(bEditor.showsPreview, @"to read");
    XCTAssertEqualObjects(_controller.window.firstResponder, bEditor.previewTextView);
    NSTextView *preview = bEditor.previewTextView;
    NSRange visible = [preview.layoutManager characterRangeForGlyphRange:
        [preview.layoutManager glyphRangeForBoundingRect:preview.visibleRect inTextContainer:preview.textContainer]
                                                        actualGlyphRange:NULL];
    XCTAssertTrue(NSLocationInRange([preview.string rangeOfString:@"Two"].location, visible), @"at its heading");

    [tabs selectItem:tabs.items[count - 1]];
    [aEditor followPreviewLink:[NSURL URLWithString:@"b.md" relativeToURL:a] editing:YES];
    XCTAssertEqual(tabs.items.count, count + 1, @"b's tab again");
    XCTAssertEqual([tabs viewControllerForItem:tabs.selectedItem], bEditor);
    XCTAssertFalse(bEditor.showsPreview, @"to edit");
    XCTAssertEqualObjects(_controller.window.firstResponder, bEditor.textView);

    // not ours to open: an image (the default app's), a file not there
    XCTAssertFalse([_controller codeEditor:aEditor openLink:[folder URLByAppendingPathComponent:@"pic.png"] editing:NO]);
    XCTAssertFalse([_controller codeEditor:aEditor openLink:[NSURL URLWithString:@"https://example.com/"] editing:NO]);
    XCTAssertTrue([_controller codeEditor:aEditor openLink:[folder URLByAppendingPathComponent:@"none.md"] editing:NO],
                  @"nothing there: a beep, not the browser");
    XCTAssertEqual(tabs.items.count, count + 1);
    [[NSFileManager defaultManager] removeItemAtURL:folder error:NULL];
}

- (void)testTheIssuesNavigator {
    [_controller toggleNavigator:nil];
    [_controller showIssuesNavigator:nil];
    XCTAssertFalse([[self pane:0] isHidden], @"showing a navigator shows the pane");
    XCTAssertEqual(_controller.navigatorControl.selectedSegment, 2);
    XCTAssertEqualObjects(_controller.navigatorTabView.selectedTabViewItem.identifier, @"issues");
}

#ifdef __APPLE__
/// File > Open takes any text file, SVG, and what the system has no type
/// for (NORMA's .orm), as a single-tab workspace; a workspace stays one.
/// (On GNUstep the Text Document type's extension is "*".)
- (void)testOpenTakesAnyTextFile {
    NSDocumentController *controller = [NSDocumentController sharedDocumentController];
    NSString *dir = NSTemporaryDirectory();
    for (NSString *name in @[ @"page.xhtml", @"logo.svg", @"model.orm", @"notes.txt", @"data.json", @"my.udworkspace" ]) {
        NSURL *url = [NSURL fileURLWithPath:[dir stringByAppendingPathComponent:name]];
        NSString *text = [name hasSuffix:@"udworkspace"] ? @"{\"version\":1,\"openFiles\":[]}" : @"<a/>";
        XCTAssertTrue([text writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
        NSError *error = nil;
        NSString *type = [controller typeForContentsOfURL:url error:&error];
        XCTAssertNotNil(type, @"%@: %@", name, error);
        XCTAssertEqual([controller documentClassForType:type], [UDWorkspace class], @"%@ (%@)", name, type);
        [[NSFileManager defaultManager] removeItemAtURL:url error:NULL];
    }
}
#endif

@end
