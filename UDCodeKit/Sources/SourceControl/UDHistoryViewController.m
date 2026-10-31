/*---------------------------------------------------------------------------------------------
 *  UDHistoryViewController.m
 *--------------------------------------------------------------------------------------------*/

#import "UDHistoryViewController.h"
#import "UDBadgeTextFieldCell.h"

/// How many commits a history reads.
static const NSInteger UDHistoryLength = 500;

@interface UDHistoryViewController () <NSTableViewDataSource, NSTableViewDelegate>
@end

@implementation UDHistoryViewController {
    NSTableView *_commitsTable, *_filesTable;
    NSTextView *_details;
    NSDateFormatter *_dates;
}

- (instancetype)initWithSourceControl:(id<UDSourceControl>)sourceControl ref:(NSString *)ref {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _sourceControl = sourceControl;
        _ref = [ref copy];
        _commits = @[];
        _selectedCommitFiles = @[];
        _dates = [[NSDateFormatter alloc] init];
        _dates.dateStyle = NSDateFormatterMediumStyle;
        _dates.timeStyle = NSDateFormatterShortStyle;
    }
    return self;
}

static NSTableView *UDMakeTable(NSRect frame, NSArray<NSArray *> *columns, id owner, NSScrollView *__autoreleasing *scroll) {
    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:frame];
    scrollView.hasVerticalScroller = YES;
    scrollView.autohidesScrollers = YES;
    scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    NSTableView *table = [[NSTableView alloc] initWithFrame:scrollView.bounds];
    for (NSArray *column in columns) {
        NSTableColumn *tableColumn = [[NSTableColumn alloc] initWithIdentifier:column[0]];
        [tableColumn.headerCell setStringValue:column[1]];
        tableColumn.width = [column[2] doubleValue];
        UDBadgeTextFieldCell *cell = [[UDBadgeTextFieldCell alloc] initTextCell:@""];
        cell.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
        cell.lineBreakMode = NSLineBreakByTruncatingTail;
        cell.editable = NO;
        tableColumn.dataCell = cell;
        [table addTableColumn:tableColumn];
    }
    table.rowHeight = 18;
    table.columnAutoresizingStyle = NSTableViewFirstColumnOnlyAutoresizingStyle;
    table.dataSource = owner;
    table.delegate = owner;
    table.target = owner;
    scrollView.documentView = table;
    // as wide as what shows it, the first column taking what the others leave
    table.autoresizingMask = NSViewWidthSizable;
    table.frame = scrollView.contentView.bounds;
    [table sizeToFit];
    *scroll = scrollView;
    return table;
}

- (void)loadView {
    NSSplitView *split = [[NSSplitView alloc] initWithFrame:NSMakeRect(0, 0, 800, 600)];
    split.vertical = NO;
    split.dividerStyle = NSSplitViewDividerStyleThin;
    split.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    NSScrollView *scroll = nil;
    _commitsTable = UDMakeTable(NSMakeRect(0, 0, 800, 340), @[ @[ @"message", @"Message", @420 ], @[ @"author", @"Author", @140 ],
                                                                @[ @"date", @"Date", @140 ], @[ @"commit", @"Commit", @70 ] ],
                                self, &scroll);
    [split addSubview:scroll];

    NSSplitView *detail = [[NSSplitView alloc] initWithFrame:NSMakeRect(0, 0, 800, 260)];
    detail.vertical = YES;
    detail.dividerStyle = NSSplitViewDividerStyleThin;
    detail.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    NSScrollView *detailsScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 480, 260)];
    detailsScroll.hasVerticalScroller = YES;
    detailsScroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _details = [[NSTextView alloc] initWithFrame:detailsScroll.bounds];
    _details.editable = NO;
    _details.textContainerInset = NSMakeSize(8, 8);
    _details.autoresizingMask = NSViewWidthSizable;
    detailsScroll.documentView = _details;
    [detail addSubview:detailsScroll];
    _filesTable = UDMakeTable(NSMakeRect(0, 0, 320, 260), @[ @[ @"file", @"Files Changed", @300 ] ], self, &scroll);
    _filesTable.doubleAction = @selector(_openFile:);
    [detail addSubview:scroll];
    [detail adjustSubviews];
    [split addSubview:detail];
    [split adjustSubviews];
    self.view = split;
    [self reload];
}

- (NSTableView *)commitsTable {
    (void)self.view;
    return _commitsTable;
}

- (NSTableView *)filesTable {
    (void)self.view;
    return _filesTable;
}

- (void)reload {
    if ([_sourceControl respondsToSelector:@selector(historyOfRef:count:target:action:)]) {
        [_sourceControl historyOfRef:_ref count:UDHistoryLength target:self action:@selector(_didReadLog:)];
    }
}

- (void)_didReadLog:(UDSourceControlResult *)result {
    _commits = [result.value isKindOfClass:[NSArray class]] ? result.value : @[];
    [_commitsTable reloadData];
    if (_commits.count) [_commitsTable selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    [self _showSelectedCommit];
}

- (nullable UDSourceControlCommit *)_selectedCommit {
    NSInteger row = _commitsTable.selectedRow;
    return row >= 0 && row < (NSInteger)_commits.count ? _commits[(NSUInteger)row] : nil;
}

- (void)_showSelectedCommit {
    UDSourceControlCommit *commit = [self _selectedCommit];
    _selectedCommitFiles = @[];
    [_filesTable reloadData];
    if (!commit) {
        _details.string = @"";
        return;
    }
    NSMutableString *details = [NSMutableString string];
    [details appendFormat:@"%@\n\n", commit.message];
    [details appendFormat:@"%@ <%@>\n%@\n", commit.authorName, commit.authorEmail, [_dates stringFromDate:commit.authorDate]];
    [details appendFormat:@"Commit %@\n", commit.identifier];
    if (commit.parents.count) [details appendFormat:@"Parent %@\n", [commit.parents componentsJoinedByString:@", "]];
    if (commit.refNames.count) [details appendFormat:@"%@\n", [commit.refNames componentsJoinedByString:@", "]];
    _details.string = details;
    if ([_sourceControl respondsToSelector:@selector(filesOfCommit:target:action:)]) {
        [_sourceControl filesOfCommit:commit.identifier target:self action:@selector(_didReadFiles:)];
    }
}

- (void)_didReadFiles:(UDSourceControlResult *)result {
    if (![result.context isEqual:[self _selectedCommit].identifier]) return;
    _selectedCommitFiles = [result.value isKindOfClass:[NSArray class]] ? result.value : @[];
    [_filesTable reloadData];
}

- (void)_openFile:(id)sender {
    NSInteger row = _filesTable.clickedRow >= 0 ? _filesTable.clickedRow : _filesTable.selectedRow;
    UDSourceControlCommit *commit = [self _selectedCommit];
    if (row < 0 || row >= (NSInteger)_selectedCommitFiles.count || !commit) return;
    [_delegate history:self openFile:_selectedCommitFiles[(NSUInteger)row] ofCommit:commit];
}

// ---------------------------------------------------------------------------
// MARK: - The tables
// ---------------------------------------------------------------------------

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)(tableView == _commitsTable ? _commits.count : _selectedCommitFiles.count);
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (tableView == _filesTable) return _selectedCommitFiles[(NSUInteger)row].path;
    UDSourceControlCommit *commit = _commits[(NSUInteger)row];
    NSString *column = tableColumn.identifier;
    if ([column isEqualToString:@"message"]) return commit.subject;
    if ([column isEqualToString:@"author"]) return commit.authorName;
    if ([column isEqualToString:@"date"]) return [_dates stringFromDate:commit.authorDate];
    return commit.shortIdentifier;
}

- (void)tableView:(NSTableView *)tableView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (![cell isKindOfClass:[UDBadgeTextFieldCell class]]) return;
    NSString *badge = nil;
    if (tableView == _filesTable) {
        badge = _selectedCommitFiles[(NSUInteger)row].letter;
    } else if ([tableColumn.identifier isEqualToString:@"message"]) {
        UDSourceControlCommit *commit = _commits[(NSUInteger)row];
        NSMutableArray *names = [NSMutableArray array];
        for (NSString *name in commit.refNames) {
            [names addObject:[name hasPrefix:@"HEAD -> "] ? [name substringFromIndex:8] : name];
        }
        badge = names.count ? [names componentsJoinedByString:@", "] : nil;
    }
    [(UDBadgeTextFieldCell *)cell setBadge:badge];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    if (notification.object == _commitsTable) [self _showSelectedCommit];
}

@end
