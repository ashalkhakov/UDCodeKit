/*---------------------------------------------------------------------------------------------
 *  UDDebugAreaViewController.m
 *--------------------------------------------------------------------------------------------*/

#import "UDDebugAreaViewController.h"
#import <objc/runtime.h>

/// A watch expression's row: the expression, and what it evaluated to.
@interface UDWatchRow : NSObject
/// Its place among the store's; NSNotFound for a new one, being written.
@property (nonatomic) NSUInteger index;
@property (nonatomic, copy) NSString *expression;
@property (nonatomic, strong, nullable) UDDebugVariable *value;
@end

@implementation UDWatchRow
@end

@interface UDDebugAreaViewController ()
@property (nonatomic, weak) IBOutlet NSOutlineView *variablesView;
@property (nonatomic, weak) IBOutlet NSTextView *consoleView;
@property (nonatomic, weak) IBOutlet NSTextField *evaluateField;
@property (nonatomic, weak) IBOutlet NSButton *addExpressionButton;
@property (nonatomic, weak) IBOutlet NSButton *removeExpressionButton;
@property (nonatomic, strong) IBOutlet UDPaneSplitController *paneSplit;
@end

@implementation UDDebugAreaViewController {
    /// What is expanded, by the names on the way ("Locals/info", "watch:info").
    NSMutableSet<NSString *> *_expandedPaths;
    BOOL _restoring;          // expanding what was: not the user's doing
    NSArray<UDWatchRow *> *_watchRows;
    UDWatchRow *_newRow;      // Add Expression's, until it is written
    id _editingItem;          // what an edit this controller began is of: the only one
    id _menuItem;             // what the context menu is about
    NSString *_copyFallback;  // Copy Value's, when the clipboard evaluation fails
}

- (instancetype)init {
    self = [super initWithNibName:@"UDDebugArea" bundle:[NSBundle bundleForClass:[UDDebugAreaViewController class]]];
    if (self) {
        _expandedPaths = [NSMutableSet set];
        _watchRows = @[];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _paneSplit.flexiblePaneIndex = 1;
    _paneSplit.minimumThicknesses = @[@160, @200];
    _paneSplit.defaultThicknesses = @[@300, @0];
    _paneSplit.autosaveName = @"UDCodeKit Debug Area";
    [_paneSplit restoreLayout];
    _consoleView.font = [self _consoleFont];
    _evaluateField.enabled = NO;
    // An edit in place ended (committed or not): Add Expression's row goes
    // unless it was written.
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_editingDidEnd:)
                                                 name:NSControlTextDidEndEditingNotification object:_variablesView];
    [self _updateButtons];
}

- (NSFont *)_consoleFont {
    return [NSFont userFixedPitchFontOfSize:11.0];
}

- (void)setSession:(UDDebugSession *)session {
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    if (_session) [center removeObserver:self name:nil object:_session];
    _session = session;
    (void)self.view;
    if (session) {
        [center addObserver:self selector:@selector(_variablesDidLoad:)
                       name:UDDebugSessionDidLoadVariablesNotification object:session];
        [center addObserver:self selector:@selector(_watchesDidEvaluate:)
                       name:UDDebugSessionDidEvaluateWatchesNotification object:session];
        [center addObserver:self selector:@selector(_didOutput:)
                       name:UDDebugSessionDidOutputNotification object:session];
        [center addObserver:self selector:@selector(_stateDidChange:)
                       name:UDDebugSessionDidChangeStateNotification object:session];
        self.breakpoints = session.breakpoints;
    }
    // What it has printed so far.
    [_consoleView.textStorage setAttributedString:[[NSAttributedString alloc] initWithString:session.consoleText ?: @""
                                                                                    attributes:[self _attributesFor:@"console"]]];
    [self _reload];
    [self _stateDidChange:nil];
}

- (void)setBreakpoints:(UDBreakpointStore *)breakpoints {
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    if (_breakpoints) [center removeObserver:self name:UDBreakpointStoreDidChangeWatchExpressionsNotification object:_breakpoints];
    _breakpoints = breakpoints;
    if (breakpoints) {
        [center addObserver:self selector:@selector(_watchesDidEvaluate:)
                       name:UDBreakpointStoreDidChangeWatchExpressionsNotification object:breakpoints];
    }
    (void)self.view;
    [self _reload];
}

- (void)_stateDidChange:(NSNotification *)note {
    _evaluateField.enabled = _session && _session.state != UDDebugSessionStateEnded;
}

// ---------------------------------------------------------------------------
// MARK: - The console
// ---------------------------------------------------------------------------

/// Errors red, what was evaluated bold, the rest as text.
- (NSDictionary *)_attributesFor:(NSString *)category {
    NSFont *font = [self _consoleFont];
    NSColor *color = [NSColor textColor];
    if ([category isEqualToString:@"stderr"]) {
        color = [NSColor systemRedColor];
    } else if ([category isEqualToString:@"input"]) {
        font = [[NSFontManager sharedFontManager] convertFont:font toHaveTrait:NSBoldFontMask];
    } else if ([category isEqualToString:@"console"]) {
        color = [NSColor secondaryLabelColor];
    }
    return @{ NSFontAttributeName: font, NSForegroundColorAttributeName: color };
}

- (void)_didOutput:(NSNotification *)note {
    NSString *text = note.userInfo[UDDebugSessionOutputKey];
    NSString *category = note.userInfo[UDDebugSessionOutputCategoryKey];
    NSAttributedString *output = [[NSAttributedString alloc] initWithString:text attributes:[self _attributesFor:category]];
    NSTextStorage *storage = _consoleView.textStorage;
    [storage appendAttributedString:output];
    [_consoleView scrollRangeToVisible:NSMakeRange(storage.length, 0)];
}

- (IBAction)evaluate:(id)sender {
    NSString *expression = _evaluateField.stringValue;
    if (!expression.length) return;
    [_session evaluate:expression];
    _evaluateField.stringValue = @"";
}

- (IBAction)clearConsole:(id)sender {
    [_consoleView.textStorage setAttributedString:[[NSAttributedString alloc] initWithString:@""]];
}

// ---------------------------------------------------------------------------
// MARK: - The rows: watches, then scopes
// ---------------------------------------------------------------------------

/// The store's watch expressions, with the session's values when it has
/// them (and Add Expression's new one last).
- (void)_rebuildWatchRows {
    NSArray<NSString *> *expressions = _breakpoints.watchExpressions ?: @[];
    NSArray<UDDebugVariable *> *values = _session.watches;
    if (values.count != expressions.count) values = nil;
    NSMutableArray<UDWatchRow *> *rows = [NSMutableArray array];
    for (NSUInteger i = 0; i < expressions.count; i++) {
        UDWatchRow *row = [[UDWatchRow alloc] init];
        row.index = i;
        row.expression = expressions[i];
        row.value = values[i];
        [rows addObject:row];
    }
    if (_newRow) [rows addObject:_newRow];
    _watchRows = rows;
}

- (nullable UDWatchRow *)_rowOfValue:(UDDebugVariable *)value {
    for (UDWatchRow *row in _watchRows) if (row.value == value) return row;
    return nil;
}

/// What the outline has for @a item: a watch's row for its value.
- (id)_itemFor:(UDDebugVariable *)variable {
    return [self _rowOfValue:variable] ?: variable;
}

- (NSString *)_pathOf:(id)item {
    if ([item isKindOfClass:[UDWatchRow class]]) return [@"watch:" stringByAppendingString:((UDWatchRow *)item).expression];
    NSMutableArray *names = [NSMutableArray array];
    UDDebugVariable *root = item;
    for (UDDebugVariable *v = item; v; v = v.parent) {
        [names insertObject:v.name atIndex:0];
        root = v;
    }
    NSString *path = [names componentsJoinedByString:@"/"];
    return [self _rowOfValue:root] ? [@"watch:" stringByAppendingString:path] : path;
}

/// Everything again: the watches and the scopes, and what was expanded
/// expanded again.
- (void)_reload {
    [self _rebuildWatchRows];
    _restoring = YES;
    [_variablesView reloadData];
    NSArray<UDDebugVariable *> *scopes = _session.scopes;
    BOOL any = NO;
    for (UDDebugVariable *scope in scopes) any = any || [_expandedPaths containsObject:[self _pathOf:scope]];
    // The first time, the first scope that is not expensive.
    if (!any) {
        for (UDDebugVariable *scope in scopes) {
            if (scope.expensive) continue;
            [_expandedPaths addObject:[self _pathOf:scope]];
            break;
        }
    }
    [self _expandAgain:_watchRows];
    [self _expandAgain:scopes];
    _restoring = NO;
    [self _updateButtons];
}

/// Scopes loaded (a new frame), or a variable's children: shown, and what
/// was expanded before expanded again.
- (void)_variablesDidLoad:(NSNotification *)note {
    UDDebugVariable *variable = note.userInfo[UDDebugSessionVariableKey];
    if (!variable) {
        [self _reload];
        return;
    }
    id item = [self _itemFor:variable];
    if ([_variablesView rowForItem:item] < 0) return;
    _restoring = YES;
    [_variablesView reloadItem:item reloadChildren:YES];
    if ([_expandedPaths containsObject:[self _pathOf:item]]) {
        [_variablesView expandItem:item];
        [self _expandAgain:variable.children];
    }
    _restoring = NO;
}

- (void)_watchesDidEvaluate:(NSNotification *)note {
    [self _reload];
}

/// Each of @a items that was expanded: expanded, or its children asked for.
- (void)_expandAgain:(NSArray *)items {
    for (id item in items) {
        UDDebugVariable *variable = [item isKindOfClass:[UDWatchRow class]] ? ((UDWatchRow *)item).value : item;
        if (!variable.hasChildren || ![_expandedPaths containsObject:[self _pathOf:item]]) continue;
        if (variable.children) {
            [_variablesView expandItem:item];
            [self _expandAgain:variable.children];
        } else {
            [_session loadChildrenOfVariable:variable];
        }
    }
}

- (NSUInteger)watchIndexOfRow:(NSInteger)row {
    id item = row >= 0 ? [_variablesView itemAtRow:row] : nil;
    return [item isKindOfClass:[UDWatchRow class]] ? ((UDWatchRow *)item).index : NSNotFound;
}

- (UDDebugVariable *)variableOfRow:(NSInteger)row {
    id item = row >= 0 ? [_variablesView itemAtRow:row] : nil;
    return [item isKindOfClass:[UDWatchRow class]] ? ((UDWatchRow *)item).value : item;
}

// ---------------------------------------------------------------------------
// MARK: - NSOutlineViewDataSource
// ---------------------------------------------------------------------------

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {
    if (item == nil) return (NSInteger)(_watchRows.count + _session.scopes.count);
    if ([item isKindOfClass:[UDWatchRow class]]) return (NSInteger)((UDWatchRow *)item).value.children.count;
    return (NSInteger)((UDDebugVariable *)item).children.count;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item {
    if (item == nil) {
        NSUInteger watches = _watchRows.count;
        return (NSUInteger)index < watches ? _watchRows[(NSUInteger)index] : _session.scopes[(NSUInteger)index - watches];
    }
    if ([item isKindOfClass:[UDWatchRow class]]) return ((UDWatchRow *)item).value.children[(NSUInteger)index];
    return ((UDDebugVariable *)item).children[(NSUInteger)index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    if ([item isKindOfClass:[UDWatchRow class]]) return ((UDWatchRow *)item).value.hasChildren;
    return ((UDDebugVariable *)item).hasChildren;
}

// A cell-based outline, as the issues navigator's (gnustep-patches#26).
- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item {
    BOOL value = [tableColumn.identifier isEqualToString:@"value"];
    if ([item isKindOfClass:[UDWatchRow class]]) {
        UDWatchRow *row = item;
        return value ? row.value.value ?: @"" : row.expression;
    }
    UDDebugVariable *variable = item;
    return value ? variable.value : variable.name;
}

/// An edit this controller began: a watch's expression, or a variable's
/// value (Set Value). Made on the next turn, the edit being over.
- (void)outlineView:(NSOutlineView *)outlineView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn
             byItem:(id)item {
    // Only the edit begun here: GNUstep's table goes on to edit the next
    // row at Return, and writes what that one ends with.
    if (item != _editingItem) return;
    NSString *text = [object isKindOfClass:[NSString class]] ? object : [object description];
    if ([item isKindOfClass:[UDWatchRow class]] && [tableColumn.identifier isEqualToString:@"name"]) {
        [self performSelector:@selector(_writeExpression:) withObject:@[ item, text ?: @"" ] afterDelay:0
                      inModes:@[ NSDefaultRunLoopMode, NSModalPanelRunLoopMode ]];
    } else if ([item isKindOfClass:[UDDebugVariable class]] && [tableColumn.identifier isEqualToString:@"value"]) {
        if (![text isEqualToString:((UDDebugVariable *)item).value]) [_session setValue:text ofVariable:item];
    }
}

- (void)_writeExpression:(NSArray *)edit {
    UDWatchRow *row = edit[0];
    NSString *expression = edit[1];
    // Add Expression's (gone already, when the edit's end came first).
    if (row.index == NSNotFound) {
        if (row == _newRow) _newRow = nil;
        if ([expression stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]].length) {
            [_breakpoints addWatchExpression:expression];
        } else {
            [self _reload];
        }
        return;
    }
    [_breakpoints replaceWatchExpressionAtIndex:row.index withExpression:expression];
}

/// Only what this controller begins is edited, and only that row (GNUstep's
/// tables go on to the next row's cell at Return).
- (BOOL)outlineView:(NSOutlineView *)outlineView shouldEditTableColumn:(NSTableColumn *)tableColumn item:(id)item {
    return item != nil && item == _editingItem;
}

/// Over: on the next turn, when what was written is written.
- (void)_editingDidEnd:(NSNotification *)note {
    [self performSelector:@selector(_editingIsOver) withObject:nil afterDelay:0
                  inModes:@[ NSDefaultRunLoopMode, NSModalPanelRunLoopMode ]];
}

- (void)_editingIsOver {
    _editingItem = nil;
    [self _dropNewRow];
}

/// Add Expression's row, left empty (Escape): gone.
- (void)_dropNewRow {
    if (!_newRow) return;
    _newRow = nil;
    [self _reload];
}

- (void)_editItem:(id)item column:(NSString *)identifier {
    NSInteger row = [_variablesView rowForItem:item];
    NSInteger column = [_variablesView columnWithIdentifier:identifier];
    if (row < 0 || column < 0) return;
    [_variablesView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
    [_variablesView.window makeFirstResponder:_variablesView];
    _editingItem = item;
    [_variablesView editColumn:column row:row withEvent:nil select:YES];
}

// ---------------------------------------------------------------------------
// MARK: - NSOutlineViewDelegate
// ---------------------------------------------------------------------------

/// Scopes bold; a watch that did not evaluate grey.
- (void)outlineView:(NSOutlineView *)outlineView willDisplayCell:(id)cell
     forTableColumn:(NSTableColumn *)tableColumn item:(id)item {
    if (![cell isKindOfClass:[NSTextFieldCell class]]) return;
    NSTextFieldCell *text = cell;
    BOOL scope = [item isKindOfClass:[UDDebugVariable class]] && ((UDDebugVariable *)item).parent == nil &&
                 [_session.scopes containsObject:item];
    text.font = scope ? [NSFont boldSystemFontOfSize:NSFont.smallSystemFontSize]
                      : [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    BOOL failed = [item isKindOfClass:[UDWatchRow class]] && ((UDWatchRow *)item).value.failed &&
                  [tableColumn.identifier isEqualToString:@"value"];
    text.textColor = failed ? [NSColor secondaryLabelColor] : [NSColor controlTextColor];
}

- (NSString *)outlineView:(NSOutlineView *)outlineView toolTipForCell:(NSCell *)cell rect:(NSRectPointer)rect
              tableColumn:(NSTableColumn *)tableColumn item:(id)item mouseLocation:(NSPoint)mouseLocation {
    UDDebugVariable *variable = [item isKindOfClass:[UDWatchRow class]] ? ((UDWatchRow *)item).value : item;
    NSString *name = [item isKindOfClass:[UDWatchRow class]] ? ((UDWatchRow *)item).expression : variable.name;
    return variable.type ? [NSString stringWithFormat:@"%@ (%@)", name, variable.type] : name;
}

/// Expanded by the user: remembered, and the children asked for.
- (void)outlineViewItemWillExpand:(NSNotification *)note {
    id item = note.userInfo[@"NSObject"];
    UDDebugVariable *variable = [item isKindOfClass:[UDWatchRow class]] ? ((UDWatchRow *)item).value : item;
    if (![variable isKindOfClass:[UDDebugVariable class]]) return;
    [_expandedPaths addObject:[self _pathOf:item]];
    if (!variable.children) [_session loadChildrenOfVariable:variable];
}

- (void)outlineViewItemDidCollapse:(NSNotification *)note {
    id item = note.userInfo[@"NSObject"];
    if (_restoring || !item) return;
    [_expandedPaths removeObject:[self _pathOf:item]];
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification {
    [self _updateButtons];
}

// ---------------------------------------------------------------------------
// MARK: - Actions: the watch expressions
// ---------------------------------------------------------------------------

- (void)_updateButtons {
    _addExpressionButton.enabled = _breakpoints != nil;
    _removeExpressionButton.enabled = [self watchIndexOfRow:_variablesView.selectedRow] != NSNotFound;
}

/// What an action is about: the context menu's row, or the selected one.
- (nullable id)_targetItemOf:(id)sender {
    if ([sender isKindOfClass:[NSMenuItem class]] && [(NSMenuItem *)sender menu] == _variablesView.menu && _menuItem) {
        return _menuItem;
    }
    NSInteger row = _variablesView.selectedRow;
    return row >= 0 ? [_variablesView itemAtRow:row] : nil;
}

/// The context menu is about the row clicked (GNUstep's tables do not say
/// which: the event does).
- (void)menuNeedsUpdate:(NSMenu *)menu {
    NSInteger row = _variablesView.clickedRow;
    if (row < 0) {
        NSEvent *event = [NSApp currentEvent];
        if (event.window == _variablesView.window) {
            row = [_variablesView rowAtPoint:[_variablesView convertPoint:event.locationInWindow fromView:nil]];
        }
    }
    _menuItem = row >= 0 ? [_variablesView itemAtRow:row] : nil;
}

- (IBAction)addExpression:(id)sender {
    if (!_breakpoints) {
        NSBeep();
        return;
    }
    if (!_newRow) {
        _newRow = [[UDWatchRow alloc] init];
        _newRow.index = NSNotFound;
        _newRow.expression = @"";
        [self _reload];
    }
    [self _editItem:_newRow column:@"name"];
}

- (IBAction)editExpression:(id)sender {
    id item = [self _targetItemOf:sender];
    if ([item isKindOfClass:[UDWatchRow class]]) [self _editItem:item column:@"name"];
}

- (IBAction)removeExpression:(id)sender {
    id item = [self _targetItemOf:sender];
    if (![item isKindOfClass:[UDWatchRow class]]) return;
    if (item == _newRow) [self _dropNewRow];
    else [_breakpoints removeWatchExpressionAtIndex:((UDWatchRow *)item).index];
}

- (IBAction)removeAllExpressions:(id)sender {
    [_breakpoints removeAllWatchExpressions];
}

/// A double click: a watch's expression, or a value that can be set, edited.
- (IBAction)editClickedCell:(id)sender {
    NSInteger row = _variablesView.clickedRow, column = _variablesView.clickedColumn;
    if (row < 0 || column < 0) return;
    id item = [_variablesView itemAtRow:row];
    NSString *identifier = ((NSTableColumn *)_variablesView.tableColumns[(NSUInteger)column]).identifier;
    if ([item isKindOfClass:[UDWatchRow class]] && [identifier isEqualToString:@"name"]) {
        [self _editItem:item column:@"name"];
    } else if ([item isKindOfClass:[UDDebugVariable class]] && [identifier isEqualToString:@"value"] &&
               [_session canSetVariable:item]) {
        [self _editItem:item column:@"value"];
    }
}

// ---------------------------------------------------------------------------
// MARK: - Actions: a variable's
// ---------------------------------------------------------------------------

- (nullable UDDebugVariable *)_targetVariableOf:(id)sender {
    id item = [self _targetItemOf:sender];
    return [item isKindOfClass:[UDWatchRow class]] ? ((UDWatchRow *)item).value : item;
}

static void UDCopyString(NSString *text) {
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard declareTypes:@[ NSPasteboardTypeString ] owner:nil];
    [pasteboard setString:text forType:NSPasteboardTypeString];
}

/// The value, or what the adapter makes of it for the clipboard (VS Code
/// asks with context "clipboard" when it can).
- (IBAction)copyValue:(id)sender {
    UDDebugVariable *variable = [self _targetVariableOf:sender];
    if (!variable) return;
    if (variable.evaluateName && _session.client.supportsClipboardContext && _session.state == UDDebugSessionStateStopped) {
        _copyFallback = variable.value;
        [_session evaluate:variable.evaluateName context:@"clipboard" target:self action:@selector(_didEvaluateForClipboard:)];
        return;
    }
    UDCopyString(variable.value);
}

- (void)_didEvaluateForClipboard:(UDDebugVariable *)result {
    UDCopyString(result.failed ? _copyFallback ?: @"" : result.value);
    _copyFallback = nil;
}

- (IBAction)copyAsExpression:(id)sender {
    NSString *expression = [self _targetVariableOf:sender].evaluateName;
    if (expression) UDCopyString(expression);
}

- (IBAction)addToWatch:(id)sender {
    NSString *expression = [self _targetVariableOf:sender].evaluateName;
    if (expression) [_breakpoints addWatchExpression:expression];
}

- (IBAction)setValue:(id)sender {
    UDDebugVariable *variable = [self _targetVariableOf:sender];
    if ([_session canSetVariable:variable]) [self _editItem:variable column:@"value"];
}

/// sel_isEqual: on GNUstep a XIB's selector is another pointer.
- (BOOL)validateMenuItem:(NSMenuItem *)item {
    SEL action = item.action;
    id target = [self _targetItemOf:item];
    UDDebugVariable *variable = [target isKindOfClass:[UDWatchRow class]] ? ((UDWatchRow *)target).value : target;
    BOOL watch = [target isKindOfClass:[UDWatchRow class]];
    if (sel_isEqual(action, @selector(addExpression:))) return _breakpoints != nil;
    if (sel_isEqual(action, @selector(editExpression:)) || sel_isEqual(action, @selector(removeExpression:))) return watch;
    if (sel_isEqual(action, @selector(removeAllExpressions:))) return _breakpoints.watchExpressions.count > 0;
    if (sel_isEqual(action, @selector(copyValue:))) return variable != nil && (watch || variable.parent || variable.value.length);
    if (sel_isEqual(action, @selector(copyAsExpression:))) return variable.evaluateName.length > 0;
    if (sel_isEqual(action, @selector(addToWatch:))) return !watch && variable.evaluateName.length > 0 && _breakpoints;
    if (sel_isEqual(action, @selector(setValue:))) return !watch && [_session canSetVariable:variable];
    return YES;
}

@end
