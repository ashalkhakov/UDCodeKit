/*---------------------------------------------------------------------------------------------
 *  UDSourceControlNavigatorViewController.m
 *--------------------------------------------------------------------------------------------*/

#import "UDSourceControlNavigatorViewController.h"
#import "UDBadgeTextFieldCell.h"
#import <objc/runtime.h>

@interface UDSourceControlNavigatorViewController () <NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate>
@property (nonatomic, weak) IBOutlet NSSegmentedControl *tabsControl;
@property (nonatomic, weak) IBOutlet NSView *changesPane;
@property (nonatomic, weak) IBOutlet NSView *repositoriesPane;
@property (nonatomic, weak) IBOutlet NSTextField *statusLabel;
@property (nonatomic, weak) IBOutlet NSTextField *emptyLabel;
@property (nonatomic, weak) IBOutlet NSOutlineView *changesView;
@property (nonatomic, weak) IBOutlet NSTextField *messageField;
@property (nonatomic, weak) IBOutlet NSButton *commitButton;
@property (nonatomic, weak) IBOutlet NSPopUpButton *commitOptionsButton;
/// A file's own items, after the source control's (Show Change, Reveal).
@property (nonatomic, strong) IBOutlet NSMenu *fileMenu;
@end

@implementation UDSourceControlNavigatorViewController {
    NSArray<UDSourceControlResourceGroup *> *_groups;
    UDSourceControlResource *_menuResource;     // what the context menu is about
}

- (instancetype)init {
    return [super initWithNibName:@"UDSourceControlNavigator"
                           bundle:[NSBundle bundleForClass:[UDSourceControlNavigatorViewController class]]];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

// ---------------------------------------------------------------------------
// MARK: - The view (UDSourceControlNavigator.xib)
// ---------------------------------------------------------------------------

- (void)viewDidLoad {
    [super viewDidLoad];
    // as wide as what shows it: the badges at its right edge
    _changesView.frame = _changesView.enclosingScrollView.contentView.bounds;
    [_changesView sizeLastColumnToFit];
    [self _installRepositoriesView];
    [self _reload];
}

- (NSOutlineView *)changesView {
    (void)self.view;
    return _changesView;
}

- (NSTextField *)messageField {
    (void)self.view;
    return _messageField;
}

- (IBAction)tabChanged:(id)sender {
    self.selectedTab = _tabsControl.selectedSegment;
}

- (void)setSelectedTab:(NSInteger)selectedTab {
    (void)self.view;
    _selectedTab = selectedTab;
    _tabsControl.selectedSegment = selectedTab;
    [self _showPanes];
}

- (BOOL)_hasRepositoriesView {
    return [_sourceControl respondsToSelector:@selector(repositoriesViewController)] && [_sourceControl repositoriesViewController];
}

- (void)_showPanes {
    BOOL has = _sourceControl != nil, repositories = [self _hasRepositoriesView];
    _tabsControl.hidden = !has || !repositories;
    _changesPane.hidden = !has || (repositories && _selectedTab != 0);
    _repositoriesPane.hidden = !has || !repositories || _selectedTab != 1;
    _emptyLabel.hidden = has;
}

- (void)focusCommitMessage {
    self.selectedTab = 0;
    [self.view.window makeFirstResponder:_messageField];
}

// ---------------------------------------------------------------------------
// MARK: - The source control
// ---------------------------------------------------------------------------

- (void)setSourceControl:(id<UDSourceControl>)sourceControl {
    if (_sourceControl == sourceControl) return;
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    if (_sourceControl) [center removeObserver:self name:UDSourceControlDidChangeNotification object:_sourceControl];
    _sourceControl = sourceControl;
    if (sourceControl) {
        [center addObserver:self selector:@selector(_sourceControlDidChange:) name:UDSourceControlDidChangeNotification object:sourceControl];
    }
    if (!self.isViewLoaded) return;
    [self _installRepositoriesView];
    [self _reload];
}

/// The provider's Repositories view, in its pane.
- (void)_installRepositoriesView {
    for (NSView *view in [_repositoriesPane.subviews copy]) [view removeFromSuperview];
    if (![self _hasRepositoriesView]) return;
    NSView *view = [_sourceControl repositoriesViewController].view;
    view.frame = _repositoriesPane.bounds;
    view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [_repositoriesPane addSubview:view];
}

- (void)_sourceControlDidChange:(NSNotification *)note {
    [self _reload];
}

- (void)_reload {
    [self _showPanes];
    id<UDSourceControl> sourceControl = _sourceControl;
    NSMutableArray *groups = [NSMutableArray array];
    for (UDSourceControlResourceGroup *group in sourceControl.resourceGroups) {
        if (group.hidesWhenEmpty && group.resources.count == 0) continue;
        [groups addObject:group];
    }
    _statusLabel.stringValue = sourceControl
        ? [NSString stringWithFormat:@"%@ — %@", sourceControl.rootPath.lastPathComponent, sourceControl.statusText] : @"";
    // what was selected, by its path and group, selected again
    NSMutableSet<NSString *> *selected = [NSMutableSet set];
    for (UDSourceControlResource *resource in self.selectedResources) {
        [selected addObject:[NSString stringWithFormat:@"%@\n%@", [self _groupOf:resource].identifier, resource.path]];
    }
    _groups = groups;
    [_changesView reloadData];
    for (UDSourceControlResourceGroup *group in _groups) [_changesView expandItem:group];
    NSMutableIndexSet *rows = [NSMutableIndexSet indexSet];
    for (NSInteger row = 0; row < _changesView.numberOfRows; row++) {
        id item = [_changesView itemAtRow:row];
        if (![item isKindOfClass:[UDSourceControlResource class]]) continue;
        NSString *key = [NSString stringWithFormat:@"%@\n%@", [self _groupOf:item].identifier, [item path]];
        if ([selected containsObject:key]) [rows addIndex:(NSUInteger)row];
    }
    [_changesView selectRowIndexes:rows byExtendingSelection:NO];
}

- (nullable UDSourceControlResourceGroup *)_groupOf:(UDSourceControlResource *)resource {
    for (UDSourceControlResourceGroup *group in _groups) {
        if ([group.resources indexOfObjectIdenticalTo:resource] != NSNotFound) return group;
    }
    return nil;
}

// ---------------------------------------------------------------------------
// MARK: - The outline: its groups, their resources
// ---------------------------------------------------------------------------

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {
    if (!item) return (NSInteger)_groups.count;
    return [item isKindOfClass:[UDSourceControlResourceGroup class]] ? (NSInteger)[item resources].count : 0;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item {
    return item ? [item resources][(NSUInteger)index] : _groups[(NSUInteger)index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    return [item isKindOfClass:[UDSourceControlResourceGroup class]];
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item {
    return [item isKindOfClass:[UDSourceControlResourceGroup class]] ? [item label] : [[item path] lastPathComponent];
}

- (void)outlineView:(NSOutlineView *)outlineView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn item:(id)item {
    BOOL group = [item isKindOfClass:[UDSourceControlResourceGroup class]];
    NSString *badge = nil;
    if (group) {
        NSUInteger count = [item resources].count;
        badge = count ? [NSString stringWithFormat:@"%lu", (unsigned long)count] : nil;
    } else {
        badge = [item letter];
    }
    if ([cell isKindOfClass:[UDBadgeTextFieldCell class]]) [(UDBadgeTextFieldCell *)cell setBadge:badge];
    [cell setFont:group ? [NSFont boldSystemFontOfSize:[NSFont smallSystemFontSize]] : [NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
    [cell setTextColor:!group && [item isDeleted] ? [NSColor disabledControlTextColor] : [NSColor controlTextColor]];
}

- (NSString *)outlineView:(NSOutlineView *)outlineView toolTipForCell:(NSCell *)cell rect:(NSRectPointer)rect
              tableColumn:(NSTableColumn *)tableColumn item:(id)item mouseLocation:(NSPoint)mouseLocation {
    if (![item isKindOfClass:[UDSourceControlResource class]]) return nil;
    UDSourceControlResource *resource = item;
    return [NSString stringWithFormat:@"%@ — %@", resource.path, resource.statusDescription];
}

- (NSArray<UDSourceControlResource *> *)selectedResources {
    NSMutableArray<UDSourceControlResource *> *resources = [NSMutableArray array];
    NSIndexSet *rows = _changesView.selectedRowIndexes;
    for (NSUInteger row = rows.firstIndex; row != NSNotFound; row = [rows indexGreaterThanIndex:row]) {
        id item = [_changesView itemAtRow:(NSInteger)row];
        if ([item isKindOfClass:[UDSourceControlResource class]]) [resources addObject:item];
    }
    return resources;
}

/// The file clicked (or the menu's) shown: its change.
- (IBAction)showChange:(id)sender {
    id item = [sender isKindOfClass:[NSMenuItem class]] ? _menuResource : nil;
    if (!item) {
        NSInteger row = _changesView.clickedRow >= 0 ? _changesView.clickedRow : _changesView.selectedRow;
        item = row >= 0 ? [_changesView itemAtRow:row] : nil;
    }
    if ([item isKindOfClass:[UDSourceControlResource class]]) [_delegate sourceControlNavigator:self openChange:item];
}

// ---------------------------------------------------------------------------
// MARK: - Context menus: the provider's, and Show Change, Reveal
// ---------------------------------------------------------------------------

- (void)menuNeedsUpdate:(NSMenu *)menu {
    if (menu != _changesView.menu) return;
    [menu removeAllItems];
    _menuResource = nil;
    id<UDSourceControl> sourceControl = _sourceControl;
    if (!sourceControl) return;
    NSInteger row = _changesView.clickedRow;
    if (row < 0) row = [_changesView rowAtPoint:[_changesView convertPoint:[NSApp currentEvent].locationInWindow fromView:nil]];
    id item = row >= 0 ? [_changesView itemAtRow:row] : nil;
    if ([item isKindOfClass:[UDSourceControlResourceGroup class]]) {
        for (NSMenuItem *entry in [sourceControl menuItemsForGroup:item]) [menu addItem:entry];
        return;
    }
    if (![item isKindOfClass:[UDSourceControlResource class]]) return;
    // the clicked file, or the selection it is in
    NSArray<UDSourceControlResource *> *resources = self.selectedResources;
    if (![resources containsObject:item]) resources = @[ item ];
    for (NSMenuItem *entry in [sourceControl menuItemsForResources:resources]) [menu addItem:entry];
    // then the file's own, from the XIB
    _menuResource = item;
    [menu addItem:[NSMenuItem separatorItem]];
    for (NSMenuItem *entry in _fileMenu.itemArray) [menu addItem:[entry copy]];
}

- (IBAction)revealInProjectNavigator:(id)sender {
    if (_menuResource) [_delegate sourceControlNavigator:self revealInProjectNavigator:_menuResource.path];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    if (sel_isEqual(item.action, @selector(revealInProjectNavigator:))) {
        return _menuResource && [_delegate respondsToSelector:@selector(sourceControlNavigator:revealInProjectNavigator:)];
    }
    return YES;
}

// ---------------------------------------------------------------------------
// MARK: - Committing
// ---------------------------------------------------------------------------

- (void)_didCommit:(UDSourceControlResult *)result {
    if (result.succeeded) _messageField.stringValue = @"";
}

- (void)_commitWithOptions:(UDSourceControlCommitOptions)options {
    NSString *message = [_messageField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!(options & UDSourceControlCommitAmend) && message.length == 0) {
        NSBeep();
        [self focusCommitMessage];
        return;
    }
    [_sourceControl commitWithMessage:message options:options target:self action:@selector(_didCommit:)];
}

- (IBAction)commit:(id)sender {
    [self _commitWithOptions:0];
}

- (IBAction)commitAndPush:(id)sender {
    [self _commitWithOptions:UDSourceControlCommitPush];
}

- (IBAction)amend:(id)sender {
    [self _commitWithOptions:UDSourceControlCommitAmend];
}

@end
