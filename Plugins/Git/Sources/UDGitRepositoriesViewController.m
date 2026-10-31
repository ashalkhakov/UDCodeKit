/*---------------------------------------------------------------------------------------------
 *  UDGitRepositoriesViewController.m
 *--------------------------------------------------------------------------------------------*/

#import "UDGitRepositoriesViewController.h"
#import "UDGitDialogs.h"
#import <objc/runtime.h>

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
@property (nonatomic, weak) IBOutlet NSOutlineView *outlineView;
// Each kind's context menu, UDGitRepositories.xib's: “{name}” in a title is
// the row's, “{current}” the current branch.
@property (nonatomic, strong) IBOutlet NSMenu *branchMenu;
@property (nonatomic, strong) IBOutlet NSMenu *remoteBranchMenu;
@property (nonatomic, strong) IBOutlet NSMenu *tagMenu;
@property (nonatomic, strong) IBOutlet NSMenu *remoteMenu;
@property (nonatomic, strong) IBOutlet NSMenu *stashMenu;
@property (nonatomic, strong) IBOutlet NSMenu *branchesMenu;
@property (nonatomic, strong) IBOutlet NSMenu *remotesMenu;
@end

@implementation UDGitRepositoriesViewController {
    UDGitRepository *_repository;
    __weak id<UDSourceControl> _sourceControl;
    NSArray<UDGitItem *> *_groups;
}

- (instancetype)initWithRepository:(UDGitRepository *)repository sourceControl:(id<UDSourceControl>)sourceControl {
    self = [super initWithNibName:@"UDGitRepositories" bundle:[NSBundle bundleForClass:[UDGitRepositoriesViewController class]]];
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

- (void)viewDidLoad {
    [super viewDidLoad];
    // as wide as what shows it: the badges at its right edge
    _outlineView.frame = _outlineView.enclosingScrollView.contentView.bounds;
    [_outlineView sizeLastColumnToFit];
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

- (IBAction)showHistory:(id)sender {
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

- (nullable NSMenu *)_menuOfItem:(UDGitItem *)item {
    switch (item.kind) {
        case UDGitItemBranch: return _branchMenu;
        case UDGitItemRemoteBranch: return _remoteBranchMenu;
        case UDGitItemTag: return _tagMenu;
        case UDGitItemRemote: return _remoteMenu;
        case UDGitItemStash: return _stashMenu;
        case UDGitItemGroup:
            if ([item.title isEqualToString:@"Branches"]) return _branchesMenu;
            if ([item.title isEqualToString:@"Remotes"]) return _remotesMenu;
            return nil;
    }
    return nil;
}

/// The clicked row's kind's menu: its items for the row (the current branch
/// can't be switched to, merged or deleted; with none, nothing is merged).
- (void)menuNeedsUpdate:(NSMenu *)menu {
    if (menu != _outlineView.menu) return;
    [menu removeAllItems];
    NSInteger row = _outlineView.clickedRow;
    if (row < 0) row = [_outlineView rowAtPoint:[_outlineView convertPoint:[NSApp currentEvent].locationInWindow fromView:nil]];
    UDGitItem *item = row >= 0 ? [_outlineView itemAtRow:row] : nil;
    NSString *current = _repository.branch;
    UDGitRef *ref = [item.object isKindOfClass:[UDGitRef class]] ? item.object : nil;
    BOOL isCurrent = item.kind == UDGitItemBranch && [ref.name isEqualToString:current];
    for (NSMenuItem *entry in [self _menuOfItem:item].itemArray) {
        SEL action = entry.action;
        if (isCurrent && (sel_isEqual(action, @selector(switchToRef:)) || sel_isEqual(action, @selector(merge:)) ||
                          sel_isEqual(action, @selector(deleteBranch:)))) {
            continue;
        }
        if (!current && sel_isEqual(action, @selector(merge:))) continue;
        if (!current && item.kind == UDGitItemGroup && sel_isEqual(action, @selector(newBranch:))) continue;
        if (entry.isSeparatorItem && (menu.numberOfItems == 0 || [menu itemAtIndex:menu.numberOfItems - 1].isSeparatorItem)) continue;
        NSMenuItem *copy = [entry copy];
        NSString *title = [copy.title stringByReplacingOccurrencesOfString:@"{name}" withString:ref.name ?: @""];
        copy.title = [title stringByReplacingOccurrencesOfString:@"{current}" withString:current ?: @""];
        copy.representedObject = item.object;
        [menu addItem:copy];
    }
    while (menu.numberOfItems && [menu itemAtIndex:menu.numberOfItems - 1].isSeparatorItem) [menu removeItemAtIndex:menu.numberOfItems - 1];
}

- (IBAction)switchToRef:(NSMenuItem *)sender {
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

- (IBAction)newBranch:(NSMenuItem *)sender {
    UDGitRef *ref = sender.representedObject;
    NSString *from = ref.name ?: _repository.branch ?: @"HEAD";
    NSString *name = UDGitAsk([NSString stringWithFormat:@"New Branch from “%@”", from], @"The new branch is checked out.", @"", @"Create");
    if (name) [_repository createBranch:name fromRef:ref.name checkout:YES target:self action:@selector(_operationDidFinish:)];
}

- (IBAction)renameBranch:(NSMenuItem *)sender {
    UDGitRef *ref = sender.representedObject;
    NSString *name = UDGitAsk([NSString stringWithFormat:@"Rename “%@”", ref.name], nil, ref.name, @"Rename");
    if (name && ![name isEqualToString:ref.name]) [_repository renameBranch:ref.name to:name target:self action:@selector(_operationDidFinish:)];
}

- (IBAction)merge:(NSMenuItem *)sender {
    UDGitRef *ref = sender.representedObject;
    if (UDGitConfirm([NSString stringWithFormat:@"Merge “%@” into “%@”?", ref.name, _repository.branch], nil, @"Merge")) {
        [_repository merge:ref.name target:self action:@selector(_operationDidFinish:)];
    }
}

- (IBAction)newTag:(NSMenuItem *)sender {
    UDGitRef *ref = sender.representedObject;
    NSString *name = UDGitAsk([NSString stringWithFormat:@"New Tag from “%@”", ref.name], nil, @"", @"Create");
    if (name) [_repository createTag:name message:nil atRef:ref.name target:self action:@selector(_operationDidFinish:)];
}

- (IBAction)deleteBranch:(NSMenuItem *)sender {
    UDGitRef *ref = sender.representedObject;
    if (UDGitConfirm([NSString stringWithFormat:@"Delete the branch “%@”?", ref.name], @"This can't be undone.", @"Delete")) {
        [_repository deleteBranch:ref.name force:NO target:self action:@selector(_operationDidFinish:)];
    }
}

- (IBAction)deleteTag:(NSMenuItem *)sender {
    UDGitRef *ref = sender.representedObject;
    if (UDGitConfirm([NSString stringWithFormat:@"Delete the tag “%@”?", ref.name], nil, @"Delete")) {
        [_repository deleteTag:ref.name target:self action:@selector(_operationDidFinish:)];
    }
}

- (IBAction)addRemote:(id)sender {
    NSString *name = UDGitAsk(@"Add Existing Remote", @"The remote's name.", _repository.remotes.count ? @"" : @"origin", @"Next");
    if (!name) return;
    NSString *url = UDGitAsk(@"Add Existing Remote", [NSString stringWithFormat:@"The address of “%@”.", name], @"", @"Add");
    if (url) [_repository addRemote:name url:url target:self action:@selector(_operationDidFinish:)];
}

- (IBAction)removeRemote:(NSMenuItem *)sender {
    UDGitRemote *remote = sender.representedObject;
    if (UDGitConfirm([NSString stringWithFormat:@"Remove the remote “%@”?", remote.name], nil, @"Remove")) {
        [_repository removeRemote:remote.name target:self action:@selector(_operationDidFinish:)];
    }
}

- (IBAction)applyStash:(NSMenuItem *)sender {
    UDGitStash *stash = sender.representedObject;
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = [NSString stringWithFormat:@"Apply “%@”?", stash.message];
    [alert addButtonWithTitle:@"Apply"];
    [alert addButtonWithTitle:@"Cancel"];
    NSButton *keep = UDGitCheckBox(@"Keep the stashed changes");
    alert.accessoryView = keep;
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    [_repository applyStash:stash.index pop:keep.state != NSControlStateValueOn target:self action:@selector(_operationDidFinish:)];
}

- (IBAction)dropStash:(NSMenuItem *)sender {
    UDGitStash *stash = sender.representedObject;
    if (UDGitConfirm([NSString stringWithFormat:@"Delete “%@”?", stash.message], @"This can't be undone.", @"Delete")) {
        [_repository dropStash:stash.index target:self action:@selector(_operationDidFinish:)];
    }
}

@end
