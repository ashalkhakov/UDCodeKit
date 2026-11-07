/*---------------------------------------------------------------------------------------------
 *  UDTreeView.m
 *--------------------------------------------------------------------------------------------*/

#import "UDTreeView.h"
#import "UDWorkbench.h"
#import "UDBadgeTextFieldCell.h"

@implementation UDTreeItem
+ (instancetype)itemWithLabel:(NSString *)label {
    UDTreeItem *item = [[self alloc] init];
    item.label = label;
    return item;
}
@end

/// An element of the outline, its item, and its children once asked for.
@interface UDTreeNode : NSObject
@property (nonatomic, strong) id element;
@property (nonatomic, strong) UDTreeItem *item;
@property (nonatomic, weak, nullable) UDTreeNode *parent;
/// Its item's identifier, else its parent's key and its label.
@property (nonatomic, copy) NSString *key;
/// nil: not asked for yet.
@property (nonatomic, copy, nullable) NSArray<UDTreeNode *> *children;
@end

@implementation UDTreeNode
@end

@interface UDTreeViewController ()
@property (nonatomic, weak) IBOutlet NSOutlineView *outlineView;
@property (nonatomic, weak) IBOutlet NSSearchField *filterField;
@property (nonatomic, weak) IBOutlet NSScrollView *scrollView;
@end

@implementation UDTreeViewController {
    NSArray<UDTreeNode *> *_roots;            // nil: not asked for yet
    NSMutableSet<NSString *> *_expandedKeys;  // what is shown open
    NSMutableSet<NSString *> *_seenKeys;      // what was shown before (an Expanded item opened once)
    BOOL _restoring;                          // expanding and selecting what was: no choices made
}

- (instancetype)initWithDataProvider:(id<UDTreeDataProvider>)provider workbench:(id<UDWorkbench>)workbench title:(NSString *)title {
    self = [super initWithNibName:@"UDTreeView" bundle:[NSBundle bundleForClass:[UDTreeViewController class]]];
    if (!self) return nil;
    _dataProvider = provider;
    _workbench = workbench;
    _expandedKeys = [NSMutableSet set];
    _seenKeys = [NSMutableSet set];
    self.title = title;
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];
    menu.delegate = self;
    _outlineView.menu = menu;
    // no filter of the provider's: the outline the whole height
    if (![_dataProvider respondsToSelector:@selector(treeView:filterDidChange:)]) {
        _filterField.hidden = YES;
        NSRect frame = _scrollView.frame;
        frame.size.height = NSMaxY(frame);
        frame.origin.y = 0;
        _scrollView.frame = frame;
    }
}

// ---------------------------------------------------------------------------
// MARK: - Nodes
// ---------------------------------------------------------------------------

- (NSArray<UDTreeNode *> *)_nodesOf:(NSArray *)elements parent:(nullable UDTreeNode *)parent {
    NSMutableArray<UDTreeNode *> *nodes = [NSMutableArray arrayWithCapacity:elements.count];
    for (id element in elements) {
        UDTreeNode *node = [[UDTreeNode alloc] init];
        node.element = element;
        node.parent = parent;
        [self _setItemOf:node];
        [nodes addObject:node];
    }
    return nodes;
}

- (void)_setItemOf:(UDTreeNode *)node {
    node.item = [_dataProvider treeView:self itemForElement:node.element] ?: [UDTreeItem itemWithLabel:@""];
    node.key = node.item.identifier ?: [NSString stringWithFormat:@"%@/%@", node.parent.key ?: @"", node.item.label];
    if (![_seenKeys containsObject:node.key]) {
        [_seenKeys addObject:node.key];
        if (node.item.collapsibleState == UDTreeItemCollapsibleStateExpanded) [_expandedKeys addObject:node.key];
    }
}

- (NSArray<UDTreeNode *> *)_childrenOf:(nullable UDTreeNode *)node {
    if (!node) {
        if (!_roots) _roots = [self _nodesOf:[_dataProvider treeView:self childrenOfElement:nil] ?: @[] parent:nil];
        return _roots;
    }
    if (!node.children) {
        node.children = node.item.collapsibleState == UDTreeItemCollapsibleStateNone ? @[] :
                        [self _nodesOf:[_dataProvider treeView:self childrenOfElement:node.element] ?: @[] parent:node];
    }
    return node.children;
}

/// The node of @a element among those asked for, under @a nodes.
- (nullable UDTreeNode *)_nodeOf:(id)element in:(nullable NSArray<UDTreeNode *> *)nodes {
    for (UDTreeNode *node in nodes) {
        if ([node.element isEqual:element]) return node;
        UDTreeNode *found = [self _nodeOf:element in:node.children];
        if (found) return found;
    }
    return nil;
}

- (nullable UDTreeNode *)_nodeOfRow:(NSInteger)row {
    return row >= 0 && row < _outlineView.numberOfRows ? [_outlineView itemAtRow:row] : nil;
}

// ---------------------------------------------------------------------------
// MARK: - Refreshing
// ---------------------------------------------------------------------------

- (void)refresh {
    [self refreshElement:nil];
}

- (void)refreshElement:(nullable id)element {
    [self view];
    NSMutableSet<NSString *> *selected = [NSMutableSet set];
    [_outlineView.selectedRowIndexes enumerateIndexesUsingBlock:^(NSUInteger row, BOOL *stop) {
        [selected addObject:[self _nodeOfRow:(NSInteger)row].key];
    }];
    UDTreeNode *node = element ? [self _nodeOf:element in:_roots] : nil;
    _restoring = YES;
    if (node) {
        [self _setItemOf:node];
        node.children = nil;
        [_outlineView reloadItem:node reloadChildren:YES];
    } else {
        _roots = nil;
        [_outlineView reloadData];
    }
    // what was open, opened; what was selected, selected
    for (NSInteger row = 0; row < _outlineView.numberOfRows; row++) {
        UDTreeNode *shown = [self _nodeOfRow:row];
        if ([_expandedKeys containsObject:shown.key] && ![_outlineView isItemExpanded:shown]) [_outlineView expandItem:shown];
    }
    NSMutableIndexSet *rows = [NSMutableIndexSet indexSet];
    for (NSInteger row = 0; row < _outlineView.numberOfRows; row++) {
        if ([selected containsObject:[self _nodeOfRow:row].key]) [rows addIndex:(NSUInteger)row];
    }
    [_outlineView selectRowIndexes:rows byExtendingSelection:NO];
    _restoring = NO;
}

// ---------------------------------------------------------------------------
// MARK: - Selection, choosing, revealing
// ---------------------------------------------------------------------------

- (NSArray *)selectedElements {
    NSMutableArray *elements = [NSMutableArray array];
    [_outlineView.selectedRowIndexes enumerateIndexesUsingBlock:^(NSUInteger row, BOOL *stop) {
        UDTreeNode *node = [self _nodeOfRow:(NSInteger)row];
        if (node) [elements addObject:node.element];
    }];
    return elements;
}

/// @a node chosen: its item's command sent; NO when it has none.
- (BOOL)_choose:(UDTreeNode *)node {
    SEL action = node.item.action;
    if (!action) return NO;
    id target = node.item.target ?: self;
    if (![target respondsToSelector:action]) return NO;
    _chosenElement = node.element;
    [NSApp sendAction:action to:target from:self];
    _chosenElement = nil;
    return YES;
}

- (IBAction)openResource:(id)sender {
    UDTreeNode *node = _chosenElement ? [self _nodeOf:_chosenElement in:_roots] : nil;
    NSURL *url = node.item.resourceURL;
    if (url) [_workbench showURL:url];
}

- (IBAction)chooseSelectedElement:(id)sender {
    NSInteger row = _outlineView.clickedRow >= 0 ? _outlineView.clickedRow : _outlineView.selectedRow;
    UDTreeNode *node = [self _nodeOfRow:row];
    if (!node) return;
    if ([self _choose:node]) return;
    // no command: a folder's, opened or closed
    if (node.item.collapsibleState == UDTreeItemCollapsibleStateNone) return;
    if ([_outlineView isItemExpanded:node]) [_outlineView collapseItem:node];
    else [_outlineView expandItem:node];
}

- (BOOL)revealElement:(id)element {
    [self view];
    NSMutableArray *chain = [NSMutableArray arrayWithObject:element];
    if ([_dataProvider respondsToSelector:@selector(treeView:parentOfElement:)]) {
        for (id parent = [_dataProvider treeView:self parentOfElement:element]; parent;
             parent = [_dataProvider treeView:self parentOfElement:parent]) {
            [chain insertObject:parent atIndex:0];
        }
    }
    UDTreeNode *node = nil;
    for (id link in chain) {
        UDTreeNode *found = nil;
        for (UDTreeNode *child in [self _childrenOf:node]) {
            if ([child.element isEqual:link]) { found = child; break; }
        }
        if (!found) return NO;
        if (node) [_outlineView expandItem:node];
        node = found;
    }
    NSInteger row = [_outlineView rowForItem:node];
    if (row < 0) return NO;
    _restoring = YES;
    [_outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
    _restoring = NO;
    [_outlineView scrollRowToVisible:row];
    return YES;
}

- (IBAction)filterChanged:(id)sender {
    if ([_dataProvider respondsToSelector:@selector(treeView:filterDidChange:)]) {
        [_dataProvider treeView:self filterDidChange:_filterField.stringValue ?: @""];
    }
}

// ---------------------------------------------------------------------------
// MARK: - The context menu: the provider's, its items copied
// ---------------------------------------------------------------------------

- (void)menuNeedsUpdate:(NSMenu *)menu {
    [menu removeAllItems];
    if (![_dataProvider respondsToSelector:@selector(treeView:menuForElements:)]) return;
    NSInteger row = _outlineView.clickedRow;
    if (row < 0) {
        NSPoint point = [_outlineView convertPoint:[NSApp currentEvent].locationInWindow fromView:nil];
        row = [_outlineView rowAtPoint:point];
    }
    UDTreeNode *clicked = [self _nodeOfRow:row];
    if (!clicked) return;
    // the selection, when the click is in it; else the one clicked
    NSArray *elements = [_outlineView isRowSelected:row] ? self.selectedElements : @[ clicked.element ];
    NSMenu *provided = [_dataProvider treeView:self menuForElements:elements];
    for (NSMenuItem *item in provided.itemArray) [menu addItem:[item copy]];
}

// ---------------------------------------------------------------------------
// MARK: - NSOutlineViewDataSource, NSOutlineViewDelegate
// ---------------------------------------------------------------------------

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {
    return (NSInteger)[self _childrenOf:item].count;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item {
    return [self _childrenOf:item][(NSUInteger)index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    return ((UDTreeNode *)item).item.collapsibleState != UDTreeItemCollapsibleStateNone;
}

// A cell-based outline, as the other navigators'.
- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item {
    return ((UDTreeNode *)item).item.label;
}

- (void)outlineView:(NSOutlineView *)outlineView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn item:(id)item {
    if (![cell isKindOfClass:[UDBadgeTextFieldCell class]]) return;
    UDTreeItem *shown = ((UDTreeNode *)item).item;
    [(UDBadgeTextFieldCell *)cell setBadge:shown.detail];
    [(UDBadgeTextFieldCell *)cell setLeadingImage:shown.image];
}

- (NSString *)outlineView:(NSOutlineView *)outlineView toolTipForCell:(NSCell *)cell rect:(NSRectPointer)rect
              tableColumn:(NSTableColumn *)tableColumn item:(id)item mouseLocation:(NSPoint)mouseLocation {
    return ((UDTreeNode *)item).item.toolTip ?: @"";
}

- (void)outlineViewItemDidExpand:(NSNotification *)note {
    UDTreeNode *node = note.userInfo[@"NSObject"];
    if (node.key) [_expandedKeys addObject:node.key];
}

- (void)outlineViewItemDidCollapse:(NSNotification *)note {
    UDTreeNode *node = note.userInfo[@"NSObject"];
    if (node.key) [_expandedKeys removeObject:node.key];
}

/// An element selected by the keyboard or a click is chosen, as the file
/// navigator's files are; not when what was selected is selected again.
- (void)outlineViewSelectionDidChange:(NSNotification *)notification {
    if (_restoring || _outlineView.selectedRowIndexes.count != 1) return;
    UDTreeNode *node = [self _nodeOfRow:_outlineView.selectedRow];
    if (node) [self _choose:node];
}

@end
