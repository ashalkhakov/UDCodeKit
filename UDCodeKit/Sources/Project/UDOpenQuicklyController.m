/*---------------------------------------------------------------------------------------------
 *  UDOpenQuicklyController.m
 *--------------------------------------------------------------------------------------------*/

#import "UDOpenQuicklyController.h"
#import "UDSearchResultsViewController.h"
#import "UDToolLocator.h"
#import <LSPKit/LSPKit.h>
#import <objc/runtime.h>

/// The most matches shown of each kind.
static const NSUInteger UDOpenQuicklyLimit = 200;

@interface UDOpenQuicklyController ()
@property (nonatomic, weak) IBOutlet NSSearchField *searchField;
@property (nonatomic, weak) IBOutlet NSTableView *tableView;
@end

@implementation UDOpenQuicklyController {
    NSArray<NSString *> *_files;
    NSArray<UDSearchResult *> *_fileResults;
    NSArray<UDSearchResult *> *_symbolResults;
    NSArray<NSString *> *_symbolTitles;
    NSInteger _symbolRequest;
    NSString *_query;
}

- (instancetype)init {
    NSBundle *bundle = [NSBundle bundleForClass:[UDOpenQuicklyController class]];
    NSString *path = [bundle pathForResource:@"UDOpenQuickly" ofType:@"nib"] ?: [bundle pathForResource:@"UDOpenQuickly" ofType:@"xib"];
    self = [super initWithWindowNibPath:path owner:self];
    if (self) {
        _fileResults = @[];
        _symbolResults = @[];
        _symbolTitles = @[];
    }
    return self;
}

- (void)beginSheetForWindow:(NSWindow *)window {
    (void)self.window;
    _files = nil;
    self.query = @"";
    [self.window makeFirstResponder:_searchField];
    [NSApp beginSheet:self.window modalForWindow:window modalDelegate:self
       didEndSelector:@selector(_sheetDidEnd:returnCode:contextInfo:) contextInfo:NULL];
}

- (void)_sheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo {
    [sheet orderOut:self];
}

/// Ended: GNUstep's modal loop notices only with the next event, so one comes.
- (void)_end {
    _symbolRequest = 0;
    [NSApp endSheet:self.window returnCode:NSModalResponseCancel];
    NSEvent *wake = [NSEvent otherEventWithType:NSEventTypeApplicationDefined location:NSZeroPoint modifierFlags:0
                                      timestamp:0 windowNumber:0 context:nil subtype:0 data1:0 data2:0];
    [NSApp postEvent:wake atStart:NO];
}

// ---------------------------------------------------------------------------
// MARK: - The folder's files
// ---------------------------------------------------------------------------

- (NSArray<NSString *> *)files {
    if (_files) return _files;
    if (!_folderURL) return _files = @[];
    NSMutableArray<NSString *> *files = [NSMutableArray array];
    NSString *rg = [UDToolLocator pathOfTool:@"rg"];
    if (rg) {
        NSTask *task = [[NSTask alloc] init];
        task.environment = [LSPTransport hostEnvironment];
        task.launchPath = rg;
        task.arguments = @[ @"--files", @"--color=never" ];
        task.currentDirectoryPath = _folderURL.path;
        NSPipe *pipe = [NSPipe pipe];
        task.standardOutput = pipe;
        task.standardError = [NSFileHandle fileHandleWithNullDevice];
        @try {
            [task launch];
            NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
            [task waitUntilExit];
            NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
            for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
                if (line.length) [files addObject:[line hasPrefix:@"./"] ? [line substringFromIndex:2] : line];
            }
        } @catch (NSException *exception) {
            rg = nil;
        }
    }
    if (!rg) {
        NSFileManager *manager = [NSFileManager defaultManager];
        NSDirectoryEnumerator *enumerator = [manager enumeratorAtPath:_folderURL.path];
        for (NSString *path in enumerator) {
            BOOL directory = NO;
            [manager fileExistsAtPath:[_folderURL.path stringByAppendingPathComponent:path] isDirectory:&directory];
            // a hidden folder's files left out (GNUstep's enumerator does not skip it)
            BOOL hidden = NO;
            for (NSString *component in path.pathComponents) hidden = hidden || [component hasPrefix:@"."];
            if (hidden) {
                if (directory) [enumerator skipDescendants];
                continue;
            }
            if (!directory) [files addObject:path];
        }
    }
    [files sortUsingSelector:@selector(compare:)];
    return _files = files;
}

/// How well @a name matches @a query, its letters in order (case aside):
/// higher better, -1 not at all. A prefix beats a run, a run beats letters apart.
static NSInteger UDMatchScore(NSString *name, NSString *query) {
    NSString *lowerName = name.lowercaseString, *lowerQuery = query.lowercaseString;
    if ([lowerName hasPrefix:lowerQuery]) return 3000 - (NSInteger)name.length;
    if ([lowerName rangeOfString:lowerQuery].location != NSNotFound) return 2000 - (NSInteger)name.length;
    NSUInteger at = 0;
    for (NSUInteger i = 0; i < lowerQuery.length; i++) {
        unichar c = [lowerQuery characterAtIndex:i];
        while (at < lowerName.length && [lowerName characterAtIndex:at] != c) at++;
        if (at == lowerName.length) return -1;
        at++;
    }
    return 1000 - (NSInteger)name.length;
}

// ---------------------------------------------------------------------------
// MARK: - Searching
// ---------------------------------------------------------------------------

- (NSString *)query {
    return _query ?: @"";
}

- (void)setQuery:(NSString *)query {
    (void)self.window;
    _query = [query copy] ?: @"";
    _searchField.stringValue = _query;
    [self _search];
}

- (NSArray<UDSearchResult *> *)results {
    return [_fileResults arrayByAddingObjectsFromArray:_symbolResults];
}

- (void)controlTextDidChange:(NSNotification *)note {
    _query = [_searchField.stringValue copy] ?: @"";
    [self _search];
}

- (void)_search {
    NSString *query = [self.query stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSMutableArray *scored = [NSMutableArray array];
    if (query.length) {
        for (NSString *file in self.files) {
            NSInteger score = UDMatchScore(file.lastPathComponent, query);
            // a query with a slash matches the path
            if ([query rangeOfString:@"/"].location != NSNotFound) score = MAX(score, UDMatchScore(file, query) - 500);
            if (score >= 0) [scored addObject:@[ @(score), file ]];
        }
        [scored sortUsingComparator:^NSComparisonResult(NSArray *a, NSArray *b) {
            NSComparisonResult byScore = [b[0] compare:a[0]];
            return byScore != NSOrderedSame ? byScore : [a[1] compare:b[1]];
        }];
    }
    NSMutableArray<UDSearchResult *> *fileResults = [NSMutableArray array];
    for (NSArray *match in scored) {
        if (fileResults.count == UDOpenQuicklyLimit) break;
        NSURL *url = [_folderURL URLByAppendingPathComponent:match[1]];
        [fileResults addObject:[[UDSearchResult alloc] initWithURL:url line:0 column:0 length:0 lineText:match[1]]];
    }
    _fileResults = fileResults;
    _symbolResults = @[];
    _symbolTitles = @[];
    _symbolRequest = 0;
    if (query.length >= 2 && _client.workspaceSymbolProvider) {
        _symbolRequest = [_client sendRequest:@"workspace/symbol" params:@{ @"query": query }
                                       target:self action:@selector(_didFindSymbols:)];
    }
    [self _reload];
}

- (void)_didFindSymbols:(LSPResponse *)response {
    if (response.requestID != _symbolRequest) return;      // typed on since
    NSMutableArray<UDSearchResult *> *results = [NSMutableArray array];
    NSMutableArray<NSString *> *titles = [NSMutableArray array];
    for (NSDictionary *symbol in [response.result isKindOfClass:[NSArray class]] ? response.result : @[]) {
        if (results.count == UDOpenQuicklyLimit) break;
        if (![symbol isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *location = symbol[@"location"];
        NSString *uri = [location isKindOfClass:[NSDictionary class]] ? location[@"uri"] : nil;
        NSURL *url = [uri isKindOfClass:[NSString class]] ? [NSURL URLWithString:uri] : nil;
        if (!url) continue;
        NSDictionary *start = location[@"range"][@"start"];
        NSString *name = symbol[@"name"] ?: @"";
        NSString *container = [symbol[@"containerName"] isKindOfClass:[NSString class]] ? symbol[@"containerName"] : @"";
        [results addObject:[[UDSearchResult alloc] initWithURL:url line:[start[@"line"] integerValue] + 1
                                                        column:[start[@"character"] integerValue] length:(NSInteger)name.length
                                                      lineText:name]];
        NSString *place = url.lastPathComponent;
        [titles addObject:container.length ? [NSString stringWithFormat:@"%@%@%@ — %@", container,
                                              [container hasSuffix:@":"] ? @"" : @"::", name, place]
                                           : [NSString stringWithFormat:@"%@ — %@", name, place]];
    }
    _symbolResults = results;
    _symbolTitles = titles;
    [self _reload];
}

- (void)_reload {
    [_tableView reloadData];
    if (_tableView.numberOfRows > 0) [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
}

// ---------------------------------------------------------------------------
// MARK: - The list, and the keys that move in it from the field
// ---------------------------------------------------------------------------

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)(_fileResults.count + _symbolResults.count);
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSUInteger index = (NSUInteger)row;
    if (index < _fileResults.count) return _fileResults[index].lineText;
    index -= _fileResults.count;
    return index < _symbolTitles.count ? _symbolTitles[index] : @"";
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)command {
    if (sel_isEqual(command, @selector(moveDown:)) || sel_isEqual(command, @selector(moveUp:))) {
        NSInteger rows = _tableView.numberOfRows;
        if (!rows) return YES;
        NSInteger row = _tableView.selectedRow + (sel_isEqual(command, @selector(moveDown:)) ? 1 : -1);
        row = MAX(0, MIN(rows - 1, row));
        [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
        [_tableView scrollRowToVisible:row];
        return YES;
    }
    if (sel_isEqual(command, @selector(insertNewline:))) {
        [self open:nil];
        return YES;
    }
    if (sel_isEqual(command, @selector(cancelOperation:))) {
        [self cancel:nil];
        return YES;
    }
    return NO;
}

- (IBAction)open:(id)sender {
    NSInteger row = _tableView.clickedRow >= 0 ? _tableView.clickedRow : _tableView.selectedRow;
    NSArray<UDSearchResult *> *results = self.results;
    UDSearchResult *chosen = row >= 0 && (NSUInteger)row < results.count ? results[(NSUInteger)row] : nil;
    if (!chosen) {
        NSBeep();
        return;
    }
    [self _end];
    [_delegate openQuickly:self showResult:chosen];
}

- (IBAction)cancel:(id)sender {
    [self _end];
}

@end
