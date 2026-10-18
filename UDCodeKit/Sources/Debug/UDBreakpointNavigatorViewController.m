/*---------------------------------------------------------------------------------------------
 *  UDBreakpointNavigatorViewController.m
 *--------------------------------------------------------------------------------------------*/

#import "UDBreakpointNavigatorViewController.h"
#import <objc/runtime.h>

/// A file's row: its breakpoints under it.
@interface UDBreakpointFileRow : NSObject
@property (nonatomic, copy) NSString *path;
@property (nonatomic, copy) NSArray<UDBreakpoint *> *breakpoints;
@end

@implementation UDBreakpointFileRow
@end

/// An exception filter's row: the adapter's ExceptionBreakpointsFilter.
@interface UDExceptionFilterRow : NSObject
@property (nonatomic, copy) NSDictionary *filter;
@end

@implementation UDExceptionFilterRow
@end

@interface UDBreakpointNavigatorViewController ()
@property (nonatomic, weak) IBOutlet NSOutlineView *outlineView;
@property (nonatomic, weak) IBOutlet NSButton *removeButton;
@end

@implementation UDBreakpointNavigatorViewController {
    NSArray *_rows;                              // the filters' rows, then the files'
    NSMutableSet<NSString *> *_collapsedFiles;   // the files closed by hand
    BOOL _reloading;
    id _menuItem;                                // what the context menu is about
}

- (instancetype)init {
    self = [super initWithNibName:@"UDBreakpointNavigator"
                           bundle:[NSBundle bundleForClass:[UDBreakpointNavigatorViewController class]]];
    if (self) {
        _rows = @[];
        _collapsedFiles = [NSMutableSet set];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self _updateButtons];
}

- (void)setBreakpoints:(UDBreakpointStore *)breakpoints {
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    if (_breakpoints) [center removeObserver:self name:nil object:_breakpoints];
    _breakpoints = breakpoints;
    if (breakpoints) {
        [center addObserver:self selector:@selector(_storeDidChange:)
                       name:UDBreakpointStoreDidChangeNotification object:breakpoints];
        [center addObserver:self selector:@selector(_storeDidChange:)
                       name:UDBreakpointStoreDidChangeExceptionFiltersNotification object:breakpoints];
    }
    (void)self.view;
    [self _reload];
}

- (void)_storeDidChange:(NSNotification *)note {
    [self _reload];
}

/// The rows again, the files open but those closed by hand, the selection
/// kept on the breakpoint it was on.
- (void)_reload {
    id selected = _outlineView.selectedRow >= 0 ? [_outlineView itemAtRow:_outlineView.selectedRow] : nil;
    NSMutableArray *rows = [NSMutableArray array];
    for (NSDictionary *filter in _breakpoints.exceptionFilters) {
        UDExceptionFilterRow *row = [[UDExceptionFilterRow alloc] init];
        row.filter = filter;
        [rows addObject:row];
    }
    for (NSString *path in _breakpoints.files) {
        UDBreakpointFileRow *row = [[UDBreakpointFileRow alloc] init];
        row.path = path;
        row.breakpoints = [_breakpoints breakpointsInFile:path];
        [rows addObject:row];
    }
    _rows = rows;
    _reloading = YES;
    [_outlineView reloadData];
    for (id row in _rows) {
        if ([row isKindOfClass:[UDBreakpointFileRow class]] && ![_collapsedFiles containsObject:[row path]]) {
            [_outlineView expandItem:row];
        }
    }
    NSInteger index = [selected isKindOfClass:[UDBreakpoint class]] ? [_outlineView rowForItem:selected] : -1;
    if (index >= 0) [_outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)index] byExtendingSelection:NO];
    else [_outlineView deselectAll:nil];
    _reloading = NO;
    [self _updateButtons];
}

- (UDBreakpoint *)breakpointOfRow:(NSInteger)row {
    id item = row >= 0 ? [_outlineView itemAtRow:row] : nil;
    return [item isKindOfClass:[UDBreakpoint class]] ? item : nil;
}

- (NSString *)exceptionFilterOfRow:(NSInteger)row {
    id item = row >= 0 ? [_outlineView itemAtRow:row] : nil;
    return [item isKindOfClass:[UDExceptionFilterRow class]] ? ((UDExceptionFilterRow *)item).filter[@"filter"] : nil;
}

// ---------------------------------------------------------------------------
// MARK: - NSOutlineViewDataSource
// ---------------------------------------------------------------------------

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {
    if (item == nil) return (NSInteger)_rows.count;
    if ([item isKindOfClass:[UDBreakpointFileRow class]]) return (NSInteger)((UDBreakpointFileRow *)item).breakpoints.count;
    return 0;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item {
    if (item == nil) return _rows[(NSUInteger)index];
    return ((UDBreakpointFileRow *)item).breakpoints[(NSUInteger)index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    return [item isKindOfClass:[UDBreakpointFileRow class]];
}

/// What a breakpoint does besides stopping, as VS Code says it.
static NSString *UDBreakpointTitle(UDBreakpoint *breakpoint) {
    NSMutableString *title = [NSMutableString stringWithFormat:@"Line %ld", (long)breakpoint.line];
    if (breakpoint.condition) [title appendFormat:@"  ·  Condition: %@", breakpoint.condition];
    if (breakpoint.hitCondition) [title appendFormat:@"  ·  Hit Count: %@", breakpoint.hitCondition];
    if (breakpoint.logMessage) [title appendFormat:@"  ·  Log: %@", breakpoint.logMessage];
    return title;
}

// A cell-based outline, as the debug navigator's (gnustep-patches#26).
- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item {
    BOOL check = [tableColumn.identifier isEqualToString:@"enabled"];
    if ([item isKindOfClass:[UDExceptionFilterRow class]]) {
        NSDictionary *filter = ((UDExceptionFilterRow *)item).filter;
        if (check) return @([_breakpoints isExceptionFilterEnabled:filter[@"filter"]]);
        return [filter[@"label"] isKindOfClass:[NSString class]] ? filter[@"label"] : filter[@"filter"];
    }
    if ([item isKindOfClass:[UDBreakpointFileRow class]]) {
        return check ? @NO : [((UDBreakpointFileRow *)item).path lastPathComponent];
    }
    UDBreakpoint *breakpoint = item;
    return check ? @(breakpoint.enabled) : UDBreakpointTitle(breakpoint);
}

/// A check box clicked: the breakpoint, or the filter, on or off.
- (void)outlineView:(NSOutlineView *)outlineView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn
             byItem:(id)item {
    if (![tableColumn.identifier isEqualToString:@"enabled"]) return;
    BOOL on = [object boolValue];
    if ([item isKindOfClass:[UDBreakpoint class]]) {
        [_breakpoints setBreakpoint:item enabled:on];
    } else if ([item isKindOfClass:[UDExceptionFilterRow class]]) {
        [_breakpoints setExceptionFilter:((UDExceptionFilterRow *)item).filter[@"filter"] enabled:on];
    }
}

// ---------------------------------------------------------------------------
// MARK: - NSOutlineViewDelegate
// ---------------------------------------------------------------------------

/// Only the check boxes, and not a file's.
- (BOOL)outlineView:(NSOutlineView *)outlineView shouldEditTableColumn:(NSTableColumn *)tableColumn item:(id)item {
    return [tableColumn.identifier isEqualToString:@"enabled"] && ![item isKindOfClass:[UDBreakpointFileRow class]];
}

/// Files bold, without a check box; a breakpoint not bound grey.
- (void)outlineView:(NSOutlineView *)outlineView willDisplayCell:(id)cell
     forTableColumn:(NSTableColumn *)tableColumn item:(id)item {
    BOOL file = [item isKindOfClass:[UDBreakpointFileRow class]];
    if ([cell isKindOfClass:[NSButtonCell class]]) {
        [(NSButtonCell *)cell setTransparent:file];
        [(NSButtonCell *)cell setEnabled:!file];
        return;
    }
    if (![cell isKindOfClass:[NSTextFieldCell class]]) return;
    NSTextFieldCell *text = cell;
    text.font = file ? [NSFont boldSystemFontOfSize:NSFont.smallSystemFontSize]
                     : [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    BOOL unbound = [item isKindOfClass:[UDBreakpoint class]] && ((UDBreakpoint *)item).enabled && !((UDBreakpoint *)item).verified;
    text.textColor = unbound ? [NSColor secondaryLabelColor] : [NSColor controlTextColor];
}

- (NSString *)outlineView:(NSOutlineView *)outlineView toolTipForCell:(NSCell *)cell rect:(NSRectPointer)rect
              tableColumn:(NSTableColumn *)tableColumn item:(id)item mouseLocation:(NSPoint)mouseLocation {
    if ([item isKindOfClass:[UDBreakpointFileRow class]]) return ((UDBreakpointFileRow *)item).path;
    if ([item isKindOfClass:[UDExceptionFilterRow class]]) {
        NSString *description = ((UDExceptionFilterRow *)item).filter[@"description"];
        return [description isKindOfClass:[NSString class]] ? description : nil;
    }
    UDBreakpoint *breakpoint = item;
    return breakpoint.message ?: [NSString stringWithFormat:@"%@:%ld", breakpoint.path, (long)breakpoint.line];
}

- (void)outlineViewItemDidCollapse:(NSNotification *)note {
    UDBreakpointFileRow *row = note.userInfo[@"NSObject"];
    if (!_reloading && [row isKindOfClass:[UDBreakpointFileRow class]]) [_collapsedFiles addObject:row.path];
}

- (void)outlineViewItemDidExpand:(NSNotification *)note {
    UDBreakpointFileRow *row = note.userInfo[@"NSObject"];
    if ([row isKindOfClass:[UDBreakpointFileRow class]]) [_collapsedFiles removeObject:row.path];
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification {
    [self _updateButtons];
}

// ---------------------------------------------------------------------------
// MARK: - Actions
// ---------------------------------------------------------------------------

- (void)_updateButtons {
    _removeButton.enabled = [self breakpointOfRow:_outlineView.selectedRow] != nil;
}

/// The context menu is about the row clicked (GNUstep's tables do not say
/// which: the event does).
- (void)menuNeedsUpdate:(NSMenu *)menu {
    NSInteger row = _outlineView.clickedRow;
    if (row < 0) {
        NSEvent *event = [NSApp currentEvent];
        if (event.window == _outlineView.window) {
            row = [_outlineView rowAtPoint:[_outlineView convertPoint:event.locationInWindow fromView:nil]];
        }
    }
    _menuItem = row >= 0 ? [_outlineView itemAtRow:row] : nil;
}

/// What an action is about: the context menu's row, the double-clicked
/// one, or the selected one.
- (nullable UDBreakpoint *)_targetOf:(id)sender {
    id item = nil;
    if ([sender isKindOfClass:[NSMenuItem class]] && [(NSMenuItem *)sender menu] == _outlineView.menu && _menuItem) {
        item = _menuItem;
    } else if (sender == _outlineView && _outlineView.clickedRow >= 0) {
        item = [_outlineView itemAtRow:_outlineView.clickedRow];
    } else if (_outlineView.selectedRow >= 0) {
        item = [_outlineView itemAtRow:_outlineView.selectedRow];
    }
    return [item isKindOfClass:[UDBreakpoint class]] ? item : nil;
}

- (IBAction)showBreakpoint:(id)sender {
    UDBreakpoint *breakpoint = [self _targetOf:sender];
    id<UDBreakpointNavigatorDelegate> delegate = _delegate;
    if (breakpoint && [delegate respondsToSelector:@selector(breakpointNavigator:showBreakpoint:)]) {
        [delegate breakpointNavigator:self showBreakpoint:breakpoint];
    }
}

- (IBAction)editBreakpoint:(id)sender {
    UDBreakpoint *breakpoint = [self _targetOf:sender];
    id<UDBreakpointNavigatorDelegate> delegate = _delegate;
    if (breakpoint && [delegate respondsToSelector:@selector(breakpointNavigator:editBreakpoint:)]) {
        [delegate breakpointNavigator:self editBreakpoint:breakpoint];
    }
}

- (IBAction)toggleBreakpointEnabled:(id)sender {
    UDBreakpoint *breakpoint = [self _targetOf:sender];
    if (breakpoint) [_breakpoints setBreakpoint:breakpoint enabled:!breakpoint.enabled];
}

- (IBAction)deleteBreakpoint:(id)sender {
    UDBreakpoint *breakpoint = [self _targetOf:sender];
    if (breakpoint) [_breakpoints removeBreakpoint:breakpoint];
}

- (IBAction)enableAllBreakpoints:(id)sender  { [_breakpoints setAllBreakpointsEnabled:YES]; }
- (IBAction)disableAllBreakpoints:(id)sender { [_breakpoints setAllBreakpointsEnabled:NO]; }
- (IBAction)deleteAllBreakpoints:(id)sender  { [_breakpoints removeAllBreakpoints]; }

/// sel_isEqual: on GNUstep a XIB's selector is another pointer.
- (BOOL)validateMenuItem:(NSMenuItem *)item {
    SEL action = item.action;
    UDBreakpoint *breakpoint = [self _targetOf:item];
    if (sel_isEqual(action, @selector(toggleBreakpointEnabled:))) {
        item.title = breakpoint && !breakpoint.enabled ? @"Enable Breakpoint" : @"Disable Breakpoint";
        return breakpoint != nil;
    }
    if (sel_isEqual(action, @selector(showBreakpoint:))) {
        return breakpoint && [_delegate respondsToSelector:@selector(breakpointNavigator:showBreakpoint:)];
    }
    if (sel_isEqual(action, @selector(editBreakpoint:))) {
        return breakpoint && [_delegate respondsToSelector:@selector(breakpointNavigator:editBreakpoint:)];
    }
    if (sel_isEqual(action, @selector(deleteBreakpoint:))) return breakpoint != nil;
    if (sel_isEqual(action, @selector(enableAllBreakpoints:)) || sel_isEqual(action, @selector(disableAllBreakpoints:)) ||
        sel_isEqual(action, @selector(deleteAllBreakpoints:))) {
        return _breakpoints.files.count > 0;
    }
    return YES;
}

@end
