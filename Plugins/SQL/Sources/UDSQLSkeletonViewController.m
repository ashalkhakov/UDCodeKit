/*---------------------------------------------------------------------------------------------
 *  UDSQLSkeletonViewController.m
 *--------------------------------------------------------------------------------------------*/

#import "UDSQLSkeletonViewController.h"
#import "UDSQLQbE.h"
#import "UDSQLConditionCell.h"
#import <objc/runtime.h>

/// The menu's own items (the XIB's tags): P., a new element, the row removed;
/// the elements in the query from UDElementTag on.
enum { UDPrintTag = 100, UDNewElementTag = 101, UDRemoveRowTag = 102, UDElementTag = 200 };

@implementation UDSQLSkeletonView

- (void)setSelected:(BOOL)selected {
    if (_selected == selected) return;
    _selected = selected;
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect {
    if (!_selected) return;
    // its title's band (the XIB's: its top 26 points)
    [[NSColor selectedControlColor] setFill];
    NSRectFill(NSMakeRect(0, NSHeight(self.bounds) - 26, NSWidth(self.bounds), 26));
}

- (void)mouseDown:(NSEvent *)event {
    UDSQLSkeletonViewController *controller = _controller;
    [controller.delegate skeletonWantsToBeSelected:controller];
    [super mouseDown:event];
}

@end

@interface UDSQLSkeletonViewController ()
@property (nonatomic, weak) IBOutlet NSTextField *titleLabel;
@property (nonatomic, weak) IBOutlet NSTableView *rowsView;
@property (nonatomic, strong) IBOutlet NSMenu *operatorMenu;
@property (nonatomic, strong) IBOutlet NSTableColumn *flagTemplate;
@property (nonatomic, strong) IBOutlet NSTableColumn *entryTemplate;
@end

@implementation UDSQLSkeletonViewController {
    UDSQLTable *_table;
    UDSQLSchema *_schema;
    NSArray<NSString *> *_columns;      // its table's, else those typed under
    NSInteger _menuRow, _menuColumn;    // the entry whose ▾ was clicked; -1: none
}

- (instancetype)initWithSkeleton:(UDSQLExampleFileSkeleton *)skeleton table:(UDSQLTable *)table schema:(UDSQLSchema *)schema {
    self = [super initWithNibName:@"UDSQLSkeleton" bundle:[NSBundle bundleForClass:[UDSQLSkeletonViewController class]]];
    if (self) {
        _skeleton = skeleton;
        _table = table;
        _schema = schema;
        _menuRow = _menuColumn = -1;
        if (table) _columns = [table.columns valueForKey:@"name"];
        else {
            NSMutableSet *typed = [NSMutableSet set];
            for (UDSQLExampleRow *row in skeleton.rows) [typed addObjectsFromArray:row.entries.allKeys];
            _columns = [typed.allObjects sortedArrayUsingSelector:@selector(compare:)];
        }
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [_entryTemplate.tableView removeTableColumn:_entryTemplate];
    _operatorMenu.delegate = self;
    if ([self.view isKindOfClass:[UDSQLSkeletonView class]]) {
        UDSQLSkeletonView *view = (UDSQLSkeletonView *)self.view;
        view.controller = self;
        view.selected = _selected;
    }
    NSString *table = _skeleton.schema.length ? [NSString stringWithFormat:@"%@.%@", _skeleton.schema, _skeleton.table] : _skeleton.table;
    _titleLabel.stringValue = _table ? table : [table stringByAppendingString:@" (not in this database)"];
    NSDictionary *font = @{ NSFontAttributeName: [NSFont boldSystemFontOfSize:[NSFont smallSystemFontSize]] };
    for (NSString *name in _columns) {
        NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:name];
        column.dataCell = [_entryTemplate.dataCell copy];
        UDSQLColumnInfo *info = [self _infoOf:name];
        [(NSTextFieldCell *)column.dataCell setPlaceholderString:info ? [UDSQLQbE exampleForColumn:info schema:_schema] : @""];
        [column.headerCell setStringValue:name];
        column.headerToolTip = info.type;
        column.width = MAX(90, MIN(260, ceil([name sizeWithAttributes:font].width) + 28));
        column.minWidth = 40;
        column.maxWidth = 2000;
        column.editable = YES;
        [_rowsView addTableColumn:column];
    }
    [_rowsView reloadData];
}

- (nullable UDSQLColumnInfo *)_infoOf:(NSString *)name {
    for (UDSQLColumnInfo *info in _table.columns) if ([info.name isEqualToString:name]) return info;
    return nil;
}

- (CGFloat)preferredHeight {
    // its title, its header, its rows, its scroller
    CGFloat row = (self.isViewLoaded ? _rowsView.rowHeight + _rowsView.intercellSpacing.height : 24);
    return 26 + 23 + MAX(1u, _skeleton.rows.count) * row + 20;
}

- (void)setSelected:(BOOL)selected {
    _selected = selected;
    if (self.isViewLoaded && [self.view isKindOfClass:[UDSQLSkeletonView class]]) [(UDSQLSkeletonView *)self.view setSelected:selected];
}

- (void)reload {
    [_rowsView reloadData];
}

- (void)_changed {
    [_rowsView reloadData];
    [_delegate skeletonDidChange:self];
}

// ---------------------------------------------------------------------------
// MARK: - Its rows
// ---------------------------------------------------------------------------

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)_skeleton.rows.count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    UDSQLExampleRow *kept = _skeleton.rows[(NSUInteger)row];
    if (column == _flagTemplate) return @(kept.negated ? 1 : kept.inclusive ? 2 : 0);
    return kept.entries[column.identifier] ?: @"";
}

- (void)setEntry:(NSString *)text column:(NSString *)column row:(NSUInteger)row {
    if (row >= _skeleton.rows.count) return;
    UDSQLExampleRow *kept = _skeleton.rows[row];
    NSMutableDictionary *entries = [kept.entries mutableCopy];
    NSString *typed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([typed isEqualToString:entries[column] ?: @""]) return;
    entries[column] = typed.length ? typed : nil;
    kept.entries = entries;
    [self _changed];
}

- (void)tableView:(NSTableView *)tableView setObjectValue:(id)value forTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    if (column == _flagTemplate) {
        UDSQLExampleRow *kept = _skeleton.rows[(NSUInteger)row];
        NSInteger flag = [value integerValue];
        kept.negated = flag == 1;
        kept.inclusive = flag == 2;
        [self _changed];
        return;
    }
    [self setEntry:[value description] ?: @"" column:column.identifier row:(NSUInteger)row];
}

- (NSString *)tableView:(NSTableView *)tableView toolTipForCell:(NSCell *)cell rect:(NSRectPointer)rect tableColumn:(NSTableColumn *)column
                    row:(NSInteger)row mouseLocation:(NSPoint)location {
    if (column == _flagTemplate) return @"¬: no such row; !: kept without a match";
    UDSQLColumnInfo *info = [self _infoOf:column.identifier];
    NSString *help = info ? [UDSQLQbE helpForColumn:info schema:_schema] : @"";
    return [help stringByAppendingString:@"\nP. prints it; _c, an example element, links it to the same in another row (a join); > _c compares with it."];
}

- (IBAction)addRow:(id)sender {
    _skeleton.rows = [_skeleton.rows arrayByAddingObject:[UDSQLExampleRow rowWithEntries:@{}]];
    [self _changed];
}

- (IBAction)removeRow:(id)sender {
    NSInteger row = _rowsView.selectedRow >= 0 ? _rowsView.selectedRow : (NSInteger)_skeleton.rows.count - 1;
    [_rowsView abortEditing];
    if (row >= 0) [self applyOperator:UDRemoveRowTag element:nil column:@"" row:(NSUInteger)row];
}

- (IBAction)removeSkeleton:(id)sender {
    [_delegate skeletonWantsToBeRemoved:self];
}

// ---------------------------------------------------------------------------
// MARK: - Its ▾: what an entry can be
// ---------------------------------------------------------------------------

/// A click on an entry: on its ▾, the menu; else it edited, at once (as
/// a spreadsheet's cell: no double-click, no row selected first). Its
/// skeleton selected, either way.
- (IBAction)entryClicked:(id)sender {
    [_delegate skeletonWantsToBeSelected:self];
    NSInteger row = _rowsView.clickedRow, column = _rowsView.clickedColumn;
    NSEvent *event = [NSApp currentEvent];
    if (row < 0 || column < 1 || !event) return;
    NSRect cell = [_rowsView frameOfCellAtColumn:column row:row];
    NSPoint point = [_rowsView convertPoint:event.locationInWindow fromView:nil];
    if (point.x < NSMaxX(cell) - [UDSQLConditionCell menuWidth]) {
        // the row selected first (GNUstep edits a selected row's only)
        [_rowsView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
        [_rowsView editColumn:column row:row withEvent:nil select:YES];
        return;
    }
    _menuRow = row;
    _menuColumn = column;
    [NSMenu popUpContextMenu:_operatorMenu withEvent:event forView:_rowsView];
}

/// The elements in the query, as items of their own.
- (void)menuNeedsUpdate:(NSMenu *)menu {
    for (NSMenuItem *item in [menu.itemArray copy]) if (item.tag >= UDElementTag) [menu removeItem:item];
    NSUInteger index = [menu indexOfItemWithTag:UDNewElementTag] + 1;
    for (NSString *element in [_delegate exampleElementsForSkeleton:self]) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:element action:@selector(applyOperator:) keyEquivalent:@""];
        item.target = self;
        item.tag = UDElementTag;
        item.representedObject = element;
        [menu insertItem:item atIndex:index++];
    }
}

- (void)applyOperator:(NSInteger)tag element:(NSString *)element column:(NSString *)column row:(NSUInteger)row {
    if (row >= _skeleton.rows.count) return;
    if (tag == UDRemoveRowTag) {
        NSMutableArray *rows = [_skeleton.rows mutableCopy];
        [rows removeObjectAtIndex:row];
        _skeleton.rows = rows.count ? rows : @[ [UDSQLExampleRow rowWithEntries:@{}] ];
        [self _changed];
        return;
    }
    NSString *typed = [_skeleton.rows[row].entries[column] ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    // P. kept apart: what follows it made, then it put back
    BOOL printed = [typed.uppercaseString hasPrefix:@"P."];
    NSString *rest = printed ? [[typed substringFromIndex:2] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] : typed;
    if (tag == UDPrintTag) printed = !printed;
    else if (tag == UDNewElementTag) rest = [_delegate newExampleElementForSkeleton:self];
    else if (tag == UDElementTag && element) rest = element;
    else {
        BOOL complete = NO;
        rest = [UDSQLQbE condition:rest withOperator:(UDSQLQbEOperator)tag complete:&complete];
    }
    NSString *made = printed ? (rest.length ? [@"P." stringByAppendingString:rest] : @"P.") : rest;
    [self setEntry:made column:column row:row];
}

- (IBAction)applyOperator:(id)sender {
    NSInteger row = _menuRow >= 0 ? _menuRow : _rowsView.clickedRow;
    NSInteger column = _menuRow >= 0 ? _menuColumn : _rowsView.clickedColumn;
    _menuRow = _menuColumn = -1;
    if (row < 0 || column < 1 || column >= (NSInteger)_rowsView.tableColumns.count) return;
    [_rowsView abortEditing];
    NSTableColumn *tableColumn = [_rowsView.tableColumns objectAtIndex:(NSUInteger)column];
    [self applyOperator:[sender tag] element:[sender representedObject] column:tableColumn.identifier row:(NSUInteger)row];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    if (sel_isEqual(item.action, @selector(applyOperator:))) {
        NSInteger column = _menuRow >= 0 ? _menuColumn : _rowsView.clickedColumn;
        return column >= 1 || item.tag == UDRemoveRowTag;
    }
    return YES;
}

@end
