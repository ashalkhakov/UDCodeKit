/*---------------------------------------------------------------------------------------------
 *  UDEditorTabsController.m
 *--------------------------------------------------------------------------------------------*/

#import "UDEditorTabsController.h"

@implementation UDEditorTabsController {
    NSMapTable<UDTabBarItem *, NSViewController *> *_controllers;
    NSMapTable<UDTabBarItem *, NSTabViewItem *> *_pages;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    _controllers = [NSMapTable strongToStrongObjectsMapTable];
    _pages = [NSMapTable strongToStrongObjectsMapTable];
    return self;
}

- (void)setTabBar:(UDTabBarView *)tabBar {
    _tabBar = tabBar;
    tabBar.delegate = self;
}

- (void)awakeFromNib {
    [super awakeFromNib];
    _tabBar.delegate = self;
}

- (NSArray<UDTabBarItem *> *)items {
    return _tabBar.items ?: @[];
}

- (UDTabBarItem *)selectedItem {
    return _tabBar.selectedItem;
}

- (UDTabBarItem *)addItemWithTitle:(NSString *)title
                 representedObject:(id)representedObject
                    viewController:(NSViewController *)viewController {
    UDTabBarItem *item = [UDTabBarItem itemWithTitle:title representedObject:representedObject];
    NSTabViewItem *page = [[NSTabViewItem alloc] initWithIdentifier:item];
    page.label = title;
    page.view = viewController.view;
    [_controllers setObject:viewController forKey:item];
    [_pages setObject:page forKey:item];
    [_tabView addTabViewItem:page];
    [_tabBar addItem:item];
    [self selectItem:item];
    return item;
}

- (NSViewController *)viewControllerForItem:(UDTabBarItem *)item {
    return [_controllers objectForKey:item];
}

- (UDTabBarItem *)itemWithRepresentedObject:(id)representedObject {
    return [_tabBar itemWithRepresentedObject:representedObject];
}

- (void)selectItem:(UDTabBarItem *)item {
    NSTabViewItem *page = [_pages objectForKey:item];
    if (!page) return;
    _tabBar.selectedItem = item;
    [_tabView selectTabViewItem:page];
    if ([_delegate respondsToSelector:@selector(editorTabs:didSelectItem:)]) {
        [_delegate editorTabs:self didSelectItem:item];
    }
}

- (BOOL)closeItem:(UDTabBarItem *)item {
    if (item.pinned || ![_pages objectForKey:item]) return NO;
    if ([_delegate respondsToSelector:@selector(editorTabs:shouldCloseItem:)] &&
        ![_delegate editorTabs:self shouldCloseItem:item]) {
        return NO;
    }
    [self removeItem:item];
    return YES;
}

- (void)removeItem:(UDTabBarItem *)item {
    NSTabViewItem *page = [_pages objectForKey:item];
    if (!page) return;
    NSArray<UDTabBarItem *> *items = self.items;
    NSUInteger index = [items indexOfObject:item];
    BOOL wasSelected = _tabBar.selectedItem == item;

    [_tabBar removeItem:item];
    [_tabView removeTabViewItem:page];
    [_pages removeObjectForKey:item];
    [_controllers removeObjectForKey:item];
    if ([_delegate respondsToSelector:@selector(editorTabs:didCloseItem:)]) {
        [_delegate editorTabs:self didCloseItem:item];
    }

    // The neighbour takes its place, as in Xcode: the next tab, or the one before.
    if (wasSelected) {
        NSArray<UDTabBarItem *> *left = self.items;
        if (left.count) {
            [self selectItem:left[MIN(index, left.count - 1)]];
        } else if ([_delegate respondsToSelector:@selector(editorTabs:didSelectItem:)]) {
            [_delegate editorTabs:self didSelectItem:nil];
        }
    }
}

- (IBAction)closeSelectedTab:(id)sender {
    UDTabBarItem *item = self.selectedItem;
    if (item) [self closeItem:item];
}

- (void)_selectBy:(NSInteger)step {
    NSArray<UDTabBarItem *> *items = self.items;
    if (items.count < 2) return;
    NSUInteger index = [items indexOfObject:self.selectedItem];
    if (index == NSNotFound) index = 0;
    NSInteger next = ((NSInteger)index + step + (NSInteger)items.count) % (NSInteger)items.count;
    [self selectItem:items[(NSUInteger)next]];
}

- (IBAction)selectNextTab:(id)sender     { [self _selectBy:1]; }
- (IBAction)selectPreviousTab:(id)sender { [self _selectBy:-1]; }

// ---------------------------------------------------------------------------
// MARK: - UDTabBarViewDelegate
// ---------------------------------------------------------------------------

- (void)tabBarView:(UDTabBarView *)tabBarView didSelectItem:(UDTabBarItem *)item {
    [self selectItem:item];
}

- (void)tabBarView:(UDTabBarView *)tabBarView requestsCloseForItem:(UDTabBarItem *)item {
    [self closeItem:item];
}

@end
