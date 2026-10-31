/*---------------------------------------------------------------------------------------------
 *  UDSQLNavigatorViewController.m
 *--------------------------------------------------------------------------------------------*/

#import "UDSQLNavigatorViewController.h"
#import "UDSQLDatabases.h"
#import "UDSQLSheets.h"
#import <objc/runtime.h>

typedef NS_ENUM(NSInteger, UDSQLNodeKind) {
    UDSQLNodeDatabase,
    UDSQLNodeNote,              // Connecting…, an error, the store's metadata
    UDSQLNodeGroup,             // Tables, Views, Core Data
    UDSQLNodeTable,
    UDSQLNodeColumn,
    UDSQLNodeIndex,
    UDSQLNodeForeignKey,
};

/// A row of the outline.
@interface UDSQLNode : NSObject
@property (nonatomic) UDSQLNodeKind kind;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy, nullable) NSString *badge;
@property (nonatomic, copy, nullable) NSString *toolTip;
@property (nonatomic, strong, nullable) id object;          // its database, table or column
@property (nonatomic, weak, nullable) UDSQLNode *parent;
@property (nonatomic, copy) NSArray<UDSQLNode *> *children;
@property (nonatomic, readonly, copy) NSString *path;       // for what was open to be opened again
@end

@implementation UDSQLNode

+ (instancetype)nodeOfKind:(UDSQLNodeKind)kind title:(NSString *)title object:(id)object {
    UDSQLNode *node = [[self alloc] init];
    node.kind = kind;
    node.title = title;
    node.object = object;
    node.children = @[];
    return node;
}

- (void)setChildren:(NSArray<UDSQLNode *> *)children {
    _children = [children copy];
    for (UDSQLNode *child in _children) child.parent = self;
}

- (NSString *)path {
    UDSQLNode *parent = _parent;
    return parent ? [NSString stringWithFormat:@"%@/%@", parent.path, _title] : _title;
}

@end

@interface UDSQLNavigatorViewController ()
@property (nonatomic, weak) IBOutlet NSOutlineView *outlineView;
@property (nonatomic, strong) IBOutlet NSMenu *databaseMenu;
@property (nonatomic, strong) IBOutlet NSMenu *tableMenu;
@property (nonatomic, strong) IBOutlet NSMenu *editorMenu;
@end

@implementation UDSQLNavigatorViewController {
    __weak UDSQLDatabases *_databases;
    NSArray<UDSQLNode *> *_roots;
    UDSQLNode *_menuNode;           // what the context menu is about
}

- (instancetype)initWithDatabases:(UDSQLDatabases *)databases {
    self = [super initWithNibName:@"UDSQLNavigator" bundle:[NSBundle bundleForClass:[UDSQLNavigatorViewController class]]];
    if (self) {
        _databases = databases;
        _roots = @[];
        self.title = @"Databases";
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
    _outlineView.frame = _outlineView.enclosingScrollView.contentView.bounds;
    [_outlineView sizeLastColumnToFit];
    [self _reload];
}

- (void)_databasesDidChange:(NSNotification *)note {
    if (self.isViewLoaded) [self _reload];
}

// ---------------------------------------------------------------------------
// MARK: - The rows
// ---------------------------------------------------------------------------

static NSString *UDColumnBadge(UDSQLColumnInfo *column, UDSQLTable *table) {
    NSMutableArray *parts = [NSMutableArray arrayWithObject:column.type.length ? column.type : @"?"];
    if (column.primaryKey) [parts addObject:@"PK"];
    for (UDSQLForeignKey *key in table.foreignKeys) {
        if ([key.columns containsObject:column.name]) [parts addObject:@"FK"];
    }
    if (!column.nullable && !column.primaryKey) [parts addObject:@"NOT NULL"];
    return [parts componentsJoinedByString:@" · "];
}

- (UDSQLNode *)_nodeOfTable:(UDSQLTable *)table {
    NSString *title = table.schema.length && ![table.schema isEqualToString:@"public"]
        ? [NSString stringWithFormat:@"%@.%@", table.schema, table.name] : table.name;
    UDSQLNode *node = [UDSQLNode nodeOfKind:UDSQLNodeTable title:title object:table];
    // a Core Data store's: its entities
    if (table.entities.count) node.badge = [table.entities componentsJoinedByString:@", "];
    NSMutableArray *children = [NSMutableArray array];
    for (UDSQLColumnInfo *column in table.columns) {
        UDSQLNode *child = [UDSQLNode nodeOfKind:UDSQLNodeColumn title:column.name object:column];
        child.badge = UDColumnBadge(column, table);
        child.toolTip = column.coreDataMeaning ?: (column.defaultValue ? [NSString stringWithFormat:@"Default: %@", column.defaultValue] : nil);
        [children addObject:child];
    }
    for (UDSQLIndex *index in table.indexes) {
        UDSQLNode *child = [UDSQLNode nodeOfKind:UDSQLNodeIndex title:index.name object:index];
        child.badge = [NSString stringWithFormat:@"%@(%@)", index.unique ? @"unique " : @"", [index.columns componentsJoinedByString:@", "]];
        [children addObject:child];
    }
    for (UDSQLForeignKey *key in table.foreignKeys) {
        NSString *title = [NSString stringWithFormat:@"%@ → %@", [key.columns componentsJoinedByString:@", "], key.referencedTable];
        UDSQLNode *child = [UDSQLNode nodeOfKind:UDSQLNodeForeignKey title:title object:key];
        child.badge = [NSString stringWithFormat:@"(%@)", [key.referencedColumns componentsJoinedByString:@", "]];
        [children addObject:child];
    }
    node.children = children;
    return node;
}

- (NSArray<UDSQLNode *> *)_childrenOf:(UDSQLDatabase *)database {
    if (database.connecting) return @[ [UDSQLNode nodeOfKind:UDSQLNodeNote title:@"Connecting…" object:nil] ];
    if (database.error) {
        UDSQLNode *note = [UDSQLNode nodeOfKind:UDSQLNodeNote title:database.error.localizedDescription object:nil];
        note.toolTip = database.error.localizedDescription;
        return @[ note ];
    }
    UDSQLSchema *schema = database.schema;
    if (!schema) return @[];
    NSMutableArray *groups = [NSMutableArray array];
    if (schema.coreDataStore) {
        // the store's metadata: its identity, and the model's
        UDSQLNode *store = [UDSQLNode nodeOfKind:UDSQLNodeGroup title:@"Core Data Store" object:nil];
        store.badge = [NSString stringWithFormat:@"%lu entities", (unsigned long)schema.coreDataEntities.count];
        NSMutableArray *notes = [NSMutableArray array];
        for (NSString *key in @[ @"NSStoreType", @"NSStoreUUID", @"NSPersistenceFrameworkVersion", @"NSStoreModelVersionIdentifiers" ]) {
            id value = schema.coreDataMetadata[key];
            if (!value) continue;
            if ([value isKindOfClass:[NSArray class]]) value = [value componentsJoinedByString:@", "];
            UDSQLNode *note = [UDSQLNode nodeOfKind:UDSQLNodeNote title:[key stringByReplacingOccurrencesOfString:@"NS" withString:@""] object:nil];
            note.badge = [value description];
            [notes addObject:note];
        }
        store.children = notes;
        [groups addObject:store];
    }
    NSMutableArray *tables = [NSMutableArray array], *views = [NSMutableArray array];
    for (UDSQLTable *table in schema.tables) [table.view ? views : tables addObject:[self _nodeOfTable:table]];
    for (NSArray *group in @[ @[ @"Tables", tables ], @[ @"Views", views ] ]) {
        if (![group[1] count]) continue;
        UDSQLNode *node = [UDSQLNode nodeOfKind:UDSQLNodeGroup title:group[0] object:nil];
        node.badge = [NSString stringWithFormat:@"%lu", (unsigned long)[group[1] count]];
        node.children = group[1];
        [groups addObject:node];
    }
    return groups;
}

- (void)_reload {
    UDSQLDatabases *databases = _databases;
    // what was open, opened again
    NSMutableSet<NSString *> *open = [NSMutableSet set];
    for (NSInteger row = 0; row < _outlineView.numberOfRows; row++) {
        UDSQLNode *node = [_outlineView itemAtRow:row];
        if ([_outlineView isItemExpanded:node]) [open addObject:node.path];
    }
    NSString *selected = _outlineView.selectedRow >= 0 ? [[_outlineView itemAtRow:_outlineView.selectedRow] path] : nil;
    NSMutableArray *roots = [NSMutableArray array];
    for (UDSQLDatabase *database in databases.databases) {
        UDSQLNode *node = [UDSQLNode nodeOfKind:UDSQLNodeDatabase title:database.name object:database];
        node.badge = database.runner.connection.serverDescription.length ? database.runner.connection.serverDescription
                   : database.dialect == UDSQLDialectSQLite ? @"SQLite" : database.dialect == UDSQLDialectPostgreSQL ? @"PostgreSQL" : @"MySQL";
        node.toolTip = database.URL.isFileURL ? database.URL.path : database.URL.absoluteString;
        node.children = [self _childrenOf:database];
        [roots addObject:node];
    }
    _roots = roots;
    [_outlineView reloadData];
    for (NSInteger row = 0; row < _outlineView.numberOfRows; row++) {
        UDSQLNode *node = [_outlineView itemAtRow:row];
        // a database opened: what it holds, its groups too
        BOOL wasOpen = [open containsObject:node.path];
        BOOL connected = node.kind == UDSQLNodeDatabase && ([node.object isConnected] || [node.object error] || [node.object isConnecting]);
        BOOL group = node.kind == UDSQLNodeGroup && node.parent && [open containsObject:node.parent.path] && ![node.title isEqualToString:@"Core Data Store"];
        if (wasOpen || (connected && [open containsObject:node.path]) || group) [_outlineView expandItem:node];
        if (selected && [node.path isEqualToString:selected]) {
            [_outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
        }
    }
}

- (NSArray<NSString *> *)visibleTitles {
    NSMutableArray *titles = [NSMutableArray array];
    for (NSInteger row = 0; row < _outlineView.numberOfRows; row++) {
        UDSQLNode *node = [_outlineView itemAtRow:row];
        NSString *indent = [@"" stringByPaddingToLength:(NSUInteger)[_outlineView levelForRow:row] * 2 withString:@" " startingAtIndex:0];
        [titles addObject:[indent stringByAppendingString:node.title]];
    }
    return titles;
}

- (void)revealDatabase:(UDSQLDatabase *)database {
    (void)self.view;
    UDSQLDatabases *databases = _databases;
    [databases.workbench showNavigatorOfExtension:(id<UDExtension>)[self _plugin]];
    for (UDSQLNode *node in _roots) {
        if (node.object != database) continue;
        [_outlineView expandItem:node];
        NSInteger row = [_outlineView rowForItem:node];
        if (row >= 0) [_outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
    }
}

/// The SQL extension (its principal class's instance), the navigator's.
- (id)_plugin {
    for (id<UDExtension> extension in [UDLanguageModeRegistry sharedRegistry].extensions) {
        if ([extension isKindOfClass:NSClassFromString(@"UDSQLPlugin")]) return extension;
    }
    return nil;
}

// ---------------------------------------------------------------------------
// MARK: - The outline
// ---------------------------------------------------------------------------

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {
    return (NSInteger)(item ? [(UDSQLNode *)item children] : _roots).count;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item {
    return (item ? [item children] : _roots)[(NSUInteger)index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    UDSQLNode *node = item;
    return node.kind == UDSQLNodeDatabase || node.children.count > 0;
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)column byItem:(id)item {
    return [item title];
}

- (void)outlineView:(NSOutlineView *)outlineView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)column item:(id)item {
    UDSQLNode *node = item;
    if ([cell isKindOfClass:[UDBadgeTextFieldCell class]]) [(UDBadgeTextFieldCell *)cell setBadge:node.badge];
    BOOL bold = node.kind == UDSQLNodeDatabase || node.kind == UDSQLNodeGroup;
    [cell setFont:bold ? [NSFont boldSystemFontOfSize:[NSFont smallSystemFontSize]] : [NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
    BOOL dim = node.kind == UDSQLNodeNote && ![node.parent.title isEqualToString:@"Core Data Store"];
    [cell setTextColor:dim ? [NSColor disabledControlTextColor] : [NSColor controlTextColor]];
}

- (NSString *)outlineView:(NSOutlineView *)outlineView toolTipForCell:(NSCell *)cell rect:(NSRectPointer)rect
              tableColumn:(NSTableColumn *)column item:(id)item mouseLocation:(NSPoint)location {
    return [item toolTip];
}

- (void)outlineViewItemWillExpand:(NSNotification *)note {
    // a database opened: connected
    UDSQLNode *node = note.userInfo[@"NSObject"];
    UDSQLDatabase *database = node.kind == UDSQLNodeDatabase ? node.object : nil;
    UDSQLDatabases *databases = _databases;
    // connected once the outline is done expanding: its rows are made again then
    if (database && !database.connected && !database.connecting) {
        [databases performSelector:@selector(connect:) withObject:database afterDelay:0];
    }
}

- (nullable UDSQLNode *)_clickedNode {
    NSInteger row = _outlineView.clickedRow >= 0 ? _outlineView.clickedRow : _outlineView.selectedRow;
    return row >= 0 ? [_outlineView itemAtRow:row] : nil;
}

- (nullable UDSQLDatabase *)_databaseOf:(UDSQLNode *)node {
    while (node && node.kind != UDSQLNodeDatabase) node = node.parent;
    return node.object;
}

// ---------------------------------------------------------------------------
// MARK: - Menus: the clicked row's (its kind's, from the XIB)
// ---------------------------------------------------------------------------

- (void)menuNeedsUpdate:(NSMenu *)menu {
    if (menu != _outlineView.menu) return;
    [menu removeAllItems];
    NSInteger row = _outlineView.clickedRow;
    _menuNode = row >= 0 ? [_outlineView itemAtRow:row] : nil;
    NSMenu *source = _menuNode.kind == UDSQLNodeTable ? _tableMenu : _menuNode ? _databaseMenu : nil;
    for (NSMenuItem *item in source.itemArray) [menu addItem:[item copy]];
}

- (UDSQLNode *)_actedOn:(id)sender {
    return [sender isKindOfClass:[NSMenuItem class]] && _menuNode ? _menuNode : [self _clickedNode];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    SEL action = item.action;
    UDSQLDatabases *databases = _databases;
    if (sel_isEqual(action, @selector(runStatement:)) || sel_isEqual(action, @selector(runAll:))) return [databases canRun];
    if (sel_isEqual(action, @selector(stopRunning:))) {
        UDSQLDatabase *database = databases.workbench.selectedDocument ? [databases databaseOfDocument:databases.workbench.selectedDocument] : nil;
        return database.runner.running;
    }
    if (sel_isEqual(action, @selector(disconnectDatabase:))) return [self _databaseOf:[self _actedOn:item]].connected;
    return YES;
}

- (NSArray<NSMenuItem *> *)editorMenuItems {
    (void)self.view;
    NSMutableArray *items = [NSMutableArray array];
    for (NSMenuItem *item in _editorMenu.itemArray) [items addObject:[item copy]];
    return items;
}

- (IBAction)runStatement:(id)sender {
    [_databases runStatement:sender];
}

- (IBAction)runAll:(id)sender {
    [_databases runAll:sender];
}

- (IBAction)stopRunning:(id)sender {
    [_databases stopRunning:sender];
}

// ---------------------------------------------------------------------------
// MARK: - What the rows do
// ---------------------------------------------------------------------------

- (void)_editDatabase:(nullable UDSQLDatabase *)database dialect:(UDSQLDialect)dialect {
    UDSQLDatabases *databases = _databases;
    [UDSQLSheets editDatabase:database dialect:dialect inProject:databases.workbench.project != nil
                       window:self.view.window target:self action:@selector(_didEditDatabase:)];
}

- (void)_didEditDatabase:(id)database {
    if (![database isKindOfClass:[UDSQLDatabase class]]) return;
    UDSQLDatabases *databases = _databases;
    [databases disconnect:database];
    [databases addDatabase:database];
    [self revealDatabase:database];
    [databases connect:database];
}

- (IBAction)addSQLiteDatabase:(id)sender {
    [self _editDatabase:nil dialect:UDSQLDialectSQLite];
}

- (IBAction)addPostgreSQLDatabase:(id)sender {
    [self _editDatabase:nil dialect:UDSQLDialectPostgreSQL];
}

- (IBAction)addMySQLDatabase:(id)sender {
    [self _editDatabase:nil dialect:UDSQLDialectMySQL];
}

- (IBAction)editDatabase:(id)sender {
    UDSQLDatabase *database = [self _databaseOf:[self _actedOn:sender]];
    if (database) [self _editDatabase:database dialect:database.dialect];
}

- (IBAction)removeDatabase:(id)sender {
    UDSQLDatabase *database = [self _databaseOf:[self _actedOn:sender]];
    if (!database) return;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"Remove the connection “%@”?", database.name];
    alert.informativeText = @"The database itself is left as it is.";
    [alert addButtonWithTitle:@"Remove"];
    [alert addButtonWithTitle:@"Cancel"];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    [_databases removeDatabase:database];
}

- (IBAction)refreshDatabase:(id)sender {
    UDSQLDatabase *database = [self _databaseOf:[self _actedOn:sender]];
    if (database) [_databases refresh:database];
}

- (IBAction)disconnectDatabase:(id)sender {
    UDSQLDatabase *database = [self _databaseOf:[self _actedOn:sender]];
    if (database) [_databases disconnect:database];
}

- (IBAction)newQuery:(id)sender {
    UDSQLNode *node = [self _actedOn:sender];
    UDSQLDatabase *database = [self _databaseOf:node];
    if (!database) return;
    NSString *text = @"";
    if (node.kind == UDSQLNodeTable) {
        text = [NSString stringWithFormat:@"SELECT *\nFROM %@\nWHERE ", [node.object qualifiedNameFor:(id)[self _quoter:database]]];
    }
    [_databases openQuery:text database:database run:NO];
}

/// What quotes @a database's identifiers: its connection, or one standing in
/// for its dialect.
- (id)_quoter:(UDSQLDatabase *)database {
    return database.runner.connection ?: [[UDSQLConnection alloc] init];
}

- (IBAction)selectRows:(id)sender {
    UDSQLNode *node = [self _actedOn:sender];
    if (node.kind != UDSQLNodeTable) return;
    UDSQLDatabase *database = [self _databaseOf:node];
    NSString *name = [node.object qualifiedNameFor:[self _quoter:database]];
    [_databases openQuery:[NSString stringWithFormat:@"SELECT * FROM %@ LIMIT 100", name] database:database run:YES];
}

- (IBAction)copyName:(id)sender {
    UDSQLNode *node = [self _actedOn:sender];
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard declareTypes:@[ NSPasteboardTypeString ] owner:nil];
    [pasteboard setString:node.kind == UDSQLNodeTable ? [node.object name] : node.title forType:NSPasteboardTypeString];
}

- (IBAction)openItem:(id)sender {
    UDSQLNode *node = [self _clickedNode];
    if (node.kind == UDSQLNodeTable) [self selectRows:nil];
    else if (node.kind == UDSQLNodeDatabase) {
        if ([_outlineView isItemExpanded:node]) [_outlineView collapseItem:node];
        else [_outlineView expandItem:node];
    }
}

@end
