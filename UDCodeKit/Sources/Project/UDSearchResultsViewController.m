/*---------------------------------------------------------------------------------------------
 *  UDSearchResultsViewController.m
 *--------------------------------------------------------------------------------------------*/

#import "UDSearchResultsViewController.h"
#import "UDToolLocator.h"

@implementation UDSearchResult

- (instancetype)initWithURL:(NSURL *)url line:(NSInteger)line column:(NSInteger)column length:(NSInteger)length
                   lineText:(NSString *)lineText {
    if (!(self = [super init])) return nil;
    _url = [url copy];
    _line = line;
    _column = column;
    _length = length;
    _lineText = [lineText copy];
    return self;
}

@end

/// A file's matches: the outline's first level.
@interface UDSearchFile : NSObject
@property (nonatomic, copy) NSURL *url;
@property (nonatomic, strong) NSMutableArray<UDSearchResult *> *results;
@end

@implementation UDSearchFile
@end

@interface UDSearchResultsViewController ()
@property (nonatomic, weak) IBOutlet NSSearchField *searchField;
@property (nonatomic, weak) IBOutlet NSOutlineView *outlineView;
@property (nonatomic, weak) IBOutlet NSTextField *statusLabel;
@end

@implementation UDSearchResultsViewController {
    NSMutableArray<UDSearchFile *> *_files;
    NSMutableDictionary<NSString *, UDSearchFile *> *_filesByPath;
    NSString *_title;
    NSTask *_task;
    NSFileHandle *_reading;
    NSMutableString *_pending;
    NSString *_searched;
}

- (instancetype)init {
    self = [super initWithNibName:@"UDSearchResults" bundle:[NSBundle bundleForClass:[UDSearchResultsViewController class]]];
    if (self) {
        _files = [NSMutableArray array];
        _filesByPath = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_task terminate];
}

- (NSArray<UDSearchResult *> *)results {
    NSMutableArray *all = [NSMutableArray array];
    for (UDSearchFile *file in _files) [all addObjectsFromArray:file.results];
    return all;
}

- (void)_clear {
    [_files removeAllObjects];
    [_filesByPath removeAllObjects];
}

- (void)_add:(UDSearchResult *)result {
    NSString *path = result.url.path;
    UDSearchFile *file = _filesByPath[path];
    if (!file) {
        file = [[UDSearchFile alloc] init];
        file.url = result.url;
        file.results = [NSMutableArray array];
        _filesByPath[path] = file;
        [_files addObject:file];
    }
    [file.results addObject:result];
}

- (void)showResults:(NSArray<UDSearchResult *> *)results title:(NSString *)title {
    (void)self.view;
    [self _stopSearching];
    [self _clear];
    for (UDSearchResult *result in results) [self _add:result];
    _title = [title copy];
    [self _reload];
}

- (void)_reload {
    [_outlineView reloadData];
    for (UDSearchFile *file in _files) [_outlineView expandItem:file];
    NSUInteger count = 0;
    for (UDSearchFile *file in _files) count += file.results.count;
    NSString *found = [NSString stringWithFormat:@"%lu result%@ in %lu file%@", (unsigned long)count, count == 1 ? @"" : @"s",
                       (unsigned long)_files.count, _files.count == 1 ? @"" : @"s"];
    _statusLabel.stringValue = _title.length ? [NSString stringWithFormat:@"%@: %@", _title, found] : found;
}

// ---------------------------------------------------------------------------
// MARK: - Find in Workspace: ripgrep, else grep
// ---------------------------------------------------------------------------

- (IBAction)search:(id)sender {
    [self searchFor:_searchField.stringValue];
}

- (BOOL)isSearching {
    return _task != nil;
}

- (void)searchFor:(NSString *)text {
    (void)self.view;
    [self _stopSearching];
    [self _clear];
    _searchField.stringValue = text ?: @"";
    _title = text.length ? [NSString stringWithFormat:@"“%@”", text] : nil;
    if (!text.length || !_folderURL) {
        [self _reload];
        return;
    }
    NSString *rg = [UDToolLocator pathOfTool:@"rg"];
    NSTask *task = [[NSTask alloc] init];
    if (rg) {
        // file:line:column:text, the files .gitignore leaves out left out
        task.launchPath = rg;
        task.arguments = @[ @"--vimgrep", @"--fixed-strings", @"--ignore-case", @"--no-heading", @"--color=never", @"--", text, @"." ];
    } else {
        task.launchPath = [UDToolLocator pathOfTool:@"grep"] ?: @"/usr/bin/grep";
        task.arguments = @[ @"-rnIiF", @"--exclude-dir=.git", @"--exclude-dir=.udcode", @"--", text, @"." ];
    }
    task.currentDirectoryPath = _folderURL.path;
    NSPipe *pipe = [NSPipe pipe];
    task.standardOutput = pipe;
    task.standardError = [NSFileHandle fileHandleWithNullDevice];
    _reading = pipe.fileHandleForReading;
    _pending = [NSMutableString string];
    _searched = [text copy];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_didRead:)
                                                 name:NSFileHandleReadCompletionNotification object:_reading];
    @try {
        [task launch];
    } @catch (NSException *exception) {
        [self _stopSearching];
        return;
    }
    _task = task;
    _statusLabel.stringValue = [NSString stringWithFormat:@"Searching for “%@”…", text];
    [_reading readInBackgroundAndNotify];
}

- (void)_stopSearching {
    if (_reading) [[NSNotificationCenter defaultCenter] removeObserver:self name:NSFileHandleReadCompletionNotification object:_reading];
    _reading = nil;
    if (_task.isRunning) [_task terminate];
    _task = nil;
}

- (void)_didRead:(NSNotification *)note {
    NSData *data = note.userInfo[NSFileHandleNotificationDataItem];
    if (!data.length) {
        if (_pending.length) [self _readLine:_pending];
        [self _stopSearching];
        [self _reload];
        return;
    }
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
                  ?: [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
    [_pending appendString:text];
    NSRange newline;
    while ((newline = [_pending rangeOfString:@"\n"]).location != NSNotFound) {
        NSString *line = [_pending substringToIndex:newline.location];
        [_pending deleteCharactersInRange:NSMakeRange(0, NSMaxRange(newline))];
        [self _readLine:line];
    }
    [self _reload];
    [_reading readInBackgroundAndNotify];
}

/// "./path:line:text" (grep) or "./path:line:column:text" (ripgrep).
- (void)_readLine:(NSString *)line {
    NSArray<NSString *> *parts = [line componentsSeparatedByString:@":"];
    if (parts.count < 3) return;
    NSString *path = parts[0];
    NSInteger lineNumber = parts[1].integerValue;
    if (lineNumber <= 0) return;
    NSUInteger textStart = 2;
    NSInteger column = -1;
    if (parts.count >= 4 && parts[2].integerValue > 0 &&
        [parts[2] rangeOfCharacterFromSet:[NSCharacterSet decimalDigitCharacterSet].invertedSet].location == NSNotFound) {
        column = parts[2].integerValue - 1;
        textStart = 3;
    }
    NSString *lineText = [[parts subarrayWithRange:NSMakeRange(textStart, parts.count - textStart)] componentsJoinedByString:@":"];
    if (column < 0) {
        NSRange found = [lineText rangeOfString:_searched options:NSCaseInsensitiveSearch];
        column = found.location == NSNotFound ? 0 : (NSInteger)found.location;
    }
    if ([path hasPrefix:@"./"]) path = [path substringFromIndex:2];
    NSURL *url = [_folderURL URLByAppendingPathComponent:path];
    [self _add:[[UDSearchResult alloc] initWithURL:url line:lineNumber column:column length:(NSInteger)_searched.length
                                          lineText:lineText]];
}

// ---------------------------------------------------------------------------
// MARK: - The outline
// ---------------------------------------------------------------------------

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {
    if (!item) return (NSInteger)_files.count;
    return [item isKindOfClass:[UDSearchFile class]] ? (NSInteger)((UDSearchFile *)item).results.count : 0;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item {
    return item ? ((UDSearchFile *)item).results[(NSUInteger)index] : _files[(NSUInteger)index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    return [item isKindOfClass:[UDSearchFile class]];
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item {
    if ([item isKindOfClass:[UDSearchFile class]]) {
        UDSearchFile *file = item;
        NSString *folder = [_folderURL.path stringByAppendingString:@"/"];
        NSString *path = file.url.path;
        return [path hasPrefix:folder] ? [path substringFromIndex:folder.length] : path.lastPathComponent;
    }
    UDSearchResult *result = item;
    NSString *text = [result.lineText stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] ?: @"";
    return [NSString stringWithFormat:@"%ld: %@", (long)result.line, text];
}

- (IBAction)showSelectedResult:(id)sender {
    NSInteger row = _outlineView.clickedRow >= 0 ? _outlineView.clickedRow : _outlineView.selectedRow;
    id item = row >= 0 ? [_outlineView itemAtRow:row] : nil;
    if ([item isKindOfClass:[UDSearchResult class]]) [_delegate searchResults:self showResult:item];
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification {
    id item = _outlineView.selectedRow >= 0 ? [_outlineView itemAtRow:_outlineView.selectedRow] : nil;
    if ([item isKindOfClass:[UDSearchResult class]]) [_delegate searchResults:self showResult:item];
}

@end
