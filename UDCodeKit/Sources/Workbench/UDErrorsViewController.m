/*---------------------------------------------------------------------------------------------
 *  UDErrorsViewController.m
 *--------------------------------------------------------------------------------------------*/

#import "UDErrorsViewController.h"

static NSString *UDIssueMark(UDDiagnosticSeverity severity);
static NSColor *UDIssueColor(UDDiagnosticSeverity severity);
static NSString *UDIssueCounts(NSArray<UDDiagnosticItem *> *diagnostics);

/// The separator colour; GNUstep's NSColor has no -separatorColor.
static NSColor *UDSeparatorColor(void) {
#ifdef __APPLE__
    return [NSColor separatorColor];
#else
    return [NSColor gridColor];
#endif
}

// ---------------------------------------------------------------------------
// MARK: - UDErrorsEntry  (private model object for one file group)
// ---------------------------------------------------------------------------

/// Represents one open document in the outline view.  Acts as the level-0
/// item identity object that NSOutlineView tracks.
@interface UDErrorsEntry : NSObject

@property (nonatomic, copy)   NSString                          *displayName;
@property (nonatomic, strong) UDDiagnosticStore                 *store;
@property (nonatomic, copy)   NSArray<UDDiagnosticItem *>       *diagnostics;

- (instancetype)initWithDisplayName:(NSString *)displayName
                              store:(UDDiagnosticStore *)store;
@end

@implementation UDErrorsEntry

- (instancetype)initWithDisplayName:(NSString *)displayName
                              store:(UDDiagnosticStore *)store {
    self = [super init];
    if (self) {
        _displayName = [displayName copy];
        _store       = store;
        _diagnostics = [store.allDiagnostics copy];
    }
    return self;
}

@end

// ---------------------------------------------------------------------------
// MARK: - Private container view (draws a 1-px right-side separator)
// ---------------------------------------------------------------------------

@interface UDErrorsPanelContainerView : NSView
@end

@implementation UDErrorsPanelContainerView

- (void)drawRect:(NSRect)dirtyRect {
    [[NSColor windowBackgroundColor] setFill];
    NSRectFill(self.bounds);
    // 1-px right border matching the visual style of the existing gutters.
    [UDSeparatorColor() setFill];
    NSRectFill(NSMakeRect(NSWidth(self.bounds) - 1.0, 0.0, 1.0, NSHeight(self.bounds)));
}

@end

// ---------------------------------------------------------------------------
// MARK: - UDErrorsViewController
// ---------------------------------------------------------------------------

@interface UDErrorsViewController ()
/// Ordered list of file-group entries, one per unique open document.
@property (nonatomic, strong) NSMutableArray<UDErrorsEntry *> *entries;
@property (nonatomic, weak) IBOutlet NSOutlineView            *outlineView;
@end

@implementation UDErrorsViewController

// ---------------------------------------------------------------------------
// MARK: - Init / dealloc
// ---------------------------------------------------------------------------

- (instancetype)init {
    self = [super initWithNibName:@"UDErrorsView" bundle:[NSBundle bundleForClass:[UDErrorsViewController class]]];
    if (self) {
        _entries = [NSMutableArray array];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

// ---------------------------------------------------------------------------
// MARK: - Public API
// ---------------------------------------------------------------------------

- (void)setStores:(NSArray<UDDiagnosticStore *> *)stores
     displayNames:(NSArray<NSString *> *)displayNames {

    // Unsubscribe from every previously observed store.
    for (UDErrorsEntry *entry in _entries) {
        [[NSNotificationCenter defaultCenter]
            removeObserver:self
                      name:UDDiagnosticsDidChangeNotification
                    object:entry.store];
    }

    // Build de-duplicated entries (first occurrence of each store wins).
    NSMutableArray<UDErrorsEntry *> *newEntries = [NSMutableArray array];
    NSMutableSet<UDDiagnosticStore *> *seen = [NSMutableSet set];
    NSUInteger n = MIN(stores.count, displayNames.count);

    for (NSUInteger i = 0; i < n; i++) {
        UDDiagnosticStore *store = stores[i];
        if ([seen containsObject:store]) continue;
        [seen addObject:store];

        NSString *name = displayNames[i] ?: @"Untitled";
        [newEntries addObject:[[UDErrorsEntry alloc] initWithDisplayName:name store:store]];

        [[NSNotificationCenter defaultCenter]
            addObserver:self
               selector:@selector(_diagnosticsDidChange:)
                   name:UDDiagnosticsDidChangeNotification
                 object:store];
    }

    _entries = newEntries;
    [self _reloadAndExpand];
}

// ---------------------------------------------------------------------------
// MARK: - Notification handler
// ---------------------------------------------------------------------------

- (void)_diagnosticsDidChange:(NSNotification *)note {
    UDDiagnosticStore *store = (UDDiagnosticStore *)note.object;
    for (UDErrorsEntry *entry in _entries) {
        if (entry.store == store) {
            entry.diagnostics = [store.allDiagnostics copy];
            break;
        }
    }
    [self _reloadAndExpand];
}

// ---------------------------------------------------------------------------
// MARK: - Private helpers
// ---------------------------------------------------------------------------

- (void)_reloadAndExpand {
    [_outlineView reloadData];
    for (UDErrorsEntry *entry in _entries) {
        [_outlineView expandItem:entry];
    }
}

// ---------------------------------------------------------------------------
// MARK: - NSOutlineViewDataSource
// ---------------------------------------------------------------------------

- (NSInteger)outlineView:(NSOutlineView *)outlineView
  numberOfChildrenOfItem:(nullable id)item {
    if (item == nil)
        return (NSInteger)_entries.count;
    if ([item isKindOfClass:[UDErrorsEntry class]])
        return (NSInteger)((UDErrorsEntry *)item).diagnostics.count;
    return 0;
}

- (id)outlineView:(NSOutlineView *)outlineView
            child:(NSInteger)index
           ofItem:(nullable id)item {
    if (item == nil)
        return _entries[(NSUInteger)index];
    return ((UDErrorsEntry *)item).diagnostics[(NSUInteger)index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    return [item isKindOfClass:[UDErrorsEntry class]];
}

// ---------------------------------------------------------------------------
// MARK: - NSOutlineViewDelegate
// ---------------------------------------------------------------------------

// A cell-based outline: GNUstep makes a view-based one's rows by copying
// the prototype, and its NSView copy keeps no subviews (gnustep-patches#26):
// rows came out empty.

- (nullable id)outlineView:(NSOutlineView *)outlineView
 objectValueForTableColumn:(nullable NSTableColumn *)tableColumn
                    byItem:(nullable id)item {
    if ([item isKindOfClass:[UDErrorsEntry class]]) {
        // File-group row: "<filename> (1 error, 2 warnings)".
        UDErrorsEntry *entry = (UDErrorsEntry *)item;
        NSString *counts = UDIssueCounts(entry.diagnostics);
        return counts.length ? [NSString stringWithFormat:@"%@ (%@)", entry.displayName, counts] : entry.displayName;
    }
    // An issue's row, as Xcode's: its mark (an error's red, a warning's
    // yellow), "Line L: message"
    UDDiagnosticItem *diag = (UDDiagnosticItem *)item;
    NSMutableAttributedString *row = [[NSMutableAttributedString alloc]
        initWithString:[UDIssueMark(diag.severity) stringByAppendingString:@" "]
            attributes:@{ NSForegroundColorAttributeName: UDIssueColor(diag.severity),
                          NSFontAttributeName: [NSFont systemFontOfSize:NSFont.smallSystemFontSize] }];
    [row appendAttributedString:[[NSAttributedString alloc]
        initWithString:[NSString stringWithFormat:@"Line %ld: %@", (long)diag.line, diag.message]
            attributes:@{ NSForegroundColorAttributeName: [NSColor labelColor],
                          NSFontAttributeName: [NSFont systemFontOfSize:NSFont.smallSystemFontSize] }]];
    return row;
}

/// An issue's mark: an error's ●, a warning's ▲, a note's ◆.
static NSString *UDIssueMark(UDDiagnosticSeverity severity) {
    switch (severity) {
        case UDDiagnosticSeverityError: return @"\u25CF";
        case UDDiagnosticSeverityWarning: return @"\u25B2";
        default: return @"\u25C6";
    }
}

static NSColor *UDIssueColor(UDDiagnosticSeverity severity) {
    switch (severity) {
        case UDDiagnosticSeverityError: return [NSColor systemRedColor];
        case UDDiagnosticSeverityWarning: return [NSColor colorWithCalibratedRed:0.85 green:0.65 blue:0.0 alpha:1];
        default: return [NSColor secondaryLabelColor];
    }
}

/// "1 error, 2 warnings": what a file's issues are, by severity.
static NSString *UDIssueCounts(NSArray<UDDiagnosticItem *> *diagnostics) {
    NSUInteger errors = 0, warnings = 0, others = 0;
    for (UDDiagnosticItem *diagnostic in diagnostics) {
        if (diagnostic.severity == UDDiagnosticSeverityError) errors++;
        else if (diagnostic.severity == UDDiagnosticSeverityWarning) warnings++;
        else others++;
    }
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    if (errors) [parts addObject:[NSString stringWithFormat:@"%lu error%@", (unsigned long)errors, errors == 1 ? @"" : @"s"]];
    if (warnings) [parts addObject:[NSString stringWithFormat:@"%lu warning%@", (unsigned long)warnings, warnings == 1 ? @"" : @"s"]];
    if (others) [parts addObject:[NSString stringWithFormat:@"%lu note%@", (unsigned long)others, others == 1 ? @"" : @"s"]];
    return [parts componentsJoinedByString:@", "];
}

/// Not edited: a double-click (which GNUstep starts editing with) goes to the issue.
- (BOOL)outlineView:(NSOutlineView *)outlineView shouldEditTableColumn:(nullable NSTableColumn *)tableColumn item:(id)item {
    return NO;
}

// File-group rows bold: red with an error among them, else secondary; issue rows as their marks colour them.
- (void)outlineView:(NSOutlineView *)outlineView
    willDisplayCell:(id)cell
     forTableColumn:(nullable NSTableColumn *)tableColumn
               item:(id)item {
    if (![cell isKindOfClass:[NSTextFieldCell class]]) return;
    NSTextFieldCell *text = cell;
    if ([item isKindOfClass:[UDErrorsEntry class]]) {
        text.font      = [NSFont boldSystemFontOfSize:NSFont.smallSystemFontSize];
        BOOL errors = NO;
        for (UDDiagnosticItem *diagnostic in ((UDErrorsEntry *)item).diagnostics) {
            errors = errors || diagnostic.severity == UDDiagnosticSeverityError;
        }
        text.textColor = errors ? [NSColor systemRedColor] : [NSColor secondaryLabelColor];
    } else {
        text.font      = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    }
}

- (CGFloat)outlineView:(NSOutlineView *)outlineView heightOfRowByItem:(id)item {
    return 18.0;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldSelectItem:(id)item {
    // Allow selection of individual error items; disallow file-group rows.
    return [item isKindOfClass:[UDDiagnosticItem class]];
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification {
    NSInteger row = [_outlineView selectedRow];
    if (row < 0) return;

    id item = [_outlineView itemAtRow:row];
    if (![item isKindOfClass:[UDDiagnosticItem class]]) return;

    UDDiagnosticItem *diagnostic = (UDDiagnosticItem *)item;
    // The outline view already tracks parent–child relationships; this is O(1).
    UDErrorsEntry *entry = [_outlineView parentForItem:diagnostic];
    if (!entry) return;

    id<UDErrorsViewControllerDelegate> delegate = _delegate;
    if ([delegate respondsToSelector:
            @selector(errorsViewController:didSelectDiagnostic:inStore:)]) {
        [delegate errorsViewController:self
                   didSelectDiagnostic:diagnostic
                               inStore:entry.store];
    }
}

@end
