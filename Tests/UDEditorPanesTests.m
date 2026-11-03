//
//  UDEditorPanesTests.m
//
//  A custom editor's own panes (UDEditorPanes), as Xcode's editors have
//  them: its inspectors as tabs after File, its panes in the bottom area,
//  its Library (⇧⌘L), an issue of its document shown in it; each there
//  while its tab is in front, and gone when another tab is.
//

#import <XCTest/XCTest.h>
#import "UDCodeTestCase.h"
#import <UDCodeKit/UDCodeKit.h>
#import "UDDocument.h"
#import "UDDocumentWindowController.h"

@interface UDDocumentWindowController (PanesTesting)
@property (nonatomic, strong) UDEditorTabsController *editorTabs;
@property (nonatomic, weak) NSSegmentedControl *inspectorSwitch;
@property (nonatomic, weak) NSView *fileInspector;
@property (nonatomic, weak) NSView *inspectorHost;
@property (nonatomic, weak) NSSegmentedControl *bottomAreaControl;
@property (nonatomic, strong, nullable) NSPopover *libraryPopover;
- (IBAction)inspectorChanged:(id)sender;
- (IBAction)showLibrary:(id)sender;
- (IBAction)bottomAreaChanged:(id)sender;
- (BOOL)validateMenuItem:(NSMenuItem *)item;
- (void)errorsViewController:(UDErrorsViewController *)vc didSelectDiagnostic:(UDDiagnosticItem *)diagnostic inStore:(UDDiagnosticStore *)store;
@end

/// A pane: a view of its own, its title its name.
static NSViewController *UDTestPane(NSString *title) {
    NSViewController *pane = [[NSViewController alloc] init];
    pane.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 200, 120)];
    pane.title = title;
    return pane;
}

/// The test mode's editor: two inspectors (Size's tab an image), a bottom
/// pane, a Library, and what was revealed in it.
@interface UDPanesTestEditor : NSViewController <UDEditorPanes>
@property (nonatomic, copy) NSArray<NSViewController *> *inspectors;
@property (nonatomic, copy) NSArray<NSViewController *> *panes;
@property (nonatomic, strong) NSViewController *library;
@property (nonatomic, strong) NSImage *sizeImage;
@property (nonatomic, strong) NSTextField *field;
@property (nonatomic, strong) NSTextView *fieldEditor;
@property (nonatomic, strong, nullable) UDDiagnosticItem *revealed;
@end

@implementation UDPanesTestEditor
- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 600, 400)];
    _inspectors = @[ UDTestPane(@"Attributes"), UDTestPane(@"Size") ];
    _panes = @[ UDTestPane(@"Verbalization") ];
    _library = UDTestPane(@"Library");
    _sizeImage = [[NSImage alloc] initWithSize:NSMakeSize(16, 16)];
    _field = [[NSTextField alloc] initWithFrame:NSMakeRect(10, 10, 100, 22)];
    [self.view addSubview:_field];
    _fieldEditor = [[NSTextView alloc] initWithFrame:NSZeroRect];
    [_fieldEditor setFieldEditor:YES];
}
- (id)fieldEditorForClient:(id)client {
    return [client isKindOfClass:[NSView class]] && [(NSView *)client isDescendantOf:self.view] ? _fieldEditor : nil;
}
- (NSArray<NSViewController *> *)inspectorViewControllers { [self view]; return _inspectors; }
- (NSImage *)imageForInspectorViewController:(NSViewController *)viewController {
    return viewController == _inspectors[1] ? _sizeImage : nil;
}
- (NSArray<NSViewController *> *)bottomAreaViewControllers { [self view]; return _panes; }
- (NSViewController *)libraryViewController { [self view]; return _library; }
- (void)revealDiagnostic:(UDDiagnosticItem *)diagnostic { _revealed = diagnostic; }
@end

/// An extension of the test's own (registered, no bundle): the editor of
/// its mode's documents.
@interface UDPanesTestExtension : NSObject <UDExtension>
@end

@implementation UDPanesTestExtension
- (void)extensionDidLoad:(NSBundle *)bundle {}
- (void)extensionWillUnload:(NSBundle *)bundle {}
- (const void *)languageFuncForIdentifier:(NSString *)identifier { return NULL; }
- (NSViewController *)workbench:(id<UDWorkbench>)workbench editorForDocument:(UDCodeDocument *)document {
    return [document.languageMode.identifier isEqualToString:@"panestest"] ? [[UDPanesTestEditor alloc] init] : nil;
}
@end

@interface UDEditorPanesTests : UDCodeTestCase
@end

@implementation UDEditorPanesTests {
    UDWorkspace *_workspace;
    UDDocumentWindowController *_controller;
}

+ (void)setUp {
    [super setUp];
    static BOOL registered;
    if (registered) return;
    registered = YES;
    UDLanguageModeRegistry *registry = [UDLanguageModeRegistry sharedRegistry];
    [registry registerMode:[[UDLanguageMode alloc] initWithIdentifier:@"panestest" displayName:@"Panes Test" fileExtensions:@[ @"panestest" ]
                                                         languageFunc:NULL highlightsQuery:nil indentsQuery:nil lspLanguageID:nil
                                                languageServerCommand:nil defaultNewDocumentText:@""
                                                languageConfiguration:[UDLanguageConfiguration emptyConfiguration] keyHandler:nil extension:nil]];
    [registry registerExtension:[[UDPanesTestExtension alloc] init]];
}

- (void)setUp {
    [super setUp];
    _workspace = [[UDWorkspace alloc] init];
    [_workspace makeWindowControllers];
    _controller = (UDDocumentWindowController *)_workspace.windowControllers.firstObject;
    [_controller.window setFrame:NSMakeRect(0, 0, 1200, 760) display:NO];
    [_controller showWindow:nil];
}

- (void)tearDown {
    [_controller close];
    [_workspace close];
    [super tearDown];
}

- (UDPanesTestEditor *)openTestDocument {
    [(id<UDWorkbench>)_controller openUntitledDocumentWithText:@"a model" languageMode:@"panestest" name:@"model"];
    id editor = [_controller.editorTabs viewControllerForItem:_controller.editorTabs.selectedItem];
    XCTAssertTrue([editor isKindOfClass:[UDPanesTestEditor class]], @"%@", editor);
    return editor;
}

- (void)testTheInspectorPaneHasTheFrontEditorsInspectorsAsTabs {
    XCTAssertNotNil(_controller.inspectorSwitch, @"connected in UDDocumentWindowController.xib");
    XCTAssertNotNil(_controller.fileInspector);
    XCTAssertNotNil(_controller.inspectorHost);
    UDTabBarItem *text = _controller.editorTabs.selectedItem;
    XCTAssertEqual(_controller.inspectorSwitch.segmentCount, 1, @"a text tab: File only");
    XCTAssertGreaterThan([_controller.inspectorSwitch widthForSegment:0], 20, @"File's tab an icon's width");
    XCTAssertGreaterThan(NSWidth(_controller.inspectorSwitch.frame), 20);

    UDPanesTestEditor *editor = [self openTestDocument];
    XCTAssertEqual(_controller.inspectorSwitch.segmentCount, 3);
    XCTAssertEqualObjects([_controller.inspectorSwitch labelForSegment:1], @"Attributes");
    // File's tab an image, as Xcode's (on GNUstep the app's doc.png, which xctest's bundle hasn't)
    if ([NSImage imageNamed:@"doc"]) XCTAssertNotNil([_controller.inspectorSwitch imageForSegment:0]);
    XCTAssertEqualObjects([_controller.inspectorSwitch labelForSegment:2], @"", @"Size's tab its image");
    XCTAssertEqual([_controller.inspectorSwitch imageForSegment:2], editor.sizeImage);
    XCTAssertEqualObjects([_controller.inspectorSwitch.cell toolTipForSegment:2], @"Size inspector");
    XCTAssertFalse(_controller.fileInspector.isHidden, @"File chosen first");

    [_controller.inspectorSwitch setSelectedSegment:2];
    [_controller inspectorChanged:_controller.inspectorSwitch];
    XCTAssertTrue(_controller.fileInspector.isHidden);
    XCTAssertFalse(_controller.inspectorHost.isHidden);
    XCTAssertEqual(editor.inspectors[1].view.superview, _controller.inspectorHost, @"Size's view in the host");

    // another tab: its own (none); back: the tab chosen stays chosen
    [_controller.editorTabs selectItem:text];
    XCTAssertEqual(_controller.inspectorSwitch.segmentCount, 1);
    XCTAssertFalse(_controller.fileInspector.isHidden);
    XCTAssertTrue(_controller.inspectorHost.isHidden);
    [_controller.editorTabs selectItem:[_controller.editorTabs.items lastObject]];
    XCTAssertEqual(_controller.inspectorSwitch.segmentCount, 3);
    XCTAssertEqual(_controller.inspectorSwitch.selectedSegment, 2);
    XCTAssertEqual(editor.inspectors[1].view.superview, _controller.inspectorHost);

    // chosen when the editor asks, and kept chosen
    XCTAssertTrue([(id<UDWorkbench>)_controller showEditorInspector:editor.inspectors[0]]);
    XCTAssertEqual(_controller.inspectorSwitch.selectedSegment, 1);
    XCTAssertEqual(editor.inspectors[0].view.superview, _controller.inspectorHost);
    XCTAssertFalse([(id<UDWorkbench>)_controller showEditorInspector:UDTestPane(@"Not the editor's")]);
    [_controller.editorTabs selectItem:text];
    [_controller.editorTabs selectItem:[_controller.editorTabs.items lastObject]];
    XCTAssertEqual(_controller.inspectorSwitch.selectedSegment, 1);
}

- (void)testATextFieldOfTheEditorsHasItsFieldEditor {
    UDPanesTestEditor *editor = [self openTestDocument];
    NSWindow *window = _controller.window;
    XCTAssertEqual([window.delegate windowWillReturnFieldEditor:window toObject:editor.field], editor.fieldEditor);
    NSTextField *outside = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 10, 10)];
    XCTAssertNil([window.delegate windowWillReturnFieldEditor:window toObject:outside], @"the window's own");
}

- (void)testTheBottomAreaHasTheFrontEditorsPanes {
    UDTabBarItem *text = _controller.editorTabs.selectedItem;
    NSInteger before = _controller.bottomAreaControl.segmentCount;
    UDPanesTestEditor *editor = [self openTestDocument];
    XCTAssertEqual(_controller.bottomAreaControl.segmentCount, before + 1);
    NSInteger segment = before;
    XCTAssertEqualObjects([_controller.bottomAreaControl.cell toolTipForSegment:segment], @"Verbalization");
    [_controller.bottomAreaControl setSelectedSegment:segment];
    [_controller bottomAreaChanged:_controller.bottomAreaControl];
    XCTAssertNotNil(editor.panes[0].view.superview, @"shown in the bottom area");
    XCTAssertFalse(editor.panes[0].view.superview.isHidden);

    // shown when the editor asks
    [_controller.bottomAreaControl setSelectedSegment:0];
    [_controller bottomAreaChanged:_controller.bottomAreaControl];
    XCTAssertTrue([(id<UDWorkbench>)_controller showEditorBottomPane:editor.panes[0]]);
    XCTAssertEqual(_controller.bottomAreaControl.selectedSegment, segment);
    XCTAssertFalse([(id<UDWorkbench>)_controller showEditorBottomPane:UDTestPane(@"Not the editor's")]);

    [_controller.editorTabs selectItem:text];
    XCTAssertEqual(_controller.bottomAreaControl.segmentCount, before, @"gone with its tab");
    XCTAssertNil(editor.panes[0].view.superview);
    XCTAssertEqual(_controller.bottomAreaControl.selectedSegment, 0, @"the debugger's shown in its place");
}

- (void)testTheLibraryIsTheFrontEditors {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Show Library" action:@selector(showLibrary:) keyEquivalent:@""];
    XCTAssertFalse([_controller validateMenuItem:item], @"a text tab has none");
    UDPanesTestEditor *editor = [self openTestDocument];
    XCTAssertTrue([_controller validateMenuItem:item]);
    [_controller showLibrary:nil];
    XCTAssertNotNil(_controller.libraryPopover);
    XCTAssertEqual(_controller.libraryPopover.contentViewController, editor.library);
    [(id<UDWorkbench>)_controller closeLibrary];
}

- (void)testAnIssueOfItsDocumentIsShownInTheEditor {
    UDPanesTestEditor *editor = [self openTestDocument];
    UDCodeDocument *document = _controller.editorTabs.selectedItem.representedObject;
    UDDiagnosticItem *issue = [[UDDiagnosticItem alloc] initWithLine:1 column:0 message:@"No reference scheme"
                                                            severity:UDDiagnosticSeverityError source:UDDiagnosticSourceParser];
    [document.diagnosticStore setDiagnostics:@[ issue ] forSource:UDDiagnosticSourceParser];
    [_controller.editorTabs selectItem:_controller.editorTabs.items.firstObject];
    [_controller errorsViewController:nil didSelectDiagnostic:issue inStore:document.diagnosticStore];
    XCTAssertEqual(_controller.editorTabs.selectedItem.representedObject, document, @"its tab brought to the front");
    XCTAssertEqual(editor.revealed, issue);
}

@end
