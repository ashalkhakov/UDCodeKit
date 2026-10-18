/*---------------------------------------------------------------------------------------------
 *  UDDebugAreaViewController.m
 *--------------------------------------------------------------------------------------------*/

#import "UDDebugAreaViewController.h"

@interface UDDebugAreaViewController ()
@property (nonatomic, weak) IBOutlet NSOutlineView *variablesView;
@property (nonatomic, weak) IBOutlet NSTextView *consoleView;
@property (nonatomic, weak) IBOutlet NSTextField *evaluateField;
@property (nonatomic, strong) IBOutlet UDPaneSplitController *paneSplit;
@end

@implementation UDDebugAreaViewController {
    /// What is expanded, by the names on the way ("Locals/info").
    NSMutableSet<NSString *> *_expandedPaths;
    BOOL _restoring;          // expanding what was: not the user's doing
}

- (instancetype)init {
    self = [super initWithNibName:@"UDDebugArea" bundle:[NSBundle bundleForClass:[UDDebugAreaViewController class]]];
    if (self) _expandedPaths = [NSMutableSet set];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
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
        [center addObserver:self selector:@selector(_didOutput:)
                       name:UDDebugSessionDidOutputNotification object:session];
        [center addObserver:self selector:@selector(_stateDidChange:)
                       name:UDDebugSessionDidChangeStateNotification object:session];
    }
    // What it has printed so far.
    [_consoleView.textStorage setAttributedString:[[NSAttributedString alloc] initWithString:session.consoleText ?: @""
                                                                                    attributes:[self _attributesFor:@"console"]]];
    [_variablesView reloadData];
    [self _stateDidChange:nil];
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
// MARK: - The variables
// ---------------------------------------------------------------------------

static NSString *UDPathOf(UDDebugVariable *variable) {
    NSMutableArray *names = [NSMutableArray array];
    for (UDDebugVariable *v = variable; v; v = v.parent) [names insertObject:v.name atIndex:0];
    return [names componentsJoinedByString:@"/"];
}

/// Scopes loaded (a new frame), or a variable's children: shown, and what
/// was expanded before expanded again.
- (void)_variablesDidLoad:(NSNotification *)note {
    UDDebugVariable *variable = note.userInfo[UDDebugSessionVariableKey];
    _restoring = YES;
    if (!variable) {
        [_variablesView reloadData];
        NSArray<UDDebugVariable *> *scopes = _session.scopes;
        BOOL any = NO;
        for (UDDebugVariable *scope in scopes) any = any || [_expandedPaths containsObject:UDPathOf(scope)];
        // The first time, the first scope that is not expensive.
        if (!any) {
            for (UDDebugVariable *scope in scopes) {
                if (scope.expensive) continue;
                [_expandedPaths addObject:UDPathOf(scope)];
                break;
            }
        }
        [self _expandAgain:scopes];
    } else {
        [_variablesView reloadItem:variable reloadChildren:YES];
        if ([_expandedPaths containsObject:UDPathOf(variable)]) {
            [_variablesView expandItem:variable];
            [self _expandAgain:variable.children];
        }
    }
    _restoring = NO;
}

/// Each of @a variables that was expanded: expanded, or its children asked for.
- (void)_expandAgain:(NSArray<UDDebugVariable *> *)variables {
    for (UDDebugVariable *variable in variables) {
        if (!variable.hasChildren || ![_expandedPaths containsObject:UDPathOf(variable)]) continue;
        if (variable.children) {
            [_variablesView expandItem:variable];
            [self _expandAgain:variable.children];
        } else {
            [_session loadChildrenOfVariable:variable];
        }
    }
}

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {
    if (item == nil) return (NSInteger)_session.scopes.count;
    return (NSInteger)((UDDebugVariable *)item).children.count;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item {
    if (item == nil) return _session.scopes[(NSUInteger)index];
    return ((UDDebugVariable *)item).children[(NSUInteger)index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    return ((UDDebugVariable *)item).hasChildren;
}

// A cell-based outline, as the issues navigator's (gnustep-patches#26).
- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item {
    UDDebugVariable *variable = item;
    if ([tableColumn.identifier isEqualToString:@"value"]) return variable.value;
    return variable.name;
}

/// Scopes bold; a variable's type is its value's tooltip.
- (void)outlineView:(NSOutlineView *)outlineView willDisplayCell:(id)cell
     forTableColumn:(NSTableColumn *)tableColumn item:(id)item {
    if (![cell isKindOfClass:[NSTextFieldCell class]]) return;
    BOOL scope = ((UDDebugVariable *)item).parent == nil;
    ((NSTextFieldCell *)cell).font = scope ? [NSFont boldSystemFontOfSize:NSFont.smallSystemFontSize]
                                           : [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
}

- (NSString *)outlineView:(NSOutlineView *)outlineView toolTipForCell:(NSCell *)cell rect:(NSRectPointer)rect
              tableColumn:(NSTableColumn *)tableColumn item:(id)item mouseLocation:(NSPoint)mouseLocation {
    UDDebugVariable *variable = item;
    return variable.type ? [NSString stringWithFormat:@"%@ (%@)", variable.name, variable.type] : variable.name;
}

/// Expanded by the user: remembered, and the children asked for.
- (void)outlineViewItemWillExpand:(NSNotification *)note {
    UDDebugVariable *variable = note.userInfo[@"NSObject"];
    if (![variable isKindOfClass:[UDDebugVariable class]]) return;
    [_expandedPaths addObject:UDPathOf(variable)];
    if (!variable.children) [_session loadChildrenOfVariable:variable];
}

- (void)outlineViewItemDidCollapse:(NSNotification *)note {
    UDDebugVariable *variable = note.userInfo[@"NSObject"];
    if (_restoring || ![variable isKindOfClass:[UDDebugVariable class]]) return;
    [_expandedPaths removeObject:UDPathOf(variable)];
}

@end
