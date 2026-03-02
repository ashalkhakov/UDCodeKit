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
@property (nonatomic, weak)   UDTreeSitterHighlighter    *highlighter;
@property (nonatomic, strong) NSOutlineView              *outlineView;
@property (nonatomic, copy)   NSArray<UDParseErrorItem *> *errors;
@end

@implementation UDErrorsViewController

// ---------------------------------------------------------------------------
// MARK: - Init
// ---------------------------------------------------------------------------

- (instancetype)initWithHighlighter:(UDTreeSitterHighlighter *)highlighter {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _highlighter = highlighter;
        _errors      = @[];
    }
    return self;
}

// ---------------------------------------------------------------------------
// MARK: - View loading
// ---------------------------------------------------------------------------

- (void)loadView {
    UDErrorsPanelContainerView *container =
        [[UDErrorsPanelContainerView alloc] initWithFrame:NSZeroRect];

    // --- Outline view ---
    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"main"];
    col.resizingMask = NSTableColumnAutoresizingMask;

    _outlineView = [[NSOutlineView alloc] initWithFrame:NSZeroRect];
    _outlineView.headerView                  = nil;
    _outlineView.rowSizeStyle                = NSTableViewRowSizeStyleSmall;
    [_outlineView addTableColumn:col];
    _outlineView.outlineTableColumn          = col;
    _outlineView.dataSource                  = self;
    _outlineView.delegate                    = self;
    _outlineView.selectionHighlightStyle     = NSTableViewSelectionHighlightStyleSourceList;
    _outlineView.allowsEmptySelection        = YES;
    _outlineView.indentationPerLevel         = 10.0;
    _outlineView.backgroundColor             = [NSColor controlBackgroundColor];

    // --- Scroll view ---
    NSScrollView *sv = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    sv.documentView          = _outlineView;
    sv.hasVerticalScroller   = YES;
    sv.hasHorizontalScroller = NO;
    sv.autohidesScrollers    = YES;
    sv.borderType            = NSNoBorder;
    sv.autoresizingMask      = NSViewWidthSizable | NSViewHeightSizable;
    sv.frame                 = container.bounds;
    [container addSubview:sv];

    self.view = container;
}

// ---------------------------------------------------------------------------
// MARK: - Public API
// ---------------------------------------------------------------------------

- (void)update {
    _errors = [self _scanErrors];
    [_outlineView reloadData];
    [_outlineView expandItem:kFileGroupItem];
}

// ---------------------------------------------------------------------------
// MARK: - Parse-tree scanning
// ---------------------------------------------------------------------------

- (NSArray<UDParseErrorItem *> *)_scanErrors {
    const TSTree *tree = (const TSTree *)_highlighter.currentParseTree;
    if (!tree) return @[];

    NSMutableArray<UDParseErrorItem *> *result = [NSMutableArray array];
    TSNode root    = ts_tree_root_node((TSTree *)tree);
    NSUInteger budget = kMaxParseErrors;
    [self _collectErrors:root budget:&budget into:result];
    return result;
}

- (void)_collectErrors:(TSNode)node
                budget:(NSUInteger *)budget
                  into:(NSMutableArray<UDParseErrorItem *> *)out {
    if (*budget == 0) return;

    // Prune subtrees that contain no errors.
    if (!ts_node_is_error(node) && !ts_node_is_missing(node) &&
        !ts_node_has_error(node)) {
        return;
    }

    if (ts_node_is_error(node)) {
        TSPoint pt = ts_node_start_point(node);
        [out addObject:[[UDParseErrorItem alloc]
                            initWithLine:(NSInteger)pt.row + 1
                                  column:columnFromTSColumn(pt.column)
                                 message:@"Unexpected token"]];
        (*budget)--;
        // Still recurse — ERROR children may contain MISSING sub-nodes.
    } else if (ts_node_is_missing(node)) {
        TSPoint pt = ts_node_start_point(node);
        const char *typeCStr = ts_node_type(node);
        NSString *typeStr    = typeCStr
            ? [NSString stringWithUTF8String:typeCStr] : @"<unknown>";
        [out addObject:[[UDParseErrorItem alloc]
                            initWithLine:(NSInteger)pt.row + 1
                                  column:columnFromTSColumn(pt.column)
                                 message:[NSString stringWithFormat:@"Missing %@", typeStr]]];
        (*budget)--;
        return; // MISSING nodes have no meaningful children.
    }

    uint32_t count = ts_node_child_count(node);
    for (uint32_t i = 0; i < count; i++) {
        if (*budget == 0) break;
        [self _collectErrors:ts_node_child(node, i) budget:budget into:out];
    }
}

// ---------------------------------------------------------------------------
// MARK: - NSOutlineViewDataSource
// ---------------------------------------------------------------------------

- (NSInteger)outlineView:(NSOutlineView *)outlineView
  numberOfChildrenOfItem:(nullable id)item {
    if (item == nil)                           return 1;   // one file group
    if ([item isKindOfClass:[NSString class]]) return (NSInteger)_errors.count;
    return 0;
}

- (id)outlineView:(NSOutlineView *)outlineView
            child:(NSInteger)index
           ofItem:(nullable id)item {
    if (item == nil) return kFileGroupItem;
    return _errors[(NSUInteger)index];
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
        NSUInteger count = _errors.count;
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
        UDParseErrorItem *err = (UDParseErrorItem *)item;
        cell.textField.stringValue =
            [NSString stringWithFormat:@"Line %ld: %@", (long)err.line, err.message];
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
    return [item isKindOfClass:[UDParseErrorItem class]];
}

@end
