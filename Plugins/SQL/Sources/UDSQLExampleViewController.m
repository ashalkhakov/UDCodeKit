/*---------------------------------------------------------------------------------------------
 *  UDSQLExampleViewController.m
 *--------------------------------------------------------------------------------------------*/

#import "UDSQLExampleViewController.h"
#import "UDSQLDatabases.h"
#import "UDSQLValues.h"
#import "UDSQLExampleSyntax.h"
#import <objc/runtime.h>

/// The rows a page has (◀ ▶ turn them), and the most an export keeps.
static const NSUInteger UDPageSize = 100;
static const NSUInteger UDMaxExported = 10000000;

@implementation UDSQLExampleStackView

- (BOOL)isFlipped {
    return YES;
}

@end

@interface UDSQLExampleViewController ()
@property (nonatomic, weak) IBOutlet NSPopUpButton *databaseButton;
@property (nonatomic, weak) IBOutlet NSPopUpButton *addTableButton;
@property (nonatomic, weak) IBOutlet NSButton *removeTableButton;
@property (nonatomic, weak) IBOutlet NSButton *previousButton;
@property (nonatomic, weak) IBOutlet NSButton *nextButton;
@property (nonatomic, strong) IBOutlet NSMenu *headerMenu;
@property (nonatomic, strong) IBOutlet NSTextView *conditionsView;
@property (nonatomic, strong) IBOutlet NSView *exportAccessory;
@property (nonatomic, weak) IBOutlet NSPopUpButton *exportFormatButton;
@property (nonatomic, weak) IBOutlet NSTextField *statusLabel;
@property (nonatomic, weak) IBOutlet UDSQLExampleStackView *stackView;
@property (nonatomic, weak) IBOutlet NSTableView *resultsView;
@property (nonatomic, strong) IBOutlet NSTableColumn *resultTemplate;
@end

@implementation UDSQLExampleViewController {
    __weak UDSQLDatabases *_databases;
    NSMutableArray<UDSQLSkeletonViewController *> *_skeletons;
    UDSQLSchema *_schema;               // the one its skeletons' tables are of
    BOOL _writing;                      // its own edit of its document's text, under way
    BOOL _waitsForConnection, _runsWhenConnected;
    NSInteger _selected;                // its selected skeleton's index; -1: none
    NSUInteger _offset, _count;         // its page's first row; how many it has (NSNotFound: not yet known)
    NSInteger _menuColumn;              // the result's column a menu is of; -1: none
    NSArray<UDSQLStatement *> *_exporting;
    NSURL *_exportURL;
    NSString *_exportFormat;
    NSArray<UDSQLStatement *> *_pending;
}

- (instancetype)initWithDatabases:(UDSQLDatabases *)databases document:(UDCodeDocument *)document {
    self = [super initWithNibName:@"UDSQLExample" bundle:[NSBundle bundleForClass:[UDSQLExampleViewController class]]];
    if (self) {
        _databases = databases;
        _document = document;
        _skeletons = [NSMutableArray array];
        _selected = 0;
        _pageSize = UDPageSize;
        _count = NSNotFound;
        _menuColumn = -1;
        [self _readDocument];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_textDidChange:)
                                                     name:UDTextModelDidChangeNotification object:document.textModel];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_databasesDidChange:)
                                                     name:UDSQLDatabasesDidChangeNotification object:databases];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_databaseChosen:)
                                                     name:UDSQLDocumentDatabaseDidChangeNotification object:document];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [_resultTemplate.tableView removeTableColumn:_resultTemplate];
    // the condition box: its lines, coloured; what it takes, its tip
    _conditionsView.font = [NSFont userFixedPitchFontOfSize:[NSFont smallSystemFontSize]];
    _conditionsView.toolTip = UDSQLExampleConditionHelp();
    [self _showConditions];
    // a column's name right-clicked: its menu (copied, sorted)
    _resultsView.headerView.menu = _headerMenu;
    // Export…'s formats, by their files' extensions
    if (_exportFormatButton.numberOfItems >= 2) {
        [_exportFormatButton itemAtIndex:0].representedObject = @"csv";
        [_exportFormatButton itemAtIndex:1].representedObject = @"json";
    }
    [self _updatePager];
    [self _reloadDatabases];
    [self _useDatabase];
}

- (NSArray<UDSQLSkeletonViewController *> *)skeletons {
    return [_skeletons copy];
}

// ---------------------------------------------------------------------------
// MARK: - Its document: its text the model
// ---------------------------------------------------------------------------

/// What its document's text says (an empty one: an empty query).
- (void)_readDocument {
    NSString *text = [_document.textModel getValue];
    _readError = nil;
    if (![text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length) {
        _file = [[UDSQLExampleFile alloc] init];
        return;
    }
    NSError *error = nil;
    _file = [UDSQLExampleFile fileWithData:[text dataUsingEncoding:NSUTF8StringEncoding] error:&error];
    _readError = _file ? nil : error;
}

/// Its model written as its document's text: one edit, undone as one.
- (void)_writeDocument {
    if (!_file) return;
    NSString *text = [[NSString alloc] initWithData:[_file data] encoding:NSUTF8StringEncoding];
    UDTextModel *model = _document.textModel;
    if ([text isEqualToString:[model getValue]]) return;
    UDRange all = [model validateRange:(UDRange){ 1, 1, NSIntegerMax, NSIntegerMax }];
    _writing = YES;
    [model applyEdits:@[ [[UDTextModelEdit alloc] initWithRange:all text:text] ]];
    _writing = NO;
}

/// Its text edited elsewhere (as text, undone): read again.
- (void)_textDidChange:(NSNotification *)note {
    if (_writing) return;
    [self _readDocument];
    if (!self.isViewLoaded) return;
    [self _makeSkeletons];
    [self _showConditions];
}

// ---------------------------------------------------------------------------
// MARK: - Its condition box
// ---------------------------------------------------------------------------

/// Its file's conditions, a line each, coloured (as typed, left be).
- (void)_showConditions {
    NSString *text = [_file.conditions componentsJoinedByString:@"\n"] ?: @"";
    NSString *shown = _conditionsView.string;
    if ([[self _linesOf:shown] isEqual:_file.conditions ?: @[]]) return;
    _conditionsView.string = text;
    UDSQLExampleHighlight(_conditionsView.textStorage);
}

/// Its lines, as kept: those typed (an empty line kept nothing).
- (NSArray<NSString *> *)_linesOf:(NSString *)text {
    NSMutableArray *lines = [NSMutableArray array];
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        NSString *typed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (typed.length) [lines addObject:typed];
    }
    return lines;
}

/// A line typed: coloured, kept in the file (its document's text).
- (void)textDidChange:(NSNotification *)note {
    if (note.object != _conditionsView || !_file) return;
    UDSQLExampleHighlight(_conditionsView.textStorage);
    NSArray *lines = [self _linesOf:_conditionsView.string];
    if ([lines isEqual:_file.conditions]) return;
    _file.conditions = lines;
    [self _writeDocument];
}

- (void)setConditionsText:(NSString *)text {
    _conditionsView.string = text;
    [self textDidChange:[NSNotification notificationWithName:NSTextDidChangeNotification object:_conditionsView]];
}

- (IBAction)undo:(id)sender {
    [_document.textModel.undoManager undo];
}

- (IBAction)redo:(id)sender {
    [_document.textModel.undoManager redo];
}

- (IBAction)showAsText:(id)sender {
    [_databases.workbench showDocumentAsText:_document];
}

// ---------------------------------------------------------------------------
// MARK: - Its connection
// ---------------------------------------------------------------------------

- (UDSQLDatabase *)database {
    return [_databases databaseOfDocument:_document];
}

- (void)_reloadDatabases {
    [_databaseButton removeAllItems];
    [_databaseButton addItemWithTitle:@"No Database"];
    for (UDSQLDatabase *database in _databases.databases) [_databaseButton addItemWithTitle:database.name];
    [_databaseButton selectItemWithTitle:self.database.name ?: @"No Database"];
}

- (IBAction)chooseDatabase:(id)sender {
    [_databases setDatabase:[_databases databaseNamed:_databaseButton.titleOfSelectedItem] ofDocument:_document];
}

/// Its document's database chosen (here, or as it was made): asked of it.
- (void)_databaseChosen:(NSNotification *)note {
    if (!self.isViewLoaded) return;
    [self _reloadDatabases];
    [self _useDatabase];
}

/// The connection chosen: its schema (connected first), its tables for its
/// skeletons and Add Table.
- (void)_useDatabase {
    UDSQLDatabase *database = self.database;
    if (database && !database.schema) {
        _waitsForConnection = YES;
        [_databases connectIfWanted:database];
        if (database.error) [self _showStatus:database.error.localizedDescription error:YES];
        else [self _showStatus:@"Connecting…" error:NO];
    }
    _schema = database.schema;
    NSMenu *menu = _addTableButton.menu;
    while (menu.numberOfItems > 1) [menu removeItemAtIndex:1];
    for (UDSQLTable *table in _schema.tables) {
        NSString *title = table.schema.length && ![table.schema isEqualToString:@"public"]
            ? [NSString stringWithFormat:@"%@.%@", table.schema, table.name] : table.name;
        NSMenuItem *item = [menu addItemWithTitle:title action:@selector(addTableChosen:) keyEquivalent:@""];
        item.target = self;
        item.representedObject = table;
    }
    [_addTableButton setEnabled:_schema != nil];
    [self _makeSkeletons];
    // browsed: its rows shown at once
    if (database && [_databases takeRunWhenShown:_document]) [self run:nil];
}

- (void)_databasesDidChange:(NSNotification *)note {
    if (!self.isViewLoaded) return;
    [self _reloadDatabases];
    UDSQLDatabase *database = self.database;
    if (database.schema != _schema) {
        _waitsForConnection = NO;
        [self _useDatabase];
        if (_runsWhenConnected && database.schema) {
            _runsWhenConnected = NO;
            [self run:nil];
        }
    } else if (_waitsForConnection && database && !database.connecting && database.error) {
        _waitsForConnection = NO;
        [self _showStatus:database.error.localizedDescription error:YES];
    }
}

// ---------------------------------------------------------------------------
// MARK: - Its skeletons
// ---------------------------------------------------------------------------

- (nullable UDSQLTable *)_tableOf:(UDSQLExampleFileSkeleton *)skeleton {
    for (UDSQLTable *table in _schema.tables) {
        if ([table.name isEqualToString:skeleton.table] && (!skeleton.schema.length || [table.schema isEqualToString:skeleton.schema])) return table;
    }
    return nil;
}

- (void)_makeSkeletons {
    for (UDSQLSkeletonViewController *skeleton in _skeletons) [skeleton.view removeFromSuperview];
    [_skeletons removeAllObjects];
    for (UDSQLExampleFileSkeleton *kept in _file.skeletons) {
        UDSQLSkeletonViewController *skeleton = [[UDSQLSkeletonViewController alloc] initWithSkeleton:kept table:[self _tableOf:kept] schema:_schema];
        skeleton.delegate = self;
        [_skeletons addObject:skeleton];
        [_stackView addSubview:skeleton.view];
    }
    [self _select:MIN(_selected, (NSInteger)_skeletons.count - 1)];
    [self _layOut];
    if (_readError) [self _showStatus:[NSString stringWithFormat:@"Its text can't be read (Show as Text): %@", _readError.localizedDescription] error:YES];
    else if (!_file.skeletons.count) [self _showStatus:_schema ? @"Add a table: its skeleton, to type what its rows are to be"
                                                               : @"Choose a database, then add a table" error:NO];
    else if (!_running) [self _showStatus:@"" error:NO];
}

/// Its skeletons one under another, each as tall as its rows.
- (void)_layOut {
    CGFloat width = NSWidth(_stackView.enclosingScrollView.contentView.bounds), y = 6;
    for (UDSQLSkeletonViewController *skeleton in _skeletons) {
        skeleton.view.frame = NSMakeRect(0, y, width, skeleton.preferredHeight);
        skeleton.view.autoresizingMask = NSViewWidthSizable;
        y += skeleton.preferredHeight + 10;
    }
    [_stackView setFrameSize:NSMakeSize(width, MAX(y, NSHeight(_stackView.enclosingScrollView.contentView.bounds)))];
}

- (void)skeletonDidChange:(UDSQLSkeletonViewController *)skeleton {
    [self _writeDocument];
    [self _layOut];
}

/// Its skeleton at @a index the selected one (-1: none): what − removes.
- (void)_select:(NSInteger)index {
    _selected = index;
    for (NSUInteger i = 0; i < _skeletons.count; i++) _skeletons[i].selected = (NSInteger)i == index;
    [_removeTableButton setEnabled:index >= 0];
}

- (NSInteger)selectedSkeleton {
    return _selected;
}

- (void)skeletonWantsToBeSelected:(UDSQLSkeletonViewController *)skeleton {
    NSUInteger index = [_skeletons indexOfObjectIdenticalTo:skeleton];
    if (index != NSNotFound) [self _select:(NSInteger)index];
}

/// Sorted by a skeleton's column: by the name it is printed under (its
/// own, its table's and its, an aggregate's of it).
- (void)skeleton:(UDSQLSkeletonViewController *)skeleton sortsByColumn:(NSString *)column ascending:(BOOL)ascending {
    NSArray<NSString *> *printed = [[self _query:NULL] printedColumns:NULL];
    NSString *table = skeleton.skeleton.table;
    NSString *found = nil;
    for (NSString *name in printed) if ([name isEqualToString:column]) found = name;
    for (NSString *name in found ? @[] : printed) if ([name isEqualToString:[NSString stringWithFormat:@"%@.%@", table, column]]) found = name;
    for (NSString *name in found ? @[] : printed) {
        if ([name hasSuffix:[NSString stringWithFormat:@"(%@)", column]] || [name hasSuffix:[NSString stringWithFormat:@"(DISTINCT %@)", column]]) found = name;
    }
    if (!found) {
        [self _showStatus:[NSString stringWithFormat:@"%@ isn't printed: it can't be sorted by", column] error:YES];
        return;
    }
    [self sortByColumn:found ascending:ascending];
}

- (IBAction)removeTable:(id)sender {
    if (_selected >= 0 && _selected < (NSInteger)_skeletons.count) [self skeletonWantsToBeRemoved:_skeletons[(NSUInteger)_selected]];
}

- (void)skeletonWantsToBeRemoved:(UDSQLSkeletonViewController *)skeleton {
    NSMutableArray *kept = [_file.skeletons mutableCopy];
    [kept removeObjectIdenticalTo:skeleton.skeleton];
    _file.skeletons = kept;
    [self _writeDocument];
    [self _makeSkeletons];
}

/// The example elements typed (alone, after P., after a comparison).
- (NSArray<NSString *> *)_elements {
    NSRegularExpression *element = [NSRegularExpression regularExpressionWithPattern:@"(^|[\\s.<>=!])(_[A-Za-z0-9_]+)$" options:0 error:NULL];
    NSMutableOrderedSet *found = [NSMutableOrderedSet orderedSet];
    for (UDSQLExampleFileSkeleton *skeleton in _file.skeletons) {
        for (UDSQLExampleRow *row in skeleton.rows) {
            for (NSString *typed in row.entries.allValues) {
                NSTextCheckingResult *match = [element firstMatchInString:typed options:0 range:NSMakeRange(0, typed.length)];
                if (match) [found addObject:[typed substringWithRange:[match rangeAtIndex:2]]];
            }
        }
    }
    return [found.array sortedArrayUsingSelector:@selector(compare:)];
}

- (NSArray<NSString *> *)exampleElementsForSkeleton:(UDSQLSkeletonViewController *)skeleton {
    return [self _elements];
}

/// A new element named after @a base (_customer, _customer2…).
- (NSString *)_newElementNamed:(NSString *)base {
    NSArray *taken = [self _elements];
    NSString *name = [@"_" stringByAppendingString:base.lowercaseString];
    for (NSUInteger n = 2; [taken containsObject:name]; n++) name = [NSString stringWithFormat:@"_%@%lu", base.lowercaseString, (unsigned long)n];
    return name;
}

- (NSString *)newExampleElementForSkeleton:(UDSQLSkeletonViewController *)skeleton {
    return [self _newElementNamed:@"x"];
}

// ---------------------------------------------------------------------------
// MARK: - Add Table: joined along its keys
// ---------------------------------------------------------------------------

/// An element under @a column of @a skeleton's first row: the one there,
/// else a new one named @a base; nil when a condition is there.
- (nullable NSString *)_elementOf:(UDSQLExampleFileSkeleton *)skeleton column:(NSString *)column base:(NSString *)base {
    UDSQLExampleRow *row = skeleton.rows.firstObject;
    NSString *typed = [row.entries[column] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] ?: @"";
    BOOL printed = [typed.uppercaseString hasPrefix:@"P."];
    NSString *rest = printed ? [typed substringFromIndex:2] : typed;
    if ([rest hasPrefix:@"_"]) return rest;
    if (rest.length) return nil;
    NSString *element = [self _newElementNamed:base];
    NSMutableDictionary *entries = [row.entries mutableCopy];
    entries[column] = printed ? [@"P." stringByAppendingString:element] : element;
    row.entries = entries;
    return element;
}

- (void)addTable:(UDSQLTable *)table {
    if (!_file) return;
    UDSQLExampleFileSkeleton *added = [UDSQLExampleFileSkeleton skeletonOfTable:table.name schema:table.schema];
    // the first key between it and a table there: an element in both
    for (UDSQLExampleFileSkeleton *other in _file.skeletons) {
        UDSQLTable *there = [self _tableOf:other];
        if (!there) continue;
        UDSQLExampleFileSkeleton *from = nil, *to = nil;
        UDSQLForeignKey *key = nil;
        for (UDSQLForeignKey *candidate in table.foreignKeys) {
            if ([candidate.referencedTable isEqualToString:there.name] && candidate.columns.count == 1) { key = candidate; from = added; to = other; break; }
        }
        for (UDSQLForeignKey *candidate in key ? @[] : there.foreignKeys) {
            if ([candidate.referencedTable isEqualToString:table.name] && candidate.columns.count == 1) { key = candidate; from = other; to = added; break; }
        }
        if (!key) continue;
        UDSQLTable *referenced = to == added ? table : there;
        NSString *target = key.referencedColumns.firstObject;
        for (UDSQLColumnInfo *column in referenced.columns) if (!target && column.primaryKey) target = column.name;
        if (!target) continue;
        NSString *element = [self _elementOf:to column:target base:referenced.name];
        if (!element) continue;
        NSMutableDictionary *entries = [from.rows.firstObject.entries mutableCopy];
        if ([entries[key.columns.firstObject] length]) continue;
        entries[key.columns.firstObject] = element;
        from.rows.firstObject.entries = entries;
        break;
    }
    _file.skeletons = [_file.skeletons arrayByAddingObject:added];
    _selected = (NSInteger)_file.skeletons.count - 1;     // the one added
    [self _writeDocument];
    [self _makeSkeletons];
}

- (IBAction)addTableChosen:(id)sender {
    UDSQLTable *table = [sender representedObject];
    if (table) [self addTable:table];
}

// ---------------------------------------------------------------------------
// MARK: - Asking it
// ---------------------------------------------------------------------------

- (void)_showStatus:(NSString *)text error:(BOOL)error {
    _statusLabel.textColor = error ? [NSColor systemRedColor] : [NSColor secondaryLabelColor];
    _statusLabel.stringValue = text;
}

- (nullable UDSQLExampleQuery *)_query:(NSError **)error {
    UDSQLDatabase *database = self.database;
    if (!database || !database.schema) {
        if (error) *error = [NSError errorWithDomain:UDSQLErrorDomain code:-1 userInfo:@{
            NSLocalizedDescriptionKey: database ? @"Not connected yet." : @"Choose the database it is asked of." }];
        return nil;
    }
    if (!_file) {
        if (error) *error = _readError;
        return nil;
    }
    return [_file queryForSchema:database.schema dialect:database.dialect databaseName:database.name error:error];
}

- (NSString *)SQL:(NSError **)error {
    return [[self _query:error] SQL:error];
}

- (IBAction)run:(id)sender {
    _offset = 0;
    [self _runPage];
}

- (IBAction)previousPage:(id)sender {
    if (_running || !_offset) return;
    _offset = _offset > _pageSize ? _offset - _pageSize : 0;
    [self _runPage];
}

- (IBAction)nextPage:(id)sender {
    if (_running || !_result || _offset + _result.rows.count >= _count) return;
    _offset += _pageSize;
    [self _runPage];
}

/// Its page from _offset, and how many rows it has: one run, two statements.
- (void)_runPage {
    [self.view.window makeFirstResponder:nil];
    UDSQLDatabase *database = self.database;
    if (database && !database.schema) {
        _runsWhenConnected = YES;
        // asked for: tried again, though it failed (its password not given)
        if (database.error && !database.connecting) [_databases connect:database];
        [self _useDatabase];
        return;
    }
    NSError *error = nil;
    UDSQLExampleQuery *query = [self _query:&error];
    UDSQLStatement *statement = [query selectStatementWithLimit:_pageSize offset:_offset error:&error];
    UDSQLStatement *count = statement ? [query countStatement:&error] : nil;
    if (!statement || !count) {
        [self _showStatus:error.localizedDescription ?: @"It can't be asked." error:YES];
        return;
    }
    _pending = @[ statement, count ];
    _running = YES;
    [self _updatePager];
    [self _showStatus:@"Running…" error:NO];
    [database.runner run:_pending maxRows:_pageSize target:self action:@selector(_didRun:)];
}

- (void)_didRun:(UDSQLRun *)run {
    if (!run.finished || run.statements != _pending) return;
    _pending = nil;
    _running = NO;
    if (run.error) {
        [self _updatePager];
        [self _showStatus:run.error.localizedDescription error:YES];
        return;
    }
    _result = run.results.firstObject;
    id counted = run.results.count > 1 ? [run.results[1].rows.firstObject firstObject] : nil;
    _count = [counted respondsToSelector:@selector(unsignedIntegerValue)] ? [counted unsignedIntegerValue] : NSNotFound;
    [self _makeResultColumns];
    [self _updatePager];
    NSNumberFormatter *numbers = [[NSNumberFormatter alloc] init];
    numbers.numberStyle = NSNumberFormatterDecimalStyle;
    NSString *shown = !_result.rows.count ? @"No rows"
        : [NSString stringWithFormat:@"Rows %@–%@", [numbers stringFromNumber:@(_offset + 1)], [numbers stringFromNumber:@(_offset + _result.rows.count)]];
    if (_count != NSNotFound && _result.rows.count) shown = [shown stringByAppendingFormat:@" of %@", [numbers stringFromNumber:@(_count)]];
    [self _showStatus:[NSString stringWithFormat:@"%@ (%@)", shown, self.database.name] error:NO];
}

/// ◀ and ▶: a page before this one, after it.
- (void)_updatePager {
    [_previousButton setEnabled:!_running && _offset > 0];
    [_nextButton setEnabled:!_running && _result && _count != NSNotFound && _offset + _result.rows.count < _count];
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
            if (i < values.count) width = MAX(width, [UDSQLTextOfValue(values[i], described.name, described.type, self.database.schema)
                                                         sizeWithAttributes:font].width);
        }
        column.width = MAX(48, MIN(320, ceil(width) + 16));
        [_resultsView addTableColumn:column];
    }
    [_resultsView reloadData];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)_result.rows.count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    NSUInteger index = (NSUInteger)[column.identifier integerValue];
    NSArray *values = _result.rows[(NSUInteger)row];
    UDSQLColumn *described = index < _result.columns.count ? _result.columns[index] : nil;
    return index < values.count ? UDSQLCellOfValue(values[index], described.name, described.type, self.database.schema) : @"";
}

/// A column's name clicked: its answer sorted by it (again: the other way).
- (void)tableView:(NSTableView *)tableView didClickTableColumn:(NSTableColumn *)column {
    NSString *name = [column.headerCell stringValue];
    NSSortDescriptor *first = _file.order.firstObject;
    [self sortByColumn:name ascending:!([first.key isEqualToString:name] && first.ascending)];
}

- (IBAction)showSQL:(id)sender {
    [self.view.window makeFirstResponder:nil];
    NSError *error = nil;
    NSString *sql = [self SQL:&error];
    if (!sql) {
        [self _showStatus:error.localizedDescription ?: @"It can't be asked." error:YES];
        return;
    }
    [_databases openQuery:[UDSQLPrettyPrinted(sql) stringByAppendingString:@";\n"] database:self.database run:NO];
}

- (IBAction)copySQL:(id)sender {
    [self.view.window makeFirstResponder:nil];
    NSError *error = nil;
    NSString *sql = [self SQL:&error];
    if (!sql) {
        [self _showStatus:error.localizedDescription ?: @"It can't be asked." error:YES];
        return;
    }
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard declareTypes:@[ NSPasteboardTypeString ] owner:nil];
    [pasteboard setString:UDSQLPrettyPrinted(sql) forType:NSPasteboardTypeString];
    [self _showStatus:[NSString stringWithFormat:@"Its SQL copied (%@'s)", self.database.name] error:NO];
}

- (void)_copyHeaders:(BOOL)headers {
    NSIndexSet *rows = _resultsView.selectedRowIndexes.count ? _resultsView.selectedRowIndexes
                                                             : [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, _result.rows.count)];
    NSMutableArray *lines = [NSMutableArray array];
    if (headers) [lines addObject:[[_result.columns valueForKey:@"name"] componentsJoinedByString:@"\t"]];
    for (NSUInteger row = rows.firstIndex; row != NSNotFound; row = [rows indexGreaterThanIndex:row]) {
        NSMutableArray *cells = [NSMutableArray array];
        NSArray *values = _result.rows[row];
        for (NSUInteger i = 0; i < values.count; i++) {
            UDSQLColumn *described = i < _result.columns.count ? _result.columns[i] : nil;
            [cells addObject:values[i] == [NSNull null] ? @"" : UDSQLTextOfValue(values[i], described.name, described.type, self.database.schema)];
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

// ---------------------------------------------------------------------------
// MARK: - A column copied, the answer exported
// ---------------------------------------------------------------------------

/// The column a menu opens on: the cell's right-clicked, else the name's.
- (void)menuNeedsUpdate:(NSMenu *)menu {
    _menuColumn = _resultsView.clickedColumn;
    NSEvent *event = [NSApp currentEvent];
    if (_menuColumn < 0 && event) {
        NSTableHeaderView *header = _resultsView.headerView;
        _menuColumn = [header columnAtPoint:[header convertPoint:event.locationInWindow fromView:nil]];
    }
}

- (void)copyColumnAtIndex:(NSUInteger)index withName:(BOOL)name {
    if (index >= _result.columns.count) return;
    NSIndexSet *rows = _resultsView.selectedRowIndexes.count ? _resultsView.selectedRowIndexes
                                                             : [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, _result.rows.count)];
    UDSQLColumn *described = _result.columns[index];
    NSMutableArray *lines = [NSMutableArray array];
    if (name) [lines addObject:described.name];
    for (NSUInteger row = rows.firstIndex; row != NSNotFound; row = [rows indexGreaterThanIndex:row]) {
        NSArray *values = _result.rows[row];
        id value = index < values.count ? values[index] : [NSNull null];
        [lines addObject:value == [NSNull null] ? @"" : UDSQLTextOfValue(value, described.name, described.type, self.database.schema)];
    }
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard declareTypes:@[ NSPasteboardTypeString ] owner:nil];
    [pasteboard setString:[lines componentsJoinedByString:@"\n"] forType:NSPasteboardTypeString];
}

/// The column's index in the answer (the table's columns may be moved).
- (NSInteger)_resultColumnOfMenu {
    if (_menuColumn < 0 || _menuColumn >= (NSInteger)_resultsView.tableColumns.count) return -1;
    return [[_resultsView.tableColumns[(NSUInteger)_menuColumn] identifier] integerValue];
}

- (IBAction)copyColumn:(id)sender {
    NSInteger index = [self _resultColumnOfMenu];
    if (index >= 0) [self copyColumnAtIndex:(NSUInteger)index withName:NO];
}

- (IBAction)copyColumnWithName:(id)sender {
    NSInteger index = [self _resultColumnOfMenu];
    if (index >= 0) [self copyColumnAtIndex:(NSUInteger)index withName:YES];
}

- (IBAction)sortAscending:(id)sender {
    NSInteger index = [self _resultColumnOfMenu];
    if (index >= 0) [self sortByColumn:_result.columns[(NSUInteger)index].name ascending:YES];
}

- (IBAction)sortDescending:(id)sender {
    NSInteger index = [self _resultColumnOfMenu];
    if (index >= 0) [self sortByColumn:_result.columns[(NSUInteger)index].name ascending:NO];
}

- (void)sortByColumn:(NSString *)name ascending:(BOOL)ascending {
    _file.order = @[ [NSSortDescriptor sortDescriptorWithKey:name ascending:ascending] ];
    [self _writeDocument];
    [self run:nil];
}

/// Export…: all its rows (not a page's), where and as what (CSV, JSON) asked.
- (IBAction)exportResult:(id)sender {
    NSSavePanel *panel = [NSSavePanel savePanel];
    NSString *name = [_document.displayName stringByDeletingPathExtension];
    panel.nameFieldStringValue = [name stringByAppendingPathExtension:@"csv"];
    panel.allowedFileTypes = @[ @"csv", @"json" ];
    panel.accessoryView = _exportAccessory;
    [_exportFormatButton selectItemAtIndex:0];
    _exportFormatButton.target = self;
    _exportFormatButton.action = @selector(_exportFormatChosen:);
    objc_setAssociatedObject(_exportFormatButton, "panel", panel, OBJC_ASSOCIATION_ASSIGN);
    [panel beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse response) {
        objc_setAssociatedObject(self->_exportFormatButton, "panel", nil, OBJC_ASSOCIATION_ASSIGN);
        if (response != NSModalResponseOK || !panel.URL) return;
        [self exportToURL:panel.URL format:self->_exportFormatButton.selectedItem.representedObject ?: panel.URL.pathExtension];
    }];
}

/// The format chosen: the file's name says it too.
- (void)_exportFormatChosen:(NSPopUpButton *)sender {
    NSSavePanel *panel = objc_getAssociatedObject(sender, "panel");
    NSString *extension = sender.selectedItem.representedObject;
    if (!panel || !extension) return;
    panel.allowedFileTypes = @[ extension ];
    panel.nameFieldStringValue = [[panel.nameFieldStringValue stringByDeletingPathExtension] stringByAppendingPathExtension:extension];
}

- (void)exportToURL:(NSURL *)url format:(NSString *)format {
    UDSQLDatabase *database = self.database;
    NSError *error = nil;
    NSString *sql = database.schema ? [self SQL:&error] : nil;
    if (!sql) {
        [self _showStatus:error.localizedDescription ?: @"Connect first: it is asked of a database." error:YES];
        return;
    }
    _exportURL = url;
    _exportFormat = [format.lowercaseString isEqualToString:@"json"] ? @"json" : @"csv";
    _exporting = @[ [[UDSQLStatement alloc] initWithText:sql SQL:sql parameters:@[]] ];
    _running = YES;
    [self _updatePager];
    [self _showStatus:@"Exporting…" error:NO];
    [database.runner run:_exporting maxRows:UDMaxExported target:self action:@selector(_didExport:)];
}

- (void)_didExport:(UDSQLRun *)run {
    if (!run.finished || run.statements != _exporting) return;
    _exporting = nil;
    _running = NO;
    [self _updatePager];
    if (run.error) {
        [self _showStatus:run.error.localizedDescription error:YES];
        return;
    }
    UDSQLResult *all = run.results.firstObject;
    UDSQLSchema *schema = self.database.schema;
    NSString *text = [_exportFormat isEqualToString:@"json"] ? UDSQLJSONOfResult(all, schema) : UDSQLCSVOfResult(all, schema);
    NSError *error = nil;
    if (![text writeToURL:_exportURL atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
        [self _showStatus:error.localizedDescription error:YES];
        return;
    }
    NSNumberFormatter *numbers = [[NSNumberFormatter alloc] init];
    numbers.numberStyle = NSNumberFormatterDecimalStyle;
    [self _showStatus:[NSString stringWithFormat:@"%@ %@ exported to %@", [numbers stringFromNumber:@(all.rows.count)],
                                                 all.rows.count == 1 ? @"row" : @"rows", _exportURL.lastPathComponent] error:NO];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    SEL action = item.action;
    if (sel_isEqual(action, @selector(copyColumn:)) || sel_isEqual(action, @selector(copyColumnWithName:)) ||
        sel_isEqual(action, @selector(sortAscending:)) || sel_isEqual(action, @selector(sortDescending:))) {
        return [self _resultColumnOfMenu] >= 0;
    }
    if (sel_isEqual(action, @selector(undo:))) return _document.textModel.undoManager.canUndo;
    if (sel_isEqual(action, @selector(redo:))) return _document.textModel.undoManager.canRedo;
    if (sel_isEqual(action, @selector(copy:)) || sel_isEqual(action, @selector(copyWithColumnNames:))) return _result.rows.count > 0;
    return YES;
}

@end
