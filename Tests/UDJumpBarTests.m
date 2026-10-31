//
//  UDJumpBarTests.m
//
//  Xcode's jump bar over a project's file (VS Code's breadcrumbs): the
//  project, its folders, the file, the symbols holding the caret, kept as
//  the caret moves; a folder's menu (its files, the open one checked) opens
//  a file; the symbols' menu (the file's outline, indented) goes to one.
//

#import <XCTest/XCTest.h>
#import "UDCodeTestCase.h"
#import <UDCodeKit/UDCodeKit.h>
#import "AppDelegate.h"
#import "UDDocument.h"
#import "UDDocumentWindowController.h"

@interface UDDocumentWindowController (JumpBarTesting)
@property (nonatomic, strong) UDEditorTabsController *editorTabs;
@end

@interface UDJumpBarTests : UDCodeTestCase
@property (nonatomic, copy) NSString *folder;
@end

@implementation UDJumpBarTests

- (void)setUp {
    [super setUp];
    _folder = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    NSFileManager *files = [NSFileManager defaultManager];
    [files createDirectoryAtPath:[_folder stringByAppendingPathComponent:@"Docs"] withIntermediateDirectories:YES attributes:nil error:NULL];
    _folder = UDRealPath(_folder);
    [@"# One\ntext\n## Two\nmore\n# Three\n" writeToFile:[_folder stringByAppendingPathComponent:@"Docs/a.md"]
                                               atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [@"b\n" writeToFile:[_folder stringByAppendingPathComponent:@"Docs/b.txt"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtPath:_folder error:NULL];
    [super tearDown];
}

- (UDCodeEditorViewController *)selectedEditor:(UDDocumentWindowController *)controller {
    return (UDCodeEditorViewController *)[controller.editorTabs viewControllerForItem:controller.editorTabs.selectedItem];
}

- (void)testTheJumpBar {
    AppDelegate *delegate = [[AppDelegate alloc] init];
    UDWorkspace *workspace = [delegate openFolderAtURL:[NSURL fileURLWithPath:_folder]];
    UDDocumentWindowController *controller = workspace.windowControllers.firstObject;
    NSString *a = [_folder stringByAppendingPathComponent:@"Docs/a.md"];
    [controller openURLInNewTab:[NSURL fileURLWithPath:a]];
    UDCodeEditorViewController *editor = [self selectedEditor:controller];
    XCTAssertTrue(editor.showsJumpBar);
    XCTAssertGreaterThan(NSMinY(editor.jumpBar.frame), NSMaxY([editor.textView.enclosingScrollView convertRect:editor.textView.enclosingScrollView.bounds
                                                                                                         toView:editor.view]) - 1,
                         @"over the text");

    // the caret in "Two"'s section
    NSString *text = editor.textView.string;
    [editor.textView setSelectedRange:NSMakeRange([text rangeOfString:@"more"].location, 0)];
    NSArray *titles = [editor.jumpBar.items valueForKey:@"title"];
    XCTAssertEqualObjects(titles, (@[ _folder.lastPathComponent, @"Docs", @"a.md", @"One", @"Two" ]));
    [editor.textView setSelectedRange:NSMakeRange([text rangeOfString:@"Three"].location, 0)];
    XCTAssertEqualObjects([editor.jumpBar.items.lastObject title], @"Three", @"kept as the caret moves");

    // the symbols' menu: the outline, indented, the caret's checked; one chosen
    id<UDJumpBarViewDelegate> bar = editor.jumpBar.delegate;
    NSMenu *symbols = [bar jumpBar:editor.jumpBar menuForItemAtIndex:3];
    XCTAssertEqualObjects([symbols.itemArray valueForKey:@"title"], (@[ @"One", @"Two", @"Three" ]));
    XCTAssertEqual([symbols itemAtIndex:1].indentationLevel, 1);
    XCTAssertEqual([symbols itemAtIndex:2].state, NSControlStateValueOn);
    NSMenuItem *two = [symbols itemAtIndex:1];
    [NSApp sendAction:two.action to:two.target from:two];
    XCTAssertEqual(editor.textView.selectedRange.location, [text rangeOfString:@"Two"].location, @"at its name");
    XCTAssertEqualObjects([editor.jumpBar.items.lastObject title], @"Two");

    // the file's menu: its folder's files, it checked; another opened
    NSMenu *folder = [bar jumpBar:editor.jumpBar menuForItemAtIndex:2];
    XCTAssertEqualObjects([folder.itemArray valueForKey:@"title"], (@[ @"a.md", @"b.txt" ]));
    XCTAssertEqual([folder itemAtIndex:0].state, NSControlStateValueOn);
    NSMenuItem *b = [folder itemAtIndex:1];
    [NSApp sendAction:b.action to:b.target from:b];
    XCTAssertEqualObjects(controller.editorTabs.selectedItem.title, @"b.txt");
    XCTAssertEqualObjects([[self selectedEditor:controller].jumpBar.items valueForKey:@"title"],
                          (@[ _folder.lastPathComponent, @"Docs", @"b.txt" ]), @"no symbols: the path");

    // the project's menu: its folders, each a submenu
    NSMenu *project = [bar jumpBar:editor.jumpBar menuForItemAtIndex:0];
    XCTAssertEqualObjects([project.itemArray valueForKey:@"title"], @[ @"Docs" ]);
    XCTAssertNotNil([project itemAtIndex:0].submenu);
    [controller close];
    [workspace close];
}

@end
