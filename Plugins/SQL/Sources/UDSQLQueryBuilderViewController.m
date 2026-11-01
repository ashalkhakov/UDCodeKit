/*---------------------------------------------------------------------------------------------
 *  UDSQLQueryBuilderViewController.m
 *--------------------------------------------------------------------------------------------*/

#import "UDSQLQueryBuilderViewController.h"
#import "UDSQLDatabases.h"
#import "UDSQLValues.h"
#import "UDSQLConditionCell.h"
#import <objc/runtime.h>

static const NSUInteger UDMaxRows = 1000;

/// The design grid's rows: its sort, whether it is shown, then its rows of
/// conditions.
enum { UDSortRow = 0, UDShowRow = 1, UDConditionRow = 2 };

@interface UDSQLQueryBuilderViewController ()
@property (nonatomic, weak) IBOutlet DKCanvasView *canvas;
@property (nonatomic, weak) IBOutlet NSTableView *designView;
@property (nonatomic, weak) IBOutlet NSTableView *resultsView;
@property (nonatomic, weak) IBOutlet NSPopUpButton *addTableButton;
@property (nonatomic, weak) IBOutlet NSSegmentedControl *paneControl;
@property (nonatomic, weak) IBOutlet NSTextField *statusLabel;
@property (nonatomic, strong) IBOutlet NSMenu *tableMenu;
@property (nonatomic, strong) IBOutlet NSMenu *columnMenu;
@property (nonatomic, strong) IBOutlet NSMenu *joinMenu;
@property (nonatomic, strong) IBOutlet NSMenu *operatorMenu;
@property (nonatomic, strong) IBOutlet NSTableColumn *labelTemplate;
@property (nonatomic, strong) IBOutlet NSTableColumn *sortTemplate;
@property (nonatomic, strong) IBOutlet NSTableColumn *showTemplate;
@property (nonatomic, strong) IBOutlet NSTableColumn *conditionTemplate;
@property (nonatomic, strong) IBOutlet NSTableColumn *resultTemplate;
@end

@implementation UDSQLQueryBuilderViewController {
    __weak UDSQLDatabases *_databases;
    NSArray<UDSQLStatement *> *_pending;    // the run asked for last
    BOOL _waitsForConnection;
    id _menuItem;                           // the canvas's item its menu is about
    NSInteger _menuRow, _menuColumn;        // the design's condition whose ▾ was clicked; -1: none
}

- (instancetype)initWithDatabases:(UDSQLDatabases *)databases database:(UDSQLDatabase *)database {
    self = [super initWithNibName:@"UDSQLQueryBuilder" bundle:[NSBundle bundleForClass:[UDSQLQueryBuilderViewController class]]];
    if (self) {
        _databases = databases;
        _database = database;
        _menuRow = _menuColumn = -1;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_databasesDidChange:)
                                                     name:UDSQLDatabasesDidChangeNotification object:databases];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    for (NSTableColumn *column in @[ _sortTemplate, _showTemplate, _conditionTemplate ]) [_designView removeTableColumn:column];
    [_resultsView removeTableColumn:_resultTemplate];
    _labelTemplate.editable = NO;
    if (_database.schema) [self _useSchema];
    else {
        _waitsForConnection = YES;
        if (!_database.connecting) [_databases connect:_database];
        _statusLabel.stringValue = @"Connecting…";
    }
}

- (void)_databasesDidChange:(NSNotification *)note {
    if (!self.isViewLoaded) return;
    if (_waitsForConnection && _database.schema) {
        _waitsForConnection = NO;
        if (!_design) [self _useSchema];
        if (_pending == nil && [_statusLabel.stringValue isEqualToString:@"Running…"]) [self run:nil];
    } else if (_waitsForConnection && !_database.connecting && _database.error) {
        _waitsForConnection = NO;
        [self _showError:_database.error];
    }
}

- (void)_useSchema {
    _design = [[UDSQLQueryDesign alloc] initWithSchema:_database.schema dialect:_database.dialect];
    _diagram = [[UDSQLQueryDiagram alloc] initWithDesign:_design measure:[DKAppKitSurface surface]];
    // Add Table: the schema's tables, then its views
    NSMenu *menu = _addTableButton.menu;
    while (menu.numberOfItems > 1) [menu removeItemAtIndex:1];
    for (UDSQLTable *table in _database.schema.tables) {
        NSString *title = table.schema.length && ![table.schema isEqualToString:@"public"]
            ? [NSString stringWithFormat:@"%@.%@", table.schema, table.name] : table.name;
        NSMenuItem *item = [menu addItemWithTitle:title action:@selector(addTableChosen:) keyEquivalent:@""];
        item.target = self;
        item.representedObject = table;
    }
    [self designChanged];
}

// ---------------------------------------------------------------------------
// MARK: - The design
// ---------------------------------------------------------------------------

- (void)designChanged {
    [_diagram update];
    [self _makeDesignColumns];
    [_canvas reloadData];
    [self _showStatus];
}

- (void)_showStatus {
    _statusLabel.textColor = [NSColor secondaryLabelColor];
    if (!_design.tables.count) {
        _statusLabel.stringValue = @"Add a table; double-click its columns to make them fields";
        return;
    }
    NSArray *crossed = [_design unjoinedTables];
    if (crossed.count) {
        _statusLabel.textColor = [NSColor systemOrangeColor];
        _statusLabel.stringValue = [NSString stringWithFormat:@"%@ joined to no other table: every pair of rows (drag a column to a column to join them)",
                                    [crossed componentsJoinedByString:@", "]];
        return;
    }
    NSUInteger fields = _design.fields.count;
    _statusLabel.stringValue = [NSString stringWithFormat:@"%lu %@, %lu %@%@", (unsigned long)_design.tables.count,
                                _design.tables.count == 1 ? @"table" : @"tables", (unsigned long)fields, fields == 1 ? @"field" : @"fields",
                                fields ? @"" : @" (all columns shown)"];
}

- (void)addTable:(UDSQLTable *)table {
    [_design addTable:table];
    [self designChanged];
}

- (IBAction)addTableChosen:(id)sender {
    UDSQLTable *table = [sender representedObject];
    if (table) [self addTable:table];
}

- (void)toggleFieldOf:(UDSQLQueryColumn *)column {
    UDSQLQueryField *field = [_design fieldOf:column.columnName table:column.alias];
    if (field) [_design removeField:field];
    else {
        field = [_design addField:column.columnName ofTable:column.alias];
        field.conditions = @[];
    }
    [self designChanged];
}

- (void)joinColumn:(UDSQLQueryColumn *)from toColumn:(UDSQLQueryColumn *)to {
    if ([from.alias isEqualToString:to.alias]) return;
    [_design joinTable:from.alias column:from.columnName toTable:to.alias column:to.columnName kind:UDSQLJoinInner];
    [self designChanged];
}

- (IBAction)addConditionRow:(id)sender {
    _design.conditionRows += 1;
    [_designView reloadData];
}

// ---------------------------------------------------------------------------
// MARK: - The design's grid: a column a field
// ---------------------------------------------------------------------------

- (void)_makeDesignColumns {
    for (NSTableColumn *column in [_designView.tableColumns copy]) {
        if (column != _labelTemplate) [_designView removeTableColumn:column];
    }
    NSDictionary *font = @{ NSFontAttributeName: [NSFont boldSystemFontOfSize:[NSFont smallSystemFontSize]] };
    NSArray *fields = _design.fields;
    for (NSUInteger i = 0; i < fields.count; i++) {
        UDSQLQueryField *field = fields[i];
        NSString *title = [NSString stringWithFormat:@"%@.%@", field.alias, field.column];
        NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:[NSString stringWithFormat:@"%lu", (unsigned long)i]];
        [column.headerCell setStringValue:title];
        column.width = MAX(100, MIN(260, ceil([title sizeWithAttributes:font].width) + 24));
        column.minWidth = 60;
        column.maxWidth = 2000;
        column.editable = YES;
        [_designView addTableColumn:column];
    }
    [_designView reloadData];
}

- (nullable UDSQLQueryField *)_fieldOfColumn:(NSTableColumn *)column {
    if (!column || column == _labelTemplate) return nil;
    NSInteger index = [column.identifier integerValue];
    NSArray *fields = _design.fields;
    return index >= 0 && (NSUInteger)index < fields.count ? fields[(NSUInteger)index] : nil;
}

- (nullable UDSQLColumnInfo *)_infoOf:(UDSQLQueryField *)field {
    for (UDSQLColumnInfo *info in [_design tableWithAlias:field.alias].table.columns) {
        if ([info.name isEqualToString:field.column]) return info;
    }
    return nil;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    if (tableView == _resultsView) return (NSInteger)_result.rows.count;
    return UDConditionRow + (NSInteger)_design.conditionRows;
}

- (NSCell *)tableView:(NSTableView *)tableView dataCellForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    if (tableView != _designView || !column || column == _labelTemplate) return column.dataCell;
    // each row its kind of cell: the XIB's templates'
    if (row == UDSortRow) return _sortTemplate.dataCell;
    if (row == UDShowRow) return _showTemplate.dataCell;
    UDSQLQueryField *field = [self _fieldOfColumn:column];
    UDSQLColumnInfo *info = field ? [self _infoOf:field] : nil;
    NSTextFieldCell *cell = [_conditionTemplate.dataCell copy];
    if (info) cell.placeholderString = [UDSQLQbE exampleForColumn:info schema:_design.schema];
    return cell;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    if (tableView == _resultsView) {
        NSUInteger index = (NSUInteger)[column.identifier integerValue];
        NSArray *values = _result.rows[(NSUInteger)row];
        UDSQLColumn *described = index < _result.columns.count ? _result.columns[index] : nil;
        return index < values.count ? UDSQLCellOfValue(values[index], described.name, described.type, _database.schema) : @"";
    }
    if (column == _labelTemplate) {
        if (row == UDSortRow) return @"Sort";
        if (row == UDShowRow) return @"Show";
        return row == UDConditionRow ? @"Where" : @"Or";
    }
    UDSQLQueryField *field = [self _fieldOfColumn:column];
    if (!field) return nil;
    if (row == UDSortRow) return @(field.sort);
    if (row == UDShowRow) return @(field.shown);
    NSUInteger index = (NSUInteger)(row - UDConditionRow);
    return index < field.conditions.count ? field.conditions[index] : @"";
}

- (void)_setCondition:(NSString *)text ofField:(UDSQLQueryField *)field row:(NSUInteger)index {
    NSMutableArray *conditions = [field.conditions mutableCopy];
    while (conditions.count <= index) [conditions addObject:@""];
    conditions[index] = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    field.conditions = conditions;
}

- (void)tableView:(NSTableView *)tableView setObjectValue:(id)value forTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    UDSQLQueryField *field = tableView == _designView ? [self _fieldOfColumn:column] : nil;
    if (!field) return;
    if (row == UDSortRow) field.sort = (UDSQLFieldSort)[value integerValue];
    else if (row == UDShowRow) field.shown = [value boolValue];
    else [self _setCondition:[value description] ?: @"" ofField:field row:(NSUInteger)(row - UDConditionRow)];
    [self _showStatus];
}

- (BOOL)tableView:(NSTableView *)tableView shouldEditTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    return tableView == _designView && [self _fieldOfColumn:column] != nil;
}

- (NSString *)tableView:(NSTableView *)tableView toolTipForCell:(NSCell *)cell rect:(NSRectPointer)rect tableColumn:(NSTableColumn *)column
                    row:(NSInteger)row mouseLocation:(NSPoint)location {
    UDSQLQueryField *field = tableView == _designView && row >= UDConditionRow ? [self _fieldOfColumn:column] : nil;
    UDSQLColumnInfo *info = field ? [self _infoOf:field] : nil;
    return info ? [UDSQLQbE helpForColumn:info schema:_design.schema] : nil;
}

/// A click on a condition: on its ▾, what can be asked.
- (IBAction)designClicked:(id)sender {
    NSInteger row = _designView.clickedRow, column = _designView.clickedColumn;
    NSEvent *event = [NSApp currentEvent];
    if (row < UDConditionRow || column < 1 || !event) return;
    NSRect cell = [_designView frameOfCellAtColumn:column row:row];
    NSPoint point = [_designView convertPoint:event.locationInWindow fromView:nil];
    if (point.x < NSMaxX(cell) - [UDSQLConditionCell menuWidth]) return;
    _menuRow = row;
    _menuColumn = column;
    [NSMenu popUpContextMenu:_operatorMenu withEvent:event forView:_designView];
}

- (IBAction)applyOperator:(id)sender {
    NSInteger row = _menuRow, column = _menuColumn;
    _menuRow = _menuColumn = -1;
    if (row < UDConditionRow || column < 1 || column >= (NSInteger)_designView.tableColumns.count) return;
    NSTableColumn *tableColumn = [_designView.tableColumns objectAtIndex:(NSUInteger)column];
    UDSQLQueryField *field = [self _fieldOfColumn:tableColumn];
    if (!field) return;
    NSUInteger index = (NSUInteger)(row - UDConditionRow);
    BOOL complete = NO;
    NSString *made = [UDSQLQbE condition:index < field.conditions.count ? field.conditions[index] : @""
                            withOperator:(UDSQLQbEOperator)[sender tag] complete:&complete];
    [_designView abortEditing];
    if (complete) {
        [self _setCondition:made ofField:field row:index];
        [_designView reloadData];
        return;
    }
    // a value still to type: the cell edited, the caret at its end
    [_designView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
    [_designView editColumn:column row:row withEvent:nil select:NO];
    NSText *editor = [_designView currentEditor];
    editor.string = made;
    editor.selectedRange = NSMakeRange(made.length, 0);
}

- (UDSQLQueryField *)_clickedField {
    NSInteger column = _designView.clickedColumn;
    return column >= 0 ? [self _fieldOfColumn:[_designView.tableColumns objectAtIndex:(NSUInteger)column]] : nil;
}

- (IBAction)moveFieldLeft:(id)sender {
    UDSQLQueryField *field = [self _clickedField];
    NSUInteger index = field ? [_design.fields indexOfObjectIdenticalTo:field] : NSNotFound;
    if (index == NSNotFound || index == 0) return;
    [_design moveField:field toIndex:index - 1];
    [self designChanged];
}

- (IBAction)moveFieldRight:(id)sender {
    UDSQLQueryField *field = [self _clickedField];
    NSUInteger index = field ? [_design.fields indexOfObjectIdenticalTo:field] : NSNotFound;
    if (index == NSNotFound) return;
    [_design moveField:field toIndex:index + 1];
    [self designChanged];
}

- (IBAction)removeField:(id)sender {
    UDSQLQueryField *field = [self _clickedField];
    if (!field) return;
    [_design removeField:field];
    [self designChanged];
}

// ---------------------------------------------------------------------------
// MARK: - The canvas: its tables, columns and joins
// ---------------------------------------------------------------------------

- (NSRect)diagramBoundsForCanvas:(DKCanvasView *)canvas {
    return _diagram ? _diagram.bounds : NSMakeRect(0, 0, 600, 300);
}

- (void)canvas:(DKCanvasView *)canvas drawInRect:(NSRect)rect surface:(id<DKSurface>)surface state:(DKDrawingState *)state {
    [_diagram drawInRect:rect surface:surface state:state];
}

- (id)canvas:(DKCanvasView *)canvas itemAtPoint:(NSPoint)point {
    return [_diagram itemAtPoint:point];
}

- (NSArray *)canvas:(DKCanvasView *)canvas itemsInRect:(NSRect)rect {
    return _diagram ? [_diagram tablesInRect:rect] : @[];
}

- (NSRect)canvas:(DKCanvasView *)canvas frameOfItem:(id)item {
    return [_diagram frameOfItem:item];
}

- (BOOL)canvas:(DKCanvasView *)canvas canMoveItem:(id)item {
    return [item isKindOfClass:[NSString class]];
}

- (void)canvas:(DKCanvasView *)canvas moveItems:(NSArray *)items by:(NSSize)delta {
    NSMutableArray *aliases = [NSMutableArray array];
    for (id item in items) if ([item isKindOfClass:[NSString class]]) [aliases addObject:item];
    [_diagram moveTables:aliases by:delta];
    [_canvas reloadData];
}

- (void)canvas:(DKCanvasView *)canvas doubleClickedItem:(id)item {
    if ([item isKindOfClass:[UDSQLQueryColumn class]]) [self toggleFieldOf:item];
}

/// A press on a column: a join made by its drag (its double-click the canvas's).
- (BOOL)canvas:(DKCanvasView *)canvas mouseDown:(NSEvent *)event atPoint:(NSPoint)point {
    id item = [_diagram itemAtPoint:point];
    if (event.clickCount != 1 || ![item isKindOfClass:[UDSQLQueryColumn class]] ||
        (event.modifierFlags & (NSEventModifierFlagShift | NSEventModifierFlagCommand))) return NO;
    _diagram.joiningFrom = item;
    _diagram.joiningTo = point;
    return YES;
}

- (void)canvas:(DKCanvasView *)canvas mouseDragged:(NSEvent *)event atPoint:(NSPoint)point {
    _diagram.joiningTo = point;
    [_canvas setNeedsDisplay:YES];
}

- (void)canvas:(DKCanvasView *)canvas mouseUp:(NSEvent *)event atPoint:(NSPoint)point {
    UDSQLQueryColumn *from = _diagram.joiningFrom;
    _diagram.joiningFrom = nil;
    id to = [_diagram itemAtPoint:point];
    if (from && [to isKindOfClass:[UDSQLQueryColumn class]] && ![[to alias] isEqualToString:from.alias]) [self joinColumn:from toColumn:to];
    else [_canvas setNeedsDisplay:YES];
}

- (NSMenu *)canvas:(DKCanvasView *)canvas menuForItem:(id)item {
    NSMenu *source = [item isKindOfClass:[UDSQLQueryJoin class]] ? _joinMenu
                   : [item isKindOfClass:[UDSQLQueryColumn class]] ? _columnMenu : item ? _tableMenu : nil;
    if (!source) return nil;
    _menuItem = item;
    NSMenu *menu = [[NSMenu alloc] initWithTitle:source.title];
    for (NSMenuItem *menuItem in source.itemArray) [menu addItem:[menuItem copy]];
    return menu;
}

- (IBAction)removeTable:(id)sender {
    if (![_menuItem isKindOfClass:[NSString class]]) return;
    [_design removeTable:_menuItem];
    _canvas.selection = [NSSet set];
    [self designChanged];
}

- (IBAction)toggleField:(id)sender {
    if ([_menuItem isKindOfClass:[UDSQLQueryColumn class]]) [self toggleFieldOf:_menuItem];
}

- (IBAction)setJoinKind:(id)sender {
    if (![_menuItem isKindOfClass:[UDSQLQueryJoin class]]) return;
    [(UDSQLQueryJoin *)_menuItem setKind:[sender tag] == 2 ? UDSQLJoinLeft : UDSQLJoinInner];
    [self designChanged];
}

- (IBAction)removeJoin:(id)sender {
    if (![_menuItem isKindOfClass:[UDSQLQueryJoin class]]) return;
    [_design removeJoin:_menuItem];
    _canvas.selection = [NSSet set];
    [self designChanged];
}

/// Delete or Backspace on the canvas: its tables and joins selected, taken away.
- (IBAction)delete:(id)sender {
    for (id item in _canvas.selection) {
        if ([item isKindOfClass:[NSString class]]) [_design removeTable:item];
        else if ([item isKindOfClass:[UDSQLQueryJoin class]]) [_design removeJoin:item];
    }
    _canvas.selection = [NSSet set];
    [self designChanged];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    SEL action = item.action;
    if (sel_isEqual(action, @selector(toggleField:)) && [_menuItem isKindOfClass:[UDSQLQueryColumn class]]) {
        item.state = [_design fieldOf:[_menuItem columnName] table:[_menuItem alias]] ? NSControlStateValueOn : NSControlStateValueOff;
    }
    if (sel_isEqual(action, @selector(setJoinKind:)) && [_menuItem isKindOfClass:[UDSQLQueryJoin class]]) {
        BOOL left = [(UDSQLQueryJoin *)_menuItem kind] == UDSQLJoinLeft;
        item.state = (item.tag == 2) == left ? NSControlStateValueOn : NSControlStateValueOff;
    }
    if (sel_isEqual(action, @selector(moveFieldLeft:)) || sel_isEqual(action, @selector(moveFieldRight:)) ||
        sel_isEqual(action, @selector(removeField:))) return [self _clickedField] != nil;
    if (sel_isEqual(action, @selector(run:)) || sel_isEqual(action, @selector(showSQL:))) return _design.tables.count > 0;
    return YES;
}

// ---------------------------------------------------------------------------
// MARK: - Running it
// ---------------------------------------------------------------------------

- (void)_showError:(NSError *)error {
    _statusLabel.textColor = [NSColor systemRedColor];
    _statusLabel.stringValue = error.localizedDescription ?: @"It failed.";
}

- (IBAction)run:(id)sender {
    [_designView.window makeFirstResponder:nil];
    if (!_database.schema) {
        _waitsForConnection = YES;
        if (!_database.connecting) [_databases connect:_database];
        _statusLabel.stringValue = @"Running…";
        return;
    }
    NSError *error = nil;
    UDSQLStatement *statement = [_design statement:&error];
    if (!statement) {
        [self _showError:error];
        return;
    }
    _pending = @[ statement ];
    _running = YES;
    _statusLabel.textColor = [NSColor secondaryLabelColor];
    _statusLabel.stringValue = @"Running…";
    [_database.runner run:_pending maxRows:UDMaxRows target:self action:@selector(_didRun:)];
}

- (void)_didRun:(UDSQLRun *)run {
    if (!run.finished || run.statements != _pending) return;
    _pending = nil;
    _running = NO;
    if (run.error) {
        [self _showError:run.error];
        return;
    }
    _result = run.results.firstObject;
    [self _makeResultColumns];
    _paneControl.selectedSegment = 1;
    [self showPane:nil];
    NSNumberFormatter *numbers = [[NSNumberFormatter alloc] init];
    numbers.numberStyle = NSNumberFormatterDecimalStyle;
    _statusLabel.textColor = [NSColor secondaryLabelColor];
    _statusLabel.stringValue = [NSString stringWithFormat:@"%@ %@%@", [numbers stringFromNumber:@(_result.rows.count)],
                                _result.rows.count == 1 ? @"row" : @"rows", _result.truncated ? @" (the first ones)" : @""];
}

- (void)_makeResultColumns {
    for (NSTableColumn *column in [_resultsView.tableColumns copy]) [_resultsView removeTableColumn:column];
    NSDictionary *font = @{ NSFontAttributeName: [NSFont systemFontOfSize:[NSFont smallSystemFontSize]] };
    for (NSUInteger i = 0; i < _result.columns.count; i++) {
        UDSQLColumn *described = _result.columns[i];
        NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:[NSString stringWithFormat:@"%lu", (unsigned long)i]];
        column.dataCell = [_resultTemplate.dataCell copy];
        [column.headerCell setStringValue:described.name];
        column.headerToolTip = described.type;
        column.editable = NO;
        CGFloat width = [described.name sizeWithAttributes:font].width;
        for (NSUInteger row = 0; row < MIN(_result.rows.count, 50u); row++) {
            NSArray *values = _result.rows[row];
            if (i < values.count) width = MAX(width, [UDSQLTextOfValue(values[i], described.name, described.type, _database.schema)
                                                         sizeWithAttributes:font].width);
        }
        column.width = MAX(48, MIN(320, ceil(width) + 16));
        [_resultsView addTableColumn:column];
    }
    [_resultsView reloadData];
}

- (IBAction)showPane:(id)sender {
    BOOL results = _paneControl.selectedSegment == 1;
    [_designView.enclosingScrollView setHidden:results];
    [_resultsView.enclosingScrollView setHidden:!results];
}

- (IBAction)showSQL:(id)sender {
    [_designView.window makeFirstResponder:nil];
    NSError *error = nil;
    NSString *sql = [_design SQL:&error];
    if (!sql) {
        [self _showError:error];
        return;
    }
    [_databases openQuery:[sql stringByAppendingString:@";\n"] database:_database run:NO];
}

@end
