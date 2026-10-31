/*---------------------------------------------------------------------------------------------
 *  UDSourceControlNavigatorViewController.m
 *--------------------------------------------------------------------------------------------*/

#import "UDSourceControlNavigatorViewController.h"
#import "UDBadgeTextFieldCell.h"

// GNUstep has AppKit's older names
#ifdef __APPLE__
#define UDTexturedRoundedBezel NSBezelStyleTexturedRounded
#define UDRoundedBezel NSBezelStyleRounded
#else
#define UDTexturedRoundedBezel NSTexturedRoundedBezelStyle
#define UDRoundedBezel NSRoundedBezelStyle
#endif

@interface UDSourceControlNavigatorViewController () <NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate>
@end

@implementation UDSourceControlNavigatorViewController {
    NSSegmentedControl *_tabs;
    NSView *_changesPane, *_repositoriesPane;
    NSTextField *_statusLabel, *_emptyLabel;
    NSButton *_commitButton;
    NSPopUpButton *_commitOptions;
    NSOutlineView *_changesView;
    NSTextField *_messageField;
    NSArray<UDSourceControlResourceGroup *> *_groups;
}

- (instancetype)init {
    return [super initWithNibName:nil bundle:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

// ---------------------------------------------------------------------------
// MARK: - The view
// ---------------------------------------------------------------------------

- (void)loadView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 240, 700)];
    view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    CGFloat width = NSWidth(view.bounds), height = NSHeight(view.bounds);

    _tabs = [NSSegmentedControl segmentedControlWithLabels:@[ @"Changes", @"Repositories" ]
                                              trackingMode:NSSegmentSwitchTrackingSelectOne
                                                    target:self action:@selector(_tabChanged:)];
    _tabs.frame = NSMakeRect(8, height - 28, width - 16, 24);
    _tabs.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    _tabs.selectedSegment = 0;
    [view addSubview:_tabs];

    NSRect paneFrame = NSMakeRect(0, 0, width, height - 32);

    // Changes: where it is, the files, the commit
    _changesPane = [[NSView alloc] initWithFrame:paneFrame];
    _changesPane.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _statusLabel = [NSTextField labelWithString:@""];
    _statusLabel.frame = NSMakeRect(8, NSHeight(paneFrame) - 20, width - 16, 16);
    _statusLabel.font = [NSFont boldSystemFontOfSize:[NSFont smallSystemFontSize]];
    [_statusLabel.cell setLineBreakMode:NSLineBreakByTruncatingTail];
    _statusLabel.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin;
    [_changesPane addSubview:_statusLabel];

    const CGFloat commitHeight = 96;
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, commitHeight, width, NSHeight(paneFrame) - commitHeight - 24)];
    scroll.hasVerticalScroller = YES;
    scroll.autohidesScrollers = YES;
    scroll.borderType = NSNoBorder;
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _changesView = [[NSOutlineView alloc] initWithFrame:scroll.bounds];
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    UDBadgeTextFieldCell *cell = [[UDBadgeTextFieldCell alloc] initTextCell:@""];
    cell.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
    cell.lineBreakMode = NSLineBreakByTruncatingMiddle;
    cell.editable = NO;
    column.dataCell = cell;
    column.width = width - 16;
    column.resizingMask = NSTableColumnAutoresizingMask;
    [_changesView addTableColumn:column];
    _changesView.outlineTableColumn = column;
    _changesView.headerView = nil;
    _changesView.rowHeight = 18;
    _changesView.indentationPerLevel = 12;
    _changesView.columnAutoresizingStyle = NSTableViewLastColumnOnlyAutoresizingStyle;
    _changesView.allowsMultipleSelection = YES;
    _changesView.dataSource = self;
    _changesView.delegate = self;
    _changesView.target = self;
    _changesView.action = @selector(_openSelectedChange:);
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];
    menu.delegate = self;
    _changesView.menu = menu;
    scroll.documentView = _changesView;
    // as wide as what shows it: the badges at its right edge
    _changesView.autoresizingMask = NSViewWidthSizable;
    _changesView.frame = scroll.contentView.bounds;
    [_changesView sizeLastColumnToFit];
    [_changesPane addSubview:scroll];

    _messageField = [[NSTextField alloc] initWithFrame:NSMakeRect(8, 36, width - 16, 56)];
    _messageField.placeholderString = @"Commit message (required)";
    _messageField.font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
    [_messageField.cell setWraps:YES];
    [_messageField.cell setScrollable:NO];
    [_messageField.cell setUsesSingleLineMode:NO];
    _messageField.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    [_changesPane addSubview:_messageField];

    _commitButton = [[NSButton alloc] initWithFrame:NSMakeRect(width - 8 - 120, 6, 90, 26)];
    _commitButton.title = @"Commit";
    _commitButton.bezelStyle = UDRoundedBezel;
    _commitButton.target = self;
    _commitButton.action = @selector(commit:);
    _commitButton.keyEquivalent = @"\r";
    _commitButton.keyEquivalentModifierMask = NSEventModifierFlagCommand;
    _commitButton.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
    [_changesPane addSubview:_commitButton];

    _commitOptions = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(width - 8 - 30, 6, 30, 26) pullsDown:YES];
    _commitOptions.bezelStyle = UDTexturedRoundedBezel;
    [_commitOptions addItemWithTitle:@""];                    // a pull-down's title
    for (NSArray *option in @[ @[ @"Commit and Push", NSStringFromSelector(@selector(commitAndPush:)) ],
                               @[ @"Amend", NSStringFromSelector(@selector(amend:)) ] ]) {
        NSMenuItem *item = [_commitOptions.menu addItemWithTitle:option[0] action:NSSelectorFromString(option[1]) keyEquivalent:@""];
        item.target = self;
    }
    _commitOptions.autoresizingMask = NSViewMinXMargin | NSViewMaxYMargin;
    [_changesPane addSubview:_commitOptions];
    [view addSubview:_changesPane];

    // Repositories: the provider's view
    _repositoriesPane = [[NSView alloc] initWithFrame:paneFrame];
    _repositoriesPane.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _repositoriesPane.hidden = YES;
    [view addSubview:_repositoriesPane];

    // none: said so (Integrate > New Git Repository… makes one)
    _emptyLabel = [NSTextField labelWithString:@"No Source Control"];
    _emptyLabel.alignment = NSTextAlignmentCenter;
    _emptyLabel.textColor = [NSColor disabledControlTextColor];
    _emptyLabel.frame = NSMakeRect(8, height / 2, width - 16, 18);
    _emptyLabel.autoresizingMask = NSViewWidthSizable | NSViewMinYMargin | NSViewMaxYMargin;
    [view addSubview:_emptyLabel];

    self.view = view;
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

- (void)_tabChanged:(id)sender {
    self.selectedTab = _tabs.selectedSegment;
}

- (void)setSelectedTab:(NSInteger)selectedTab {
    (void)self.view;
    _selectedTab = selectedTab;
    _tabs.selectedSegment = selectedTab;
    [self _showPanes];
}

- (BOOL)_hasRepositoriesView {
    return [_sourceControl respondsToSelector:@selector(repositoriesViewController)] && [_sourceControl repositoriesViewController];
}

- (void)_showPanes {
    BOOL has = _sourceControl != nil, repositories = [self _hasRepositoriesView];
    _tabs.hidden = !has || !repositories;
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

- (void)_openSelectedChange:(id)sender {
    NSInteger row = _changesView.clickedRow >= 0 ? _changesView.clickedRow : _changesView.selectedRow;
    id item = row >= 0 ? [_changesView itemAtRow:row] : nil;
    if ([item isKindOfClass:[UDSourceControlResource class]]) [_delegate sourceControlNavigator:self openChange:item];
}

// ---------------------------------------------------------------------------
// MARK: - Context menus: the provider's, and Show Change, Reveal
// ---------------------------------------------------------------------------

- (void)menuNeedsUpdate:(NSMenu *)menu {
    [menu removeAllItems];
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
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *show = [menu addItemWithTitle:@"Show Change" action:@selector(_openSelectedChange:) keyEquivalent:@""];
    show.target = self;
    if ([_delegate respondsToSelector:@selector(sourceControlNavigator:revealInProjectNavigator:)]) {
        NSMenuItem *reveal = [menu addItemWithTitle:@"Reveal in Project Navigator" action:@selector(_reveal:) keyEquivalent:@""];
        reveal.target = self;
        reveal.representedObject = [item path];
    }
}

- (void)_reveal:(NSMenuItem *)sender {
    [_delegate sourceControlNavigator:self revealInProjectNavigator:sender.representedObject];
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
