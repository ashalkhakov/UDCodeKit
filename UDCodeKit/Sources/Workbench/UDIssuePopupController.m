/*---------------------------------------------------------------------------------------------
 *  UDIssuePopupController.m
 *--------------------------------------------------------------------------------------------*/

#import "UDIssuePopupController.h"
#import "UDEditorPopup.h"

/// The panel's width, and the most fixes it shows without scrolling.
static const CGFloat UDIssuePopupWidth = 420;
static const NSUInteger UDIssuePopupVisibleFixes = 6;

@implementation UDIssuePopupController {
    NSArray<NSString *> *_fixes;
}

- (instancetype)init {
    return [super initWithNibName:@"UDIssuePopup" bundle:[NSBundle bundleForClass:[UDIssuePopupController class]]];
}

- (NSArray<NSString *> *)fixes {
    return _fixes ?: @[];
}

- (void)showMessage:(NSString *)message fixes:(NSArray<NSString *> *)fixes
   atCharacterIndex:(NSUInteger)characterIndex ofTextView:(NSTextView *)textView {
    (void)self.view;
    _fixes = [fixes copy];
    _messageLabel.stringValue = message ?: @"";
    [_tableView reloadData];
    self.selectedIndex = 0;

    // the message as tall as it wraps to, the fixes below it
    CGFloat margin = 8;
    NSSize messageSize = [_messageLabel.cell cellSizeForBounds:NSMakeRect(0, 0, UDIssuePopupWidth - 2 * margin, 1.0e4)];
    CGFloat rows = (_tableView.rowHeight + _tableView.intercellSpacing.height) * MIN(fixes.count, UDIssuePopupVisibleFixes);
    NSScrollView *scroll = _tableView.enclosingScrollView;
    CGFloat height = margin + rows + 2 + margin + ceil(messageSize.height) + margin;
    [_panel setContentSize:NSMakeSize(UDIssuePopupWidth, height)];
    scroll.frame = NSMakeRect(margin, margin, UDIssuePopupWidth - 2 * margin, rows + 2);
    _messageLabel.frame = NSMakeRect(margin, NSMaxY(scroll.frame) + margin, UDIssuePopupWidth - 2 * margin, ceil(messageSize.height));

    UDShowEditorPopup(_panel, textView, NSMakeRange(characterIndex, 1));
}

- (BOOL)isShown {
    return _panel.isVisible;
}

- (void)setSelectedIndex:(NSUInteger)index {
    if (!_fixes.count) return;
    _selectedIndex = MIN(index, _fixes.count - 1);
    [_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:_selectedIndex] byExtendingSelection:NO];
    [_tableView scrollRowToVisible:(NSInteger)_selectedIndex];
}

- (void)chooseSelectedFix {
    if (_selectedIndex >= _fixes.count) return;
    NSUInteger index = _selectedIndex;
    [self close];
    [_delegate issuePopup:self didChooseFixAtIndex:index];
}

- (IBAction)chooseFix:(id)sender {
    NSInteger row = _tableView.clickedRow >= 0 ? _tableView.clickedRow : _tableView.selectedRow;
    if (row < 0) return;
    _selectedIndex = (NSUInteger)row;
    [self chooseSelectedFix];
}

/// Away, and no longer its window's child.
- (void)close {
    if (_panel.isVisible || _panel.parentWindow) UDHideEditorPopup(_panel);
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)_fixes.count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if ([tableColumn.identifier isEqualToString:@"fix"]) return nil;
    return (NSUInteger)row < _fixes.count ? _fixes[(NSUInteger)row] : @"";
}

@end
