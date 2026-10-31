/*---------------------------------------------------------------------------------------------
 *  UDGitRepositoriesViewController.m
 *--------------------------------------------------------------------------------------------*/

#import "UDGitRepositoriesViewController.h"
#import "UDGitDialogs.h"

typedef NS_ENUM(NSInteger, UDGitItemKind) {
    UDGitItemGroup,                    // Branches, Tags, Remotes, Stashed Changes
    UDGitItemBranch,
    UDGitItemRemote,
    UDGitItemRemoteBranch,
    UDGitItemTag,
    UDGitItemStash,
};

@interface UDGitItem : NSObject
@property (nonatomic) UDGitItemKind kind;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy, nullable) NSString *badge;
@property (nonatomic, strong, nullable) id object;         // a ref, a remote, a stash
@property (nonatomic, copy) NSArray<UDGitItem *> *children;
@end

@implementation UDGitItem
+ (instancetype)itemOfKind:(UDGitItemKind)kind title:(NSString *)title object:(id)object {
    UDGitItem *item = [[self alloc] init];
    item.kind = kind;
    item.title = title;
    item.object = object;
    item.children = @[];
    return item;
}
@end

@interface UDGitRepositoriesViewController () <NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate>
@end

@implementation UDGitRepositoriesViewController {
    UDGitRepository *_repository;
    __weak id<UDSourceControl> _sourceControl;
    NSOutlineView *_outlineView;
    NSArray<UDGitItem *> *_groups;
}

- (instancetype)initWithRepository:(UDGitRepository *)repository sourceControl:(id<UDSourceControl>)sourceControl {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _repository = repository;
        _sourceControl = sourceControl;
        _groups = @[];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_repositoryDidChange:)
                                                     name:UDGitRepositoryDidChangeNotification object:repository];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)loadView {
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 240, 600)];
    scroll.hasVerticalScroller = YES;
    scroll.autohidesScrollers = YES;
    scroll.borderType = NSNoBorder;
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _outlineView = [[NSOutlineView alloc] initWithFrame:scroll.bounds];
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    UDBadgeTextFieldCell *cell = [[UDBadgeTextFieldCell alloc] initTextCell:@""];
    cell.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
    cell.lineBreakMode = NSLineBreakByTruncatingMiddle;
    cell.editable = NO;
    column.dataCell = cell;
    column.width = NSWidth(scroll.bounds) - 16;
    column.resizingMask = NSTableColumnAutoresizingMask;
    [_outlineView addTableColumn:column];
    _outlineView.outlineTableColumn = column;
    _outlineView.headerView = nil;
    _outlineView.rowHeight = 18;
    _outlineView.indentationPerLevel = 12;
    _outlineView.columnAutoresizingStyle = NSTableViewLastColumnOnlyAutoresizingStyle;
    _outlineView.dataSource = self;
    _outlineView.delegate = self;
    _outlineView.target = self;
    _outlineView.action = @selector(_selectRef:);
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];
    menu.delegate = self;
    _outlineView.menu = menu;
    scroll.documentView = _outlineView;
    _outlineView.autoresizingMask = NSViewWidthSizable;
    _outlineView.frame = scroll.contentView.bounds;
    [_outlineView sizeLastColumnToFit];
    self.view = scroll;
    [self _reload];
}

- (NSOutlineView *)outlineView {
    (void)self.view;
    return _outlineView;
}

- (void)_repositoryDidChange:(NSNotification *)note {
    if (self.isViewLoaded) [self _reload];
}

- (void)_reload {
    UDGitRepository *repository = _repository;
    NSMutableArray *branches = [NSMutableArray array], *tags = [NSMutableArray array];
    NSMutableDictionary<NSString *, NSMutableArray *> *remoteBranches = [NSMutableDictionary dictionary];
    for (UDGitRef *ref in repository.refs) {
        if (ref.type == UDGitRefTypeHead) {
            UDGitItem *item = [UDGitItem itemOfKind:UDGitItemBranch title:ref.name object:ref];
            if ([ref.name isEqualToString:repository.branch]) item.badge = @"Current";
            [branches addObject:item];
        } else if (ref.type == UDGitRefTypeTag) {
            [tags addObject:[UDGitItem itemOfKind:UDGitItemTag title:ref.name object:ref]];
        } else {
            NSRange slash = [ref.name rangeOfString:@"/"];
            NSString *remote = slash.location == NSNotFound ? ref.name : [ref.name substringToIndex:slash.location];
            NSString *name = slash.location == NSNotFound ? ref.name : [ref.name substringFromIndex:NSMaxRange(slash)];
            if (!remoteBranches[remote]) remoteBranches[remote] = [NSMutableArray array];
            [remoteBranches[remote] addObject:[UDGitItem itemOfKind:UDGitItemRemoteBranch title:name object:ref]];
        }
    }
    NSMutableArray *remotes = [NSMutableArray array];
    for (UDGitRemote *remote in repository.remotes) {
        UDGitItem *item = [UDGitItem itemOfKind:UDGitItemRemote title:remote.name object:remote];
        item.children = remoteBranches[remote.name] ?: @[];
        [remotes addObject:item];
    }
    NSMutableArray *stashes = [NSMutableArray array];
    for (UDGitStash *stash in repository.stashes) {
        [stashes addObject:[UDGitItem itemOfKind:UDGitItemStash title:stash.message object:stash]];
    }
    NSMutableArray *groups = [NSMutableArray array];
    for (NSArray *group in @[ @[ @"Branches", branches ], @[ @"Tags", tags ], @[ @"Remotes", remotes ], @[ @"Stashed Changes", stashes ] ]) {
        UDGitItem *item = [UDGitItem itemOfKind:UDGitItemGroup title:group[0] object:nil];
        item.children = group[1];
        [groups addObject:item];
    }
    _groups = groups;
    [_outlineView reloadData];
    for (UDGitItem *group in _groups) [_outlineView expandItem:group];
}

// ---------------------------------------------------------------------------
// MARK: - The outline
// ---------------------------------------------------------------------------

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {
    return (NSInteger)(item ? ((UDGitItem *)item).children : _groups).count;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item {
    return (item ? ((UDGitItem *)item).children : _groups)[(NSUInteger)index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    UDGitItem *row = item;
    return row.kind == UDGitItemGroup || row.kind == UDGitItemRemote;
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item {
    return ((UDGitItem *)item).title;
}

- (void)outlineView:(NSOutlineView *)outlineView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn item:(id)item {
    UDGitItem *row = item;
    if ([cell isKindOfClass:[UDBadgeTextFieldCell class]]) [(UDBadgeTextFieldCell *)cell setBadge:row.badge];
    [cell setFont:row.kind == UDGitItemGroup ? [NSFont boldSystemFontOfSize:[NSFont smallSystemFontSize]]
                                             : [NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
}

- (void)_selectRef:(id)sender {
    NSInteger row = _outlineView.clickedRow >= 0 ? _outlineView.clickedRow : _outlineView.selectedRow;
    UDGitItem *item = row >= 0 ? [_outlineView itemAtRow:row] : nil;
    if (item.kind != UDGitItemBranch && item.kind != UDGitItemTag && item.kind != UDGitItemRemoteBranch) return;
    id<UDSourceControl> sourceControl = _sourceControl;
    UDGitRef *ref = item.object;
    [sourceControl.host sourceControl:sourceControl showHistoryOfRef:ref.name title:ref.name];
}

// ---------------------------------------------------------------------------
// MARK: - Context menus and what they do
// ---------------------------------------------------------------------------

- (void)_operationDidFinish:(UDGitResult *)result {
    id<UDSourceControl> sourceControl = _sourceControl;
    if (result.succeeded || !sourceControl) return;
    [sourceControl.host sourceControl:sourceControl
                              didFail:[[UDSourceControlResult alloc] initSucceeded:NO message:result.message value:nil context:nil]];
}

static NSMenuItem *UDItem(NSString *title, SEL action, id target, id object) {
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:@""];
    item.target = target;
    item.representedObject = object;
    return item;
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
    [menu removeAllItems];
    NSInteger row = _outlineView.clickedRow;
    if (row < 0) row = [_outlineView rowAtPoint:[_outlineView convertPoint:[NSApp currentEvent].locationInWindow fromView:nil]];
    UDGitItem *item = row >= 0 ? [_outlineView itemAtRow:row] : nil;
    UDGitRef *ref = [item.object isKindOfClass:[UDGitRef class]] ? item.object : nil;
    NSString *current = _repository.branch;
    switch (item.kind) {
        case UDGitItemBranch:
            if (![ref.name isEqualToString:current]) [menu addItem:UDItem(@"Switch…", @selector(_switch:), self, ref)];
            [menu addItem:UDItem([NSString stringWithFormat:@"New Branch from “%@”…", ref.name], @selector(_newBranch:), self, ref)];
            [menu addItem:UDItem([NSString stringWithFormat:@"Rename “%@”…", ref.name], @selector(_renameBranch:), self, ref)];
            if (current && ![ref.name isEqualToString:current]) {
                [menu addItem:UDItem([NSString stringWithFormat:@"Merge “%@” into “%@”…", ref.name, current], @selector(_merge:), self, ref)];
            }
            [menu addItem:UDItem([NSString stringWithFormat:@"New Tag from “%@”…", ref.name], @selector(_newTag:), self, ref)];
            if (![ref.name isEqualToString:current]) {
                [menu addItem:[NSMenuItem separatorItem]];
                [menu addItem:UDItem(@"Delete…", @selector(_deleteBranch:), self, ref)];
            }
            break;
        case UDGitItemRemoteBranch:
            [menu addItem:UDItem(@"Switch…", @selector(_switch:), self, ref)];
            [menu addItem:UDItem([NSString stringWithFormat:@"New Branch from “%@”…", ref.name], @selector(_newBranch:), self, ref)];
            if (current) {
                [menu addItem:UDItem([NSString stringWithFormat:@"Merge “%@” into “%@”…", ref.name, current], @selector(_merge:), self, ref)];
            }
            break;
        case UDGitItemTag:
            [menu addItem:UDItem([NSString stringWithFormat:@"New Branch from “%@”…", ref.name], @selector(_newBranch:), self, ref)];
            [menu addItem:[NSMenuItem separatorItem]];
            [menu addItem:UDItem(@"Delete…", @selector(_deleteTag:), self, ref)];
            break;
        case UDGitItemRemote:
            [menu addItem:UDItem(@"Remove…", @selector(_removeRemote:), self, item.object)];
            break;
        case UDGitItemStash:
            [menu addItem:UDItem(@"Apply Stashed Changes…", @selector(_applyStash:), self, item.object)];
            [menu addItem:[NSMenuItem separatorItem]];
            [menu addItem:UDItem(@"Delete…", @selector(_dropStash:), self, item.object)];
            break;
        case UDGitItemGroup:
            if ([item.title isEqualToString:@"Remotes"]) [menu addItem:UDItem(@"Add Existing Remote…", @selector(_addRemote:), self, nil)];
            if ([item.title isEqualToString:@"Branches"] && current) {
                [menu addItem:UDItem([NSString stringWithFormat:@"New Branch from “%@”…", current], @selector(_newBranch:), self, nil)];
            }
            break;
    }
}

- (void)_switch:(NSMenuItem *)sender {
    UDGitRef *ref = sender.representedObject;
    if (ref.type == UDGitRefTypeRemoteHead) {
        // a remote's branch: a branch of its own that tracks it
        NSRange slash = [ref.name rangeOfString:@"/"];
        NSString *name = slash.location == NSNotFound ? ref.name : [ref.name substringFromIndex:NSMaxRange(slash)];
        [_repository createBranch:name fromRef:ref.name checkout:YES target:self action:@selector(_operationDidFinish:)];
        return;
    }
    if (!UDGitConfirm([NSString stringWithFormat:@"Switch to “%@”?", ref.name], @"Your working copy will be changed to the branch's files.", @"Switch")) return;
    [_repository checkout:ref.name target:self action:@selector(_operationDidFinish:)];
}

- (void)_newBranch:(NSMenuItem *)sender {
    UDGitRef *ref = sender.representedObject;
    NSString *from = ref.name ?: _repository.branch ?: @"HEAD";
    NSString *name = UDGitAsk([NSString stringWithFormat:@"New Branch from “%@”", from], @"The new branch is checked out.", @"", @"Create");
    if (name) [_repository createBranch:name fromRef:ref.name checkout:YES target:self action:@selector(_operationDidFinish:)];
}

- (void)_renameBranch:(NSMenuItem *)sender {
    UDGitRef *ref = sender.representedObject;
    NSString *name = UDGitAsk([NSString stringWithFormat:@"Rename “%@”", ref.name], nil, ref.name, @"Rename");
    if (name && ![name isEqualToString:ref.name]) [_repository renameBranch:ref.name to:name target:self action:@selector(_operationDidFinish:)];
}

- (void)_merge:(NSMenuItem *)sender {
    UDGitRef *ref = sender.representedObject;
    if (UDGitConfirm([NSString stringWithFormat:@"Merge “%@” into “%@”?", ref.name, _repository.branch], nil, @"Merge")) {
        [_repository merge:ref.name target:self action:@selector(_operationDidFinish:)];
    }
}

- (void)_newTag:(NSMenuItem *)sender {
    UDGitRef *ref = sender.representedObject;
    NSString *name = UDGitAsk([NSString stringWithFormat:@"New Tag from “%@”", ref.name], nil, @"", @"Create");
    if (name) [_repository createTag:name message:nil atRef:ref.name target:self action:@selector(_operationDidFinish:)];
}

- (void)_deleteBranch:(NSMenuItem *)sender {
    UDGitRef *ref = sender.representedObject;
    if (UDGitConfirm([NSString stringWithFormat:@"Delete the branch “%@”?", ref.name], @"This can't be undone.", @"Delete")) {
        [_repository deleteBranch:ref.name force:NO target:self action:@selector(_operationDidFinish:)];
    }
}

- (void)_deleteTag:(NSMenuItem *)sender {
    UDGitRef *ref = sender.representedObject;
    if (UDGitConfirm([NSString stringWithFormat:@"Delete the tag “%@”?", ref.name], nil, @"Delete")) {
        [_repository deleteTag:ref.name target:self action:@selector(_operationDidFinish:)];
    }
}

- (void)_addRemote:(id)sender {
    NSString *name = UDGitAsk(@"Add Existing Remote", @"The remote's name.", _repository.remotes.count ? @"" : @"origin", @"Next");
    if (!name) return;
    NSString *url = UDGitAsk(@"Add Existing Remote", [NSString stringWithFormat:@"The address of “%@”.", name], @"", @"Add");
    if (url) [_repository addRemote:name url:url target:self action:@selector(_operationDidFinish:)];
}

- (void)_removeRemote:(NSMenuItem *)sender {
    UDGitRemote *remote = sender.representedObject;
    if (UDGitConfirm([NSString stringWithFormat:@"Remove the remote “%@”?", remote.name], nil, @"Remove")) {
        [_repository removeRemote:remote.name target:self action:@selector(_operationDidFinish:)];
    }
}

- (void)_applyStash:(NSMenuItem *)sender {
    UDGitStash *stash = sender.representedObject;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"Apply “%@”?", stash.message];
    [alert addButtonWithTitle:@"Apply"];
    [alert addButtonWithTitle:@"Cancel"];
    NSButton *keep = UDGitCheckBox(@"Keep the stashed changes", 260);
    alert.accessoryView = keep;
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    [_repository applyStash:stash.index pop:keep.state != NSControlStateValueOn target:self action:@selector(_operationDidFinish:)];
}

- (void)_dropStash:(NSMenuItem *)sender {
    UDGitStash *stash = sender.representedObject;
    if (UDGitConfirm([NSString stringWithFormat:@"Delete “%@”?", stash.message], @"This can't be undone.", @"Delete")) {
        [_repository dropStash:stash.index target:self action:@selector(_operationDidFinish:)];
    }
}

@end
