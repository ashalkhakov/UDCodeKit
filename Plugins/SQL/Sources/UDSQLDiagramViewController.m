/*---------------------------------------------------------------------------------------------
 *  UDSQLDiagramViewController.m
 *--------------------------------------------------------------------------------------------*/

#import "UDSQLDiagramViewController.h"
#import "UDSQLDatabases.h"
#import <objc/runtime.h>

@interface UDSQLDiagramViewController ()
@property (nonatomic, weak) IBOutlet DKCanvasView *canvas;
@property (nonatomic, weak) IBOutlet NSTextField *statusLabel;
@property (nonatomic, strong) IBOutlet NSMenu *tableMenu;
@property (nonatomic, strong) IBOutlet NSMenu *columnMenu;
@property (nonatomic, strong) IBOutlet NSMenu *linkMenu;
@end

@implementation UDSQLDiagramViewController {
    __weak UDSQLDatabases *_databases;
    UDSQLDiagram *_diagram;
    UDSQLSchema *_schema;           // the one drawn
    id _menuItem;                   // what the context menu is about
}

- (instancetype)initWithDatabases:(UDSQLDatabases *)databases database:(UDSQLDatabase *)database {
    self = [super initWithNibName:@"UDSQLDiagram" bundle:[NSBundle bundleForClass:[UDSQLDiagramViewController class]]];
    if (self) {
        _databases = databases;
        _database = database;
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
    [self reload];
    if (!_database.schema && !_database.connecting) [_databases connect:_database];
}

- (UDSQLDiagram *)diagram {
    return _diagram;
}

- (void)_databasesDidChange:(NSNotification *)note {
    // a schema read again (Refresh, a connect): drawn again
    if (self.isViewLoaded && _database.schema != _schema) [self reload];
    else if (self.isViewLoaded) [self _showStatus];
}

+ (NSString *)defaultsKeyOfURL:(NSURL *)url {
    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    components.password = nil;
    return [@"UDSQLDiagram " stringByAppendingString:components.string ?: url.absoluteString];
}

- (void)reload {
    _schema = _database.schema;
    _diagram = _schema ? [[UDSQLDiagram alloc] initWithSchema:_schema measure:[DKAppKitSurface surface]] : nil;
    NSDictionary *positions = [[NSUserDefaults standardUserDefaults] dictionaryForKey:[[self class] defaultsKeyOfURL:_database.URL]];
    if (positions) [_diagram applyPositions:positions];
    _canvas.selection = [NSSet set];
    _menuItem = nil;
    [_canvas reloadData];
    [self _showStatus];
}

- (void)_showStatus {
    NSSet *selection = _canvas.selection;
    if (_diagram && selection.count == 1 && [self descriptionOfItem:selection.anyObject]) {
        _statusLabel.stringValue = [self descriptionOfItem:selection.anyObject];
    } else if (_diagram && selection.count > 1) {
        _statusLabel.stringValue = [NSString stringWithFormat:@"%lu selected", (unsigned long)selection.count];
    } else if (_diagram) {
        NSUInteger inferred = [[_diagram.links filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"inferred == YES"]] count];
        NSUInteger tables = _diagram.tables.count, links = _diagram.links.count;
        _statusLabel.stringValue = [NSString stringWithFormat:@"%lu %@, %lu %@%@", (unsigned long)tables, tables == 1 ? @"table" : @"tables",
                                    (unsigned long)links, links == 1 ? @"link" : @"links",
                                    inferred ? [NSString stringWithFormat:@" (%lu inferred, dashed)", (unsigned long)inferred] : @""];
    } else if (_database.error) {
        _statusLabel.stringValue = _database.error.localizedDescription;
    } else {
        _statusLabel.stringValue = _database.connecting ? @"Connecting…" : @"Not connected";
    }
}

- (void)_keepPositions {
    if (!_diagram) return;
    [[NSUserDefaults standardUserDefaults] setObject:[_diagram positions] forKey:[[self class] defaultsKeyOfURL:_database.URL]];
}

// ---------------------------------------------------------------------------
// MARK: - The canvas's data source and delegate
// ---------------------------------------------------------------------------

- (NSRect)diagramBoundsForCanvas:(DKCanvasView *)canvas {
    return _diagram ? _diagram.bounds : NSMakeRect(0, 0, 400, 300);
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

/// A column's frame is its table's: a selected column drags its table.
- (NSRect)canvas:(DKCanvasView *)canvas frameOfItem:(id)item {
    UDSQLDiagramTable *box = [_diagram tableOfItem:item];
    return box ? box.frame : [_diagram frameOfItem:item];
}

- (BOOL)canvas:(DKCanvasView *)canvas canMoveItem:(id)item {
    return [_diagram tableOfItem:item] != nil;
}

- (void)canvas:(DKCanvasView *)canvas moveItems:(NSArray *)items by:(NSSize)delta {
    NSMutableOrderedSet *tables = [NSMutableOrderedSet orderedSet];
    for (id item in items) {
        UDSQLDiagramTable *box = [_diagram tableOfItem:item];
        if (box) [tables addObject:box.identifier];
    }
    [self _moveTables:tables.array by:delta];
}

- (void)_moveTables:(NSArray<NSString *> *)tables by:(NSSize)delta {
    [_diagram moveTables:tables by:delta];
    [self _keepPositions];
    [_canvas reloadData];
    NSUndoManager *undo = self.view.window.undoManager ?: _canvas.undoManager;
    [undo registerUndoWithTarget:self selector:@selector(_undoMove:)
                          object:@{ @"tables": tables, @"dx": @(-delta.width), @"dy": @(-delta.height) }];
    [undo setActionName:tables.count == 1 ? @"Move Table" : @"Move Tables"];
}

- (void)_undoMove:(NSDictionary *)move {
    [self _moveTables:move[@"tables"] by:NSMakeSize([move[@"dx"] doubleValue], [move[@"dy"] doubleValue])];
}

- (void)canvasSelectionDidChange:(DKCanvasView *)canvas {
    [self _showStatus];
}

- (void)canvas:(DKCanvasView *)canvas doubleClickedItem:(id)item {
    NSString *sql = item ? [self selectQueryOfItem:item] : nil;
    if (sql) [_databases openQuery:sql database:_database run:YES];
}

- (NSMenu *)canvas:(DKCanvasView *)canvas menuForItem:(id)item {
    NSMenu *source = [item isKindOfClass:[UDSQLDiagramLink class]] ? _linkMenu
                   : [item isKindOfClass:[UDSQLColumnInfo class]] ? _columnMenu : item ? _tableMenu : nil;
    if (!source) return nil;
    _menuItem = item;
    NSMenu *menu = [[NSMenu alloc] initWithTitle:source.title];
    for (NSMenuItem *menuItem in source.itemArray) [menu addItem:[menuItem copy]];
    return menu;
}

// ---------------------------------------------------------------------------
// MARK: - What an item says, and the SQL it opens
// ---------------------------------------------------------------------------

- (id)_quoter {
    return _database.runner.connection ?: [[UDSQLConnection alloc] init];
}

- (NSString *)_nameOf:(UDSQLDiagramTable *)box {
    return [box.table qualifiedNameFor:[self _quoter]];
}

/// A link's join: its tables (the one referred to as "parent" when it is
/// the same table) and its columns' pairs.
- (NSString *)_joinOf:(UDSQLDiagramLink *)link {
    UDSQLDiagramTable *from = [_diagram tableWithIdentifier:link.from], *to = [_diagram tableWithIdentifier:link.to];
    BOOL itself = from == to;
    NSString *fromName = itself ? @"child" : [self _nameOf:from], *toName = itself ? @"parent" : [self _nameOf:to];
    NSMutableArray *pairs = [NSMutableArray array];
    for (NSUInteger i = 0; i < MIN(link.columns.count, link.referencedColumns.count); i++) {
        [pairs addObject:[NSString stringWithFormat:@"%@.%@ = %@.%@", fromName, [[self _quoter] quotedIdentifier:link.columns[i]],
                                                    toName, [[self _quoter] quotedIdentifier:link.referencedColumns[i]]]];
    }
    return [NSString stringWithFormat:@"FROM %@%@\nJOIN %@%@ ON %@", [self _nameOf:from], itself ? @" AS child" : @"",
                                      [self _nameOf:to], itself ? @" AS parent" : @"", [pairs componentsJoinedByString:@" AND "]];
}

- (NSString *)selectQueryOfItem:(id)item {
    if ([item isKindOfClass:[UDSQLDiagramLink class]]) return [NSString stringWithFormat:@"SELECT *\n%@\nLIMIT 100", [self _joinOf:item]];
    UDSQLDiagramTable *box = [_diagram tableOfItem:item];
    if (!box) return nil;
    if ([item isKindOfClass:[UDSQLColumnInfo class]]) {
        // a column's values, the commonest first
        NSString *column = [[self _quoter] quotedIdentifier:[item name]];
        return [NSString stringWithFormat:@"SELECT %@, count(*)\nFROM %@\nGROUP BY %@\nORDER BY count(*) DESC\nLIMIT 100",
                                          column, [self _nameOf:box], column];
    }
    return [NSString stringWithFormat:@"SELECT * FROM %@ LIMIT 100", [self _nameOf:box]];
}

- (NSString *)newQueryOfItem:(id)item {
    if ([item isKindOfClass:[UDSQLDiagramLink class]]) return [NSString stringWithFormat:@"SELECT *\n%@\nWHERE ", [self _joinOf:item]];
    UDSQLDiagramTable *box = [_diagram tableOfItem:item];
    if (!box) return nil;
    if ([item isKindOfClass:[UDSQLColumnInfo class]]) {
        return [NSString stringWithFormat:@"SELECT *\nFROM %@\nWHERE %@ = ", [self _nameOf:box], [[self _quoter] quotedIdentifier:[item name]]];
    }
    return [NSString stringWithFormat:@"SELECT *\nFROM %@\nWHERE ", [self _nameOf:box]];
}

/// A link as text: people.team → teams.id.
- (NSString *)_textOf:(UDSQLDiagramLink *)link {
    UDSQLDiagramTable *from = [_diagram tableWithIdentifier:link.from], *to = [_diagram tableWithIdentifier:link.to];
    return [NSString stringWithFormat:@"%@.%@ → %@.%@", from.table.name, [link.columns componentsJoinedByString:@", "],
                                      to.table.name, [link.referencedColumns componentsJoinedByString:@", "]];
}

- (NSString *)nameOfItem:(id)item {
    if ([item isKindOfClass:[UDSQLDiagramLink class]]) return [self _textOf:item];
    if ([item isKindOfClass:[UDSQLColumnInfo class]]) return [item name];
    return [_diagram tableOfItem:item].table.name;
}

- (NSString *)descriptionOfItem:(id)item {
    if ([item isKindOfClass:[UDSQLDiagramLink class]]) {
        UDSQLDiagramLink *link = item;
        NSString *many = link.toEnd == DKEdgeEndCrowFootZeroOrOne ? @"many to zero or one" : @"many to one";
        return [NSString stringWithFormat:@"%@ (%@%@)", [self _textOf:link], many, link.inferred ? @", inferred" : @""];
    }
    UDSQLDiagramTable *box = [_diagram tableOfItem:item];
    if (!box) return nil;
    if ([item isKindOfClass:[UDSQLColumnInfo class]]) {
        UDSQLColumnInfo *column = item;
        NSMutableArray *parts = [NSMutableArray arrayWithObject:[NSString stringWithFormat:@"%@.%@ %@%@", box.table.name, column.name,
                                                                 column.type, column.nullable ? @"" : @" NOT NULL"]];
        if (column.primaryKey) [parts addObject:@"primary key"];
        for (UDSQLDiagramLink *link in _diagram.links) {
            if ([link.from isEqualToString:box.identifier] && [link.columns containsObject:column.name]) {
                [parts addObject:[NSString stringWithFormat:@"refers to %@", [_diagram tableWithIdentifier:link.to].table.name]];
            }
        }
        if (column.coreDataMeaning) [parts addObject:column.coreDataMeaning];
        return [parts componentsJoinedByString:@" · "];
    }
    NSUInteger out = 0, in = 0;
    for (UDSQLDiagramLink *link in _diagram.links) {
        if ([link.from isEqualToString:box.identifier]) out++;
        if ([link.to isEqualToString:box.identifier]) in++;
    }
    return [NSString stringWithFormat:@"%@: %lu %@, refers to %lu, referred to by %lu", box.table.name,
                                      (unsigned long)box.table.columns.count, box.table.columns.count == 1 ? @"column" : @"columns",
                                      (unsigned long)out, (unsigned long)in];
}

// ---------------------------------------------------------------------------
// MARK: - Actions
// ---------------------------------------------------------------------------

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    SEL action = item.action;
    if (sel_isEqual(action, @selector(selectRows:)) || sel_isEqual(action, @selector(newQuery:)) ||
        sel_isEqual(action, @selector(copyName:))) return [self _actedOn:item] != nil;
    if (sel_isEqual(action, @selector(arrange:)) || sel_isEqual(action, @selector(exportPDF:)) ||
        sel_isEqual(action, @selector(exportPNG:)) || sel_isEqual(action, @selector(exportSVG:))) return _diagram != nil;
    return YES;
}

/// The context menu's item, else the one selected.
- (nullable id)_actedOn:(id)sender {
    if ([sender isKindOfClass:[NSMenuItem class]] && _menuItem) return _menuItem;
    return _canvas.selection.count == 1 ? _canvas.selection.anyObject : nil;
}

- (IBAction)selectRows:(id)sender {
    id item = [self _actedOn:sender];
    NSString *sql = item ? [self selectQueryOfItem:item] : nil;
    if (sql) [_databases openQuery:sql database:_database run:YES];
}

- (IBAction)newQuery:(id)sender {
    id item = [self _actedOn:sender];
    NSString *sql = item ? [self newQueryOfItem:item] : nil;
    if (sql) [_databases openQuery:sql database:_database run:NO];
}

- (IBAction)copyName:(id)sender {
    id item = [self _actedOn:sender];
    NSString *name = item ? [self nameOfItem:item] : nil;
    if (!name) return;
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard declareTypes:@[ NSPasteboardTypeString ] owner:nil];
    [pasteboard setString:name forType:NSPasteboardTypeString];
}

- (IBAction)arrange:(id)sender {
    if (!_diagram) return;
    [_diagram arrange];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:[[self class] defaultsKeyOfURL:_database.URL]];
    [_canvas reloadData];
    [_canvas zoomToFit:nil];
}

- (void)_export:(nullable NSData *)data extension:(NSString *)extension {
    if (!data) {
        NSBeep();
        return;
    }
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.allowedFileTypes = @[ extension ];
    panel.nameFieldStringValue = [_database.name stringByAppendingPathExtension:extension];
    if ([panel runModal] != NSModalResponseOK || !panel.URL) return;
    NSError *error = nil;
    if (![data writeToURL:panel.URL options:NSDataWritingAtomic error:&error]) [[NSAlert alertWithError:error] runModal];
}

- (IBAction)exportPDF:(id)sender {
    [self _export:[_canvas PDFData] extension:@"pdf"];
}

- (IBAction)exportPNG:(id)sender {
    [self _export:[_canvas PNGDataAtScale:2] extension:@"png"];
}

- (IBAction)exportSVG:(id)sender {
    [self _export:[[_canvas SVGString] dataUsingEncoding:NSUTF8StringEncoding] extension:@"svg"];
}

@end
