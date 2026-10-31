/*---------------------------------------------------------------------------------------------
 *  UDSQLSheets.m
 *--------------------------------------------------------------------------------------------*/

#import "UDSQLSheets.h"
#import "UDSQLDatabases.h"
#import "UDSQLRunner.h"

static NSMutableDictionary<NSString *, NSString *> *UDPasswords(void) {
    static NSMutableDictionary *passwords;
    if (!passwords) passwords = [NSMutableDictionary dictionary];
    return passwords;
}

NSString *UDSQLPasswordOfURL(NSURL *url) {
    return UDPasswords()[url.absoluteString];
}

void UDSQLRememberPassword(NSURL *url, NSString *password) {
    if (password.length) UDPasswords()[url.absoluteString] = password;
    else [UDPasswords() removeObjectForKey:url.absoluteString];
}

/// The sheets up: each kept till it ends.
static NSMutableSet *UDSheetsUp(void) {
    static NSMutableSet *up;
    if (!up) up = [NSMutableSet set];
    return up;
}

@interface UDSQLSheets ()
// the password's accessory
@property (nonatomic, strong) IBOutlet NSSecureTextField *passwordField;
// the parameters' sheet
@property (nonatomic, strong) IBOutlet NSPanel *parametersPanel;
@property (nonatomic, strong) IBOutlet NSTableView *parametersTable;
// the connection's sheet
@property (nonatomic, strong) IBOutlet NSPanel *connectionPanel;
@property (nonatomic, strong) IBOutlet NSPopUpButton *kindButton;
@property (nonatomic, strong) IBOutlet NSTextField *nameField;
@property (nonatomic, strong) IBOutlet NSView *fileBox;
@property (nonatomic, strong) IBOutlet NSTextField *fileField;
@property (nonatomic, strong) IBOutlet NSView *serverBox;
@property (nonatomic, strong) IBOutlet NSTextField *hostField;
@property (nonatomic, strong) IBOutlet NSTextField *portField;
@property (nonatomic, strong) IBOutlet NSTextField *databaseField;
@property (nonatomic, strong) IBOutlet NSTextField *userField;
@property (nonatomic, strong) IBOutlet NSSecureTextField *serverPasswordField;
@property (nonatomic, strong) IBOutlet NSTextField *optionsField;
@property (nonatomic, strong) IBOutlet NSPopUpButton *keptButton;
@property (nonatomic, strong) IBOutlet NSTextField *testLabel;
@property (nonatomic, strong) IBOutlet NSButton *okButton;
@end

@implementation UDSQLSheets {
    // the parameters'
    NSArray<NSString *> *_names;
    NSMutableArray<NSString *> *_texts;
    NSMutableArray<NSNumber *> *_nulls;
    // what the sheet ends with, and to whom
    id _context;
    __weak id _target;
    SEL _action;
    UDSQLDatabase *_editing;
    UDSQLRunner *_tester;
}

+ (instancetype)_loaded {
    UDSQLSheets *sheets = [[self alloc] init];
    NSNib *nib = [[NSNib alloc] initWithNibNamed:@"UDSQLSheets" bundle:[NSBundle bundleForClass:self]];
    NSArray *objects = nil;     // held by the outlets
    if (![nib instantiateWithOwner:sheets topLevelObjects:&objects]) {
        NSLog(@"UDSQLSheets: could not load UDSQLSheets.xib");
        return nil;
    }
    return sheets;
}

- (void)_send:(id)value {
    id target = _target;
    if (target && _action) ((void (*)(id, SEL, id))[target methodForSelector:_action])(target, _action, value);
}

/// @a panel on @a window as a sheet, else as a window of its own.
- (void)_begin:(NSPanel *)panel window:(NSWindow *)window {
    [UDSheetsUp() addObject:self];
    if (window) {
        [NSApp beginSheet:panel modalForWindow:window modalDelegate:self didEndSelector:@selector(_sheetDidEnd:code:context:) contextInfo:NULL];
    } else {
        [panel center];
        [panel makeKeyAndOrderFront:nil];
    }
}

- (void)_end:(NSPanel *)panel {
    if (panel.sheetParent || [panel isSheet]) [NSApp endSheet:panel];
    [panel orderOut:nil];
    [UDSheetsUp() removeObject:self];
}

- (void)_sheetDidEnd:(NSWindow *)sheet code:(NSInteger)code context:(void *)context {
}

// ---------------------------------------------------------------------------
// MARK: - A password
// ---------------------------------------------------------------------------

+ (NSString *)askPasswordOfDatabase:(NSString *)name message:(NSString *)message window:(NSWindow *)window {
    UDSQLSheets *sheets = [self _loaded];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"The password of “%@”", name];
    alert.informativeText = [NSString stringWithFormat:@"%@\n\nIt is kept until UDCode quits, never written.", message];
    [alert addButtonWithTitle:@"Connect"];
    [alert addButtonWithTitle:@"Cancel"];
    alert.accessoryView = sheets.passwordField;
    [alert.window setInitialFirstResponder:sheets.passwordField];
    if ([alert runModal] != NSAlertFirstButtonReturn) return nil;
    return sheets.passwordField.stringValue;
}

// ---------------------------------------------------------------------------
// MARK: - Parameters
// ---------------------------------------------------------------------------

+ (id)valueOfText:(NSString *)text {
    NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (trimmed.length >= 2 && [trimmed hasPrefix:@"'"] && [trimmed hasSuffix:@"'"]) {
        return [[trimmed substringWithRange:NSMakeRange(1, trimmed.length - 2)] stringByReplacingOccurrencesOfString:@"''" withString:@"'"];
    }
    NSScanner *scanner = [NSScanner scannerWithString:trimmed];
    long long integer = 0;
    if (trimmed.length && [scanner scanLongLong:&integer] && scanner.isAtEnd) return @(integer);
    scanner = [NSScanner scannerWithString:trimmed];
    double real = 0;
    if (trimmed.length && [scanner scanDouble:&real] && scanner.isAtEnd) return @(real);
    return text;
}

static NSString *UDTextOfValue(id value) {
    if (!value || value == [NSNull null]) return @"";
    if ([value isKindOfClass:[NSString class]]) {
        // text that would read as a number: quoted, so it stays text
        id read = [UDSQLSheets valueOfText:value];
        return [read isKindOfClass:[NSNumber class]] ? [NSString stringWithFormat:@"'%@'", value] : value;
    }
    return [value description];
}

+ (void)askValuesOfParameters:(NSArray<NSString *> *)names previous:(NSDictionary *)previous window:(NSWindow *)window
                      context:(id)context target:(id)target action:(SEL)action {
    UDSQLSheets *sheets = [self _loaded];
    sheets->_names = [names copy];
    sheets->_texts = [NSMutableArray array];
    sheets->_nulls = [NSMutableArray array];
    for (NSString *name in names) {
        id value = previous[name];
        [sheets->_texts addObject:UDTextOfValue(value)];
        [sheets->_nulls addObject:@(value == [NSNull null])];
    }
    sheets->_context = context;
    sheets->_target = target;
    sheets->_action = action;
    [sheets.parametersTable reloadData];
    // the first value to type, before the sheet is up (GNUstep's sheets are
    // modal: -_begin: returns once it is down)
    if (names.count) {
        [sheets.parametersTable selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
        [sheets.parametersPanel setInitialFirstResponder:sheets.parametersTable];
    }
    [sheets _begin:sheets.parametersPanel window:window];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)_names.count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    NSString *identifier = column.identifier;
    if ([identifier isEqualToString:@"name"]) return _names[(NSUInteger)row];
    if ([identifier isEqualToString:@"null"]) return _nulls[(NSUInteger)row];
    return _texts[(NSUInteger)row];
}

- (void)tableView:(NSTableView *)tableView setObjectValue:(id)value forTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    if ([column.identifier isEqualToString:@"null"]) _nulls[(NSUInteger)row] = @([value boolValue]);
    else if ([column.identifier isEqualToString:@"value"]) {
        _texts[(NSUInteger)row] = [value description] ?: @"";
        _nulls[(NSUInteger)row] = @NO;
    }
    [tableView reloadData];
}

- (IBAction)runWithParameters:(id)sender {
    [_parametersPanel makeFirstResponder:nil];          // the value typed, ended
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    for (NSUInteger i = 0; i < _names.count; i++) {
        values[_names[i]] = [_nulls[i] boolValue] ? [NSNull null] : [UDSQLSheets valueOfText:_texts[i]];
    }
    [self _end:_parametersPanel];
    [self _send:@[ values, _context ?: [NSNull null] ]];
}

- (IBAction)cancelParameters:(id)sender {
    [self _end:_parametersPanel];
    [self _send:@[ [NSNull null], _context ?: [NSNull null] ]];
}

// ---------------------------------------------------------------------------
// MARK: - A connection
// ---------------------------------------------------------------------------

+ (void)editDatabase:(UDSQLDatabase *)database dialect:(UDSQLDialect)dialect inProject:(BOOL)inProject
              window:(NSWindow *)window target:(id)target action:(SEL)action {
    UDSQLSheets *sheets = [self _loaded];
    sheets->_editing = database;
    sheets->_target = target;
    sheets->_action = action;
    [sheets.keptButton.lastItem setEnabled:inProject];
    [sheets.keptButton selectItemWithTag:inProject && (!database || database.inProject) ? 1 : 0];
    if (database) {
        [sheets _fillFrom:database];
        sheets.okButton.title = @"Save";
    } else {
        [sheets.kindButton selectItemWithTag:dialect];
    }
    [sheets kindChanged:nil];
    [sheets _begin:sheets.connectionPanel window:window];
}

- (void)_fillFrom:(UDSQLDatabase *)database {
    [_kindButton selectItemWithTag:database.dialect];
    _nameField.stringValue = database.name;
    NSURL *url = database.URL;
    if (database.dialect == UDSQLDialectSQLite) {
        _fileField.stringValue = url.path ?: @"";
        return;
    }
    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    _hostField.stringValue = components.host ?: @"";
    _portField.stringValue = components.port ? components.port.stringValue : @"";
    _databaseField.stringValue = [components.path stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]] ?: @"";
    _userField.stringValue = components.user.stringByRemovingPercentEncoding ?: @"";
    _optionsField.stringValue = components.query ?: @"";
    _serverPasswordField.stringValue = UDSQLPasswordOfURL(url) ?: @"";
}

- (UDSQLDialect)_dialect {
    return (UDSQLDialect)_kindButton.selectedTag;
}

- (IBAction)kindChanged:(id)sender {
    BOOL file = [self _dialect] == UDSQLDialectSQLite;
    [_fileBox setHidden:!file];
    [_serverBox setHidden:file];
    _testLabel.stringValue = @"";
    if (!file && !_portField.stringValue.length) {
        _portField.placeholderString = [self _dialect] == UDSQLDialectPostgreSQL ? @"5432" : @"3306";
    }
}

- (IBAction)chooseFile:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.message = @"A SQLite database (a Core Data store's .sqlite, say)";
    if ([panel runModal] != NSModalResponseOK) return;
    _fileField.stringValue = panel.URL.path;
    if (!_nameField.stringValue.length) _nameField.stringValue = panel.URL.lastPathComponent;
}

/// The connection's URL as the fields say; nil (and why, said) when they
/// say too little.
- (nullable NSURL *)_URL {
    if ([self _dialect] == UDSQLDialectSQLite) {
        NSString *path = [_fileField.stringValue stringByExpandingTildeInPath];
        if (!path.length) {
            _testLabel.stringValue = @"Choose the database's file.";
            return nil;
        }
        return [NSURL fileURLWithPath:path];
    }
    NSURLComponents *components = [[NSURLComponents alloc] init];
    components.scheme = [self _dialect] == UDSQLDialectPostgreSQL ? @"postgresql" : @"mysql";
    components.host = _hostField.stringValue.length ? _hostField.stringValue : @"localhost";
    if (_portField.integerValue > 0) components.port = @(_portField.integerValue);
    if (_userField.stringValue.length) components.user = _userField.stringValue;
    components.path = [@"/" stringByAppendingString:_databaseField.stringValue];
    if (_optionsField.stringValue.length) components.query = _optionsField.stringValue;
    return components.URL;
}

- (IBAction)testConnection:(id)sender {
    NSURL *url = [self _URL];
    if (!url) return;
    _testLabel.stringValue = @"Connecting…";
    [_tester close];
    _tester = [[UDSQLRunner alloc] initWithURL:url password:_serverPasswordField.stringValue.length ? _serverPasswordField.stringValue : nil];
    [_tester connectWithTarget:self action:@selector(_didTest:)];
}

- (void)_didTest:(NSError *)error {
    UDSQLConnection *connection = _tester.connection;
    _testLabel.stringValue = error ? error.localizedDescription
                                   : [NSString stringWithFormat:@"Connected: %@.", connection.serverDescription];
    [_tester close];
    _tester = nil;
}

- (IBAction)saveConnection:(id)sender {
    [_connectionPanel makeFirstResponder:nil];
    NSURL *url = [self _URL];
    if (!url) return;
    UDSQLDatabase *database = _editing ?: [[UDSQLDatabase alloc] init];
    NSString *name = [_nameField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    database.name = name.length ? name : ([self _dialect] == UDSQLDialectSQLite ? url.lastPathComponent : url.host ?: @"Database");
    database.URL = url;
    database.inProject = _keptButton.selectedTag == 1;
    if ([self _dialect] != UDSQLDialectSQLite) UDSQLRememberPassword(url, _serverPasswordField.stringValue);
    [self _end:_connectionPanel];
    [self _send:database];
}

- (IBAction)cancelConnection:(id)sender {
    [_tester close];
    [self _end:_connectionPanel];
    [self _send:[NSNull null]];
}

@end
