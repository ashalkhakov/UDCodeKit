//
//  UDSQLQueryBuilderWindowTests.m
//
//  The query builder in the window: Design Query from the navigator (its
//  XIB's canvas, grids and menus connected); tables added (joined along
//  their keys), columns made fields by a double-click, a condition and a
//  sort in the design's grid (each row its kind of cell), Run (its rows in
//  Results), a join made left by its menu, one made by a drag from column
//  to column, a table joined to none said so, Show SQL.
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
#import "UDSQLQueryBuilderViewController.h"

static Class UDPluginClass(NSString *name) {
    (void)[UDLanguageModeRegistry sharedRegistry];
    return NSClassFromString(name);
}
#define UDPlugin(name) ((id)UDPluginClass(@#name))

@interface UDDocumentWindowController (QueryBuilderTesting)
@property (nonatomic, strong) UDEditorTabsController *editorTabs;
@end

@interface UDSQLQueryBuilderWindowTests : UDCodeTestCase
@property (nonatomic, copy) NSString *folder;
@end

@implementation UDSQLQueryBuilderWindowTests

- (void)setUp {
    [super setUp];
    _folder = UDRealPath([NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]]);
    [[NSFileManager defaultManager] createDirectoryAtPath:_folder withIntermediateDirectories:YES attributes:nil error:NULL];
    _folder = UDRealPath(_folder);
    NSString *store = [_folder stringByAppendingPathComponent:@"shop.sqlite"];
    [[NSData data] writeToFile:store atomically:YES];
    NSError *error = nil;
    UDSQLConnection *connection = [UDPlugin(UDSQLConnection) connectionToURL:[NSURL fileURLWithPath:store] password:nil error:&error];
    for (NSString *sql in @[ @"CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT, city TEXT)",
                             @"CREATE TABLE orders (id INTEGER PRIMARY KEY, customer INTEGER REFERENCES customers(id), total REAL)",
                             @"CREATE TABLE notes (id INTEGER PRIMARY KEY, about INTEGER, text TEXT)",
                             @"INSERT INTO customers VALUES (1, 'Ann', 'Oslo'), (2, 'Bob', 'Rome'), (3, 'Cy', 'Oslo')",
                             @"INSERT INTO orders VALUES (10, 1, 5.5), (11, 1, 20), (12, 2, 7)",
                             @"INSERT INTO notes VALUES (1, 1, 'first'), (2, 3, 'third')" ]) {
        XCTAssertNotNil([connection execute:sql parameters:@[] maxRows:1 error:&error], @"%@", error);
    }
    [connection close];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"UDSQLDatabases"];
}

- (void)tearDown {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"UDSQLDatabases"];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"UDSQLDocumentDatabases"];
    [[NSFileManager defaultManager] removeItemAtPath:_folder error:NULL];
    [super tearDown];
}

- (UDSQLDatabases *)databasesOf:(UDDocumentWindowController *)controller {
    id plugin = nil;
    for (id<UDExtension> extension in [UDLanguageModeRegistry sharedRegistry].extensions) {
        if ([extension isKindOfClass:UDPluginClass(@"UDSQLPlugin")]) plugin = extension;
    }
    return [plugin performSelector:@selector(_databasesOf:) withObject:controller];
}

- (NSEvent *)mouse:(NSEventType)type at:(NSPoint)point in:(NSView *)view clicks:(NSInteger)clicks {
    return [NSEvent mouseEventWithType:type location:[view convertPoint:point toView:nil] modifierFlags:0 timestamp:0
                          windowNumber:view.window.windowNumber context:nil eventNumber:0 clickCount:clicks pressure:1];
}

- (void)testAQueryBuilt {
    AppDelegate *delegate = [[AppDelegate alloc] init];
    UDWorkspace *workspace = [delegate openFolderAtURL:[NSURL fileURLWithPath:_folder]];
    UDDocumentWindowController *controller = workspace.windowControllers.firstObject;
    [controller showWindow:nil];
    [controller openURLInNewTab:[NSURL fileURLWithPath:[_folder stringByAppendingPathComponent:@"shop.sqlite"]]];
    UDSQLDatabases *databases = [self databasesOf:controller];
    UDSQLDatabase *shop = databases.databases.firstObject;
    UDRunUntil(shop.connected, 10.0);

    // Design Query: a tab of its own, its XIB's
    NSArray *titles = [databases.navigator visibleTitles];
    [databases.navigator.outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:[titles indexOfObject:@"shop.sqlite"]] byExtendingSelection:NO];
    NSUInteger tabs = controller.editorTabs.items.count;
    [databases.navigator designQuery:nil];
    XCTAssertEqual(controller.editorTabs.items.count, tabs + 1);
    XCTAssertEqualObjects(controller.editorTabs.selectedItem.title, @"Query (shop.sqlite)");
    UDSQLQueryBuilderViewController *builder = (UDSQLQueryBuilderViewController *)[controller.editorTabs viewControllerForItem:controller.editorTabs.selectedItem];
    XCTAssertTrue([builder isKindOfClass:UDPluginClass(@"UDSQLQueryBuilderViewController")]);
    XCTAssertEqual(builder.canvas.dataSource, (id)builder);
    XCTAssertEqual(builder.canvas.delegate, (id)builder);
    XCTAssertEqual(builder.designView.dataSource, (id)builder);
    XCTAssertTrue(builder.resultsView.enclosingScrollView.isHidden, @"the design first");
    XCTAssertEqualObjects([builder.designView.menu.itemArray valueForKey:@"title"], (@[ @"Move Left", @"Move Right", @"", @"Remove Field" ]));
    NSArray *addable = [[builder.addTableButton.menu.itemArray subarrayWithRange:NSMakeRange(1, builder.addTableButton.menu.numberOfItems - 1)]
                           valueForKey:@"title"];
    XCTAssertEqualObjects(addable, (@[ @"customers", @"notes", @"orders" ]), @"Add Table: the schema's");
    XCTAssertEqualObjects(builder.statusLabel.stringValue, @"Add a table; double-click its columns to make them fields");

    // tables added from its menu: joined along their key
    [builder addTableChosen:[builder.addTableButton.menu itemWithTitle:@"orders"]];
    [builder addTableChosen:[builder.addTableButton.menu itemWithTitle:@"customers"]];
    XCTAssertEqual(builder.design.joins.count, 1u);
    XCTAssertEqualObjects(builder.statusLabel.stringValue, @"2 tables, 0 fields (all columns shown)");
    // columns double-clicked: fields
    UDSQLQueryColumn *name = [UDPluginClass(@"UDSQLQueryColumn") column:@"name" ofTable:@"customers"];
    UDSQLQueryColumn *total = [UDPluginClass(@"UDSQLQueryColumn") column:@"total" ofTable:@"orders"];
    NSRect nameRow = [builder.diagram frameOfItem:name];
    XCTAssertEqualObjects([builder canvas:builder.canvas itemAtPoint:NSMakePoint(NSMidX(nameRow), NSMidY(nameRow))], name);
    [builder canvas:builder.canvas doubleClickedItem:name];
    [builder canvas:builder.canvas doubleClickedItem:total];
    XCTAssertEqualObjects([builder.design.fields valueForKey:@"column"], (@[ @"name", @"total" ]));
    XCTAssertEqual(builder.designView.numberOfColumns, 3, @"its labels, a column a field");
    XCTAssertEqual(builder.designView.numberOfRows, 3, @"Sort, Show, Where");
    NSTableColumn *totals = [builder.designView.tableColumns objectAtIndex:2];
    XCTAssertEqualObjects([totals.headerCell stringValue], @"orders.total");
    XCTAssertTrue([[builder tableView:builder.designView dataCellForTableColumn:totals row:0] isKindOfClass:[NSPopUpButtonCell class]], @"Sort");
    XCTAssertTrue([[builder tableView:builder.designView dataCellForTableColumn:totals row:1] isKindOfClass:[NSButtonCell class]], @"Show");
    NSCell *where = [builder tableView:builder.designView dataCellForTableColumn:totals row:2];
    XCTAssertEqualObjects(NSStringFromClass([where class]), @"UDSQLConditionCell");
    XCTAssertEqualObjects([(NSTextFieldCell *)where placeholderString], @"e.g. > 5");
    XCTAssertEqualObjects([builder tableView:builder.designView objectValueForTableColumn:[builder.designView.tableColumns objectAtIndex:0] row:2], @"Where");

    // a condition and a sort, typed; run: its rows
    [builder tableView:builder.designView setObjectValue:@"> 6" forTableColumn:totals row:2];
    [builder tableView:builder.designView setObjectValue:@(UDSQLFieldDescending) forTableColumn:totals row:0];
    [builder run:nil];
    UDRunUntil(!builder.running && builder.result != nil, 10.0);
    XCTAssertEqualObjects(builder.result.rows, (@[ @[ @"Ann", @20 ], @[ @"Bob", @7 ] ]));
    XCTAssertEqualObjects(builder.statusLabel.stringValue, @"2 rows");
    XCTAssertFalse(builder.resultsView.enclosingScrollView.isHidden, @"Results, shown");
    XCTAssertEqual(builder.resultsView.numberOfRows, 2);
    builder.paneControl.selectedSegment = 0;
    [builder showPane:nil];

    // the join made left by its menu: every order, its customer where there is one
    UDSQLQueryJoin *join = builder.design.joins.firstObject;
    NSMenu *joinMenu = [builder canvas:builder.canvas menuForItem:join];
    XCTAssertEqualObjects([joinMenu.itemArray valueForKey:@"title"],
                          (@[ @"Inner Join (Rows of Both)", @"Left Join (Every Row of the First)", @"", @"Remove Join" ]));
    [builder setJoinKind:[joinMenu itemAtIndex:1]];
    XCTAssertEqual(join.kind, UDSQLJoinLeft);

    // notes, joined to none: said so; joined by a drag from a column to a column
    [builder addTableChosen:[builder.addTableButton.menu itemWithTitle:@"notes"]];
    XCTAssertTrue([builder.statusLabel.stringValue hasPrefix:@"notes joined to no other table"], @"%@", builder.statusLabel.stringValue);
    UDRunUntil(NO, 0.2);
    NSRect about = [builder.diagram frameOfItem:[UDPluginClass(@"UDSQLQueryColumn") column:@"about" ofTable:@"notes"]];
    NSRect customerId = [builder.diagram frameOfItem:[UDPluginClass(@"UDSQLQueryColumn") column:@"id" ofTable:@"customers"]];
    NSPoint from = NSMakePoint(NSMidX(about), NSMidY(about)), to = NSMakePoint(NSMidX(customerId), NSMidY(customerId));
    XCTAssertTrue([builder canvas:builder.canvas mouseDown:[self mouse:NSEventTypeLeftMouseDown at:from in:builder.canvas clicks:1] atPoint:from],
                  @"a press on a column: a join's");
    [builder canvas:builder.canvas mouseDragged:[self mouse:NSEventTypeLeftMouseDragged at:to in:builder.canvas clicks:1] atPoint:to];
    XCTAssertNotNil(builder.diagram.joiningFrom, @"drawn as it is dragged");
    [builder canvas:builder.canvas mouseUp:[self mouse:NSEventTypeLeftMouseUp at:to in:builder.canvas clicks:1] atPoint:to];
    XCTAssertNil(builder.diagram.joiningFrom);
    XCTAssertEqual(builder.design.joins.count, 2u);
    UDSQLQueryJoin *made = builder.design.joins.lastObject;
    XCTAssertEqualObjects((@[ made.from, made.fromColumn, made.to, made.toColumn ]), (@[ @"notes", @"about", @"customers", @"id" ]));
    XCTAssertEqualObjects(builder.statusLabel.stringValue, @"3 tables, 2 fields");

    // Show SQL: a document of its own
    NSUInteger before = controller.editorTabs.items.count;
    [builder showSQL:nil];
    XCTAssertEqual(controller.editorTabs.items.count, before + 1);
    UDCodeEditorViewController *shown = (UDCodeEditorViewController *)[controller.editorTabs viewControllerForItem:controller.editorTabs.selectedItem];
    XCTAssertEqualObjects(shown.textView.string, @"SELECT \"customers\".\"name\", \"orders\".\"total\"\n"
                                                  "FROM \"orders\" LEFT JOIN \"customers\" ON \"orders\".\"customer\" = \"customers\".\"id\" "
                                                  "JOIN \"notes\" ON \"notes\".\"about\" = \"customers\".\"id\"\n"
                                                  "WHERE \"orders\".\"total\" > 6\n"
                                                  "ORDER BY \"orders\".\"total\" DESC;\n");
    // a table's menu: taken away, with its joins
    NSMenu *tableMenu = [builder canvas:builder.canvas menuForItem:@"notes"];
    [builder removeTable:[tableMenu itemAtIndex:0]];
    XCTAssertEqual(builder.design.tables.count, 2u);
    XCTAssertEqual(builder.design.joins.count, 1u);
    [controller close];
    [workspace close];
}

@end
