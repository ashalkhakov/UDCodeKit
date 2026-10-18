/*---------------------------------------------------------------------------------------------
 *  UDDebugHoverViewController.m
 *--------------------------------------------------------------------------------------------*/

#import "UDDebugHoverViewController.h"
#import "UDEditorPopup.h"

/// The widest the panel grows, and how many rows of children it shows
/// before they scroll.
static const CGFloat UDDebugHoverMaxWidth = 480, UDDebugHoverMinWidth = 200;
static const NSInteger UDDebugHoverMaxRows = 12;

NSRange UDEvaluatableExpressionRange(NSString *line, NSRange word) {
    static NSRegularExpression *expression, *subExpression;
    if (!expression) {
        // Any character that does not usually break an interesting
        // sub-expression, or "->" (VS Code's).
        expression = [NSRegularExpression regularExpressionWithPattern:@"([^()\\[\\]{}<>\\s+\\-/%~#^;=|,`!]|->)+"
                                                               options:0 error:NULL];
        subExpression = [NSRegularExpression regularExpressionWithPattern:@"\\w+" options:0 error:NULL];
    }
    NSRange found = NSMakeRange(NSNotFound, 0);
    for (NSTextCheckingResult *match in [expression matchesInString:line options:0 range:NSMakeRange(0, line.length)]) {
        if (match.range.location <= word.location && NSMaxRange(match.range) >= NSMaxRange(word)) {
            found = match.range;
            break;
        }
    }
    if (found.location == NSNotFound) return found;
    // Cut after the sub-expression the word ends in: "a.b" of "a.b.c" at b.
    for (NSTextCheckingResult *part in [subExpression matchesInString:line options:0 range:found]) {
        if (NSMaxRange(part.range) >= NSMaxRange(word)) {
            found.length = NSMaxRange(part.range) - found.location;
            break;
        }
    }
    return found;
}

/// The panel's content: it says when the mouse leaves it.
@interface UDDebugHoverContentView : NSView
@property (nonatomic, weak) UDDebugHoverViewController *controller;
@end

@interface UDDebugHoverViewController ()
@property (nonatomic, strong, nullable) UDDebugVariable *variable;
@property (nonatomic, strong, nullable) UDDebugSession *session;
- (void)_mouseLeftPanel;
@end

@implementation UDDebugHoverContentView {
    NSTrackingRectTag _tag;
#ifdef __APPLE__
    NSTrackingArea *_area;
#endif
}

#ifdef __APPLE__
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_area) [self removeTrackingArea:_area];
    // Always: the panel is never the key window.
    _area = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                         options:NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect
                                           owner:self userInfo:nil];
    [self addTrackingArea:_area];
}
#else
- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    [self _track];
}

- (void)setFrameSize:(NSSize)size {
    [super setFrameSize:size];
    [self _track];
}

- (void)_track {
    if (_tag != 0) [self removeTrackingRect:_tag];
    _tag = self.window != nil ? [self addTrackingRect:self.bounds owner:self userData:NULL assumeInside:NO] : 0;
}
#endif

- (void)mouseExited:(NSEvent *)event {
    [_controller _mouseLeftPanel];
}

@end

@implementation UDDebugHoverViewController

- (instancetype)init {
    return [super initWithNibName:@"UDDebugHover" bundle:[NSBundle bundleForClass:[UDDebugHoverViewController class]]];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    UDDebugHoverContentView *content = (UDDebugHoverContentView *)_panel.contentView;
    if ([content isKindOfClass:[UDDebugHoverContentView class]]) content.controller = self;
}

- (void)showVariable:(UDDebugVariable *)variable ofSession:(UDDebugSession *)session
    atCharacterRange:(NSRange)characterRange ofTextView:(NSTextView *)textView {
    (void)self.view;
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center removeObserver:self];
    _variable = variable;
    _session = session;
    [center addObserver:self selector:@selector(_variablesDidLoad:)
                   name:UDDebugSessionDidLoadVariablesNotification object:session];
    // Running again, or another frame: what it showed is gone.
    [center addObserver:self selector:@selector(_sessionMovedOn:)
                   name:UDDebugSessionDidSelectFrameNotification object:session];
    _titleField.stringValue = [NSString stringWithFormat:@"%@ = %@", variable.name, variable.value];
    [_outlineView reloadData];
    if (variable.hasChildren && !variable.children) [session loadChildrenOfVariable:variable];
    [self _fit];
    UDShowEditorPopup(_panel, textView, characterRange);
}

/// As wide as its title (within limits), as high as its rows.
- (void)_fit {
    NSScrollView *scroll = _outlineView.enclosingScrollView;
    CGFloat title = NSHeight(_titleField.frame) + 6.0;
    NSInteger rows = _variable.hasChildren ? MIN(MAX(_outlineView.numberOfRows, 1), UDDebugHoverMaxRows) : 0;
    CGFloat list = rows ? rows * (_outlineView.rowHeight + _outlineView.intercellSpacing.height) + 4.0 : 0.0;
    CGFloat width = MIN(MAX([_titleField.cell cellSize].width + 16.0, UDDebugHoverMinWidth), UDDebugHoverMaxWidth);
    if (rows) width = MAX(width, 320.0);
    NSRect frame = _panel.frame;
    CGFloat height = title + list;
    // Grown from its top, where it hangs from the text.
    frame.origin.y += NSHeight(frame) - height;
    frame.size = NSMakeSize(width, height);
    [_panel setFrame:frame display:NO];
    NSRect bounds = ((NSView *)_panel.contentView).bounds;
    _titleField.frame = NSMakeRect(6.0, NSHeight(bounds) - title + 3.0, NSWidth(bounds) - 12.0, NSHeight(_titleField.frame));
    scroll.hidden = rows == 0;
    scroll.frame = NSMakeRect(0.0, 0.0, NSWidth(bounds), list);
    [(NSView *)_panel.contentView setNeedsDisplay:YES];
}

- (BOOL)isShown {
    return _panel.isVisible;
}

- (BOOL)containsMouse {
    return self.isShown && NSPointInRect([NSEvent mouseLocation], _panel.frame);
}

- (void)close {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    if (_panel.isVisible) UDHideEditorPopup(_panel);
    _variable = nil;
    _session = nil;
}

- (void)_mouseLeftPanel {
    [self close];
}

- (void)_sessionMovedOn:(NSNotification *)note {
    [self close];
}

- (void)_variablesDidLoad:(NSNotification *)note {
    UDDebugVariable *variable = note.userInfo[UDDebugSessionVariableKey];
    if (!variable || !_panel.isVisible) return;
    if (variable == _variable) {
        [_outlineView reloadData];
        [self _fit];
    } else if ([_outlineView rowForItem:variable] >= 0) {
        [_outlineView reloadItem:variable reloadChildren:YES];
        [_outlineView expandItem:variable];
    }
}

// ---------------------------------------------------------------------------
// MARK: - The children
// ---------------------------------------------------------------------------

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {
    UDDebugVariable *variable = item ?: _variable;
    return (NSInteger)variable.children.count;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item {
    UDDebugVariable *variable = item ?: _variable;
    return variable.children[(NSUInteger)index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    return ((UDDebugVariable *)item).hasChildren;
}

// A cell-based outline, as the debug area's.
- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item {
    UDDebugVariable *variable = item;
    return [tableColumn.identifier isEqualToString:@"value"] ? variable.value : variable.name;
}

- (void)outlineViewItemWillExpand:(NSNotification *)note {
    UDDebugVariable *variable = note.userInfo[@"NSObject"];
    if ([variable isKindOfClass:[UDDebugVariable class]] && !variable.children) [_session loadChildrenOfVariable:variable];
}

@end
