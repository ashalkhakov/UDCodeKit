/*---------------------------------------------------------------------------------------------
 *  UDSQLSkeletonViewController.m
 *--------------------------------------------------------------------------------------------*/

#import "UDSQLSkeletonViewController.h"
#import "UDSQLQbE.h"
#import "UDSQLConditionCell.h"
#import "UDSQLExampleSyntax.h"
#import "UDSQLExampleEntry.h"
#import <objc/runtime.h>

/// The menu's own items (the XIB's tags): P., a new element, the row removed;
/// the elements in the query from UDElementTag on.
enum { UDPrintTag = 100, UDNewElementTag = 101, UDRemoveRowTag = 102, UDGroupTag = 103, UDAggregateTag = 110, UDAscendingTag = 120,
       UDDescendingTag = 121, UDElementTag = 200 };

/// The Aggregate submenu's (tags 110-115), as typed after P.
static NSArray<NSString *> *UDAggregatePrefixes(void) {
    return @[ @"SUM.", @"AVG.", @"MIN.", @"MAX.", @"CNT.", @"CNT.UNQ." ];
}

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

/// A column of the form whose first line (a row's kind) has a cell of its
/// own (the ¬ ! popup), or none to speak of; its others, the column's.
@interface UDSQLFormColumn : NSTableColumn
@property (nonatomic, strong, nullable) NSCell *firstLineCell;
@end

@implementation UDSQLFormColumn

- (id)dataCellForRow:(NSInteger)row {
    return row == 0 && _firstLineCell ? _firstLineCell : [super dataCellForRow:row];
}

@end

/// A row's columns in the form, as their identifiers end (2.op: the second
/// row's operator).
static NSArray<NSString *> *UDParts(void) {
    return @[ @"show", @"total", @"op", @"value", @"to" ];
}

@interface UDSQLSkeletonViewController ()
@property (nonatomic, weak) IBOutlet NSTextField *titleLabel;
@property (nonatomic, weak) IBOutlet NSTableView *rowsView;
@property (nonatomic, strong) IBOutlet NSMenu *operatorMenu;
@property (nonatomic, strong) IBOutlet NSTableColumn *flagTemplate;
@property (nonatomic, strong) IBOutlet NSTableColumn *nameColumn;
@property (nonatomic, strong) IBOutlet NSTableColumn *sortColumn;
@property (nonatomic, strong) IBOutlet NSTableColumn *showTemplate;
@property (nonatomic, strong) IBOutlet NSTableColumn *totalTemplate;
@property (nonatomic, strong) IBOutlet NSTableColumn *opTemplate;
@property (nonatomic, strong) IBOutlet NSTableColumn *valueTemplate;
@property (nonatomic, strong) IBOutlet NSTableColumn *toTemplate;
@end

@implementation UDSQLSkeletonViewController {
    UDSQLTable *_table;
    UDSQLSchema *_schema;
    NSArray<NSString *> *_columns;      // its table's, else those typed under: a line each
    NSInteger _menuRow, _menuColumn;    // the cell right-clicked; -1: none
    NSUInteger _currentRow;             // the row (tuple) last clicked in: Remove Row's
    NSTextFieldCell *_blankCell;        // a first line's, where a row's kind isn't
    NSMutableDictionary<NSString *, NSNumber *> *_pendingOps;   // an operator chosen before its value ("row column"): the text has none yet
}

- (instancetype)initWithSkeleton:(UDSQLExampleFileSkeleton *)skeleton table:(UDSQLTable *)table schema:(UDSQLSchema *)schema {
    self = [super initWithNibName:@"UDSQLSkeleton" bundle:[NSBundle bundleForClass:[UDSQLSkeletonViewController class]]];
    if (self) {
        _skeleton = skeleton;
        _table = table;
        _schema = schema;
        _menuRow = _menuColumn = -1;
        _currentRow = NSNotFound;
        _pendingOps = [NSMutableDictionary dictionary];
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
    // the row's parts are made like the XIB's, a set each row
    for (NSTableColumn *template in @[ _showTemplate, _totalTemplate, _opTemplate, _valueTemplate, _toTemplate, _flagTemplate ]) {
        [_rowsView removeTableColumn:template];
    }
    _blankCell = [[NSTextFieldCell alloc] initTextCell:@""];
    _blankCell.editable = NO;
    _operatorMenu.delegate = self;
    if ([self.view isKindOfClass:[UDSQLSkeletonView class]]) {
        UDSQLSkeletonView *view = (UDSQLSkeletonView *)self.view;
        view.controller = self;
        view.selected = _selected;
    }
    NSString *table = _skeleton.schema.length ? [NSString stringWithFormat:@"%@.%@", _skeleton.schema, _skeleton.table] : _skeleton.table;
    _titleLabel.stringValue = _table ? table : [table stringByAppendingString:@" (not in this database)"];
    [self _makeRowColumns];
}

/// A set of the parts (Show, Total, Op, Value, To) for each of its rows.
- (void)_makeRowColumns {
    for (NSTableColumn *column in [_rowsView.tableColumns copy]) {
        if (column != _nameColumn && column != _sortColumn) [_rowsView removeTableColumn:column];
    }
    NSDictionary *templates = @{ @"show": _showTemplate, @"total": _totalTemplate, @"op": _opTemplate, @"value": _valueTemplate, @"to": _toTemplate };
    NSUInteger count = MAX(1u, _skeleton.rows.count);
    for (NSUInteger row = 0; row < count; row++) {
        for (NSString *part in UDParts()) {
            NSTableColumn *template = templates[part];
            UDSQLFormColumn *column = [[UDSQLFormColumn alloc] initWithIdentifier:[NSString stringWithFormat:@"%lu.%@", (unsigned long)row, part]];
            column.dataCell = [template.dataCell copy];
            column.firstLineCell = [part isEqualToString:@"op"] ? [_flagTemplate.dataCell copy] : _blankCell;
            NSString *title = [template.headerCell stringValue];
            [column.headerCell setStringValue:count > 1 ? [NSString stringWithFormat:@"%@ %lu", title, (unsigned long)row + 1] : title];
            column.headerToolTip = template.headerToolTip;
            column.width = [part isEqualToString:@"op"] ? MAX(template.width, 104) : template.width;
            column.minWidth = template.minWidth;
            column.maxWidth = template.maxWidth;
            column.editable = YES;
            [_rowsView addTableColumn:column];
        }
    }
    [_rowsView reloadData];
}

- (nullable UDSQLColumnInfo *)_infoOf:(NSString *)name {
    for (UDSQLColumnInfo *info in _table.columns) if ([info.name isEqualToString:name]) return info;
    return nil;
}

- (CGFloat)preferredHeight {
    // its title, its header, a line a column (and its rows' kinds), its scroller
    CGFloat line = (self.isViewLoaded ? _rowsView.rowHeight + _rowsView.intercellSpacing.height : 24);
    return 26 + 23 + (_columns.count + 1) * line + 20;
}

- (void)setSelected:(BOOL)selected {
    _selected = selected;
    if (self.isViewLoaded && [self.view isKindOfClass:[UDSQLSkeletonView class]]) [(UDSQLSkeletonView *)self.view setSelected:selected];
}

- (void)reload {
    [_rowsView reloadData];
}

- (void)_changed {
    // a row added or removed: its parts' columns made again
    NSUInteger sets = (_rowsView.tableColumns.count - 2) / UDParts().count;
    if (sets != MAX(1u, _skeleton.rows.count)) [self _makeRowColumns];
    else [_rowsView reloadData];
    [_delegate skeletonDidChange:self];
}

// ---------------------------------------------------------------------------
// MARK: - Its form: a line each column, a set of parts each row
// ---------------------------------------------------------------------------

/// A form's column's row (its tuple) and part; NO for the name's and Sort.
static BOOL UDPartOf(NSTableColumn *column, NSUInteger *row, NSString **part) {
    NSRange dot = [column.identifier rangeOfString:@"."];
    if (dot.location == NSNotFound) return NO;
    if (row) *row = (NSUInteger)[[column.identifier substringToIndex:dot.location] integerValue];
    if (part) *part = [column.identifier substringFromIndex:NSMaxRange(dot)];
    return YES;
}

/// A line's column (its table's): line 0 is the rows' kinds.
- (nullable NSString *)_columnOfLine:(NSInteger)line {
    return line >= 1 && line <= (NSInteger)_columns.count ? _columns[(NSUInteger)line - 1] : nil;
}

- (UDSQLExampleEntry *)_entryOfColumn:(NSString *)column row:(NSUInteger)row {
    NSString *text = row < _skeleton.rows.count ? _skeleton.rows[row].entries[column] : nil;
    UDSQLExampleEntry *entry = [UDSQLExampleEntry entryOfText:text];
    // an operator chosen, its value still to type
    NSNumber *pending = _pendingOps[[NSString stringWithFormat:@"%lu %@", (unsigned long)row, column]];
    if (entry.op == UDSQLExampleOperatorNone && !entry.value.length && pending) entry.op = pending.integerValue;
    return entry;
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)_columns.count + 1;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)line {
    NSString *column = [self _columnOfLine:line];
    if (tableColumn == _nameColumn) return column ?: @"Row";
    if (tableColumn == _sortColumn) return column ? @([_delegate skeleton:self sortOfColumn:column]) : @"";
    NSUInteger row = 0;
    NSString *part = nil;
    if (!UDPartOf(tableColumn, &row, &part)) return @"";
    UDSQLExampleRow *kept = row < _skeleton.rows.count ? _skeleton.rows[row] : nil;
    if (!column) return [part isEqualToString:@"op"] ? @(kept.negated ? 1 : kept.inclusive ? 2 : 0) : @"";
    UDSQLExampleEntry *entry = [self _entryOfColumn:column row:row];
    if ([part isEqualToString:@"show"]) return @(entry.shown ? NSControlStateValueOn : NSControlStateValueOff);
    if ([part isEqualToString:@"total"]) return @(entry.total);
    if ([part isEqualToString:@"op"]) return @(entry.op);
    NSString *text = [part isEqualToString:@"value"] ? entry.value : entry.to;
    // coloured (an element, a pattern…); being edited, as typed
    if (!text.length || (tableView.editedRow == line && tableView.editedColumn == [tableView.tableColumns indexOfObject:tableColumn])) return text;
    NSFont *font = [(NSCell *)tableColumn.dataCell font] ?: [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
    return UDSQLExampleAttributedString(text, font);
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

- (void)tableView:(NSTableView *)tableView setObjectValue:(id)value forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)line {
    NSString *column = [self _columnOfLine:line];
    if (tableColumn == _sortColumn) {
        if (!column) return;
        NSInteger sort = [value integerValue];
        if (sort == 0) [_delegate skeleton:self unsortsColumn:column];
        else [_delegate skeleton:self sortsByColumn:column ascending:sort == 1];
        return;
    }
    NSUInteger row = 0;
    NSString *part = nil;
    if (!UDPartOf(tableColumn, &row, &part) || row >= _skeleton.rows.count) return;
    _currentRow = row;
    if (!column) {
        // a row's kind: there, not there (¬), optional (!)
        if (![part isEqualToString:@"op"]) return;
        UDSQLExampleRow *kept = _skeleton.rows[row];
        NSInteger flag = [value integerValue];
        kept.negated = flag == 1;
        kept.inclusive = flag == 2;
        [self _changed];
        return;
    }
    UDSQLExampleEntry *entry = [self _entryOfColumn:column row:row];
    if ([part isEqualToString:@"show"]) entry.shown = [value integerValue] == NSControlStateValueOn;
    else if ([part isEqualToString:@"total"]) {
        entry.total = [value integerValue];
        // an aggregate shown (else it only keeps groups, with a condition)
        if (entry.total > UDSQLExampleTotalGroup && entry.op == UDSQLExampleOperatorNone) entry.shown = YES;
    }
    else if ([part isEqualToString:@"op"]) {
        entry.op = [value integerValue];
        // kept till its value is typed (its text has none without one)
        NSString *key = [NSString stringWithFormat:@"%lu %@", (unsigned long)row, column];
        if (entry.op != UDSQLExampleOperatorNone && !entry.value.length) _pendingOps[key] = @(entry.op);
        else [_pendingOps removeObjectForKey:key];
    }
    else {
        NSString *typed = [value isKindOfClass:[NSAttributedString class]] ? [value string] : [value description] ?: @"";
        if ([part isEqualToString:@"value"]) {
            // typed with nothing asked: = (an element, a value), or as it reads
            if (entry.op == UDSQLExampleOperatorNone && typed.length) {
                UDSQLExampleEntry *read = [UDSQLExampleEntry entryOfText:typed];
                entry.op = read.op;
                entry.value = read.value;
                entry.to = read.to.length ? read.to : entry.to;
            } else {
                entry.value = typed;
            }
        } else {
            entry.to = typed;
            if (typed.length && entry.op == UDSQLExampleOperatorNone) entry.op = UDSQLExampleOperatorBetween;
        }
    }
    if (entry.value.length) [_pendingOps removeObjectForKey:[NSString stringWithFormat:@"%lu %@", (unsigned long)row, column]];
    [self setEntry:entry.text column:column row:row];
    [_rowsView reloadData];
}

- (BOOL)tableView:(NSTableView *)tableView shouldEditTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)line {
    if (tableColumn == _nameColumn) return NO;
    if (line == 0) {
        NSString *part = nil;
        return UDPartOf(tableColumn, NULL, &part) && [part isEqualToString:@"op"];
    }
    return YES;
}

/// An empty value shows what its column takes (e.g. Ann*); a line's name,
/// bold for the rows' kinds.
- (void)tableView:(NSTableView *)tableView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)line {
    NSString *column = [self _columnOfLine:line];
    NSString *part = nil;
    if (UDPartOf(tableColumn, NULL, &part) && [part isEqualToString:@"value"] && [cell isKindOfClass:[NSTextFieldCell class]] && column) {
        UDSQLColumnInfo *info = [self _infoOf:column];
        [(NSTextFieldCell *)cell setPlaceholderString:info ? [UDSQLQbE exampleForColumn:info schema:_schema] : @""];
    }
    if (tableColumn == _nameColumn && [cell isKindOfClass:[NSTextFieldCell class]]) {
        CGFloat size = [NSFont smallSystemFontSize];
        [(NSTextFieldCell *)cell setFont:column ? [NSFont systemFontOfSize:size] : [NSFont boldSystemFontOfSize:size]];
    }
}

- (NSString *)tableView:(NSTableView *)tableView toolTipForCell:(NSCell *)cell rect:(NSRectPointer)rect tableColumn:(NSTableColumn *)tableColumn
                    row:(NSInteger)line mouseLocation:(NSPoint)location {
    NSString *column = [self _columnOfLine:line];
    UDSQLColumnInfo *info = column ? [self _infoOf:column] : nil;
    if (tableColumn == _nameColumn) {
        if (!column) return @"Each row asked of its table: one there is; one that isn't there (¬: none of the rows it is linked to has one); "
                             "or optional (!: the rows it is linked to are kept where it has no match)";
        return info.coreDataMeaning ? [NSString stringWithFormat:@"%@: %@", info.type, info.coreDataMeaning] : info.type;
    }
    if (tableColumn == _sortColumn) return @"The answer sorted by it, ascending (↑) or descending (↓)";
    NSUInteger row = 0;
    NSString *part = nil;
    if (!UDPartOf(tableColumn, &row, &part)) return nil;
    if (!column) return [part isEqualToString:@"op"] ? @"This row: there is one; isn't there (¬); or optional (!: kept without a match)" : nil;
    if ([part isEqualToString:@"show"]) return @"Shown: a column of the answer (P.)";
    if ([part isEqualToString:@"total"]) return @"Group by it (G.), or a total of its values in each group: Sum, Average, Minimum, Maximum, Count "
                                                 "(SUM. AVG. MIN. MAX. CNT.); the other columns shown are the groups. With a total, the operator "
                                                 "and value keep groups (HAVING)";
    if ([part isEqualToString:@"to"]) return @"A range's end: from the value to it, both included (between)";
    NSString *help = info ? [UDSQLQbE helpForColumn:info schema:_schema] : @"";
    help = [help stringByAppendingString:@"\nAn example element (_c) as the value: the same one in another row's column joins them; "
                                          "the condition box may name it."];
    NSString *entry = row < _skeleton.rows.count ? _skeleton.rows[row].entries[column] : nil;
    NSString *explained = entry ? UDSQLExampleExplanation(entry) : nil;
    return explained ? [NSString stringWithFormat:@"%@\n\n%@", explained, help] : help;
}

- (IBAction)addRow:(id)sender {
    [_pendingOps removeAllObjects];
    _skeleton.rows = [_skeleton.rows arrayByAddingObject:[UDSQLExampleRow rowWithEntries:@{}]];
    [self _changed];
}

- (IBAction)removeRow:(id)sender {
    [_rowsView abortEditing];
    NSUInteger row = _currentRow < _skeleton.rows.count ? _currentRow : _skeleton.rows.count - 1;
    _currentRow = NSNotFound;
    if (_skeleton.rows.count) [self applyOperator:UDRemoveRowTag element:nil column:@"" row:row];
}

- (IBAction)removeSkeleton:(id)sender {
    [_delegate skeletonWantsToBeRemoved:self];
}

// ---------------------------------------------------------------------------
// MARK: - A click; its right-click's menu
// ---------------------------------------------------------------------------

/// A click: its row (tuple) the current one (Remove Row's); in a value or
/// To, it edited at once (as a spreadsheet's cell: no double-click, no
/// line selected first). Its skeleton selected, either way.
- (IBAction)entryClicked:(id)sender {
    [_delegate skeletonWantsToBeSelected:self];
    NSInteger line = _rowsView.clickedRow, index = _rowsView.clickedColumn;
    if (line < 0 || index < 0 || index >= (NSInteger)_rowsView.tableColumns.count) return;
    NSUInteger row = 0;
    NSString *part = nil;
    if (!UDPartOf(_rowsView.tableColumns[(NSUInteger)index], &row, &part)) return;
    _currentRow = row;
    if (line >= 1 && ([part isEqualToString:@"value"] || [part isEqualToString:@"to"])) {
        // the line selected first (GNUstep edits a selected line's only)
        [_rowsView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)line] byExtendingSelection:NO];
        [_rowsView editColumn:index row:line withEvent:nil select:YES];
    }
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
    // G. kept apart, and what it aggregates: SUM. and the like
    BOOL grouped = [rest.uppercaseString hasPrefix:@"G."];
    if (grouped) rest = [[rest substringFromIndex:2] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSString *aggregate = @"";
    for (NSString *prefix in [UDAggregatePrefixes() reverseObjectEnumerator]) {
        if (![rest.uppercaseString hasPrefix:prefix]) continue;
        aggregate = prefix;
        rest = [[rest substringFromIndex:prefix.length] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        break;
    }
    if (tag == UDAscendingTag || tag == UDDescendingTag) {
        // sorted by it, what is printed left as it is
        [_delegate skeleton:self sortsByColumn:column ascending:tag == UDAscendingTag];
        return;
    }
    if (tag >= UDAggregateTag && tag < UDAggregateTag + (NSInteger)UDAggregatePrefixes().count) {
        NSString *chosen = UDAggregatePrefixes()[(NSUInteger)(tag - UDAggregateTag)];
        printed = YES;
        grouped = NO;
        aggregate = [aggregate isEqualToString:chosen] ? @"" : chosen;    // again: none
    }
    else if (tag == UDGroupTag) {
        grouped = !grouped;
        if (grouped) aggregate = @"";
    }
    else if (tag == UDPrintTag) {
        printed = !printed;
        if (!printed) aggregate = @"";
    }
    else if (tag == UDNewElementTag) rest = [_delegate newExampleElementForSkeleton:self];
    else if (tag == UDElementTag && element) rest = element;
    else {
        BOOL complete = NO;
        rest = [UDSQLQbE condition:rest withOperator:(UDSQLQbEOperator)tag complete:&complete];
    }
    NSString *head = [NSString stringWithFormat:@"%@%@%@", printed ? @"P." : @"", grouped ? @"G." : @"", aggregate];
    NSString *made = head.length && rest.length ? [head stringByAppendingFormat:@"%@%@", aggregate.length ? @" " : @"", rest]
                                                : [head stringByAppendingString:rest];
    [self setEntry:made column:column row:row];
}

- (IBAction)applyOperator:(id)sender {
    NSInteger line = _menuRow >= 0 ? _menuRow : _rowsView.clickedRow;
    NSInteger index = _menuRow >= 0 ? _menuColumn : _rowsView.clickedColumn;
    _menuRow = _menuColumn = -1;
    NSUInteger row = 0;
    if (index < 0 || index >= (NSInteger)_rowsView.tableColumns.count || !UDPartOf(_rowsView.tableColumns[(NSUInteger)index], &row, NULL)) {
        // not a row's cell: the current row's, removed
        if ([sender tag] == UDRemoveRowTag) [self removeRow:sender];
        return;
    }
    [_rowsView abortEditing];
    NSString *column = [self _columnOfLine:line];
    if ([sender tag] == UDRemoveRowTag) [self applyOperator:UDRemoveRowTag element:nil column:@"" row:row];
    else if (column) [self applyOperator:[sender tag] element:[sender representedObject] column:column row:row];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    if (sel_isEqual(item.action, @selector(applyOperator:))) {
        NSInteger index = _menuRow >= 0 ? _menuColumn : _rowsView.clickedColumn;
        NSInteger line = _menuRow >= 0 ? _menuRow : _rowsView.clickedRow;
        BOOL cell = index >= 0 && index < (NSInteger)_rowsView.tableColumns.count && UDPartOf(_rowsView.tableColumns[(NSUInteger)index], NULL, NULL);
        return item.tag == UDRemoveRowTag || (cell && line >= 1);
    }
    return YES;
}

@end
