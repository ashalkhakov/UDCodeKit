//
//  UDSQLWindowTests.m
//
//  The SQL extension in the window: the Databases navigator (a segment after
//  the window's own); a Core Data store opened from the project (its file
//  claimed, read as one: its entities, its metadata); a SQL document run
//  against it (its results under its text, each statement's; its
//  parameters asked for in a sheet; a store's dates and entities shown as
//  such); the Editor menu's Run Statement and Run All; the store's ER
//  diagram, in a tab of its own (its XIB's views and menu connected).
//

#import <XCTest/XCTest.h>
#import "UDCodeTestCase.h"
#import <UDCodeKit/UDCodeKit.h>
#import "AppDelegate.h"
#import "UDDocument.h"
#import "UDDocumentWindowController.h"
#import "UDSQLConnection.h"
#import "UDSQLDatabases.h"
#import "UDSQLNavigatorViewController.h"
#import "UDSQLResultsViewController.h"
#import "UDSQLSheets.h"
#import "UDSQLDiagramViewController.h"

static Class UDPluginClass(NSString *name) {
    (void)[UDLanguageModeRegistry sharedRegistry];
    return NSClassFromString(name);
}
#define UDPlugin(name) ((id)UDPluginClass(@#name))

@interface UDDocumentWindowController (SQLTesting)
@property (nonatomic, strong) UDEditorTabsController *editorTabs;
@property (nonatomic, weak) NSSegmentedControl *navigatorControl;
- (void)_rebuildEditorMenu;
@end

@interface UDSQLWindowTests : UDCodeTestCase
@property (nonatomic, copy) NSString *folder;
@property (nonatomic, weak) NSWindow *sheetParent;
@end

@implementation UDSQLWindowTests

- (void)setUp {
    [super setUp];
    _folder = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:_folder withIntermediateDirectories:YES attributes:nil error:NULL];
    _folder = UDRealPath(_folder);
    // a Core Data store's tables: Person (and Employee, its subentity), with a date
    NSString *store = [_folder stringByAppendingPathComponent:@"Model.sqlite"];
    [[NSData data] writeToFile:store atomically:YES];
    NSError *error = nil;
    UDSQLConnection *connection = [UDPlugin(UDSQLConnection) connectionToURL:[NSURL fileURLWithPath:store] password:nil error:&error];
    for (NSString *sql in @[ @"CREATE TABLE Z_PRIMARYKEY (Z_ENT INTEGER PRIMARY KEY, Z_NAME VARCHAR, Z_SUPER INTEGER, Z_MAX INTEGER)",
                             @"INSERT INTO Z_PRIMARYKEY VALUES (1, 'Person', 0, 2), (2, 'Employee', 1, 0)",
                             @"CREATE TABLE Z_METADATA (Z_VERSION INTEGER PRIMARY KEY, Z_UUID VARCHAR(255), Z_PLIST BLOB)",
                             @"CREATE TABLE ZPERSON (Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZNAME VARCHAR, ZBORN TIMESTAMP, ZTEAM INTEGER)",
                             @"INSERT INTO ZPERSON (Z_PK, Z_ENT, Z_OPT, ZNAME, ZBORN) VALUES (1, 1, 1, 'Ann', 0), (2, 2, 1, 'Bob', 86400)",
                             @"CREATE TABLE ZTEAM (Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZTITLE VARCHAR)" ]) {
        XCTAssertNotNil([connection execute:sql parameters:@[] maxRows:1 error:&error], @"%@", error);
    }
    [connection close];
    [@"SELECT ZNAME, ZBORN, Z_ENT FROM ZPERSON ORDER BY Z_PK;\nSELECT count(*) FROM ZPERSON WHERE Z_PK > :after;\n"
        writeToFile:[_folder stringByAppendingPathComponent:@"query.sql"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"UDSQLDatabases"];
}

- (void)tearDown {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"UDSQLDatabases"];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"UDSQLDocumentDatabases"];
    [[NSFileManager defaultManager] removeItemAtPath:_folder error:NULL];
    [super tearDown];
}

/// The parameters' sheet: :after given 1, and Run.
- (void)fillSheet {
    NSWindow *sheet = _sheetParent.attachedSheet ?: [NSApp modalWindow];
    XCTAssertNotNil(sheet, @"the parameters' sheet");
    NSTableView *table = nil;
    for (NSView *view in [(NSView *)sheet.contentView subviews]) {
        if ([view isKindOfClass:[NSScrollView class]]) table = (NSTableView *)[(NSScrollView *)view documentView];
    }
    UDSQLSheets *sheets = (UDSQLSheets *)table.dataSource;
    XCTAssertEqualObjects([sheets tableView:table objectValueForTableColumn:[table tableColumnWithIdentifier:@"name"] row:0], @":after");
    [sheet makeFirstResponder:nil];
    [sheets tableView:table setObjectValue:@"1" forTableColumn:[table tableColumnWithIdentifier:@"value"] row:0];
    [sheets performSelector:@selector(runWithParameters:) withObject:nil];
}

- (UDSQLDatabases *)databasesOf:(UDDocumentWindowController *)controller {
    id plugin = nil;
    for (id<UDExtension> extension in [UDLanguageModeRegistry sharedRegistry].extensions) {
        if ([extension isKindOfClass:UDPluginClass(@"UDSQLPlugin")]) plugin = extension;
    }
    return [plugin performSelector:@selector(_databasesOf:) withObject:controller];
}

- (void)testAStoreAndAQuery {
    AppDelegate *delegate = [[AppDelegate alloc] init];
    UDWorkspace *workspace = [delegate openFolderAtURL:[NSURL fileURLWithPath:_folder]];
    UDDocumentWindowController *controller = workspace.windowControllers.firstObject;
    [controller showWindow:nil];
    NSSegmentedControl *navigators = controller.navigatorControl;
    NSInteger segment = navigators.segmentCount - 1;
    XCTAssertEqualObjects([navigators.cell toolTipForSegment:segment], @"Databases", @"the extension's navigator, last");

    // the store, double-clicked in the project: a database, not text
    NSUInteger tabs = controller.editorTabs.items.count;
    [controller openURLInNewTab:[NSURL fileURLWithPath:[_folder stringByAppendingPathComponent:@"Model.sqlite"]]];
    XCTAssertEqual(controller.editorTabs.items.count, tabs, @"no tab of its bytes");
    XCTAssertEqual(navigators.selectedSegment, segment, @"the Databases navigator shown");
    UDSQLDatabases *databases = [self databasesOf:controller];
    UDSQLDatabase *store = databases.databases.firstObject;
    XCTAssertEqualObjects(store.name, @"Model.sqlite");
    UDRunUntil(store.connected, 10.0);
    XCTAssertTrue(store.schema.coreDataStore);
    NSArray *titles = [databases.navigator visibleTitles];
    XCTAssertTrue([titles containsObject:@"Model.sqlite"], @"%@", titles);
    XCTAssertTrue([titles containsObject:@"  Entities"], @"%@", titles);
    XCTAssertTrue([titles containsObject:@"    Person"], @"%@", titles);
    XCTAssertTrue([titles containsObject:@"      Employee"], @"a subentity under its superentity: %@", titles);
    XCTAssertTrue([titles containsObject:@"    ZPERSON"], @"%@", titles);

    // its ER diagram: a tab of its own, once
    NSOutlineView *outline = databases.navigator.outlineView;
    [outline selectRowIndexes:[NSIndexSet indexSetWithIndex:[titles indexOfObject:@"Model.sqlite"]] byExtendingSelection:NO];
    tabs = controller.editorTabs.items.count;
    [databases.navigator showDiagram:nil];
    XCTAssertEqual(controller.editorTabs.items.count, tabs + 1);
    UDSQLDiagramViewController *diagram = (UDSQLDiagramViewController *)[controller.editorTabs viewControllerForItem:controller.editorTabs.selectedItem];
    XCTAssertTrue([diagram isKindOfClass:UDPluginClass(@"UDSQLDiagramViewController")]);
    XCTAssertEqualObjects(controller.editorTabs.selectedItem.title, @"Model.sqlite (ER Diagram)");
    XCTAssertNotNil(diagram.canvas, @"the XIB's canvas");
    XCTAssertEqual(diagram.canvas.dataSource, (id)diagram);
    XCTAssertEqual(diagram.canvas.delegate, (id)diagram);
    XCTAssertTrue([diagram.canvas.enclosingScrollView isKindOfClass:[NSScrollView class]]);
    XCTAssertEqualObjects([[diagram.diagram.tables valueForKey:@"identifier"] sortedArrayUsingSelector:@selector(compare:)], (@[ @"ZPERSON", @"ZTEAM" ]));
    XCTAssertEqualObjects(diagram.statusLabel.stringValue, @"2 tables, 1 link (1 inferred, dashed)");
    NSString *person = @"ZPERSON";
    NSRect box = [diagram.diagram tableWithIdentifier:person].frame;
    NSMenu *tableMenu = [diagram canvas:diagram.canvas menuForItem:person];
    XCTAssertEqualObjects([tableMenu.itemArray valueForKey:@"title"], (@[ @"Select Rows", @"New Query", @"Copy Name" ]));
    XCTAssertEqual([tableMenu itemAtIndex:0].target, (id)diagram);
    [[tableMenu itemWithTitle:@"Copy Name"].target performSelector:@selector(copyName:) withObject:[tableMenu itemWithTitle:@"Copy Name"]];
    XCTAssertEqualObjects([[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString], person);
    // a move: kept by database, and undone
    [diagram canvas:diagram.canvas moveItems:@[ person ] by:NSMakeSize(30, 40)];
    XCTAssertEqual(NSMinX([diagram.diagram tableWithIdentifier:person].frame), NSMinX(box) + 30);
    NSString *key = [UDPluginClass(@"UDSQLDiagramViewController") defaultsKeyOfURL:store.URL];
    XCTAssertNotNil([[NSUserDefaults standardUserDefaults] dictionaryForKey:key][person]);
    NSUndoManager *undo = controller.window.undoManager;
    XCTAssertTrue(undo.canUndo);
    [undo undo];
    XCTAssertEqual(NSMinX([diagram.diagram tableWithIdentifier:person].frame), NSMinX(box), @"undone");

    // a column, selected: described, its own menu and SQL; it drags its table
    UDSQLDiagramTable *personBox = [diagram.diagram tableWithIdentifier:person];
    UDSQLColumnInfo *name = personBox.table.columns[3];
    XCTAssertEqualObjects(name.name, @"ZNAME");
    NSRect nameRow = [diagram.diagram frameOfItem:name];
    XCTAssertEqual([diagram canvas:diagram.canvas itemAtPoint:NSMakePoint(NSMidX(nameRow), NSMidY(nameRow))], (id)name);
    XCTAssertEqualObjects([diagram canvas:diagram.canvas itemAtPoint:NSMakePoint(NSMidX(box), NSMinY(box) + 6)], person, @"its header: the table");
    diagram.canvas.selection = [NSSet setWithObject:name];
    [diagram canvasSelectionDidChange:diagram.canvas];
    XCTAssertEqualObjects(diagram.statusLabel.stringValue, @"ZPERSON.ZNAME VARCHAR");
    XCTAssertEqualObjects([[diagram canvas:diagram.canvas menuForItem:name].itemArray valueForKey:@"title"],
                          (@[ @"Select Values", @"New Query", @"Copy Name" ]));
    XCTAssertEqualObjects([diagram selectQueryOfItem:name],
                          @"SELECT \"ZNAME\", count(*)\nFROM \"ZPERSON\"\nGROUP BY \"ZNAME\"\nORDER BY count(*) DESC\nLIMIT 100");
    XCTAssertEqualObjects([diagram newQueryOfItem:name], @"SELECT *\nFROM \"ZPERSON\"\nWHERE \"ZNAME\" = ");
    XCTAssertTrue(NSEqualRects([diagram canvas:diagram.canvas frameOfItem:name], box), @"dragged as its table");
    XCTAssertTrue([diagram canvas:diagram.canvas canMoveItem:name]);
    [diagram canvas:diagram.canvas moveItems:@[ name, person ] by:NSMakeSize(10, 0)];
    XCTAssertEqual(NSMinX(personBox.frame), NSMinX(box) + 10, @"moved once, its column and itself selected");
    [undo undo];
    XCTAssertEqual(NSMinX(personBox.frame), NSMinX(box));

    // a line (ZTEAM, inferred), selected: picked near it, not moved, its join
    UDSQLDiagramLink *link = diagram.diagram.links.firstObject;
    NSPoint a = link.route[0].pointValue, b = link.route[1].pointValue;
    XCTAssertEqual([diagram canvas:diagram.canvas itemAtPoint:NSMakePoint((a.x + b.x) / 2 + 2, (a.y + b.y) / 2 + 2)], (id)link);
    XCTAssertFalse([diagram canvas:diagram.canvas canMoveItem:link]);
    XCTAssertEqualObjects([diagram nameOfItem:link], @"ZPERSON.ZTEAM → ZTEAM.Z_PK");
    XCTAssertEqualObjects([diagram descriptionOfItem:link], @"ZPERSON.ZTEAM → ZTEAM.Z_PK (many to zero or one, inferred)");
    XCTAssertEqualObjects([[diagram canvas:diagram.canvas menuForItem:link].itemArray valueForKey:@"title"],
                          (@[ @"Select Joined Rows", @"New Query", @"Copy" ]));
    XCTAssertEqualObjects([diagram selectQueryOfItem:link],
                          @"SELECT *\nFROM \"ZPERSON\"\nJOIN \"ZTEAM\" ON \"ZPERSON\".\"ZTEAM\" = \"ZTEAM\".\"Z_PK\"\nLIMIT 100");
    diagram.canvas.selection = [NSSet set];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:key];
    [databases.navigator showDiagram:nil];
    XCTAssertEqual(controller.editorTabs.items.count, tabs + 1, @"its tab again, not another");

    // the query: run against it (its only database), every statement
    [controller openURLInNewTab:[NSURL fileURLWithPath:[_folder stringByAppendingPathComponent:@"query.sql"]]];
    UDCodeEditorViewController *editor = (UDCodeEditorViewController *)[controller.editorTabs viewControllerForItem:controller.editorTabs.selectedItem];
    [controller.window makeFirstResponder:editor.textView];
    XCTAssertTrue([databases canRun]);
    [editor.textView setSelectedRange:NSMakeRange(3, 0)];
    [databases runStatement:nil];
    UDSQLResultsViewController *results = (UDSQLResultsViewController *)editor.accessoryViewController;
    XCTAssertTrue([results isKindOfClass:UDPluginClass(@"UDSQLResultsViewController")], @"the results under its text");
    UDRunUntil(results.results.count == 1, 10.0);
    UDSQLResult *rows = results.shownResult;
    XCTAssertEqualObjects([rows.columns valueForKey:@"name"], (@[ @"ZNAME", @"ZBORN", @"Z_ENT" ]));
    XCTAssertEqual(rows.rows.count, 2u);
    XCTAssertTrue([[results textOfValue:rows.rows[1][1] column:1] hasPrefix:@"2001-01-0"], @"a Core Data date: %@",
                  [results textOfValue:rows.rows[1][1] column:1]);
    XCTAssertEqualObjects([results textOfValue:rows.rows[1][2] column:2], @"2 · Employee");
    XCTAssertEqual(results.grid.numberOfRows, 2);
    XCTAssertEqual(results.grid.numberOfColumns, 3);

    // the second statement's parameter: asked for in a sheet (filled in, and
    // Run pressed, as the run loop turns: GNUstep's sheet is modal)
    NSString *text = editor.textView.string;
    [editor.textView setSelectedRange:NSMakeRange([text rangeOfString:@"count"].location, 0)];
    _sheetParent = controller.window;
    [self performSelector:@selector(fillSheet) withObject:nil afterDelay:0.3 inModes:@[ NSDefaultRunLoopMode, NSModalPanelRunLoopMode ]];
    [databases runStatement:nil];
    UDRunUntil(results.results.count == 1 && [results.shownResult.rows.firstObject isEqual:@[ @1 ]], 10.0);
    XCTAssertEqualObjects(results.shownResult.rows.firstObject, @[ @1 ], @"Z_PK > 1: one; %@", results.messagesView.string);

    // the Editor menu's own
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Main"];
    NSMenuItem *editorItem = [menu addItemWithTitle:@"Editor" action:NULL keyEquivalent:@""];
    editorItem.submenu = [[NSMenu alloc] initWithTitle:@"Editor"];
    NSMenu *before = NSApp.mainMenu;
    NSApp.mainMenu = menu;
    [controller _rebuildEditorMenu];
    NSMenuItem *run = [editorItem.submenu itemWithTitle:@"Run Statement"];
    XCTAssertEqualObjects(run.keyEquivalent, @"\r", @"⌘↩");
    XCTAssertNotNil([editorItem.submenu itemWithTitle:@"Run All"]);
    NSApp.mainMenu = before;
    [controller close];
    [workspace close];
}

@end
