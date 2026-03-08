/*---------------------------------------------------------------------------------------------
 *  UDErrorsViewController.m
 *--------------------------------------------------------------------------------------------*/

#import "UDErrorsViewController.h"
#import <tree_sitter/api.h>

// Tree-sitter stores column offsets as UTF-16 code-unit counts (2 bytes per
// BMP code unit; surrogate pairs use 4 bytes for supplementary characters).
// Dividing by 2 gives the 0-based character column for ASCII/BMP-only content.
static inline NSInteger columnFromTSColumn(uint32_t col) { return (NSInteger)(col / 2); }

/// The single root item shown in the outline view.
static NSString * const kFileGroupItem = @"current.json";

/// Maximum number of errors collected (mirrors VS Code's maxNumberOfProblems).
static const NSUInteger kMaxParseErrors = 100;

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
    [[NSColor separatorColor] setFill];
    NSRectFill(NSMakeRect(NSWidth(self.bounds) - 1.0, 0.0, 1.0, NSHeight(self.bounds)));
}

@end

// ---------------------------------------------------------------------------
// MARK: - UDErrorsViewController
// ---------------------------------------------------------------------------

@interface UDErrorsViewController ()
@property (nonatomic, weak)   UDDiagnosticStore                 *diagnosticStore;
@property (nonatomic, weak) IBOutlet NSOutlineView              *outlineView;
@property (nonatomic, strong) NSArray<UDDiagnosticItem *>       *diagnostics;

@end

@implementation UDErrorsViewController

// ---------------------------------------------------------------------------
// MARK: - Init
// ---------------------------------------------------------------------------

- (instancetype)initWithDiagnosticStore:(UDDiagnosticStore *)store {
    self = [super initWithNibName:@"UDErrorsView" bundle:nil];
    if (self) {
        _diagnosticStore = store;
        
        // 19. Diagnostic-store change notification.
        [[NSNotificationCenter defaultCenter]
            addObserver:self
               selector:@selector(_diagnosticsDidChange:)
                   name:UDDiagnosticsDidChangeNotification
                 object:_diagnosticStore];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

// ---------------------------------------------------------------------------
// MARK: - Parse-tree scanning
// ---------------------------------------------------------------------------

- (void)_diagnosticsDidChange:(NSNotification *)note {
    // note.object is _diagnosticStore.
    NSArray<UDDiagnosticItem *> *all = _diagnosticStore.allDiagnostics;

    self.diagnostics = [all copy];
    [_outlineView reloadData];
    [_outlineView expandItem:kFileGroupItem];
}

// ---------------------------------------------------------------------------
// MARK: - NSOutlineViewDataSource
// ---------------------------------------------------------------------------

- (NSInteger)outlineView:(NSOutlineView *)outlineView
  numberOfChildrenOfItem:(nullable id)item {
    if (item == nil)                           return 1;   // one file group
    if ([item isKindOfClass:[NSString class]]) return (NSInteger)_diagnostics.count;
    return 0;
}

- (id)outlineView:(NSOutlineView *)outlineView
            child:(NSInteger)index
           ofItem:(nullable id)item {
    if (item == nil) return kFileGroupItem;
    return _diagnostics[(NSUInteger)index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    return [item isKindOfClass:[NSString class]];
}

// ---------------------------------------------------------------------------
// MARK: - NSOutlineViewDelegate
// ---------------------------------------------------------------------------

- (nullable NSView *)outlineView:(NSOutlineView *)outlineView
              viewForTableColumn:(nullable NSTableColumn *)tableColumn
                            item:(id)item {
    static NSString * const kCellID = @"UDErrorCell";
    NSTableCellView *cell = [outlineView makeViewWithIdentifier:kCellID owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
        NSTextField *tf = [NSTextField labelWithString:@""];
        tf.translatesAutoresizingMaskIntoConstraints = NO;
        tf.lineBreakMode = NSLineBreakByTruncatingTail;
        [cell addSubview:tf];
        [NSLayoutConstraint activateConstraints:@[
            [tf.leadingAnchor  constraintEqualToAnchor:cell.leadingAnchor  constant:2.0],
            [tf.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-2.0],
            [tf.centerYAnchor  constraintEqualToAnchor:cell.centerYAnchor],
        ]];
        cell.textField  = tf;
        cell.identifier = kCellID;
    }

    if ([item isKindOfClass:[NSString class]]) {
        // File-group row: "current.json (N error(s))"
        NSUInteger count = _diagnostics.count;
        NSString *label;
        if (count == 0) {
            label = (NSString *)item;
        } else {
            label = [NSString stringWithFormat:@"%@ (%lu %@)",
                     (NSString *)item,
                     (unsigned long)count,
                     count == 1 ? @"error" : @"errors"];
        }
        cell.textField.stringValue = label;
        cell.textField.font        = [NSFont boldSystemFontOfSize:NSFont.smallSystemFontSize];
        cell.textField.textColor   = (count > 0)
            ? [NSColor systemRedColor] : [NSColor secondaryLabelColor];
    } else {
        // Error row: "Line L: message"
        UDDiagnosticItem *diag = (UDDiagnosticItem *)item;
        cell.textField.stringValue =
            [NSString stringWithFormat:@"Line %ld: %@", (long)diag.line, diag.message];
        cell.textField.font      = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
        cell.textField.textColor = [NSColor labelColor];
    }

    return cell;
}

- (CGFloat)outlineView:(NSOutlineView *)outlineView heightOfRowByItem:(id)item {
    return 18.0;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldSelectItem:(id)item {
    // Allow selection of individual error items; disallow the file-group row.
    return [item isKindOfClass:[UDDiagnosticItem class]];
}

@end
