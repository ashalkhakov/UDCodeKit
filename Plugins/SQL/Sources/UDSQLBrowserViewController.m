/*---------------------------------------------------------------------------------------------
 *  UDSQLBrowserViewController.m
 *--------------------------------------------------------------------------------------------*/

#import "UDSQLBrowserViewController.h"
#import "UDSQLDatabases.h"
#import "UDSQLValues.h"
#import <objc/runtime.h>

static const CGFloat UDMenuArrowWidth = 14;

/// A condition's cell: its text, and at its right a ▾ for what can be asked
/// (its menu, the browser's); an empty one shows what may be typed, dimmed.
@interface UDSQLConditionCell : NSTextFieldCell
@end

@implementation UDSQLConditionCell

- (NSRect)_textFrameOf:(NSRect)frame {
    frame.size.width = MAX(0, frame.size.width - UDMenuArrowWidth);
    return frame;
}

- (void)drawInteriorWithFrame:(NSRect)frame inView:(NSView *)view {
    [super drawInteriorWithFrame:[self _textFrameOf:frame] inView:view];
    // the ▾: a small triangle, in the middle of its strip
    CGFloat x = NSMaxX(frame) - UDMenuArrowWidth / 2, y = NSMidY(frame), flip = view.isFlipped ? 1 : -1;
    NSBezierPath *arrow = [NSBezierPath bezierPath];
    [arrow moveToPoint:NSMakePoint(x - 3.5, y - 1.5 * flip)];
    [arrow lineToPoint:NSMakePoint(x + 3.5, y - 1.5 * flip)];
    [arrow lineToPoint:NSMakePoint(x, y + 2.5 * flip)];
    [arrow closePath];
    [[NSColor disabledControlTextColor] setFill];
    [arrow fill];
}

- (void)editWithFrame:(NSRect)frame inView:(NSView *)view editor:(NSText *)editor delegate:(id)delegate event:(NSEvent *)event {
    [super editWithFrame:[self _textFrameOf:frame] inView:view editor:editor delegate:delegate event:event];
}

- (void)selectWithFrame:(NSRect)frame inView:(NSView *)view editor:(NSText *)editor delegate:(id)delegate
                  start:(NSInteger)start length:(NSInteger)length {
    [super selectWithFrame:[self _textFrameOf:frame] inView:view editor:editor delegate:delegate start:start length:length];
}

@end

@interface UDSQLBrowserViewController ()
@property (nonatomic, weak) IBOutlet NSTableView *conditionsView;
@property (nonatomic, weak) IBOutlet NSTableView *rowsView;
@property (nonatomic, weak) IBOutlet NSTextField *statusLabel;
@property (nonatomic, weak) IBOutlet NSButton *previousButton;
@property (nonatomic, weak) IBOutlet NSButton *nextButton;
@property (nonatomic, strong) IBOutlet NSTableColumn *conditionTemplate;
@property (nonatomic, strong) IBOutlet NSTableColumn *rowTemplate;
@property (nonatomic, strong) IBOutlet NSMenu *operatorMenu;
@end

@implementation UDSQLBrowserViewController {
    __weak UDSQLDatabases *_databases;
    UDSQLSchema *_schema;               // the one its columns are of
    NSMutableArray<NSMutableDictionary<NSString *, NSString *> *> *_conditions;
    NSArray<UDSQLStatement *> *_pending;    // the run asked for last
    BOOL _waitsForConnection;
    BOOL _sized;                        // its columns sized to their values once
    BOOL _scrolling;                    // one grid's scroll being followed by the other
    NSError *_conditionError;           // what can't be read, and where
    NSInteger _menuRow, _menuColumn;    // the condition whose ▾ was clicked; -1: none
}

- (instancetype)initWithDatabases:(UDSQLDatabases *)databases database:(UDSQLDatabase *)database
                            table:(UDSQLTable *)table entity:(NSNumber *)entity {
    self = [super initWithNibName:@"UDSQLBrowser" bundle:[NSBundle bundleForClass:[UDSQLBrowserViewController class]]];
    if (self) {
        _databases = databases;
        _database = database;
        _entity = entity;
        _pageSize = 100;
        _menuRow = _menuColumn = -1;
        _count = NSNotFound;
        _rows = @[];
        _conditions = [NSMutableArray arrayWithObject:[NSMutableDictionary dictionary]];
        [self _useTable:table schema:database.schema];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_databasesDidChange:)
                                                     name:UDSQLDatabasesDidChangeNotification object:databases];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

/// The query of @a table's rows (an entity's: its own and its subentities'),
/// its conditions and order kept (of the columns it still has).
- (void)_useTable:(UDSQLTable *)table schema:(UDSQLSchema *)schema {
    NSArray *order = [_query.order filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"key IN %@",
                                                                [table.columns valueForKey:@"name"]]];
    _table = table;
    _schema = schema;
    _query = [[UDSQLQbE alloc] initWithTable:table schema:schema dialect:_database.dialect];
    _query.conditions = _conditions;
    _query.order = order ?: @[];
    if (_entity && schema.coreDataStore) {
        NSMutableArray *entities = [NSMutableArray arrayWithObject:_entity];
        for (NSUInteger i = 0; i < entities.count; i++) [entities addObjectsFromArray:[schema coreDataSubentitiesOf:entities[i]]];
        // only when the table holds others' rows too
        if (entities.count < table.entities.count) {
            _query.restrictionColumn = @"Z_ENT";
            _query.restrictionValues = entities;
        }
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [_conditionTemplate.tableView removeTableColumn:_conditionTemplate];
    [_rowTemplate.tableView removeTableColumn:_rowTemplate];
    [self _makeColumns];
    // the grids scroll together, and the conditions' columns size the rows'
    for (NSScrollView *scroll in @[ _conditionsView.enclosingScrollView, _rowsView.enclosingScrollView ]) {
        scroll.contentView.postsBoundsChangedNotifications = YES;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_scrolled:)
                                                     name:NSViewBoundsDidChangeNotification object:scroll.contentView];
    }
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_columnResized:)
                                                 name:NSTableViewColumnDidResizeNotification object:_conditionsView];
    [self reload];
}

// ---------------------------------------------------------------------------
// MARK: - Columns: the table's, in both grids
// ---------------------------------------------------------------------------

- (void)_makeColumns {
    for (NSTableView *view in @[ _conditionsView, _rowsView ]) {
        for (NSTableColumn *column in [view.tableColumns copy]) [view removeTableColumn:column];
    }
    NSDictionary *font = @{ NSFontAttributeName: [NSFont boldSystemFontOfSize:[NSFont smallSystemFontSize]] };
    for (UDSQLColumnInfo *info in _table.columns) {
        CGFloat width = MAX(60, MIN(320, ceil([info.name sizeWithAttributes:font].width) + 28));
        NSTableColumn *condition = [[NSTableColumn alloc] initWithIdentifier:info.name];
        condition.dataCell = [_conditionTemplate.dataCell copy];
        [(NSTextFieldCell *)condition.dataCell setPlaceholderString:[UDSQLQbE exampleForColumn:info schema:_schema]];
        condition.headerToolTip = info.coreDataMeaning ? [NSString stringWithFormat:@"%@ — %@", info.type, info.coreDataMeaning] : info.type;
        condition.width = width;
        condition.minWidth = 30;
        condition.maxWidth = 2000;
        condition.editable = YES;
        [_conditionsView addTableColumn:condition];
        NSTableColumn *row = [[NSTableColumn alloc] initWithIdentifier:info.name];
        row.dataCell = [_rowTemplate.dataCell copy];
        row.width = width;
        row.editable = NO;
        [_rowsView addTableColumn:row];
    }
    [self _showOrder];
}

/// Each column's name, its place in the order marked.
- (void)_showOrder {
    for (NSTableColumn *column in _conditionsView.tableColumns) {
        NSString *mark = @"";
        for (NSSortDescriptor *descriptor in _query.order) {
            if ([descriptor.key isEqualToString:column.identifier]) mark = descriptor.ascending ? @" ▲" : @" ▼";
        }
        [column.headerCell setStringValue:[column.identifier stringByAppendingString:mark]];
    }
    [_conditionsView.headerView setNeedsDisplay:YES];
}

/// The rows' columns as wide as their values, once (the conditions' too).
- (void)_sizeColumns {
    if (_sized || !_rows.count) return;
    _sized = YES;
    NSDictionary *font = @{ NSFontAttributeName: [NSFont systemFontOfSize:[NSFont smallSystemFontSize]] };
    for (NSUInteger i = 0; i < _table.columns.count && i < _conditionsView.tableColumns.count; i++) {
        UDSQLColumnInfo *info = _table.columns[i];
        NSTableColumn *column = [_conditionsView.tableColumns objectAtIndex:i];
        CGFloat width = column.width;
        for (NSUInteger row = 0; row < MIN(_rows.count, 50u); row++) {
            NSArray *values = _rows[row];
            if (i < values.count) width = MAX(width, [UDSQLTextOfValue(values[i], info.name, info.type, _schema) sizeWithAttributes:font].width + 16);
        }
        column.width = MIN(320, ceil(width));
    }
}

- (void)_columnResized:(NSNotification *)note {
    NSTableColumn *column = note.userInfo[@"NSTableColumn"];
    [_rowsView tableColumnWithIdentifier:column.identifier].width = column.width;
}

- (void)_scrolled:(NSNotification *)note {
    if (_scrolling) return;
    _scrolling = YES;
    NSClipView *moved = note.object;
    NSClipView *other = moved == _rowsView.enclosingScrollView.contentView ? _conditionsView.enclosingScrollView.contentView
                                                                          : _rowsView.enclosingScrollView.contentView;
    if (NSMinX(other.bounds) != NSMinX(moved.bounds)) {
        [other scrollToPoint:NSMakePoint(NSMinX(moved.bounds), NSMinY(other.bounds))];
        [other.enclosingScrollView reflectScrolledClipView:other];
    }
    _scrolling = NO;
}

// ---------------------------------------------------------------------------
// MARK: - Running: a page, and the count
// ---------------------------------------------------------------------------

- (void)_databasesDidChange:(NSNotification *)note {
    UDSQLSchema *schema = _database.schema;
    if (schema && schema != _schema) {
        // read again (Refresh, a row expanded): the table as it is now; the
        // same page again while its columns are the same
        UDSQLTable *table = [schema tableNamed:_table.name] ?: _table;
        BOOL same = [[table.columns valueForKey:@"name"] isEqual:[_table.columns valueForKey:@"name"]];
        [self _useTable:table schema:schema];
        if (!self.isViewLoaded) return;
        if (same) {
            _count = NSNotFound;
            [self _run];
        } else {
            [self _makeColumns];
            [self reload];
        }
        return;
    }
    if (_waitsForConnection && _database.connected) {
        _waitsForConnection = NO;
        [self _run];
    } else if (_waitsForConnection && !_database.connecting && _database.error) {
        _waitsForConnection = NO;
        [self _showError:_database.error];
    }
}

- (void)reload {
    _offset = 0;
    _count = NSNotFound;
    [self _run];
}

- (void)_run {
    if (!_database.connected) {
        _waitsForConnection = YES;
        if (!_database.connecting) [_databases connect:_database];
        _statusLabel.stringValue = @"Connecting…";
        return;
    }
    NSError *error = nil;
    UDSQLStatement *select = [_query selectStatementWithLimit:_pageSize offset:_offset error:&error];
    UDSQLStatement *count = select && _count == NSNotFound ? [_query countStatement:&error] : nil;
    _conditionError = select ? nil : error;
    [_conditionsView reloadData];
    if (!select) {
        [self _showError:error];
        return;
    }
    _pending = count ? @[ select, count ] : @[ select ];
    _running = YES;
    _statusLabel.textColor = [NSColor secondaryLabelColor];
    _statusLabel.stringValue = @"Running…";
    [_database.runner run:_pending maxRows:_pageSize target:self action:@selector(_didRun:)];
}

- (void)_didRun:(UDSQLRun *)run {
    if (!run.finished || run.statements != _pending) return;
    _pending = nil;
    _running = NO;
    if (run.error) {
        [self _showError:run.error];
        return;
    }
    _rows = run.results.firstObject.rows ?: @[];
    if (run.results.count > 1) _count = (NSUInteger)[[run.results[1].rows.firstObject firstObject] longLongValue];
    [self _sizeColumns];
    [_rowsView reloadData];
    [_rowsView scrollRowToVisible:0];
    [self _showPage];
}

- (void)_showError:(NSError *)error {
    _statusLabel.textColor = [NSColor systemRedColor];
    _statusLabel.stringValue = error.localizedDescription ?: @"It failed.";
    _previousButton.enabled = _offset > 0;
    _nextButton.enabled = NO;
}

- (void)_showPage {
    NSNumberFormatter *numbers = [[NSNumberFormatter alloc] init];
    numbers.numberStyle = NSNumberFormatterDecimalStyle;
    _statusLabel.textColor = [NSColor secondaryLabelColor];
    if (!_rows.count) {
        _statusLabel.stringValue = _offset ? @"No more rows" : @"No rows";
    } else {
        NSString *range = [NSString stringWithFormat:@"%@–%@", [numbers stringFromNumber:@(_offset + 1)],
                                                     [numbers stringFromNumber:@(_offset + _rows.count)]];
        _statusLabel.stringValue = _count == NSNotFound ? [NSString stringWithFormat:@"Rows %@", range]
            : [NSString stringWithFormat:@"Rows %@ of %@", range, [numbers stringFromNumber:@(_count)]];
    }
    _previousButton.enabled = _offset > 0;
    _nextButton.enabled = _count == NSNotFound ? _rows.count == _pageSize : _offset + _rows.count < _count;
}

// ---------------------------------------------------------------------------
// MARK: - Conditions and order
// ---------------------------------------------------------------------------

- (void)setCondition:(NSString *)text column:(NSString *)column row:(NSUInteger)row {
    while (_conditions.count <= row) [_conditions addObject:[NSMutableDictionary dictionary]];
    NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([trimmed isEqualToString:_conditions[row][column] ?: @""]) return;
    _conditions[row][column] = trimmed.length ? trimmed : nil;
    _query.conditions = _conditions;
    [self reload];
}

- (void)sortByColumn:(NSString *)column {
    NSMutableArray *order = [_query.order mutableCopy];
    NSSortDescriptor *first = order.firstObject;
    if ([first.key isEqualToString:column]) {
        order[0] = [NSSortDescriptor sortDescriptorWithKey:column ascending:!first.ascending];
    } else {
        // first by it, then as before
        [order filterUsingPredicate:[NSPredicate predicateWithFormat:@"key != %@", column]];
        [order insertObject:[NSSortDescriptor sortDescriptorWithKey:column ascending:YES] atIndex:0];
        while (order.count > 3) [order removeLastObject];
    }
    _query.order = order;
    [self _showOrder];
    [self reload];
}

/// A click on a condition: on its ▾, what can be asked.
- (IBAction)conditionClicked:(id)sender {
    NSInteger row = _conditionsView.clickedRow, column = _conditionsView.clickedColumn;
    NSEvent *event = [NSApp currentEvent];
    if (row < 0 || column < 0 || !event) return;
    NSRect cell = [_conditionsView frameOfCellAtColumn:column row:row];
    NSPoint point = [_conditionsView convertPoint:event.locationInWindow fromView:nil];
    if (point.x < NSMaxX(cell) - UDMenuArrowWidth) return;
    _menuRow = row;
    _menuColumn = column;
    [NSMenu popUpContextMenu:_operatorMenu withEvent:event forView:_conditionsView];
}

- (void)applyOperator:(UDSQLQbEOperator)op column:(NSString *)column row:(NSUInteger)row {
    NSString *typed = row < _conditions.count ? _conditions[row][column] ?: @"" : @"";
    BOOL complete = NO;
    NSString *made = [UDSQLQbE condition:typed withOperator:op complete:&complete];
    if (complete) {
        [self setCondition:made column:column row:row];
        return;
    }
    // a value still to type: the cell edited, the caret where it goes
    NSInteger index = [_conditionsView columnWithIdentifier:column];
    if (index < 0) return;
    [_conditionsView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
    [_conditionsView editColumn:index row:(NSInteger)row withEvent:nil select:NO];
    NSText *editor = [_conditionsView currentEditor];
    editor.string = made;
    editor.selectedRange = NSMakeRange(op == UDSQLQbELike && [made isEqualToString:@"*"] ? 0 : made.length, 0);
}

- (IBAction)applyOperator:(id)sender {
    // the ▾'s cell, else the one right-clicked
    NSInteger row = _menuRow >= 0 ? _menuRow : _conditionsView.clickedRow;
    NSInteger column = _menuRow >= 0 ? _menuColumn : _conditionsView.clickedColumn;
    _menuRow = _menuColumn = -1;
    if (row < 0 || column < 0 || column >= (NSInteger)_conditionsView.tableColumns.count) return;
    [_conditionsView abortEditing];
    NSTableColumn *tableColumn = [_conditionsView.tableColumns objectAtIndex:(NSUInteger)column];
    [self applyOperator:(UDSQLQbEOperator)[sender tag] column:tableColumn.identifier row:(NSUInteger)row];
}

- (IBAction)refresh:(id)sender {
    [self reload];
}

- (IBAction)addConditionRow:(id)sender {
    [_conditions addObject:[NSMutableDictionary dictionary]];
    _query.conditions = _conditions;
    [_conditionsView reloadData];
    // selected first: GNUstep edits a selected row only
    NSInteger row = (NSInteger)_conditions.count - 1;
    [_conditionsView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
    [_conditionsView editColumn:0 row:row withEvent:nil select:YES];
}

- (IBAction)removeConditionRow:(id)sender {
    if (_conditions.count <= 1) {
        [self clearConditions:sender];
        return;
    }
    NSInteger selected = _conditionsView.selectedRow;
    [_conditions removeObjectAtIndex:selected >= 0 && (NSUInteger)selected < _conditions.count ? (NSUInteger)selected : _conditions.count - 1];
    _query.conditions = _conditions;
    [_conditionsView reloadData];
    [self reload];
}

- (IBAction)clearConditions:(id)sender {
    [_conditions setArray:@[ [NSMutableDictionary dictionary] ]];
    _query.conditions = _conditions;
    [_conditionsView reloadData];
    [self reload];
}

- (IBAction)previousPage:(id)sender {
    if (!_offset) return;
    _offset = _offset > _pageSize ? _offset - _pageSize : 0;
    [self _run];
}

- (IBAction)nextPage:(id)sender {
    if (!_nextButton.isEnabled) return;
    _offset += _pageSize;
    [self _run];
}

- (IBAction)showSQL:(id)sender {
    NSError *error = nil;
    NSString *sql = [_query SQLWithLimit:_pageSize offset:_offset error:&error];
    if (!sql) {
        [self _showError:error];
        return;
    }
    [_databases openQuery:[sql stringByAppendingString:@";\n"] database:_database run:NO];
}

// ---------------------------------------------------------------------------
// MARK: - The grids
// ---------------------------------------------------------------------------

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)(tableView == _conditionsView ? _conditions.count : _rows.count);
}

- (NSUInteger)_indexOf:(NSTableColumn *)column {
    for (NSUInteger i = 0; i < _table.columns.count; i++) {
        if ([_table.columns[i].name isEqualToString:column.identifier]) return i;
    }
    return NSNotFound;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    if (tableView == _conditionsView) return _conditions[(NSUInteger)row][column.identifier] ?: @"";
    NSUInteger index = [self _indexOf:column];
    NSArray *values = _rows[(NSUInteger)row];
    if (index == NSNotFound || index >= values.count) return @"";
    UDSQLColumnInfo *info = _table.columns[index];
    return UDSQLCellOfValue(values[index], info.name, info.type, _schema);
}

- (void)tableView:(NSTableView *)tableView setObjectValue:(id)value forTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    if (tableView == _conditionsView) [self setCondition:[value description] ?: @"" column:column.identifier row:(NSUInteger)row];
}

- (void)tableView:(NSTableView *)tableView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    if (tableView != _conditionsView || ![cell respondsToSelector:@selector(setTextColor:)]) return;
    // the condition that can't be read, in red
    BOOL wrong = _conditionError && [_conditionError.userInfo[UDSQLQbEColumnErrorKey] isEqual:column.identifier] &&
                 [_conditionError.userInfo[UDSQLQbERowErrorKey] integerValue] == row;
    [cell setTextColor:wrong ? [NSColor systemRedColor] : [NSColor controlTextColor]];
}

- (void)tableView:(NSTableView *)tableView didClickTableColumn:(NSTableColumn *)column {
    if (tableView == _conditionsView) [self sortByColumn:column.identifier];
}

- (NSString *)tableView:(NSTableView *)tableView toolTipForCell:(NSCell *)cell rect:(NSRectPointer)rect tableColumn:(NSTableColumn *)column
                    row:(NSInteger)row mouseLocation:(NSPoint)location {
    if (tableView == _conditionsView) {
        NSUInteger index = [self _indexOf:column];
        return index == NSNotFound ? nil : [UDSQLQbE helpForColumn:_table.columns[index] schema:_schema];
    }
    if (tableView != _rowsView) return nil;
    NSUInteger index = [self _indexOf:column];
    NSArray *values = _rows[(NSUInteger)row];
    id value = index < values.count ? values[index] : nil;
    return [value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSNumber class]] ? [value description] : nil;
}

// ---------------------------------------------------------------------------
// MARK: - Copying
// ---------------------------------------------------------------------------

- (void)_copyHeaders:(BOOL)headers {
    NSIndexSet *rows = _rowsView.selectedRowIndexes.count ? _rowsView.selectedRowIndexes
                                                         : [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, _rows.count)];
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    if (headers) [lines addObject:[[_table.columns valueForKey:@"name"] componentsJoinedByString:@"\t"]];
    for (NSUInteger row = rows.firstIndex; row != NSNotFound; row = [rows indexGreaterThanIndex:row]) {
        NSMutableArray *cells = [NSMutableArray array];
        NSArray *values = _rows[row];
        for (NSUInteger i = 0; i < values.count; i++) {
            UDSQLColumnInfo *info = i < _table.columns.count ? _table.columns[i] : nil;
            [cells addObject:values[i] == [NSNull null] ? @"" : UDSQLTextOfValue(values[i], info.name, info.type, _schema)];
        }
        [lines addObject:[cells componentsJoinedByString:@"\t"]];
    }
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard declareTypes:@[ NSPasteboardTypeString ] owner:nil];
    [pasteboard setString:[lines componentsJoinedByString:@"\n"] forType:NSPasteboardTypeString];
}

- (IBAction)copy:(id)sender {
    [self _copyHeaders:NO];
}

- (IBAction)copyWithColumnNames:(id)sender {
    [self _copyHeaders:YES];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    SEL action = item.action;
    if (sel_isEqual(action, @selector(copy:)) || sel_isEqual(action, @selector(copyWithColumnNames:))) return _rows.count > 0;
    if (sel_isEqual(action, @selector(previousPage:))) return _offset > 0;
    if (sel_isEqual(action, @selector(nextPage:))) return _nextButton.isEnabled;
    return YES;
}

@end
