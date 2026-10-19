/*---------------------------------------------------------------------------------------------
 *  UDTestNavigatorViewController.m
 *--------------------------------------------------------------------------------------------*/

#import "UDTestNavigatorViewController.h"

@interface UDTestNavigatorViewController ()
@property (nonatomic, weak) IBOutlet NSOutlineView *outlineView;
@property (nonatomic, weak) IBOutlet NSTextField *summaryLabel;
@end

/// A status's mark and its colour.
static NSString *UDTestMark(UDTestStatus status) {
    switch (status) {
        case UDTestStatusPassed: return @"✓";
        case UDTestStatusFailed: return @"✗";
        case UDTestStatusRunning: return @"◌";
        default: return @"◇";
    }
}

static NSColor *UDTestColor(UDTestStatus status) {
    switch (status) {
        case UDTestStatusPassed: return [NSColor colorWithCalibratedRed:0.15 green:0.6 blue:0.2 alpha:1];
        case UDTestStatusFailed: return [NSColor systemRedColor];
        case UDTestStatusRunning: return [NSColor systemBlueColor];
        default: return [NSColor secondaryLabelColor];
    }
}

@implementation UDTestNavigatorViewController

- (instancetype)init {
    return [super initWithNibName:@"UDTestNavigator" bundle:[NSBundle bundleForClass:[UDTestNavigatorViewController class]]];
}

- (void)setCatalog:(UDTestCatalog *)catalog {
    _catalog = catalog;
    (void)self.view;
    [_outlineView reloadData];
    for (UDTestSuite *suite in _catalog.suites) [_outlineView expandItem:suite];
    [self _updateSummary];
}

- (void)reload {
    [_outlineView reloadData];
    for (UDTestSuite *suite in _catalog.suites) [_outlineView expandItem:suite];
    [self _updateSummary];
}

- (void)_updateSummary {
    NSUInteger tests = _catalog.allTests.count, passed = _catalog.passedCount, failed = _catalog.failedCount;
    if (!tests) {
        _summaryLabel.stringValue = @"No tests";
    } else if (passed + failed == 0) {
        _summaryLabel.stringValue = [NSString stringWithFormat:@"%lu test%@", (unsigned long)tests, tests == 1 ? @"" : @"s"];
    } else {
        _summaryLabel.stringValue = [NSString stringWithFormat:@"%lu passed, %lu failed, of %lu", (unsigned long)passed,
                                     (unsigned long)failed, (unsigned long)tests];
    }
}

// ---------------------------------------------------------------------------
// MARK: - The outline
// ---------------------------------------------------------------------------

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {
    if (!item) return (NSInteger)_catalog.suites.count;
    return [item isKindOfClass:[UDTestSuite class]] ? (NSInteger)((UDTestSuite *)item).tests.count : 0;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item {
    return item ? ((UDTestSuite *)item).tests[(NSUInteger)index] : _catalog.suites[(NSUInteger)index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    return [item isKindOfClass:[UDTestSuite class]];
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item {
    BOOL suite = [item isKindOfClass:[UDTestSuite class]];
    UDTestStatus status = suite ? ((UDTestSuite *)item).status : ((UDTest *)item).status;
    NSFont *font = suite ? [NSFont boldSystemFontOfSize:NSFont.smallSystemFontSize] : [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    NSMutableAttributedString *row = [[NSMutableAttributedString alloc]
        initWithString:[UDTestMark(status) stringByAppendingString:@" "]
            attributes:@{ NSForegroundColorAttributeName: UDTestColor(status), NSFontAttributeName: font }];
    NSString *name = suite ? ((UDTestSuite *)item).name : ((UDTest *)item).name;
    [row appendAttributedString:[[NSAttributedString alloc] initWithString:name
        attributes:@{ NSForegroundColorAttributeName: [NSColor labelColor], NSFontAttributeName: font }]];
    return row;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldEditTableColumn:(NSTableColumn *)tableColumn item:(id)item {
    return NO;
}

- (NSString *)outlineView:(NSOutlineView *)outlineView toolTipForCell:(NSCell *)cell rect:(NSRectPointer)rect
              tableColumn:(NSTableColumn *)tableColumn item:(id)item mouseLocation:(NSPoint)mouseLocation {
    NSArray<NSString *> *failures = [item isKindOfClass:[UDTest class]] ? ((UDTest *)item).failures : ((UDTestSuite *)item).failures;
    return [failures componentsJoinedByString:@"\n"];
}

- (NSString *)textOfRow:(NSInteger)row {
    id item = [_outlineView itemAtRow:row];
    id value = item ? [self outlineView:_outlineView objectValueForTableColumn:nil byItem:item] : nil;
    return [value isKindOfClass:[NSAttributedString class]] ? [value string] : @"";
}

/// Chosen: its place.
- (void)outlineViewSelectionDidChange:(NSNotification *)notification {
    id item = _outlineView.selectedRow >= 0 ? [_outlineView itemAtRow:_outlineView.selectedRow] : nil;
    NSString *path = [item isKindOfClass:[UDTest class]] ? ((UDTest *)item).path : ((UDTestSuite *)item).path;
    NSInteger line = [item isKindOfClass:[UDTest class]] ? ((UDTest *)item).line : ((UDTestSuite *)item).line;
    if (path) [_delegate testNavigator:self showPath:path line:MAX(line, 1)];
}

// ---------------------------------------------------------------------------
// MARK: - Running
// ---------------------------------------------------------------------------

- (NSArray<UDTest *> *)selectedTests {
    NSInteger row = _outlineView.clickedRow >= 0 ? _outlineView.clickedRow : _outlineView.selectedRow;
    id item = row >= 0 ? [_outlineView itemAtRow:row] : nil;
    if ([item isKindOfClass:[UDTestSuite class]]) return ((UDTestSuite *)item).tests;
    return item ? @[ item ] : @[];
}

- (IBAction)runSelected:(id)sender {
    NSArray<UDTest *> *tests = self.selectedTests;
    [_delegate testNavigator:self runTests:tests.count ? tests : nil debugging:NO];
}

- (IBAction)debugSelected:(id)sender {
    NSArray<UDTest *> *tests = self.selectedTests;
    [_delegate testNavigator:self runTests:tests.count ? tests : nil debugging:YES];
}

/// The context menu's items name what they run.
- (void)menuNeedsUpdate:(NSMenu *)menu {
    NSInteger row = _outlineView.clickedRow;
    id item = row >= 0 ? [_outlineView itemAtRow:row] : nil;
    NSString *name = [item isKindOfClass:[UDTest class]] ? ((UDTest *)item).name
                   : [item isKindOfClass:[UDTestSuite class]] ? ((UDTestSuite *)item).name : @"All Tests";
    if (menu.itemArray.count >= 2) {
        [[menu itemAtIndex:0] setTitle:[NSString stringWithFormat:@"Run “%@”", name]];
        [[menu itemAtIndex:1] setTitle:[NSString stringWithFormat:@"Debug “%@”", name]];
    }
}

@end
