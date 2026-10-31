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
@end

@implementation UDSQLDiagramViewController {
    __weak UDSQLDatabases *_databases;
    UDSQLDiagram *_diagram;
    UDSQLSchema *_schema;           // the one drawn
    NSString *_menuTable;           // what the context menu is about
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
    [_canvas reloadData];
    [self _showStatus];
}

- (void)_showStatus {
    if (_diagram) {
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
    return [_diagram tableAtPoint:point];
}

- (NSArray *)canvas:(DKCanvasView *)canvas itemsInRect:(NSRect)rect {
    return _diagram ? [_diagram tablesInRect:rect] : @[];
}

- (NSRect)canvas:(DKCanvasView *)canvas frameOfItem:(id)item {
    return [_diagram tableWithIdentifier:item].frame;
}

- (void)canvas:(DKCanvasView *)canvas moveItems:(NSArray *)items by:(NSSize)delta {
    [self _moveTables:items by:delta];
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

- (void)canvas:(DKCanvasView *)canvas doubleClickedItem:(id)item {
    if (item) [self _selectRowsOf:item];
}

- (NSMenu *)canvas:(DKCanvasView *)canvas menuForItem:(id)item {
    if (!item) return nil;
    _menuTable = item;
    NSMenu *menu = [[NSMenu alloc] initWithTitle:_tableMenu.title];
    for (NSMenuItem *source in _tableMenu.itemArray) [menu addItem:[source copy]];
    return menu;
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

/// The context menu's table (its identifier), else the one selected.
- (nullable NSString *)_actedOnIdentifier:(id)sender {
    NSString *identifier = [sender isKindOfClass:[NSMenuItem class]] && _menuTable ? _menuTable
                         : _canvas.selection.count == 1 ? _canvas.selection.anyObject : nil;
    return [_diagram tableWithIdentifier:identifier ?: @""] ? identifier : nil;
}

- (nullable UDSQLTable *)_actedOn:(id)sender {
    NSString *identifier = [self _actedOnIdentifier:sender];
    return identifier ? [_diagram tableWithIdentifier:identifier].table : nil;
}

- (id)_quoter {
    return _database.runner.connection ?: [[UDSQLConnection alloc] init];
}

- (void)_selectRowsOf:(NSString *)identifier {
    UDSQLTable *table = [_diagram tableWithIdentifier:identifier].table;
    if (!table) return;
    NSString *sql = [NSString stringWithFormat:@"SELECT * FROM %@ LIMIT 100", [table qualifiedNameFor:[self _quoter]]];
    [_databases openQuery:sql database:_database run:YES];
}

- (IBAction)selectRows:(id)sender {
    NSString *identifier = [self _actedOnIdentifier:sender];
    if (identifier) [self _selectRowsOf:identifier];
}

- (IBAction)newQuery:(id)sender {
    UDSQLTable *table = [self _actedOn:sender];
    if (!table) return;
    [_databases openQuery:[NSString stringWithFormat:@"SELECT *\nFROM %@\nWHERE ", [table qualifiedNameFor:[self _quoter]]]
                 database:_database run:NO];
}

- (IBAction)copyName:(id)sender {
    UDSQLTable *table = [self _actedOn:sender];
    if (!table) return;
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard declareTypes:@[ NSPasteboardTypeString ] owner:nil];
    [pasteboard setString:table.name forType:NSPasteboardTypeString];
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
