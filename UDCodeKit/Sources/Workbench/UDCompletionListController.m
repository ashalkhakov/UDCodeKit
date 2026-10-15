/*---------------------------------------------------------------------------------------------
 *  UDCompletionListController.m
 *--------------------------------------------------------------------------------------------*/

#import "UDCompletionListController.h"
#import "UDEditorPopup.h"

/// At most this many rows show at once; the rest scroll.
static const NSUInteger UDCompletionVisibleRows = 10;

@implementation UDCompletionListController

- (instancetype)init {
    return [super initWithWindowNibName:@"UDCompletionList" owner:self];
}

// The XIB is UDCodeKit's, not the app's.
- (NSString *)windowNibPath {
    return [[NSBundle bundleForClass:[UDCompletionListController class]] pathForResource:@"UDCompletionList" ofType:@"nib"]
        ?: [[NSBundle bundleForClass:[UDCompletionListController class]] pathForResource:@"UDCompletionList" ofType:@"xib"];
}

- (void)showItems:(NSArray<NSString *> *)items atRange:(NSRange)range ofTextView:(NSTextView *)textView {
    (void)self.window;
    _items = [items copy];
    [_tableView reloadData];

    // As tall as the items, up to a limit; as wide as the longest.
    NSUInteger rows = MIN(MAX(items.count, 1u), UDCompletionVisibleRows);
    CGFloat rowHeight = _tableView.rowHeight + _tableView.intercellSpacing.height;
    NSDictionary *attributes = @{ NSFontAttributeName: ((NSCell *)((NSTableColumn *)_tableView.tableColumns.firstObject).dataCell).font ?: [NSFont systemFontOfSize:0] };
    CGFloat width = 160;
    for (NSString *item in items) width = MAX(width, [item sizeWithAttributes:attributes].width + 40);
    [self.window setContentSize:NSMakeSize(MIN(width, 480), rows * rowHeight + 4)];

    [self _select:items.count > 0 ? 0 : NSNotFound];
    UDShowEditorPopup(self.window, textView, range);
}

- (BOOL)isShown {
    return self.isWindowLoaded && self.window.isVisible;
}

- (void)close {
    if (self.isShown) UDHideEditorPopup(self.window);
}

- (NSUInteger)selectedIndex {
    NSInteger row = _tableView.selectedRow;
    return row < 0 ? NSNotFound : (NSUInteger)row;
}

- (NSString *)selectedItem {
    NSUInteger index = self.selectedIndex;
    return index < _items.count ? _items[index] : nil;
}

- (void)_select:(NSUInteger)index {
    if (index == NSNotFound || index >= _items.count) {
        [_tableView deselectAll:nil];
        return;
    }
    [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
    [_tableView scrollRowToVisible:(NSInteger)index];
}

- (void)_move:(NSInteger)rows {
    if (_items.count == 0) return;
    NSInteger index = self.selectedIndex == NSNotFound ? 0 : (NSInteger)self.selectedIndex + rows;
    [self _select:(NSUInteger)MAX(0, MIN(index, (NSInteger)_items.count - 1))];
}

- (BOOL)handleKeyEvent:(NSEvent *)event {
    if (!self.isShown) return NO;
    NSString *characters = event.charactersIgnoringModifiers;
    unichar c = characters.length ? [characters characterAtIndex:0] : 0;
    switch (c) {
        case NSUpArrowFunctionKey:   [self _move:-1]; return YES;
        case NSDownArrowFunctionKey: [self _move:1];  return YES;
        case NSPageUpFunctionKey:    [self _move:-(NSInteger)UDCompletionVisibleRows]; return YES;
        case NSPageDownFunctionKey:  [self _move:(NSInteger)UDCompletionVisibleRows];  return YES;
        case '\r': case '\n': case '\t': case 3:            // 3: the keypad's Enter
            if (self.selectedItem == nil) return NO;
            [self acceptSelection:nil];
            return YES;
        case 27:
            [self close];
            return YES;
    }
    return NO;
}

- (IBAction)acceptSelection:(id)sender {
    if (self.selectedItem == nil) return;
    id target = self.target;
    SEL action = self.action;
    [self close];
    if (target != nil && action != NULL) [NSApp sendAction:action to:target from:self];
}

#pragma mark - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)_items.count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    return row >= 0 && (NSUInteger)row < _items.count ? _items[(NSUInteger)row] : nil;
}

@end
