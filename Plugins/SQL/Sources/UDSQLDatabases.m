/*---------------------------------------------------------------------------------------------
 *  UDSQLDatabases.m
 *--------------------------------------------------------------------------------------------*/

#import "UDSQLDatabases.h"
#import "UDSQLText.h"
#import "UDSQLNavigatorViewController.h"
#import "UDSQLResultsViewController.h"
#import "UDSQLExampleFile.h"
#import "UDSQLSheets.h"

NSNotificationName const UDSQLDatabasesDidChangeNotification = @"UDSQLDatabasesDidChange";
NSNotificationName const UDSQLDocumentDatabaseDidChangeNotification = @"UDSQLDocumentDatabaseDidChange";

/// The project's settings key, and the user's defaults key, of the connections.
static NSString *const UDSQLSettingsKey = @"databases";
static NSString *const UDSQLDefaultsKey = @"UDSQLDatabases";
/// Each saved document's database, by its path.
static NSString *const UDSQLDocumentsDefaultsKey = @"UDSQLDocumentDatabases";
/// The rows a result keeps.
static const NSUInteger UDSQLMaxRows = 1000;

@implementation UDSQLDatabase

- (UDSQLDialect)dialect {
    NSInteger dialect = [UDSQLConnection dialectOfURL:_URL];
    return dialect < 0 ? UDSQLDialectSQLite : (UDSQLDialect)dialect;
}

- (BOOL)isConnected {
    return _schema != nil;
}

- (NSDictionary *)plist {
    return @{ @"name": _name, @"url": _URL.absoluteString };
}

@end

/// A request to a database's runner: its reply handed to the window's
/// databases with what it was for (the runner holds its target weakly, so
/// the window keeps it till the reply that finishes it).
@interface UDSQLCall : NSObject
@property (nonatomic, weak) UDSQLDatabases *owner;
@property (nonatomic, strong) UDSQLDatabase *database;
@property (nonatomic, strong, nullable) NSDictionary *context;
@property (nonatomic) SEL forward;
@end

@implementation UDSQLCall

- (void)reply:(id)value {
    UDSQLDatabases *owner = _owner;
    if (owner) ((void (*)(id, SEL, id, id))[owner methodForSelector:_forward])(owner, _forward, self, value);
}

@end

@implementation UDSQLDatabases {
    NSMutableSet<UDSQLCall *> *_calls;
    NSMutableArray<UDSQLDatabase *> *_databases;
    NSMapTable<UDCodeDocument *, UDSQLResultsViewController *> *_results;
    NSMapTable<UDCodeDocument *, NSString *> *_documentDatabases;     // untitled documents'
    NSMapTable<UDCodeDocument *, NSDictionary *> *_parameterValues;   // the last given, a document's
    NSMapTable<NSString *, UDCodeDocument *> *_browsed;   // by database, table and entity: what browses it
    NSHashTable<UDCodeDocument *> *_runWhenShown;          // browsed: run once their editors have their database
}

- (instancetype)initWithWorkbench:(id<UDWorkbench>)workbench {
    self = [super init];
    if (self) {
        _workbench = workbench;
        _databases = [NSMutableArray array];
        _results = [NSMapTable weakToStrongObjectsMapTable];
        _documentDatabases = [NSMapTable weakToStrongObjectsMapTable];
        _parameterValues = [NSMapTable weakToStrongObjectsMapTable];
        _runWhenShown = [NSHashTable weakObjectsHashTable];
        _calls = [NSMutableSet set];
        [self _load];
        _navigator = [[UDSQLNavigatorViewController alloc] initWithDatabases:self];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_documentSaved:)
                                                     name:UDCodeDocumentFileURLDidChangeNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_selectionDidChange:)
                                                     name:UDWorkbenchSelectionDidChangeNotification object:nil];
    }
    return self;
}

/// An untitled document saved as a file: its database kept for the file.
- (void)_documentSaved:(NSNotification *)note {
    UDCodeDocument *document = note.object;
    NSString *name = [_documentDatabases objectForKey:document];
    UDSQLDatabase *database = name ? [self databaseNamed:name] : nil;
    if (database) [self setDatabase:database ofDocument:document];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    for (UDSQLDatabase *database in _databases) [database.runner close];
}

- (NSArray<UDSQLDatabase *> *)databases {
    return [_databases copy];
}

- (UDSQLDatabase *)databaseNamed:(NSString *)name {
    for (UDSQLDatabase *database in _databases) {
        if ([database.name isEqualToString:name]) return database;
    }
    return nil;
}

- (void)_changed {
    [[NSNotificationCenter defaultCenter] postNotificationName:UDSQLDatabasesDidChangeNotification object:self];
}

// ---------------------------------------------------------------------------
// MARK: - Kept: the project's settings, the user's defaults
// ---------------------------------------------------------------------------

- (void)_load {
    UDProject *project = _workbench.project;
    NSArray *fromProject = [project.settings[UDSQLSettingsKey] isKindOfClass:[NSArray class]] ? project.settings[UDSQLSettingsKey] : @[];
    NSArray *fromUser = [[NSUserDefaults standardUserDefaults] arrayForKey:UDSQLDefaultsKey] ?: @[];
    for (NSArray *list in @[ fromProject, fromUser ]) {
        for (NSDictionary *entry in list) {
            if (![entry isKindOfClass:[NSDictionary class]]) continue;
            NSString *name = entry[@"name"], *address = entry[@"url"];
            NSURL *url = [address isKindOfClass:[NSString class]] ? [NSURL URLWithString:address] : nil;
            if (![name isKindOfClass:[NSString class]] || !url || [self databaseNamed:name]) continue;
            UDSQLDatabase *database = [[UDSQLDatabase alloc] init];
            database.name = name;
            database.URL = url;
            database.inProject = list == fromProject;
            [_databases addObject:database];
        }
    }
}

- (void)_save {
    NSMutableArray *project = [NSMutableArray array], *user = [NSMutableArray array];
    for (UDSQLDatabase *database in _databases) [database.inProject ? project : user addObject:[database plist]];
    [[NSUserDefaults standardUserDefaults] setObject:user forKey:UDSQLDefaultsKey];
    UDProject *folder = _workbench.project;
    if (folder) {
        NSMutableDictionary *settings = [folder.settings mutableCopy] ?: [NSMutableDictionary dictionary];
        NSArray *before = settings[UDSQLSettingsKey];
        if (project.count) settings[UDSQLSettingsKey] = project;
        else [settings removeObjectForKey:UDSQLSettingsKey];
        if (![before isEqual:settings[UDSQLSettingsKey]] && (before || project.count)) {
            NSError *error = nil;
            if (![folder setSettings:settings error:&error]) NSLog(@"UDSQLDatabases: the project's settings weren't written: %@", error);
        }
    }
}

- (void)addDatabase:(UDSQLDatabase *)database {
    UDSQLDatabase *before = [self databaseNamed:database.name];
    if (before && before != database) {
        [before.runner close];
        [_databases replaceObjectAtIndex:[_databases indexOfObjectIdenticalTo:before] withObject:database];
    } else if (!before) {
        [_databases addObject:database];
    }
    if (!database.inProject && !_workbench.project) database.inProject = NO;
    [self _save];
    [self _changed];
}

- (void)removeDatabase:(UDSQLDatabase *)database {
    [database.runner close];
    [_databases removeObjectIdenticalTo:database];
    // its password forgotten, unless another connection is to the same
    BOOL shared = NO;
    for (UDSQLDatabase *other in _databases) {
        if ([[UDSQLPasswords accountOfURL:other.URL] isEqualToString:[UDSQLPasswords accountOfURL:database.URL]]) shared = YES;
    }
    if (!shared && database.dialect != UDSQLDialectSQLite) [UDSQLPasswords forgetPasswordOfURL:database.URL];
    [self _save];
    [self _changed];
}

// ---------------------------------------------------------------------------
// MARK: - Connecting: a password asked for when the server wants one
// ---------------------------------------------------------------------------

- (UDSQLRunner *)_runnerOf:(UDSQLDatabase *)database {
    if (!database.runner) {
        database.runner = [[UDSQLRunner alloc] initWithURL:database.URL password:[UDSQLPasswords passwordOfURL:database.URL]];
    }
    return database.runner;
}

- (UDSQLCall *)_callFor:(UDSQLDatabase *)database context:(NSDictionary *)context forward:(SEL)forward {
    UDSQLCall *call = [[UDSQLCall alloc] init];
    call.owner = self;
    call.database = database;
    call.context = context;
    call.forward = forward;
    [_calls addObject:call];
    return call;
}

/// Whether @a error is a server's asking for a password (or refusing one).
static BOOL UDWantsPassword(NSError *error) {
    NSString *state = error.userInfo[UDSQLStateErrorKey];
    if ([state hasPrefix:@"28"]) return YES;
    NSString *message = error.localizedDescription.lowercaseString;
    return [message containsString:@"password"] || [message containsString:@"authentication"] || [message containsString:@"access denied"];
}

/// Asks for @a database's password after @a error; YES when one was given
/// (its runner then made again, with it).
- (BOOL)_askPasswordOf:(UDSQLDatabase *)database after:(NSError *)error {
    if (database.dialect == UDSQLDialectSQLite || !UDWantsPassword(error)) return NO;
    // asked again: a kept password that failed, forgotten for the session
    BOOL keep = [UDSQLPasswords isKeptForURL:database.URL] || [UDSQLPasswords passwordOfURL:database.URL] == nil;
    NSString *password = [UDSQLSheets askPasswordOfDatabase:database.name message:error.localizedDescription keep:&keep
                                                     window:_workbench.window];
    if (!password) return NO;
    NSError *failure = [UDSQLPasswords rememberPassword:password ofURL:database.URL keep:keep];
    if (failure) NSLog(@"%@", failure.localizedDescription);
    [database.runner close];
    database.runner = nil;
    return YES;
}

- (void)connect:(UDSQLDatabase *)database {
    if (database.connecting) return;
    database.connecting = YES;
    database.error = nil;
    [self _changed];
    UDSQLCall *call = [self _callFor:database context:nil forward:@selector(_call:readSchema:)];
    [[self _runnerOf:database] readSchemaWithTarget:call action:@selector(reply:)];
}

- (void)connectIfWanted:(UDSQLDatabase *)database {
    if (!database.connected && !database.connecting && !database.error) [self connect:database];
}

- (void)refresh:(UDSQLDatabase *)database {
    database.schema = nil;
    [self connect:database];
}

- (void)_call:(UDSQLCall *)call readSchema:(id)value {
    [_calls removeObject:call];
    UDSQLDatabase *database = call.database;
    database.connecting = NO;
    if ([value isKindOfClass:[UDSQLSchema class]]) {
        database.schema = value;
        database.error = nil;
    } else {
        NSError *error = [value isKindOfClass:[NSError class]] ? value : nil;
        if ([self _askPasswordOf:database after:error]) {
            [self connect:database];
            return;
        }
        database.error = error;
    }
    [self _changed];
}

- (void)disconnect:(UDSQLDatabase *)database {
    [database.runner close];
    database.runner = nil;
    database.schema = nil;
    database.error = nil;
    [self _changed];
}

// ---------------------------------------------------------------------------
// MARK: - A document's database
// ---------------------------------------------------------------------------

- (UDSQLDatabase *)databaseOfDocument:(UDCodeDocument *)document {
    NSString *name = [_documentDatabases objectForKey:document];
    NSString *path = document.fileURL.path;
    if (!name && path) name = [[NSUserDefaults standardUserDefaults] dictionaryForKey:UDSQLDocumentsDefaultsKey][path];
    UDSQLDatabase *database = name ? [self databaseNamed:name] : nil;
    if (!database && _databases.count == 1) database = _databases.firstObject;
    return database;
}

- (void)setDatabase:(UDSQLDatabase *)database ofDocument:(UDCodeDocument *)document {
    if (database) [_documentDatabases setObject:database.name forKey:document];
    else [_documentDatabases removeObjectForKey:document];
    NSString *path = document.fileURL.path;
    if (path) {
        NSMutableDictionary *saved = [[[NSUserDefaults standardUserDefaults] dictionaryForKey:UDSQLDocumentsDefaultsKey] mutableCopy]
                                     ?: [NSMutableDictionary dictionary];
        if (database) saved[path] = database.name;
        else [saved removeObjectForKey:path];
        [[NSUserDefaults standardUserDefaults] setObject:saved forKey:UDSQLDocumentsDefaultsKey];
    }
    [[_results objectForKey:document] reloadDatabases];
    [[NSNotificationCenter defaultCenter] postNotificationName:UDSQLDocumentDatabaseDidChangeNotification object:document];
}

- (void)browseTable:(UDSQLTable *)table entity:(NSNumber *)entity database:(UDSQLDatabase *)database {
    // the one browsing it still open, untitled: shown again
    if (!_browsed) _browsed = [NSMapTable strongToWeakObjectsMapTable];
    NSString *key = [@[ database.name, table.schema ?: @"", table.name, entity ?: @"" ] componentsJoinedByString:@"\t"];
    UDCodeDocument *open = [_browsed objectForKey:key];
    id<UDWorkbench> workbench = _workbench;
    if (open && !open.fileURL && [workbench showDocument:open]) return;
    UDSQLExampleFileSkeleton *skeleton = [UDSQLExampleFileSkeleton skeletonOfTable:table.name schema:table.schema];
    UDSQLSchema *schema = database.schema;
    if (entity && schema.coreDataStore) {
        // an entity's rows: its own and its subentities', by Z_ENT
        NSMutableArray *entities = [NSMutableArray arrayWithObject:entity];
        for (NSUInteger i = 0; i < entities.count; i++) [entities addObjectsFromArray:[schema coreDataSubentitiesOf:entities[i]]];
        skeleton.rows = @[ [UDSQLExampleRow rowWithEntries:@{ @"Z_ENT": [[entities valueForKey:@"stringValue"] componentsJoinedByString:@", "] }] ];
    }
    NSString *name = entity ? schema.coreDataEntities[entity] ?: table.name : table.name;
    UDCodeDocument *document = [self _openExampleQuery:skeleton database:database name:name];
    if (!document) return;
    [_browsed setObject:document forKey:key];
    [_runWhenShown addObject:document];
    [self setDatabase:database ofDocument:document];
}

- (void)newExampleQueryOfDatabase:(UDSQLDatabase *)database table:(UDSQLTable *)table {
    UDSQLExampleFileSkeleton *skeleton = table ? [UDSQLExampleFileSkeleton skeletonOfTable:table.name schema:table.schema] : nil;
    UDCodeDocument *document = [self _openExampleQuery:skeleton database:database name:table.name];
    // asked of the database it was made from
    if (document) [self setDatabase:database ofDocument:document];
}

/// An untitled query by example of @a skeleton's table (none: of nothing
/// yet), named @a name, opened in its editor.
- (nullable UDCodeDocument *)_openExampleQuery:(nullable UDSQLExampleFileSkeleton *)skeleton database:(UDSQLDatabase *)database
                                          name:(nullable NSString *)name {
    UDSQLExampleFile *file = [[UDSQLExampleFile alloc] init];
    if (skeleton) file.skeletons = @[ skeleton ];
    id<UDWorkbench> workbench = _workbench;
    [workbench openUntitledDocumentWithText:[[NSString alloc] initWithData:[file data] encoding:NSUTF8StringEncoding]
                               languageMode:@"qbe" name:name];
    return workbench.selectedDocument;
}

- (BOOL)takeRunWhenShown:(UDCodeDocument *)document {
    if (![_runWhenShown containsObject:document]) return NO;
    [_runWhenShown removeObject:document];
    return YES;
}

- (void)openQuery:(NSString *)text database:(UDSQLDatabase *)database run:(BOOL)run {
    id<UDWorkbench> workbench = _workbench;
    [workbench openUntitledDocumentWithText:text languageMode:@"sql"];
    UDCodeDocument *document = workbench.selectedDocument;
    if (!document) return;
    [self setDatabase:database ofDocument:document];
    UDCodeEditorViewController *editor = workbench.selectedEditor;
    [editor.textView setSelectedRange:NSMakeRange(0, 0)];
    [self _showResultsOf:document inEditor:editor];
    if (run) [self _runInEditor:editor document:document all:YES];
}

// ---------------------------------------------------------------------------
// MARK: - Running
// ---------------------------------------------------------------------------

- (BOOL)canRun {
    id<UDWorkbench> workbench = _workbench;
    UDCodeDocument *document = workbench.selectedDocument;
    UDCodeEditorViewController *editor = workbench.selectedEditor;
    if (![document.languageMode.identifier isEqualToString:@"sql"] || !editor) return NO;
    // the editor's (its text) or its results in front: not a field elsewhere
    NSResponder *responder = workbench.window.firstResponder;
    if (![responder isKindOfClass:[NSView class]]) return NO;
    UDSQLResultsViewController *results = [_results objectForKey:document];
    return [(NSView *)responder isDescendantOf:editor.view] || (results.isViewLoaded && [(NSView *)responder isDescendantOf:results.view]);
}

- (UDSQLResultsViewController *)resultsOfDocument:(UDCodeDocument *)document {
    return [_results objectForKey:document];
}

/// @a document's results, in the bottom area's Results (beside the
/// debugger and the terminal), not on top of it under the editor.
- (UDSQLResultsViewController *)_showResultsOf:(UDCodeDocument *)document inEditor:(UDCodeEditorViewController *)editor {
    UDSQLResultsViewController *results = [_results objectForKey:document];
    if (!results) {
        results = [[UDSQLResultsViewController alloc] initWithDatabases:self document:document];
        [_results setObject:results forKey:document];
    }
    id<UDExtension> extension = _extension;
    id<UDWorkbench> workbench = _workbench;
    if (extension) [workbench showBottomAreaViewController:results title:@"Results" extension:extension];
    return results;
}

/// Another tab chosen: Results, in front, shows its document's (a SQL
/// document's that has some).
- (void)_selectionDidChange:(NSNotification *)note {
    id<UDWorkbench> workbench = _workbench;
    id<UDExtension> extension = _extension;
    if (note.object != workbench || !extension || ![workbench isBottomAreaShowingExtension:extension]) return;
    UDSQLResultsViewController *results = [_results objectForKey:workbench.selectedDocument];
    if (results && [workbench bottomAreaViewControllerOfExtension:extension] != results) {
        [workbench showBottomAreaViewController:results title:@"Results" extension:extension];
    }
}

- (IBAction)runStatement:(id)sender {
    id<UDWorkbench> workbench = _workbench;
    if (workbench.selectedDocument && workbench.selectedEditor) {
        [self _runInEditor:workbench.selectedEditor document:workbench.selectedDocument all:NO];
    }
}

- (IBAction)runAll:(id)sender {
    id<UDWorkbench> workbench = _workbench;
    if (workbench.selectedDocument && workbench.selectedEditor) {
        [self _runInEditor:workbench.selectedEditor document:workbench.selectedDocument all:YES];
    }
}

- (IBAction)stopRunning:(id)sender {
    UDSQLDatabase *database = [self databaseOfDocument:_workbench.selectedDocument];
    [database.runner stop];
}

- (void)_runInEditor:(UDCodeEditorViewController *)editor document:(UDCodeDocument *)document all:(BOOL)all {
    if (![document.languageMode.identifier isEqualToString:@"sql"]) return;
    UDSQLResultsViewController *results = [self _showResultsOf:document inEditor:editor];
    UDSQLDatabase *database = [self databaseOfDocument:document];
    if (!database) {
        [results showMessage:@"Choose the database to run against (above), or add one in the Databases navigator." error:NO];
        return;
    }
    if (database.runner.running) {
        [results showMessage:@"Still running the statements before: wait, or Stop them." error:NO];
        return;
    }
    NSString *text = editor.textView.string;
    NSRange selection = editor.textView.selectedRange;
    NSMutableArray<NSString *> *statements = [NSMutableArray array];
    if (all || selection.length) {
        NSRange scope = all ? NSMakeRange(0, text.length) : selection;
        NSString *part = [text substringWithRange:scope];
        for (NSValue *range in [UDSQLText statementRangesOfText:part dialect:database.dialect]) {
            [statements addObject:[part substringWithRange:range.rangeValue]];
        }
    } else {
        NSRange range = [UDSQLText statementRangeAtIndex:selection.location ofText:text dialect:database.dialect];
        if (range.location != NSNotFound) {
            [statements addObject:[text substringWithRange:range]];
            // where it is shown (AppKit's; GNUstep has none)
            SEL indicate = NSSelectorFromString(@"showFindIndicatorForRange:");
            if ([editor.textView respondsToSelector:indicate]) {
                ((void (*)(id, SEL, NSRange))[editor.textView methodForSelector:indicate])(editor.textView, indicate, range);
            }
        }
    }
    if (!statements.count) {
        [results showMessage:all ? @"There is no statement to run." : @"There is no statement at the caret." error:NO];
        return;
    }
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (NSString *statement in statements) {
        for (NSString *name in [UDSQLText parametersOfStatement:statement dialect:database.dialect]) {
            if (![names containsObject:name]) [names addObject:name];
        }
    }
    NSDictionary *context = @{ @"statements": statements, @"database": database, @"document": document, @"results": results };
    if (!names.count) {
        [self _run:context values:@{}];
        return;
    }
    // parameters: their values asked for (the last given, offered again)
    [UDSQLSheets askValuesOfParameters:names previous:[_parameterValues objectForKey:document] ?: @{}
                                window:_workbench.window context:context target:self action:@selector(_didGetValues:)];
}

- (void)_didGetValues:(NSArray *)reply {
    // [values or NSNull (cancelled), context]
    NSDictionary *context = reply[1];
    if (![reply[0] isKindOfClass:[NSDictionary class]]) return;
    [_parameterValues setObject:reply[0] forKey:context[@"document"]];
    [self _run:context values:reply[0]];
}

- (void)_run:(NSDictionary *)context values:(NSDictionary *)values {
    UDSQLDatabase *database = context[@"database"];
    UDSQLResultsViewController *results = context[@"results"];
    NSMutableArray<UDSQLStatement *> *statements = [NSMutableArray array];
    for (NSString *text in context[@"statements"]) {
        NSArray<NSString *> *order = nil;
        NSString *sql = [UDSQLText statement:text convertedForDialect:database.dialect order:&order];
        NSMutableArray *parameters = [NSMutableArray array];
        for (NSString *name in order) [parameters addObject:values[name] ?: [NSNull null]];
        [statements addObject:[[UDSQLStatement alloc] initWithText:text SQL:sql parameters:parameters]];
    }
    [results beginRun:statements database:database];
    UDSQLCall *call = [self _callFor:database context:@{ @"context": context, @"values": values } forward:@selector(_call:ran:)];
    [[self _runnerOf:database] run:statements maxRows:UDSQLMaxRows target:call action:@selector(reply:)];
}

- (void)_call:(UDSQLCall *)call ran:(UDSQLRun *)run {
    UDSQLDatabase *database = call.database;
    UDSQLResultsViewController *results = call.context[@"context"][@"results"];
    if (run.finished) {
        [_calls removeObject:call];
        // refused for want of a password: asked, and run again
        if (run.error && !run.results.count && [self _askPasswordOf:database after:run.error]) {
            [self _run:call.context[@"context"] values:call.context[@"values"]];
            return;
        }
        // what changes the schema: read again
        for (UDSQLResult *result in run.results) {
            NSString *head = [result.statement stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            NSRange word = [head rangeOfString:@"^(--[^\n]*\n\\s*)*(CREATE|ALTER|DROP|RENAME)\\b"
                                       options:NSRegularExpressionSearch | NSCaseInsensitiveSearch];
            if (word.location != NSNotFound && database.connected) {
                [self refresh:database];
                break;
            }
        }
    }
    [results showRun:run];
}

// ---------------------------------------------------------------------------
// MARK: - A database file
// ---------------------------------------------------------------------------

- (void)openDatabaseFile:(NSURL *)url {
    url = url.URLByStandardizingPath;
    UDSQLDatabase *database = nil;
    for (UDSQLDatabase *known in _databases) {
        if ([known.URL isEqual:url]) database = known;
    }
    if (!database) {
        database = [[UDSQLDatabase alloc] init];
        NSString *name = url.lastPathComponent;
        for (NSUInteger n = 2; [self databaseNamed:name]; n++) name = [NSString stringWithFormat:@"%@ %lu", url.lastPathComponent, (unsigned long)n];
        database.name = name;
        database.URL = url;
        [self addDatabase:database];
    }
    [_navigator revealDatabase:database];
    if (!database.connected) [self connect:database];
}

@end
