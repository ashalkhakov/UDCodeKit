//
//  UDSQLExampleWindowTests.m
//
//  A query by example kept as a file (.qbe: its JSON written and read back,
//  its tables found by name in the database asked), and its editor in the
//  window, as VS Code's custom text editors are: a new one opened in it,
//  untitled; a table added (its foreign key's example elements filled
//  in), printed columns and a condition typed, Run (its answer); its
//  document changed (its tab's dot), saved as a file (its tab named for
//  it, its database remembered), by the window's Save (its JSON on disk),
//  undone; shown as text, its text edited (read back); the same
//  file asked of another database (staging) and of one without its table;
//  Copy SQL (as by hand); a row and a table removed.
//

#import <XCTest/XCTest.h>
#import "UDCodeTestCase.h"
#import <UDCodeKit/UDCodeKit.h>
#import "AppDelegate.h"
#import "UDDocument.h"
#import "UDDocumentWindowController.h"
#import "UDSQLConnection.h"
#import "UDSQLDatabases.h"
#import "UDSQLExampleFile.h"
#import "UDSQLExampleViewController.h"
#import "UDSQLExampleEntry.h"

static Class UDPluginClass(NSString *name) {
    (void)[UDLanguageModeRegistry sharedRegistry];
    return NSClassFromString(name);
}
#define UDPlugin(name) ((id)UDPluginClass(@#name))

@interface UDDocumentWindowController (ExampleTesting)
@property (nonatomic, strong) UDEditorTabsController *editorTabs;
- (void)_save:(UDCodeDocument *)document asURL:(NSURL *)url;
@end

@interface UDSQLExampleWindowTests : UDCodeTestCase
@property (nonatomic, copy) NSString *folder;
@end

@implementation UDSQLExampleWindowTests

- (void)makeDatabase:(NSString *)name statements:(NSArray *)statements {
    NSString *path = [_folder stringByAppendingPathComponent:name];
    [[NSData data] writeToFile:path atomically:YES];
    NSError *error = nil;
    UDSQLConnection *connection = [UDPlugin(UDSQLConnection) connectionToURL:[NSURL fileURLWithPath:path] password:nil error:&error];
    for (NSString *sql in statements) XCTAssertNotNil([connection execute:sql parameters:@[] maxRows:1 error:&error], @"%@", error);
    [connection close];
}

- (void)setUp {
    [super setUp];
    _folder = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [[NSFileManager defaultManager] createDirectoryAtPath:_folder withIntermediateDirectories:YES attributes:nil error:NULL];
    _folder = UDRealPath(_folder);
    NSArray *tables = @[ @"CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT, city TEXT)",
                         @"CREATE TABLE orders (id INTEGER PRIMARY KEY, customer INTEGER REFERENCES customers(id), total REAL)" ];
    [self makeDatabase:@"shop.sqlite" statements:[tables arrayByAddingObjectsFromArray:@[
        @"INSERT INTO customers VALUES (1, 'Ann', 'Oslo'), (2, 'Bob', 'Rome'), (3, 'Cy', 'Oslo')",
        @"CREATE TABLE notes (id INTEGER PRIMARY KEY, body TEXT, data BLOB, kind TEXT)",
        @"INSERT INTO notes VALUES (1, 'a' || char(10) || 'b\tc', x'0a1b', NULL)",
        @"INSERT INTO orders VALUES (10, 1, 5.5), (11, 1, 20), (12, 2, 7)" ]]];
    [self makeDatabase:@"staging.sqlite" statements:[tables arrayByAddingObjectsFromArray:@[
        @"INSERT INTO customers VALUES (1, 'Test', 'Oslo')", @"INSERT INTO orders VALUES (1, 1, 99)" ]]];
    [self makeDatabase:@"empty.sqlite" statements:@[ tables.firstObject ]];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"UDSQLDatabases"];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"UDSQLDocumentDatabases"];
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

// ---------------------------------------------------------------------------
// MARK: - The file
// ---------------------------------------------------------------------------

- (void)testItsFile {
    UDSQLExampleFile *file = [[UDPluginClass(@"UDSQLExampleFile") alloc] init];
    UDSQLExampleFileSkeleton *customers = [UDPluginClass(@"UDSQLExampleFileSkeleton") skeletonOfTable:@"customers" schema:nil];
    customers.rows = @[ [UDPluginClass(@"UDSQLExampleRow") rowWithEntries:@{ @"id": @"_c", @"name": @"P.", @"city": @"  " }] ];
    UDSQLExampleFileSkeleton *orders = [UDPluginClass(@"UDSQLExampleFileSkeleton") skeletonOfTable:@"orders" schema:@"sales"];
    UDSQLExampleRow *kept = [UDPluginClass(@"UDSQLExampleRow") rowWithEntries:@{ @"customer": @"_c" }];
    kept.inclusive = YES;
    orders.rows = @[ kept ];
    file.skeletons = @[ customers, orders ];
    file.order = @[ [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:NO] ];
    NSString *json = [[NSString alloc] initWithData:[file data] encoding:NSUTF8StringEncoding];
    XCTAssertTrue([json hasPrefix:@"{\n  \"kind\": \"UDCode query by example\",\n  \"order\": [\n    {\n      \"ascending\": false,\n      \"column\": \"name\"\n    }\n  ],"], @"%@", json);
    XCTAssertFalse([json containsString:@"city"], @"what is typed only");
    NSError *error = nil;
    UDSQLExampleFile *read = [UDPluginClass(@"UDSQLExampleFile") fileWithData:[file data] error:&error];
    XCTAssertNotNil(read, @"%@", error);
    XCTAssertEqualObjects([read.skeletons valueForKey:@"table"], (@[ @"customers", @"orders" ]));
    XCTAssertEqualObjects(read.skeletons[1].schema, @"sales");
    XCTAssertEqualObjects(read.skeletons[0].rows[0].entries, (@{ @"id": @"_c", @"name": @"P." }));
    XCTAssertTrue(read.skeletons[1].rows[0].inclusive);
    XCTAssertFalse(read.skeletons[1].rows[0].negated);
    XCTAssertEqualObjects(read.order.firstObject.key, @"name");
    XCTAssertFalse(read.order.firstObject.ascending);
    XCTAssertNil([UDPluginClass(@"UDSQLExampleFile") fileWithData:[@"{\"a\": 1}" dataUsingEncoding:NSUTF8StringEncoding] error:&error]);
    XCTAssertEqualObjects(error.localizedDescription, @"This isn't a query by example's file.");
    XCTAssertNil([UDPluginClass(@"UDSQLExampleFile") fileWithData:[@"{\"kind\": \"UDCode query by example\", \"version\": 7}"
                                                                     dataUsingEncoding:NSUTF8StringEncoding] error:&error]);
    XCTAssertEqualObjects(error.localizedDescription, @"This query by example was saved by a newer UDCode.");
    // its tables found by name, in the database asked
    UDSQLConnection *connection = [UDPlugin(UDSQLConnection) connectionToURL:[NSURL fileURLWithPath:[_folder stringByAppendingPathComponent:@"empty.sqlite"]]
                                                                   password:nil error:&error];
    UDSQLSchema *schema = [UDPlugin(UDSQLSchema) schemaOfConnection:connection error:&error];
    [connection close];
    orders.schema = nil;
    XCTAssertNil([file queryForSchema:schema dialect:UDSQLDialectSQLite databaseName:@"empty.sqlite" error:&error]);
    XCTAssertEqualObjects(error.localizedDescription, @"empty.sqlite has no table orders.");
    file.skeletons = @[ customers ];
    XCTAssertNotNil([file queryForSchema:schema dialect:UDSQLDialectSQLite databaseName:@"empty.sqlite" error:&error], @"%@", error);
}

// ---------------------------------------------------------------------------
// MARK: - Its editor
// ---------------------------------------------------------------------------

/// Copied and exported, values as they are, not as the grid shows them: a
/// line break, a blob, NULL.
- (void)testValuesAsTheyAre {
    AppDelegate *delegate = [[AppDelegate alloc] init];
    UDWorkspace *workspace = [delegate openFolderAtURL:[NSURL fileURLWithPath:_folder]];
    UDDocumentWindowController *controller = workspace.windowControllers.firstObject;
    [controller showWindow:nil];
    UDSQLDatabases *databases = [self databasesOf:controller];
    UDSQLDatabase *shop = [[UDPluginClass(@"UDSQLDatabase") alloc] init];
    shop.name = @"shop.sqlite";
    shop.URL = [NSURL fileURLWithPath:[_folder stringByAppendingPathComponent:@"shop.sqlite"]];
    [databases addDatabase:shop];
    [databases connect:shop];
    UDRunUntil(shop.connected, 10.0);
    [databases browseTable:[shop.schema tableNamed:@"notes"] entity:nil database:shop];
    UDSQLExampleViewController *editor = (UDSQLExampleViewController *)[controller.editorTabs viewControllerForItem:controller.editorTabs.selectedItem];
    UDRunUntil(!editor.running && editor.result.rows.count == 1, 10.0);
    XCTAssertEqualObjects([editor tableView:editor.resultsView objectValueForTableColumn:editor.resultsView.tableColumns[1] row:0], @"a ↵ b\tc",
                          @"the grid shows a line break so");
    XCTAssertEqualObjects([editor valueTextAtRow:0 column:1], @"a\nb\tc", @"its value as it is");
    XCTAssertEqualObjects([editor valueTextAtRow:0 column:2], @"\\x0a1b", @"a blob in hex");
    XCTAssertNil([editor valueTextAtRow:0 column:3], @"NULL");
    // Copy: its rows tab-separated, a field with a tab or line break quoted
    [editor copyWithColumnNames:nil];
    XCTAssertEqualObjects([[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString],
                          @"id\tbody\tdata\tkind\n1\t\"a\nb\tc\"\t\\x0a1b\t");
    [editor copyColumnAtIndex:2 withName:NO];
    XCTAssertEqualObjects([[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString], @"\\x0a1b");
    // exported so too
    NSURL *csv = [NSURL fileURLWithPath:[_folder stringByAppendingPathComponent:@"notes.csv"]];
    [editor exportToURL:csv format:@"csv"];
    UDRunUntil(!editor.running && [editor.statusLabel.stringValue hasSuffix:@"notes.csv"], 10.0);
    XCTAssertEqualObjects([NSString stringWithContentsOfURL:csv encoding:NSUTF8StringEncoding error:NULL],
                          @"id,body,data,kind\r\n1,\"a\nb\tc\",\\x0a1b,\r\n");
    NSURL *json = [NSURL fileURLWithPath:[_folder stringByAppendingPathComponent:@"notes.json"]];
    [editor exportToURL:json format:@"json"];
    UDRunUntil(!editor.running && [editor.statusLabel.stringValue hasSuffix:@"notes.json"], 10.0);
    XCTAssertEqualObjects([NSString stringWithContentsOfURL:json encoding:NSUTF8StringEncoding error:NULL],
                          @"[\n  {\"id\": 1, \"body\": \"a\\nb\\tc\", \"data\": \"\\\\x0a1b\", \"kind\": null}\n]\n");
    // a double-click: its whole value, selectable
    XCTAssertNotNil(editor.valueView, @"the XIB's value view");
    XCTAssertEqual(editor.resultsView.doubleAction, @selector(showValue:));
    [controller close];
    [workspace close];
}

/// The form: what its controls set is the
/// entry's text, as typed (the query, the file as they were).
- (void)testItsForm {
    AppDelegate *delegate = [[AppDelegate alloc] init];
    UDWorkspace *workspace = [delegate openFolderAtURL:[NSURL fileURLWithPath:_folder]];
    UDDocumentWindowController *controller = workspace.windowControllers.firstObject;
    [controller showWindow:nil];
    UDSQLDatabases *databases = [self databasesOf:controller];
    UDSQLDatabase *shop = [[UDPluginClass(@"UDSQLDatabase") alloc] init];
    shop.name = @"shop.sqlite";
    shop.URL = [NSURL fileURLWithPath:[_folder stringByAppendingPathComponent:@"shop.sqlite"]];
    [databases addDatabase:shop];
    [databases connect:shop];
    UDRunUntil(shop.connected, 10.0);
    [databases newExampleQueryOfDatabase:shop table:[shop.schema tableNamed:@"customers"]];
    UDSQLExampleViewController *editor = (UDSQLExampleViewController *)[controller.editorTabs viewControllerForItem:controller.editorTabs.selectedItem];
    UDSQLSkeletonViewController *customers = editor.skeletons[0];
    XCTAssertEqualObjects([customers.lines valueForKey:@"column"], (@[ @"id", @"name", @"city" ]));
    XCTAssertEqualObjects(customers.lines[1].nameLabel.stringValue, @"name");
    XCTAssertEqualObjects(customers.rowHeads[0].titleLabel.stringValue, @"Row 1");
    NSString *(^entry)(NSString *) = ^NSString *(NSString *column) { return editor.file.skeletons[0].rows[0].entries[column]; };
    UDSQLFormParts *ids = [customers partsOfColumn:@"id" row:0], *names = [customers partsOfColumn:@"name" row:0];
    UDSQLFormParts *cities = [customers partsOfColumn:@"city" row:0];
    void (^choose)(UDSQLFormParts *, NSPopUpButton *, NSInteger) = ^(UDSQLFormParts *parts, NSPopUpButton *button, NSInteger index) {
        [button selectItemAtIndex:index];
        [parts changed:button];
    };
    void (^type)(UDSQLFormParts *, NSTextField *, NSString *) = ^(UDSQLFormParts *parts, NSTextField *field, NSString *text) {
        field.stringValue = text;
        [parts changed:field];
    };
    // Show: P.; a Total: P.CNT. (shown); a value typed whole: read so
    names.showButton.state = NSControlStateValueOn;
    [names changed:names.showButton];
    XCTAssertEqualObjects(entry(@"name"), @"P.");
    choose(ids, ids.totalButton, UDSQLExampleTotalCount);
    XCTAssertEqualObjects(entry(@"id"), @"P.CNT.");
    XCTAssertEqual(ids.showButton.state, NSControlStateValueOn, @"an aggregate, shown");
    type(ids, ids.valueField, @"> 1");
    XCTAssertEqualObjects(entry(@"id"), @"P.CNT. > 1", @"a value typed whole: its operator read from it");
    XCTAssertEqual(ids.opButton.indexOfSelectedItem, (NSInteger)UDSQLExampleOperatorGreater);
    XCTAssertEqualObjects(ids.valueField.stringValue, @"1");
    choose(ids, ids.totalButton, UDSQLExampleTotalNone);
    choose(ids, ids.opButton, UDSQLExampleOperatorNone);
    XCTAssertEqualObjects(entry(@"id"), @"P.1", @"no operator: the value as typed");
    type(ids, ids.valueField, @"");
    ids.showButton.state = NSControlStateValueOff;
    [ids changed:ids.showButton];
    XCTAssertNil(entry(@"id"), @"nothing asked: nothing kept");
    // an operator before its value; between, its To
    choose(cities, cities.opButton, UDSQLExampleOperatorBetween);
    XCTAssertEqual(cities.opButton.indexOfSelectedItem, (NSInteger)UDSQLExampleOperatorBetween, @"kept till a value is typed");
    XCTAssertTrue(cities.toField.isEnabled);
    type(cities, cities.valueField, @"A");
    type(cities, cities.toField, @"P");
    XCTAssertEqualObjects(entry(@"city"), @"A..P");
    choose(cities, cities.opButton, UDSQLExampleOperatorEqual);
    type(cities, cities.valueField, @"Oslo");
    XCTAssertEqualObjects(entry(@"city"), @"Oslo");
    XCTAssertFalse(cities.toField.isEnabled, @"To: between's alone");
    // Sort: the answer's order, shown as it is
    [customers.lines[1].sortButton selectItemAtIndex:2];
    [customers.lines[1] sortChanged:nil];
    XCTAssertEqualObjects(editor.file.order.firstObject.key, @"name");
    XCTAssertFalse(editor.file.order.firstObject.ascending);
    XCTAssertEqual(customers.lines[1].sortButton.indexOfSelectedItem, 2);
    UDRunUntil(!editor.running && editor.result.rows.count == 2, 10.0);
    XCTAssertEqualObjects(editor.result.rows, (@[ @[ @"Cy" ], @[ @"Ann" ] ]), @"%@", editor.statusLabel.stringValue);
    [customers.lines[1].sortButton selectItemAtIndex:0];
    [customers.lines[1] sortChanged:nil];
    XCTAssertEqualObjects(editor.file.order, @[]);
    // a row's kind: not there (¬)
    XCTAssertEqualObjects(customers.rowHeads[0].kindButton.itemTitles.firstObject, @"is there");
    [customers.rowHeads[0].kindButton selectItemAtIndex:1];
    [customers.rowHeads[0] kindChanged:nil];
    XCTAssertTrue(editor.file.skeletons[0].rows[0].negated);
    [customers.rowHeads[0].kindButton selectItemAtIndex:0];
    [customers.rowHeads[0] kindChanged:nil];
    // another row: its parts across; removed, the one last set
    [customers addRow:nil];
    XCTAssertEqualObjects(customers.rowHeads[1].titleLabel.stringValue, @"Row 2");
    UDSQLFormParts *names2 = [customers partsOfColumn:@"name" row:1];
    XCTAssertGreaterThan(NSMinX(names2.view.frame), NSMinX([customers partsOfColumn:@"name" row:0].view.frame), @"across, after the first");
    type(names2, names2.valueField, @"Bob");
    XCTAssertEqualObjects(editor.file.skeletons[0].rows[1].entries[@"name"], @"Bob");
    [customers removeRow:nil];
    XCTAssertEqual(editor.file.skeletons[0].rows.count, 1u);
    XCTAssertNil([customers partsOfColumn:@"name" row:1]);
    XCTAssertEqualObjects(entry(@"name"), @"P.", @"the other row as it was");
    [controller close];
    [workspace close];
}

- (void)testItsEditor {
    AppDelegate *delegate = [[AppDelegate alloc] init];
    UDWorkspace *workspace = [delegate openFolderAtURL:[NSURL fileURLWithPath:_folder]];
    UDDocumentWindowController *controller = workspace.windowControllers.firstObject;
    [controller showWindow:nil];
    UDSQLDatabases *databases = [self databasesOf:controller];
    for (NSString *name in @[ @"shop.sqlite", @"staging.sqlite", @"empty.sqlite" ]) {
        UDSQLDatabase *database = [[UDPluginClass(@"UDSQLDatabase") alloc] init];
        database.name = name;
        database.URL = [NSURL fileURLWithPath:[_folder stringByAppendingPathComponent:name]];
        [databases addDatabase:database];
    }
    UDSQLDatabase *shop = [databases databaseNamed:@"shop.sqlite"];
    [databases connect:shop];
    UDRunUntil(shop.connected, 10.0);

    // a new one: untitled, opened in its editor (its document's mode's)
    NSURL *url = [NSURL fileURLWithPath:[_folder stringByAppendingPathComponent:@"big orders.qbe"]];
    [databases newExampleQueryOfDatabase:shop table:[shop.schema tableNamed:@"customers"]];
    UDSQLExampleViewController *editor = (UDSQLExampleViewController *)[controller.editorTabs viewControllerForItem:controller.editorTabs.selectedItem];
    XCTAssertTrue([editor isKindOfClass:UDPluginClass(@"UDSQLExampleViewController")], @"%@", editor);
    XCTAssertEqualObjects(editor.document.languageMode.identifier, @"qbe");
    XCTAssertEqualObjects(editor.document.languageMode.displayName, @"Query by Example");
    XCTAssertNil(editor.document.fileURL, @"no file asked for yet");
    XCTAssertEqualObjects(controller.editorTabs.selectedItem.title, @"customers", @"named for its table, till saved");
    XCTAssertEqual(editor.database, shop, @"asked of the database it was made from");
    XCTAssertEqualObjects(editor.databaseButton.titleOfSelectedItem, @"shop.sqlite");
    XCTAssertEqual(editor.skeletons.count, 1u);
    XCTAssertNotNil(editor.skeletons[0].formView, @"its skeleton's XIB");
    XCTAssertEqualObjects([editor.skeletons[0].lines valueForKey:@"column"], (@[ @"id", @"name", @"city" ]), @"a form: a line each column");
    XCTAssertEqual(editor.skeletons[0].rowHeads.count, 1u);
    XCTAssertNotNil([editor.skeletons[0] partsOfColumn:@"city" row:0].valueField, @"its parts' XIB");
    XCTAssertEqualObjects([[editor.skeletons[0].operatorMenu itemAtIndex:0] title], @"New Example Element");
    XCTAssertFalse(controller.editorTabs.selectedItem.dirty);

    // a table added (the list's +): joined along its key by elements of
    // its own, and selected
    XCTAssertEqualObjects(editor.addTableButton.title, @"+");
    XCTAssertEqual(editor.removeTableButton.action, @selector(removeTable:));
    [editor addTableChosen:[editor.addTableButton.menu itemWithTitle:@"orders"]];
    XCTAssertEqual(editor.skeletons.count, 2u);
    XCTAssertEqual(editor.selectedSkeleton, 1);
    XCTAssertTrue([editor.skeletons[1].view isKindOfClass:UDPluginClass(@"UDSQLSkeletonView")]);
    XCTAssertEqualObjects(editor.file.skeletons[0].rows[0].entries[@"id"], @"_customers");
    XCTAssertEqualObjects(editor.file.skeletons[1].rows[0].entries[@"customer"], @"_customers");
    XCTAssertTrue(controller.editorTabs.selectedItem.dirty, @"its document changed: its tab's dot");
    XCTAssertTrue(editor.document.isModified);
    // printed columns, a condition: by its menu, and typed
    [editor.skeletons[0] applyOperator:100 element:nil column:@"name" row:0];
    [editor.skeletons[1] setEntry:@"P.> 6" column:@"total" row:0];
    XCTAssertEqualObjects(editor.file.skeletons[0].rows[0].entries[@"name"], @"P.");
    [editor run:nil];
    UDRunUntil(!editor.running && editor.result != nil, 10.0);
    XCTAssertEqualObjects(editor.result.rows, (@[ @[ @"Ann", @20 ], @[ @"Bob", @7 ] ]), @"%@", editor.statusLabel.stringValue);
    XCTAssertEqual(editor.resultsView.numberOfRows, 2);
    XCTAssertEqualObjects(editor.statusLabel.stringValue, @"Rows 1–2 of 2 (shop.sqlite)");

    // a page at a time: ◀ ▶, how many told
    editor.pageSize = 1;
    [editor run:nil];
    UDRunUntil(!editor.running && editor.result.rows.count == 1, 10.0);
    XCTAssertEqualObjects(editor.statusLabel.stringValue, @"Rows 1–1 of 2 (shop.sqlite)");
    XCTAssertTrue(editor.nextButton.isEnabled);
    XCTAssertFalse(editor.previousButton.isEnabled);
    [editor nextPage:nil];
    UDRunUntil(!editor.running && [editor.statusLabel.stringValue hasPrefix:@"Rows 2"], 10.0);
    XCTAssertEqualObjects(editor.result.rows, (@[ @[ @"Bob", @7 ] ]));
    XCTAssertFalse(editor.nextButton.isEnabled);
    XCTAssertTrue(editor.previousButton.isEnabled);
    [editor previousPage:nil];
    UDRunUntil(!editor.running && [editor.statusLabel.stringValue hasPrefix:@"Rows 1"], 10.0);
    editor.pageSize = 100;
    [editor run:nil];
    UDRunUntil(!editor.running && editor.result.rows.count == 2, 10.0);

    // a column copied: its values, its name first; its name's menu
    [editor copyColumnAtIndex:0 withName:YES];
    XCTAssertEqualObjects([[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString], @"name\nAnn\nBob");
    XCTAssertEqual(editor.resultsView.headerView.menu, editor.headerMenu);
    XCTAssertEqualObjects([editor.headerMenu.itemArray valueForKey:@"title"],
                          (@[ @"Copy Column", @"Copy Column with Name", @"", @"Sort Ascending", @"Sort Descending" ]));
    XCTAssertEqualObjects([editor.exportFormatButton itemTitles], (@[ @"CSV", @"JSON" ]));

    // exported: all of it (not a page's), as CSV and JSON
    editor.pageSize = 1;
    NSURL *csv = [NSURL fileURLWithPath:[_folder stringByAppendingPathComponent:@"orders.csv"]];
    [editor exportToURL:csv format:@"csv"];
    UDRunUntil(!editor.running && [editor.statusLabel.stringValue hasSuffix:@"orders.csv"], 10.0);
    XCTAssertEqualObjects(editor.statusLabel.stringValue, @"2 rows exported to orders.csv");
    XCTAssertEqualObjects([NSString stringWithContentsOfURL:csv encoding:NSUTF8StringEncoding error:NULL], @"name,total\r\nAnn,20\r\nBob,7\r\n");
    NSURL *json = [NSURL fileURLWithPath:[_folder stringByAppendingPathComponent:@"orders.json"]];
    [editor exportToURL:json format:@"json"];
    UDRunUntil(!editor.running && [editor.statusLabel.stringValue hasSuffix:@"orders.json"], 10.0);
    XCTAssertEqualObjects([NSString stringWithContentsOfURL:json encoding:NSUTF8StringEncoding error:NULL],
                          @"[\n  {\"name\": \"Ann\", \"total\": 20},\n  {\"name\": \"Bob\", \"total\": 7}\n]\n");
    editor.pageSize = 100;

    // its ▾'s Aggregate (again: none), and Sort, by the name it is printed under
    [editor.skeletons[1] applyOperator:110 element:nil column:@"total" row:0];
    XCTAssertEqualObjects(editor.file.skeletons[1].rows[0].entries[@"total"], @"P.SUM. > 6");
    [editor.skeletons[1] applyOperator:110 element:nil column:@"total" row:0];
    XCTAssertEqualObjects(editor.file.skeletons[1].rows[0].entries[@"total"], @"P.> 6");
    // Group By: G. (again: none)
    [editor.skeletons[0] applyOperator:103 element:nil column:@"name" row:0];
    XCTAssertEqualObjects(editor.file.skeletons[0].rows[0].entries[@"name"], @"P.G.");
    [editor.skeletons[0] applyOperator:103 element:nil column:@"name" row:0];
    XCTAssertEqualObjects(editor.file.skeletons[0].rows[0].entries[@"name"], @"P.");
    [editor skeleton:editor.skeletons[1] sortsByColumn:@"total" ascending:NO];
    XCTAssertEqualObjects(editor.file.order.firstObject.key, @"total");
    XCTAssertFalse(editor.file.order.firstObject.ascending);
    UDRunUntil(!editor.running && editor.result.rows.count == 2, 10.0);
    XCTAssertEqualObjects(editor.result.rows.firstObject, (@[ @"Ann", @20 ]));

    // its condition box: kept in its file, coloured, run with it
    XCTAssertNotNil(editor.conditionsView, @"the XIB's condition box");
    XCTAssertTrue([editor.conditionsView.toolTip hasPrefix:@"The condition box"]);
    [editor setConditionsText:@"_customers <> 2"];
    XCTAssertEqualObjects(editor.file.conditions, @[ @"_customers <> 2" ]);
    XCTAssertTrue([[editor.document.textModel getValue] containsString:@"\"conditions\": [\n    \"_customers <> 2\"\n  ]"],
                  @"%@", [editor.document.textModel getValue]);
    XCTAssertTrue([editor.conditionsView.textStorage isKindOfClass:UDPluginClass(@"UDSQLExampleTextStorage")], @"it colours as typed");
    // coloured by kind (the palette is UDSQLExampleTokenColor's): the
    // element, the operator, the number, each its own
    NSTextStorage *box = editor.conditionsView.textStorage;
    NSColor *element = [box attribute:NSForegroundColorAttributeName atIndex:1 effectiveRange:NULL];
    NSColor *op = [box attribute:NSForegroundColorAttributeName atIndex:[box.string rangeOfString:@"<>"].location effectiveRange:NULL];
    NSColor *number = [box attribute:NSForegroundColorAttributeName atIndex:box.length - 1 effectiveRange:NULL];
    NSUInteger kinds = [NSSet setWithArray:@[ element, op, number ]].count;
    XCTAssertEqual(kinds, 3u, @"%@ %@ %@", element, op, number);
    [editor run:nil];
    UDRunUntil(!editor.running && editor.result.rows.count == 1, 10.0);
    XCTAssertEqualObjects(editor.result.rows, (@[ @[ @"Ann", @20 ] ]), @"%@", editor.statusLabel.stringValue);
    [editor setConditionsText:@""];
    XCTAssertEqualObjects(editor.file.conditions, @[]);
    XCTAssertFalse([[editor.document.textModel getValue] containsString:@"conditions"], @"none typed: none kept");

    // the form's value: coloured, and what its line says in words in its tooltip
    UDSQLFormParts *total = [editor.skeletons[1] partsOfColumn:@"total" row:0];
    XCTAssertEqual(total.showButton.state, NSControlStateValueOn, @"P.: shown");
    XCTAssertEqual(total.opButton.indexOfSelectedItem, (NSInteger)UDSQLExampleOperatorGreater);
    NSAttributedString *shown = total.valueField.attributedStringValue;
    XCTAssertEqualObjects(shown.string, @"6");
    NSColor *valueColour = [shown attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL];
    XCTAssertNotNil(valueColour);
    // being edited, coloured as typed: the field editor's storage colours
    // (its own given back after)
    XCTAssertTrue([controller.window makeFirstResponder:total.valueField]);
    NSTextView *fieldEditor = (NSTextView *)total.valueField.currentEditor;
    XCTAssertTrue([fieldEditor.textStorage isKindOfClass:UDPluginClass(@"UDSQLExampleTextStorage")], @"%@", fieldEditor.textStorage);
    XCTAssertEqualObjects(fieldEditor.string, @"6");
    XCTAssertEqualObjects([fieldEditor.textStorage attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL], valueColour,
                          @"as the field shows it");
    [controller.window makeFirstResponder:nil];
    XCTAssertFalse([fieldEditor.textStorage isKindOfClass:UDPluginClass(@"UDSQLExampleTextStorage")], @"the window's field editor, as it was");
    XCTAssertEqualObjects(editor.file.skeletons[1].rows[0].entries[@"total"], @"P.> 6", @"left as it was");
    XCTAssertTrue([total.valueField.toolTip hasPrefix:@"P. — printed: a column of the answer\n> 6 — the rows whose value is so"],
                  @"%@", total.valueField.toolTip);

    // its first save: where asked (the window's Save's panel), its tab named
    // for its file, its database remembered for it
    [controller _save:editor.document asURL:url];
    XCTAssertEqualObjects(editor.document.fileURL.path, url.path);
    XCTAssertEqualObjects(controller.editorTabs.selectedItem.title, @"big orders.qbe");
    XCTAssertEqualObjects(controller.editorTabs.selectedItem.toolTip, url.path);
    XCTAssertEqualObjects([[NSUserDefaults standardUserDefaults] dictionaryForKey:@"UDSQLDocumentDatabases"][url.path], @"shop.sqlite");
    // saved by the window's Save: its JSON on disk
    [controller saveDocument:nil];
    XCTAssertFalse(editor.document.isModified);
    XCTAssertFalse(controller.editorTabs.selectedItem.dirty);
    NSError *error = nil;
    UDSQLExampleFile *saved = [UDPluginClass(@"UDSQLExampleFile") fileWithData:[NSData dataWithContentsOfURL:url] error:&error];
    XCTAssertEqualObjects([saved.skeletons valueForKey:@"table"], (@[ @"customers", @"orders" ]), @"%@", error);
    XCTAssertEqualObjects(saved.skeletons[1].rows[0].entries[@"total"], @"P.> 6");

    // undone: its document's (an event's group ended, as a click's would)
    NSUndoManager *undo = editor.document.textModel.undoManager;
    while (undo.groupingLevel > 0) [undo endUndoGrouping];
    [undo beginUndoGrouping];
    [editor.skeletons[1] setEntry:@"P." column:@"total" row:0];
    [undo endUndoGrouping];
    XCTAssertEqualObjects(editor.file.skeletons[1].rows[0].entries[@"total"], @"P.");
    [editor undo:nil];
    XCTAssertEqualObjects(editor.file.skeletons[1].rows[0].entries[@"total"], @"P.> 6", @"read back from its undone text");

    // as text: its JSON; its text edited, read back
    NSUInteger tabs = controller.editorTabs.items.count;
    [editor showAsText:nil];
    XCTAssertEqual(controller.editorTabs.items.count, tabs + 1);
    UDCodeEditorViewController *text = (UDCodeEditorViewController *)[controller.editorTabs viewControllerForItem:controller.editorTabs.selectedItem];
    XCTAssertTrue([text isKindOfClass:[UDCodeEditorViewController class]]);
    XCTAssertTrue([text.textView.string containsString:@"\"_customers\""], @"%@", text.textView.string);
    UDTextModel *model = editor.document.textModel;
    NSString *edited = [[model getValue] stringByReplacingOccurrencesOfString:@"P.> 6" withString:@"P.> 10"];
    [undo beginUndoGrouping];
    [model applyEdits:@[ [[UDTextModelEdit alloc] initWithRange:[model validateRange:(UDRange){ 1, 1, NSIntegerMax, NSIntegerMax }] text:edited] ]];
    [undo endUndoGrouping];
    XCTAssertEqualObjects(editor.file.skeletons[1].rows[0].entries[@"total"], @"P.> 10", @"its editor reads its text again");
    [editor showAsText:nil];
    XCTAssertEqual(controller.editorTabs.items.count, tabs + 1, @"its text's tab again, not another");

    // the same query, of staging; of a database without its table
    editor.databaseButton.title = @"staging.sqlite";
    [editor.databaseButton selectItemWithTitle:@"staging.sqlite"];
    [editor chooseDatabase:nil];
    [editor run:nil];
    NSArray *staged = @[ @[ @"Test", @99 ] ];
    UDRunUntil(!editor.running && [editor.result.rows isEqual:staged], 10.0);
    XCTAssertEqualObjects(editor.result.rows, staged, @"%@", editor.statusLabel.stringValue);
    XCTAssertTrue([editor.statusLabel.stringValue hasSuffix:@"(staging.sqlite)"], @"%@", editor.statusLabel.stringValue);
    [editor.databaseButton selectItemWithTitle:@"empty.sqlite"];
    [editor chooseDatabase:nil];
    [editor run:nil];
    UDRunUntil([editor.statusLabel.stringValue hasPrefix:@"empty.sqlite has"], 10.0);
    XCTAssertEqualObjects(editor.statusLabel.stringValue, @"empty.sqlite has no table orders.");
    XCTAssertTrue([editor.skeletons[1].titleLabel.stringValue hasSuffix:@"(not in this database)"]);

    // its SQL, plain, for an app
    [editor.databaseButton selectItemWithTitle:@"shop.sqlite"];
    [editor chooseDatabase:nil];
    [editor copySQL:nil];
    XCTAssertEqualObjects([[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString],
                          @"SELECT \"customers\".\"name\", \"orders\".\"total\"\nFROM \"customers\"\n"
                           "JOIN \"orders\" ON \"orders\".\"customer\" = \"customers\".\"id\"\nWHERE \"orders\".\"total\" > 10\n"
                           "ORDER BY \"orders\".\"total\" DESC",
                          @"as written by hand: a clause a line; its order, the file's");

    // a row added, the one last edited in removed (Remove Row); the selected
    // table removed (the list's −); each an event's edit
    [undo beginUndoGrouping];
    [editor.skeletons[1] addRow:nil];
    XCTAssertEqual(editor.file.skeletons[1].rows.count, 2u);
    UDSQLFormParts *second = [editor.skeletons[1] partsOfColumn:@"id" row:1];
    second.showButton.state = NSControlStateValueOn;
    [second changed:second.showButton];
    [editor.skeletons[1] removeRow:nil];
    XCTAssertEqual(editor.file.skeletons[1].rows.count, 1u);
    XCTAssertEqualObjects(editor.file.skeletons[1].rows[0].entries[@"total"], @"P.> 10", @"the one edited in went, not the other");
    [undo endUndoGrouping];
    [editor skeletonWantsToBeSelected:editor.skeletons[0]];
    XCTAssertEqual(editor.selectedSkeleton, 0);
    XCTAssertTrue(editor.skeletons[0].selected);
    XCTAssertFalse(editor.skeletons[1].selected);
    [editor skeletonWantsToBeSelected:editor.skeletons[1]];
    [undo beginUndoGrouping];
    [editor removeTable:nil];
    [undo endUndoGrouping];
    XCTAssertEqualObjects([editor.file.skeletons valueForKey:@"table"], @[ @"customers" ]);
    XCTAssertEqual(editor.selectedSkeleton, 0, @"the one left selected");
    XCTAssertTrue(editor.removeTableButton.isEnabled);
    [controller.editorTabs selectItem:controller.editorTabs.items[tabs - 1]];
    [controller saveDocument:nil];
    [controller close];
    [workspace close];
}

@end
