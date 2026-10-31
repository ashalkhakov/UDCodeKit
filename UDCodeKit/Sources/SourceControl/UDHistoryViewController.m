/*---------------------------------------------------------------------------------------------
 *  UDHistoryViewController.m
 *--------------------------------------------------------------------------------------------*/

#import "UDHistoryViewController.h"
#import "UDBadgeTextFieldCell.h"

/// How many commits a history reads.
static const NSInteger UDHistoryLength = 500;

@interface UDHistoryViewController () <NSTableViewDataSource, NSTableViewDelegate>
@property (nonatomic, weak) IBOutlet NSTableView *commitsTable;
@property (nonatomic, weak) IBOutlet NSTableView *filesTable;
@property (nonatomic, strong) IBOutlet NSTextView *detailsView;
@end

@implementation UDHistoryViewController {
    NSDateFormatter *_dates;
}

- (instancetype)initWithSourceControl:(id<UDSourceControl>)sourceControl ref:(NSString *)ref {
    self = [super initWithNibName:@"UDHistory" bundle:[NSBundle bundleForClass:[UDHistoryViewController class]]];
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

// ---------------------------------------------------------------------------
// MARK: - The view (UDHistory.xib)
// ---------------------------------------------------------------------------

- (void)viewDidLoad {
    [super viewDidLoad];
    _detailsView.textContainerInset = NSMakeSize(8, 8);
    // as wide as what shows them, the first column taking what the others leave
    for (NSTableView *table in @[ _commitsTable, _filesTable ]) {
        table.frame = table.enclosingScrollView.contentView.bounds;
        [table sizeToFit];
    }
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
        _detailsView.string = @"";
        return;
    }
    NSMutableString *details = [NSMutableString string];
    [details appendFormat:@"%@\n\n", commit.message];
    [details appendFormat:@"%@ <%@>\n%@\n", commit.authorName, commit.authorEmail, [_dates stringFromDate:commit.authorDate]];
    [details appendFormat:@"Commit %@\n", commit.identifier];
    if (commit.parents.count) [details appendFormat:@"Parent %@\n", [commit.parents componentsJoinedByString:@", "]];
    if (commit.refNames.count) [details appendFormat:@"%@\n", [commit.refNames componentsJoinedByString:@", "]];
    _detailsView.string = details;
    if ([_sourceControl respondsToSelector:@selector(filesOfCommit:target:action:)]) {
        [_sourceControl filesOfCommit:commit.identifier target:self action:@selector(_didReadFiles:)];
    }
}

- (void)_didReadFiles:(UDSourceControlResult *)result {
    if (![result.context isEqual:[self _selectedCommit].identifier]) return;
    _selectedCommitFiles = [result.value isKindOfClass:[NSArray class]] ? result.value : @[];
    [_filesTable reloadData];
}

- (IBAction)openFile:(id)sender {
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
