/*---------------------------------------------------------------------------------------------
 *  UDSQLResultsViewController.m
 *--------------------------------------------------------------------------------------------*/

#import "UDSQLResultsViewController.h"
#import "UDSQLDatabases.h"

@interface UDSQLResultsViewController ()
@property (nonatomic, weak) IBOutlet NSPopUpButton *databaseButton;
@property (nonatomic, weak) IBOutlet NSSegmentedControl *resultsControl;
@property (nonatomic, weak) IBOutlet NSTableView *grid;
@property (nonatomic, strong) IBOutlet NSTextView *messagesView;
@property (nonatomic, weak) IBOutlet NSTextField *statusLabel;
@property (nonatomic, weak) IBOutlet NSButton *stopButton;
/// The grid's column as the XIB has it: each result's columns made like it.
@property (nonatomic, strong) IBOutlet NSTableColumn *templateColumn;
@end

@implementation UDSQLResultsViewController {
    __weak UDSQLDatabases *_databases;
    __weak UDCodeDocument *_document;
    UDSQLDatabase *_database;           // the run's
    NSArray<UDSQLStatement *> *_statements;
    NSArray<UDSQLResult *> *_results;
    NSInteger _shown;                   // the result in the grid; -1: the messages
    NSDate *_started;
    NSDateFormatter *_dates;
}

- (instancetype)initWithDatabases:(UDSQLDatabases *)databases document:(UDCodeDocument *)document {
    self = [super initWithNibName:@"UDSQLResults" bundle:[NSBundle bundleForClass:[UDSQLResultsViewController class]]];
    if (self) {
        _databases = databases;
        _document = document;
        _results = @[];
        _shown = -1;
        _dates = [[NSDateFormatter alloc] init];
        _dates.dateFormat = @"yyyy-MM-dd HH:mm:ss";
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reloadDatabases)
                                                     name:UDSQLDatabasesDidChangeNotification object:databases];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [_templateColumn.tableView removeTableColumn:_templateColumn];
    _messagesView.font = [NSFont userFixedPitchFontOfSize:[NSFont smallSystemFontSize]];
    _messagesView.textContainerInset = NSMakeSize(6, 6);
    [self reloadDatabases];
    [self _showResults];
}

- (NSArray<UDSQLResult *> *)results {
    return _results;
}

- (UDSQLResult *)shownResult {
    return _shown >= 0 && _shown < (NSInteger)_results.count ? _results[(NSUInteger)_shown] : nil;
}

// ---------------------------------------------------------------------------
// MARK: - The database
// ---------------------------------------------------------------------------

- (void)reloadDatabases {
    if (!self.isViewLoaded) return;
    UDSQLDatabases *databases = _databases;
    UDCodeDocument *document = _document;
    [_databaseButton removeAllItems];
    [_databaseButton addItemWithTitle:@"No Database"];
    for (UDSQLDatabase *database in databases.databases) [_databaseButton addItemWithTitle:database.name];
    UDSQLDatabase *chosen = document ? [databases databaseOfDocument:document] : nil;
    [_databaseButton selectItemWithTitle:chosen ? chosen.name : @"No Database"];
}

- (IBAction)chooseDatabase:(id)sender {
    UDSQLDatabases *databases = _databases;
    UDCodeDocument *document = _document;
    if (!document) return;
    [databases setDatabase:[databases databaseNamed:_databaseButton.titleOfSelectedItem] ofDocument:document];
}

- (IBAction)runStatement:(id)sender {
    [self _focusText];
    [_databases runStatement:sender];
}

- (IBAction)runAll:(id)sender {
    [self _focusText];
    [_databases runAll:sender];
}

- (IBAction)stopRunning:(id)sender {
    [_databases stopRunning:sender];
}

/// The document's text, focused (Run's caret is its).
- (void)_focusText {
    UDSQLDatabases *databases = _databases;
    NSTextView *text = databases.workbench.selectedEditor.textView;
    if (text) [self.view.window makeFirstResponder:text];
}

// ---------------------------------------------------------------------------
// MARK: - A run
// ---------------------------------------------------------------------------

- (void)_log:(NSString *)line color:(nullable NSColor *)color {
    (void)self.view;
    NSDictionary *attributes = @{ NSFontAttributeName: [NSFont userFixedPitchFontOfSize:[NSFont smallSystemFontSize]],
                                  NSForegroundColorAttributeName: color ?: [NSColor textColor] };
    [_messagesView.textStorage appendAttributedString:[[NSAttributedString alloc] initWithString:[line stringByAppendingString:@"\n"]
                                                                                       attributes:attributes]];
    [_messagesView scrollRangeToVisible:NSMakeRange(_messagesView.string.length, 0)];
}

static NSString *UDFirstLine(NSString *statement) {
    NSString *line = [[statement componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]] firstObject] ?: @"";
    return line.length > 80 ? [[line substringToIndex:80] stringByAppendingString:@"…"] : line;
}

- (void)showMessage:(NSString *)message error:(BOOL)error {
    [self _log:message color:error ? [NSColor systemRedColor] : [NSColor secondaryLabelColor]];
    _statusLabel.stringValue = message;
    _shown = -1;
    [self _showResults];
}

- (void)beginRun:(NSArray<UDSQLStatement *> *)statements database:(UDSQLDatabase *)database {
    (void)self.view;
    _database = database;
    _statements = [statements copy];
    _results = @[];
    _started = [NSDate date];
    [self _log:[NSString stringWithFormat:@"— %@ — %@", database.name, [_dates stringFromDate:_started]] color:[NSColor secondaryLabelColor]];
    _statusLabel.stringValue = statements.count == 1 ? @"Running…" : [NSString stringWithFormat:@"Running %lu statements…", (unsigned long)statements.count];
    [_stopButton setEnabled:YES];
    [self _showResults];
}

- (void)showRun:(UDSQLRun *)run {
    (void)self.view;
    for (NSUInteger i = _results.count; i < run.results.count; i++) {
        UDSQLResult *result = run.results[i];
        NSString *what = result.columns.count
            ? [NSString stringWithFormat:@"%lu row%@%@", (unsigned long)result.rows.count, result.rows.count == 1 ? @"" : @"s",
               result.truncated ? @" (the first ones: there are more)" : @""]
            : result.rowsAffected >= 0 ? [NSString stringWithFormat:@"%lld row%@ changed", result.rowsAffected, result.rowsAffected == 1 ? @"" : @"s"]
            : @"done";
        [self _log:[NSString stringWithFormat:@"%@ — %@, %.0f ms", UDFirstLine(result.statement), what, result.duration * 1000] color:nil];
    }
    _results = run.results;
    // the last result with rows, shown; else the messages
    _shown = -1;
    for (NSInteger i = (NSInteger)_results.count - 1; i >= 0; i--) {
        if (_results[(NSUInteger)i].columns.count) {
            _shown = i;
            break;
        }
    }
    if (run.finished) {
        [_stopButton setEnabled:NO];
        NSTimeInterval took = -_started.timeIntervalSinceNow;
        if (run.error) {
            NSString *statement = run.failedStatement < _statements.count ? UDFirstLine(_statements[run.failedStatement].text) : @"";
            NSString *state = run.error.userInfo[UDSQLStateErrorKey];
            [self _log:[NSString stringWithFormat:@"%@ — %@%@", statement, run.error.localizedDescription,
                        state ? [NSString stringWithFormat:@" (%@)", state] : @""]
                 color:[NSColor systemRedColor]];
            _statusLabel.stringValue = run.error.localizedDescription;
            _shown = -1;
        } else {
            _statusLabel.stringValue = [NSString stringWithFormat:@"%lu statement%@ in %.0f ms", (unsigned long)_results.count,
                                        _results.count == 1 ? @"" : @"s", took * 1000];
        }
    }
    [self _showResults];
}

// ---------------------------------------------------------------------------
// MARK: - Results: one in the grid, or the messages
// ---------------------------------------------------------------------------

- (void)_showResults {
    if (!self.isViewLoaded) return;
    NSUInteger count = _results.count;
    _resultsControl.segmentCount = (NSInteger)count + 1;
    for (NSUInteger i = 0; i < count; i++) {
        UDSQLResult *result = _results[i];
        [_resultsControl setLabel:result.columns.count ? [NSString stringWithFormat:@"%lu", (unsigned long)i + 1]
                                                       : [NSString stringWithFormat:@"%lu ✓", (unsigned long)i + 1]
                       forSegment:(NSInteger)i];
    }
    [_resultsControl setLabel:@"Messages" forSegment:(NSInteger)count];
    // each as wide as its label (GNUstep's don't size themselves)
    NSDictionary *font = @{ NSFontAttributeName: [NSFont systemFontOfSize:[NSFont smallSystemFontSize]] };
    for (NSInteger segment = 0; segment <= (NSInteger)count; segment++) {
        [_resultsControl setWidth:ceil([[_resultsControl labelForSegment:segment] sizeWithAttributes:font].width) + 18 forSegment:segment];
    }
    _resultsControl.selectedSegment = _shown >= 0 ? _shown : (NSInteger)count;
    [_resultsControl sizeToFit];
    UDSQLResult *shown = self.shownResult;
    [_grid.enclosingScrollView setHidden:shown == nil];
    [_messagesView.enclosingScrollView setHidden:shown != nil];
    for (NSTableColumn *column in [_grid.tableColumns copy]) [_grid removeTableColumn:column];
    for (NSUInteger i = 0; i < shown.columns.count; i++) {
        UDSQLColumn *described = shown.columns[i];
        NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:[NSString stringWithFormat:@"%lu", (unsigned long)i]];
        column.dataCell = [_templateColumn.dataCell copy];
        [column.headerCell setStringValue:described.name];
        column.headerToolTip = described.type;
        column.editable = NO;
        // as wide as its name and its first values, within reason
        NSDictionary *font = @{ NSFontAttributeName: [NSFont systemFontOfSize:[NSFont smallSystemFontSize]] };
        CGFloat width = [described.name sizeWithAttributes:font].width;
        for (NSUInteger row = 0; row < MIN(shown.rows.count, 50u); row++) {
            NSArray *values = shown.rows[row];
            if (i < values.count) width = MAX(width, [[self textOfValue:values[i] column:i] sizeWithAttributes:font].width);
        }
        column.width = MAX(48, MIN(320, ceil(width) + 16));
        column.minWidth = 30;
        column.maxWidth = 2000;
        [_grid addTableColumn:column];
    }
    [_grid reloadData];
}

- (IBAction)showResult:(id)sender {
    NSInteger segment = _resultsControl.selectedSegment;
    _shown = segment < (NSInteger)_results.count && _results[(NSUInteger)segment].columns.count ? segment : -1;
    [self _showResults];
}

- (NSString *)textOfValue:(id)value column:(NSUInteger)column {
    if (value == [NSNull null]) return @"NULL";
    if ([value isKindOfClass:[NSData class]]) return [NSString stringWithFormat:@"⟨%lu bytes⟩", (unsigned long)[value length]];
    UDSQLColumn *described = column < self.shownResult.columns.count ? self.shownResult.columns[column] : nil;
    UDSQLSchema *schema = _database.schema;
    if (schema.coreDataStore && [value isKindOfClass:[NSNumber class]]) {
        // a Core Data store's dates and entities, as such
        if ([described.type caseInsensitiveCompare:@"TIMESTAMP"] == NSOrderedSame) {
            return [_dates stringFromDate:UDSQLDateOfCoreDataTimestamp([value doubleValue])];
        }
        if ([described.name isEqualToString:@"Z_ENT"] && schema.coreDataEntities[value]) {
            return [NSString stringWithFormat:@"%@ · %@", value, schema.coreDataEntities[value]];
        }
    }
    NSString *text = [value description];
    return [[text stringByReplacingOccurrencesOfString:@"\r\n" withString:@" ↵ "] stringByReplacingOccurrencesOfString:@"\n" withString:@" ↵ "];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)self.shownResult.rows.count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    NSUInteger index = (NSUInteger)[column.identifier integerValue];
    NSArray *values = self.shownResult.rows[(NSUInteger)row];
    id value = index < values.count ? values[index] : [NSNull null];
    NSString *text = [self textOfValue:value column:index];
    if (value == [NSNull null] || [value isKindOfClass:[NSData class]]) {
        // not the value itself: told apart
        return [[NSAttributedString alloc] initWithString:text attributes:@{
            NSForegroundColorAttributeName: [NSColor disabledControlTextColor],
            NSFontAttributeName: [NSFont systemFontOfSize:[NSFont smallSystemFontSize]] }];
    }
    return text;
}

- (NSString *)tableView:(NSTableView *)tableView toolTipForCell:(NSCell *)cell rect:(NSRectPointer)rect tableColumn:(NSTableColumn *)column
                    row:(NSInteger)row mouseLocation:(NSPoint)location {
    NSUInteger index = (NSUInteger)[column.identifier integerValue];
    NSArray *values = self.shownResult.rows[(NSUInteger)row];
    id value = index < values.count ? values[index] : nil;
    return [value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSNumber class]] ? [value description] : nil;
}

// ---------------------------------------------------------------------------
// MARK: - Copying
// ---------------------------------------------------------------------------

- (NSString *)_textOfRows:(NSIndexSet *)rows headers:(BOOL)headers {
    UDSQLResult *result = self.shownResult;
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    if (headers) [lines addObject:[[result.columns valueForKey:@"name"] componentsJoinedByString:@"\t"]];
    for (NSUInteger row = rows.firstIndex; row != NSNotFound; row = [rows indexGreaterThanIndex:row]) {
        NSMutableArray *cells = [NSMutableArray array];
        NSArray *values = result.rows[row];
        for (NSUInteger column = 0; column < values.count; column++) {
            id value = values[column];
            [cells addObject:value == [NSNull null] ? @"" : [self textOfValue:value column:column]];
        }
        [lines addObject:[cells componentsJoinedByString:@"\t"]];
    }
    return [lines componentsJoinedByString:@"\n"];
}

- (void)_copyHeaders:(BOOL)headers {
    if (!self.shownResult) return;
    NSIndexSet *rows = _grid.selectedRowIndexes.count ? _grid.selectedRowIndexes
                                                      : [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, self.shownResult.rows.count)];
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard declareTypes:@[ NSPasteboardTypeString ] owner:nil];
    [pasteboard setString:[self _textOfRows:rows headers:headers] forType:NSPasteboardTypeString];
}

- (IBAction)copy:(id)sender {
    [self _copyHeaders:NO];
}

- (IBAction)copyWithColumnNames:(id)sender {
    [self _copyHeaders:YES];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    if (item.action == @selector(copy:) || item.action == @selector(copyWithColumnNames:)) return self.shownResult != nil;
    return YES;
}

@end
