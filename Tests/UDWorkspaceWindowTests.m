//
//  UDWorkspaceWindowTests.m
//
//  The workspace window, driven in-process: its XIB (navigator, editor tabs,
//  inspector), the panes keeping their widths and hiding and showing, what
//  is remembered, and the tabs, the files navigator and the inspector
//  following each other.
//

#import <XCTest/XCTest.h>
#import <UDCodeKit/UDCodeKit.h>
#import "UDDocument.h"
#import "UDDocumentWindowController.h"

static NSString * const UDSavedPanes = @"UDPaneSplit TestApp Workspace";

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
@end

@interface UDWorkspaceWindowTests : XCTestCase
@property (nonatomic, strong) UDWorkspace *workspace;
@property (nonatomic, strong) UDDocumentWindowController *controller;
@end

@implementation UDWorkspaceWindowTests

- (void)setUp {
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

    // A wider window: the editors take it.
    CGFloat editors = NSWidth([self pane:1].frame);
    [_controller.window setFrame:NSMakeRect(0, 0, 1400, 760) display:NO];
    XCTAssertEqualWithAccuracy(NSWidth([self pane:0].frame), 240, 1);
    XCTAssertEqualWithAccuracy(NSWidth([self pane:2].frame), 260, 1);
    XCTAssertGreaterThan(NSWidth([self pane:1].frame), editors + 150);

    // The navigator hidden: its room goes to the editors; shown again, at its width.
    editors = NSWidth([self pane:1].frame);
    [_controller toggleNavigator:nil];
    XCTAssertTrue([self pane:0].hidden);
    XCTAssertGreaterThan(NSWidth([self pane:1].frame), editors + 200);
    XCTAssertEqualWithAccuracy(NSMinX([self pane:1].frame), 0, 1);
    [_controller toggleNavigator:nil];
    XCTAssertFalse([self pane:0].hidden);
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
    XCTAssertTrue([self pane:2].hidden);
    [_controller close];
    [_workspace close];

    [self openWorkspace];
    XCTAssertTrue([self pane:2].hidden, @"a new window remembers the hidden inspector");
    XCTAssertFalse([self pane:0].hidden);
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
    [editor.textView insertText:@"x" replacementRange:NSMakeRange(0, 0)];
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
    [first.textView insertText:@" " replacementRange:NSMakeRange(0, 0)];
    XCTAssertEqualObjects(second.textView.string, @" {\"a\": 1}\n");
    XCTAssertTrue(tabs.items[1].dirty && tabs.items[2].dirty);
}

- (void)testTheIssuesNavigator {
    [_controller toggleNavigator:nil];
    [_controller showIssuesNavigator:nil];
    XCTAssertFalse([self pane:0].hidden, @"showing a navigator shows the pane");
    XCTAssertEqual(_controller.navigatorControl.selectedSegment, 1);
    XCTAssertEqualObjects(_controller.navigatorTabView.selectedTabViewItem.identifier, @"issues");
}

@end
