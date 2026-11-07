//
//  UDProjectSystemTests.m
//
//  An extension's project system, as VS Code's are its extensions' (C# Dev
//  Kit's Solution Explorer): active in a window whose folder has its marker
//  (workspaceContains:), its tree in a navigator of its own (UDTreeView),
//  its items documents of a URL scheme of its own (UDFileSystemProvider),
//  opened, edited, saved and read again through it.
//

#import <XCTest/XCTest.h>
#import "UDCodeTestCase.h"
#import <UDCodeKit/UDCodeKit.h>
#import "AppDelegate.h"
#import "UDDocument.h"
#import "UDDocumentWindowController.h"

@interface UDDocumentWindowController (ProjectSystemTesting)
@property (nonatomic, strong) UDEditorTabsController *editorTabs;
@property (nonatomic, weak) NSSegmentedControl *navigatorControl;
@property (nonatomic, weak) NSTextField *inspectorPath;
- (IBAction)saveDocument:(id)sender;
@end

/// A project system's items: decls by type ("material/a"), each a document
/// of a udproj: URL; what is written to one kept.
@interface UDProjectTestProvider : NSObject <UDFileSystemProvider, UDTreeDataProvider>
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *texts;   // path → text
@property (nonatomic, strong) NSMutableArray<NSURL *> *written;
@property (nonatomic, strong) NSMenu *menu;
@property (nonatomic, copy) NSArray *menuElements;
@property (nonatomic, copy) NSString *filter;
/// What a skin's command was sent for (it opens nothing).
@property (nonatomic, strong, nullable) id previewed;
@end

@implementation UDProjectTestProvider

- (instancetype)init {
    self = [super init];
    _texts = [@{ @"/material/a": @"textures/a { diffusemap a.tga }\n",
                 @"/material/b": @"textures/b { }\n",
                 @"/skin/c": @"skin c { }\n" } mutableCopy];
    _written = [NSMutableArray array];
    _menu = [[NSMenu alloc] initWithTitle:@""];
    [_menu addItemWithTitle:@"Reveal in Pak" action:@selector(revealInPak:) keyEquivalent:@""];
    _filter = @"";
    return self;
}

- (void)revealInPak:(id)sender {}

- (void)previewSkin:(UDTreeViewController *)sender {
    _previewed = sender.chosenElement;
}

- (NSData *)contentsOfURL:(NSURL *)url error:(NSError **)error {
    NSString *text = _texts[url.path];
    if (!text && error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadNoSuchFileError userInfo:nil];
    return [text dataUsingEncoding:NSUTF8StringEncoding];
}

- (BOOL)writeContents:(NSData *)data toURL:(NSURL *)url error:(NSError **)error {
    _texts[url.path] = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    [_written addObject:url];
    return YES;
}

- (NSString *)languageModeOfURL:(NSURL *)url {
    return @"json";
}

- (NSString *)displayNameOfURL:(NSURL *)url {
    return [url.path substringFromIndex:1];
}

// The tree: types ("material", "skin"), then their decls (paths).
- (NSArray *)treeView:(UDTreeViewController *)treeView childrenOfElement:(id)element {
    NSMutableOrderedSet *found = [NSMutableOrderedSet orderedSet];
    for (NSString *path in [_texts.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        NSString *type = path.pathComponents[1];
        if (!element) [found addObject:type];
        else if ([type isEqualToString:element] && (!_filter.length || [path containsString:_filter])) [found addObject:path];
    }
    return found.array;
}

- (UDTreeItem *)treeView:(UDTreeViewController *)treeView itemForElement:(NSString *)element {
    BOOL type = ![element hasPrefix:@"/"];
    UDTreeItem *item = [UDTreeItem itemWithLabel:type ? element : element.lastPathComponent];
    item.collapsibleState = type ? ([element isEqualToString:@"material"] ? UDTreeItemCollapsibleStateExpanded
                                                                         : UDTreeItemCollapsibleStateCollapsed)
                                 : UDTreeItemCollapsibleStateNone;
    if (!type) {
        item.resourceURL = [NSURL URLWithString:[@"udproj:" stringByAppendingString:element]];
        item.detail = @"pak000";
        // a material opens (VS Code's vscode.open); a skin is previewed
        if ([element hasPrefix:@"/material/"]) {
            item.action = @selector(openResource:);
        } else {
            item.target = self;
            item.action = @selector(previewSkin:);
        }
    }
    return item;
}

- (id)treeView:(UDTreeViewController *)treeView parentOfElement:(NSString *)element {
    return [element hasPrefix:@"/"] ? element.pathComponents[1] : nil;
}

- (NSMenu *)treeView:(UDTreeViewController *)treeView menuForElements:(NSArray *)elements {
    _menuElements = elements;
    return _menu;
}

- (void)treeView:(UDTreeViewController *)treeView filterDidChange:(NSString *)filter {
    _filter = filter;
    [treeView refresh];
}

@end

/// The extension: active where a folder has a .udprojtest; its tree the
/// navigator, its provider the udproj: scheme's.
@interface UDProjectTestExtension : NSObject <UDExtension>
@property (nonatomic, strong) UDProjectTestProvider *provider;
@property (nonatomic, strong, nullable) UDTreeViewController *tree;
@end

@implementation UDProjectTestExtension
- (void)extensionDidLoad:(NSBundle *)bundle {}
- (void)extensionWillUnload:(NSBundle *)bundle {}
- (const void *)languageFuncForIdentifier:(NSString *)identifier { return NULL; }
- (NSViewController *)navigatorViewControllerForWorkbench:(id<UDWorkbench>)workbench {
    _provider = [[UDProjectTestProvider alloc] init];
    _tree = [[UDTreeViewController alloc] initWithDataProvider:_provider workbench:workbench title:@"Decls"];
    return _tree;
}
- (id<UDFileSystemProvider>)workbench:(id<UDWorkbench>)workbench fileSystemProviderForScheme:(NSString *)scheme {
    return [scheme isEqualToString:@"udproj"] ? _provider : nil;
}
@end

/// An extension that brings nothing: what is active, and where.
@interface UDProjectTestBareExtension : NSObject <UDExtension>
@end

@implementation UDProjectTestBareExtension
- (void)extensionDidLoad:(NSBundle *)bundle {}
- (void)extensionWillUnload:(NSBundle *)bundle {}
- (const void *)languageFuncForIdentifier:(NSString *)identifier { return NULL; }
@end

static UDProjectTestExtension *UDProjectTestExtensionShared;

@interface UDProjectSystemTests : UDCodeTestCase
@end

@implementation UDProjectSystemTests {
    NSString *_folder;
    AppDelegate *_delegate;
    UDWorkspace *_workspace;
    UDDocumentWindowController *_controller;
}

+ (void)setUp {
    [super setUp];
    if (UDProjectTestExtensionShared) return;
    UDProjectTestExtensionShared = [[UDProjectTestExtension alloc] init];
    [[UDLanguageModeRegistry sharedRegistry] registerExtension:UDProjectTestExtensionShared
                                              activationEvents:@[ @"workspaceContains:*.udprojtest" ]];
}

- (void)setUp {
    [super setUp];
    _folder = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:[_folder stringByAppendingPathComponent:@"sub/deeper"]
                              withIntermediateDirectories:YES attributes:nil error:NULL];
    _folder = UDRealPath(_folder);
    _delegate = [[AppDelegate alloc] init];
}

- (void)tearDown {
    [_controller close];
    [_workspace close];
    UDProjectTestExtensionShared.tree = nil;
    [[NSFileManager defaultManager] removeItemAtPath:_folder error:NULL];
    [super tearDown];
}

- (void)write:(NSString *)name {
    [@"{}" writeToFile:[_folder stringByAppendingPathComponent:name] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}

- (void)openWindow {
    _workspace = [_delegate openFolderAtURL:[NSURL fileURLWithPath:_folder]];
    _controller = _workspace.windowControllers.firstObject;
    [_controller.window setFrame:NSMakeRect(0, 0, 1200, 760) display:NO];
}

- (UDTreeViewController *)tree {
    return UDProjectTestExtensionShared.tree;
}

- (NSArray<NSString *> *)rowLabels {
    NSMutableArray *labels = [NSMutableArray array];
    NSOutlineView *outline = self.tree.outlineView;
    for (NSInteger row = 0; row < outline.numberOfRows; row++) {
        [labels addObject:[outline.dataSource outlineView:outline objectValueForTableColumn:outline.tableColumns[0]
                                                   byItem:[outline itemAtRow:row]]];
    }
    return labels;
}

- (NSInteger)rowOf:(NSString *)label {
    return (NSInteger)[self.rowLabels indexOfObject:label];
}

// ---------------------------------------------------------------------------

- (void)testAnExtensionIsActiveWhereItsFolderHasItsMarker {
    UDLanguageModeRegistry *registry = [UDLanguageModeRegistry sharedRegistry];
    NSURL *folder = [NSURL fileURLWithPath:_folder];
    XCTAssertFalse([[registry extensionsActiveInFolder:folder] containsObject:UDProjectTestExtensionShared]);
    XCTAssertFalse([[registry extensionsActiveInFolder:nil] containsObject:UDProjectTestExtensionShared], @"a window of files alone");
    [self write:@"sub/deeper/mod.udprojtest"];
    XCTAssertFalse([[registry extensionsActiveInFolder:folder] containsObject:UDProjectTestExtensionShared], @"*: the top only");
    [self write:@"mod.udprojtest"];
    XCTAssertTrue([[registry extensionsActiveInFolder:folder] containsObject:UDProjectTestExtensionShared]);

    // anywhere, a subfolder's, and always; one with no events, always
    id<UDExtension> anywhere = [[UDProjectTestBareExtension alloc] init];
    id<UDExtension> nested = [[UDProjectTestBareExtension alloc] init];
    id<UDExtension> always = [[UDProjectTestBareExtension alloc] init];
    id<UDExtension> plain = [[UDProjectTestBareExtension alloc] init];
    [registry registerExtension:anywhere activationEvents:@[ @"onLanguage:json", @"workspaceContains:**/*.udprojtest" ]];
    [registry registerExtension:nested activationEvents:@[ @"workspaceContains:sub/*/mod.udproj?est" ]];
    [registry registerExtension:always activationEvents:@[ @"*" ]];
    [registry registerExtension:plain];
    [[NSFileManager defaultManager] removeItemAtPath:[_folder stringByAppendingPathComponent:@"mod.udprojtest"] error:NULL];
    NSArray *active = [registry extensionsActiveInFolder:folder];
    XCTAssertTrue([active containsObject:anywhere]);
    XCTAssertTrue([active containsObject:nested]);
    XCTAssertTrue([active containsObject:always]);
    XCTAssertTrue([active containsObject:plain]);
    XCTAssertFalse([active containsObject:UDProjectTestExtensionShared]);
    NSArray *alone = [registry extensionsActiveInFolder:nil];
    XCTAssertFalse([alone containsObject:anywhere]);
    XCTAssertTrue([alone containsObject:always]);
    XCTAssertTrue([alone containsObject:plain]);
}

- (void)testAWindowHasTheTreeOfAnActiveProjectSystem {
    [self openWindow];
    NSInteger without = _controller.navigatorControl.segmentCount;
    XCTAssertNil(self.tree, @"no marker: not asked");
    [_controller close];
    [_workspace close];

    [self write:@"mod.udprojtest"];
    [self openWindow];
    XCTAssertNotNil(self.tree);
    XCTAssertEqual(_controller.navigatorControl.segmentCount, without + 1, @"a segment of its own");
    XCTAssertEqualObjects([_controller.navigatorControl.cell toolTipForSegment:without], @"Decls");
    [(id<UDWorkbench>)_controller showNavigatorOfExtension:UDProjectTestExtensionShared];
    XCTAssertNotNil(self.tree.view.window, @"shown in the navigator");
}

- (void)testTheTreeViewLoadsAndIsConnected {
    UDProjectTestProvider *provider = [[UDProjectTestProvider alloc] init];
    UDTreeViewController *tree = [[UDTreeViewController alloc] initWithDataProvider:provider workbench:nil title:@"Decls"];
    XCTAssertNotNil(tree.view, @"UDTreeView.xib");
    XCTAssertNotNil(tree.outlineView);
    XCTAssertEqual(tree.outlineView.dataSource, (id)tree);
    XCTAssertEqual(tree.outlineView.delegate, (id)tree);
    XCTAssertEqualObjects(NSStringFromSelector(tree.outlineView.doubleAction), @"chooseSelectedElement:");
    XCTAssertNotNil(tree.filterField);
    XCTAssertEqualObjects(NSStringFromSelector(tree.filterField.action), @"filterChanged:");
    XCTAssertFalse(tree.filterField.isHidden, @"the provider filters");
    XCTAssertEqualObjects(tree.title, @"Decls");
}

- (void)testTheTreeShowsWhatItsProviderGives {
    [self write:@"mod.udprojtest"];
    [self openWindow];
    UDTreeViewController *tree = self.tree;
    [tree refresh];
    XCTAssertEqualObjects(self.rowLabels, (@[ @"material", @"a", @"b", @"skin" ]), @"material shown open, skin closed");
    [tree.outlineView expandItem:[tree.outlineView itemAtRow:[self rowOf:@"skin"]]];
    [tree.outlineView collapseItem:[tree.outlineView itemAtRow:[self rowOf:@"material"]]];
    XCTAssertEqualObjects(self.rowLabels, (@[ @"material", @"skin", @"c" ]));

    // refreshed: what was open stays open, what was selected selected
    [tree.outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)[self rowOf:@"c"]] byExtendingSelection:NO];
    UDProjectTestExtensionShared.provider.texts[@"/skin/d"] = @"skin d { }\n";
    [tree refresh];
    XCTAssertEqualObjects(self.rowLabels, (@[ @"material", @"skin", @"c", @"d" ]));
    XCTAssertEqualObjects(tree.selectedElements, @[ @"/skin/c" ]);
    [tree refreshElement:@"material"];
    XCTAssertEqualObjects(self.rowLabels, (@[ @"material", @"skin", @"c", @"d" ]), @"closed, as the user left it");

    // revealed: its type opened, it selected
    XCTAssertTrue([tree revealElement:@"/material/b"]);
    XCTAssertEqualObjects(tree.selectedElements, @[ @"/material/b" ]);
    XCTAssertFalse([tree revealElement:@"/material/none"]);

    // the row's image and detail, the provider's
    NSTableColumn *column = tree.outlineView.tableColumns[0];
    UDBadgeTextFieldCell *cell = [column.dataCell copy];
    [tree outlineView:tree.outlineView willDisplayCell:cell forTableColumn:tree.outlineView.tableColumns[0]
                 item:[tree.outlineView itemAtRow:[self rowOf:@"b"]]];
    XCTAssertEqualObjects(cell.badge, @"pak000");

    // filtered
    tree.filterField.stringValue = @"/a";
    [tree filterChanged:tree.filterField];
    XCTAssertEqualObjects(self.rowLabels, (@[ @"material", @"a", @"skin" ]));
}

- (void)testTheTreesMenuIsItsProvidersForWhatWasClicked {
    [self write:@"mod.udprojtest"];
    [self openWindow];
    [_controller showWindow:nil];
    [(id<UDWorkbench>)_controller showNavigatorOfExtension:UDProjectTestExtensionShared];
    UDTreeViewController *tree = self.tree;
    UDProjectTestProvider *provider = UDProjectTestExtensionShared.provider;
    [tree refresh];
    NSMenu *menu = tree.outlineView.menu;
    XCTAssertNotNil(menu);
    XCTAssertEqual(menu.delegate, (id)tree);
    [tree.outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)[self rowOf:@"a"]] byExtendingSelection:NO];
    [tree.outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)[self rowOf:@"b"]] byExtendingSelection:YES];

    // a right click on a row, the application's current event (no clicked
    // row outside a click's tracking: the row under its point)
    NSRect rect = [tree.outlineView rectOfRow:[self rowOf:@"a"]];
    NSPoint point = [tree.outlineView convertPoint:NSMakePoint(NSMidX(rect), NSMidY(rect)) toView:nil];
    NSEvent *click = [NSEvent mouseEventWithType:NSEventTypeRightMouseDown location:point modifierFlags:0 timestamp:0
                                    windowNumber:tree.view.window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
    [NSApp postEvent:click atStart:YES];
    NSEvent *current = [NSApp nextEventMatchingMask:NSUIntegerMax untilDate:[NSDate dateWithTimeIntervalSinceNow:1]
                                             inMode:NSDefaultRunLoopMode dequeue:YES];
    XCTAssertNotNil(current);
    XCTAssertEqual([NSApp currentEvent], current);
    [tree menuNeedsUpdate:menu];
    NSMenuItem *item = menu.itemArray.firstObject;
    XCTAssertEqualObjects(item.title, @"Reveal in Pak");
    XCTAssertEqualObjects(NSStringFromSelector(item.action), @"revealInPak:");
    XCTAssertEqualObjects(provider.menuElements, (@[ @"/material/a", @"/material/b" ]), @"a click in the selection: the selection");
    XCTAssertEqual(provider.menu.numberOfItems, 1, @"the provider's menu left as it was");

    // a click outside it: the one clicked
    rect = [tree.outlineView rectOfRow:[self rowOf:@"skin"]];
    point = [tree.outlineView convertPoint:NSMakePoint(NSMidX(rect), NSMidY(rect)) toView:nil];
    click = [NSEvent mouseEventWithType:NSEventTypeRightMouseDown location:point modifierFlags:0 timestamp:0
                           windowNumber:tree.view.window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
    [NSApp postEvent:click atStart:YES];
    [NSApp nextEventMatchingMask:NSUIntegerMax untilDate:[NSDate dateWithTimeIntervalSinceNow:1]
                          inMode:NSDefaultRunLoopMode dequeue:YES];
    [tree menuNeedsUpdate:menu];
    XCTAssertEqualObjects(provider.menuElements, @[ @"skin" ]);
    XCTAssertEqual(menu.numberOfItems, 1, @"filled afresh");
}

- (void)testAnItemsDocumentIsOpenedEditedAndSavedThroughItsProvider {
    [self write:@"mod.udprojtest"];
    [self openWindow];
    UDTreeViewController *tree = self.tree;
    UDProjectTestProvider *provider = UDProjectTestExtensionShared.provider;
    [tree refresh];
    NSUInteger tabs = _controller.editorTabs.items.count;
    // chosen in the tree: its URL opened in a tab
    [tree.outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)[self rowOf:@"a"]] byExtendingSelection:NO];
    XCTAssertEqual(_controller.editorTabs.items.count, tabs + 1);
    UDCodeDocument *document = [(id<UDWorkbench>)_controller selectedDocument];
    NSURL *a = [NSURL URLWithString:@"udproj:/material/a"];
    XCTAssertEqualObjects(document.URL, a);
    XCTAssertNil(document.fileURL, @"not a file: no language server, source control or file watcher for it");
    XCTAssertEqual(document.fileSystemProvider, (id)provider);
    XCTAssertEqualObjects(document.displayName, @"material/a", @"the provider's name for it");
    XCTAssertEqualObjects(_controller.editorTabs.selectedItem.title, @"material/a");
    XCTAssertEqualObjects(document.languageMode.identifier, @"json", @"the provider's mode");
    XCTAssertEqualObjects([document.textModel getValue], provider.texts[@"/material/a"]);
    XCTAssertEqualObjects(_controller.editorTabs.selectedItem.toolTip, @"udproj:/material/a");

    // shown again: the same tab
    [(id<UDWorkbench>)_controller showURL:a];
    XCTAssertEqual(_controller.editorTabs.items.count, tabs + 1);

    // edited and saved: written through the provider, as it is
    [document.textModel applyEdits:@[ [[UDTextModelEdit alloc] initWithRange:PTRangeMake(1, 1, 1, 1) text:@"// edited\n"] ]];
    XCTAssertTrue(document.isModified);
    XCTAssertTrue(_controller.editorTabs.selectedItem.dirty);
    [_controller saveDocument:nil];
    XCTAssertEqualObjects(provider.written, @[ a ]);
    XCTAssertEqualObjects(provider.texts[@"/material/a"], @"// edited\ntextures/a { diffusemap a.tga }\n");
    XCTAssertFalse(document.isModified);
    XCTAssertFalse(_controller.editorTabs.selectedItem.dirty);

    // changed by the provider: read again
    provider.texts[@"/material/a"] = @"textures/a { }\n";
    [[NSNotificationCenter defaultCenter] postNotificationName:UDFileSystemProviderDidChangeFilesNotification object:provider
                                                      userInfo:@{ UDFileSystemProviderChangedURLsKey: @[ a ] }];
    XCTAssertEqualObjects([document.textModel getValue], @"textures/a { }\n");
    XCTAssertFalse(document.isModified);

    // a skin's command, its provider's: nothing opened, it told the element
    [tree.outlineView expandItem:[tree.outlineView itemAtRow:[self rowOf:@"skin"]]];
    [tree.outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)[self rowOf:@"c"]] byExtendingSelection:NO];
    XCTAssertEqualObjects(provider.previewed, @"/skin/c");
    XCTAssertNil(tree.chosenElement, @"only while its command is sent");
    XCTAssertEqual(_controller.editorTabs.items.count, tabs + 1);

    // a type has no command: chosen, it opens and closes
    NSInteger row = [self rowOf:@"skin"];
    [tree.outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
    [tree chooseSelectedElement:nil];
    XCTAssertFalse([tree.outlineView isItemExpanded:[tree.outlineView itemAtRow:row]]);
    XCTAssertEqual(_controller.editorTabs.items.count, tabs + 1);

    // a URL nobody provides: nothing opened
    [(id<UDWorkbench>)_controller showURL:[NSURL URLWithString:@"nobodys:/x"]];
    XCTAssertEqual(_controller.editorTabs.items.count, tabs + 1);
}

- (void)testADocumentOfAProvidersURL {
    UDProjectTestProvider *provider = [[UDProjectTestProvider alloc] init];
    NSURL *b = [NSURL URLWithString:@"udproj:/material/b"];
    NSError *error = nil;
    UDCodeDocument *document = [UDCodeDocument documentFromURL:b fileSystemProvider:provider error:&error];
    XCTAssertNotNil(document, @"%@", error);
    XCTAssertEqualObjects([document.textModel getValue], @"textures/b { }\n");
    XCTAssertNil([UDCodeDocument documentFromURL:[NSURL URLWithString:@"udproj:/material/none"] fileSystemProvider:provider error:&error]);
    XCTAssertNotNil(error);

    // saved as a file: of the file from then on, its provider's no more
    NSString *path = [_folder stringByAppendingPathComponent:@"b.json"];
    XCTAssertTrue([document saveAsURL:[NSURL fileURLWithPath:path] error:&error], @"%@", error);
    XCTAssertEqualObjects(document.fileURL.path, path);
    XCTAssertEqualObjects(document.URL, document.fileURL);
    XCTAssertNil(document.fileSystemProvider);
    XCTAssertEqual(provider.written.count, 0u);
}

@end
