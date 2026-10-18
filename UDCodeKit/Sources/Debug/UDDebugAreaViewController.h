/*---------------------------------------------------------------------------------------------
 *  UDDebugAreaViewController.h
 *
 *  Xcode's debug area, below the editors: the variables view (the watch
 *  expressions, then the selected frame's scopes, an outline whose
 *  variables load as they are expanded) beside the console (what the
 *  adapter prints, and a line that evaluates in the selected frame).
 *
 *    ┌ Variables ──────────────┬ Console ───────────────────────────┐
 *    │   text       "third"    │ Running script.script               │
 *    │ ▶ info       {length=5} │ text                                │
 *    │ ▼ Locals                │ "third"                             │
 *    │     line     12         │                                     │
 *    │ ▶ Globals               │ ─────────────────────────────────── │
 *    │ ─────────────────────── │                                     │
 *    │ + −                     │ Evaluate                            │
 *    └─────────────────────────┴─────────────────────────────────────┘
 *
 *  The watch expressions are VS Code's WATCH, where Xcode puts its watch
 *  expressions: on top of the variables, each evaluated in the selected
 *  frame (context "watch") at every stop and frame chosen, opening when its
 *  value is structured. + (or Add Expression…) adds one, edited in place;
 *  a double click on one, or Edit Expression, edits it (emptied, it goes);
 *  − or Delete Expression removes it, Delete All Expressions all of them.
 *  They are the store's (UDBreakpointStore's watchExpressions), kept as
 *  the host keeps it.
 *
 *  The variables' menu, as VS Code's: Copy Value (the adapter's clipboard
 *  evaluation when it has one), Copy as Expression and Add to Watch (by
 *  the variable's evaluateName), Set Value… (a double click on a value, when
 *  the adapter supportsSetVariable).
 *
 *  What was expanded is expanded again at the next stop (by the names on
 *  the way to it), as Xcode keeps it. The first scope opens by itself.
 *  A value that changed since the last stop (the same frame's, the same
 *  name's) shows blue, as Xcode shows it. The filter field, under the
 *  variables as Xcode's, leaves the watches and variables whose name has
 *  its text (or that have such a child loaded); the scopes stay.
 *
 *  Laid out in UDDebugArea.xib; the split between the two keeps the
 *  variables' width (UDPaneSplitController), remembered under
 *  "UDCodeKit Debug Area". A host puts its view below its editors (with
 *  UDDebugBarViewController's above it) and gives it the session, or the
 *  store alone (the watch expressions, before a session).
 *--------------------------------------------------------------------------------------------*/

#import <Cocoa/Cocoa.h>
#import "UDDebugSession.h"
#import "UDPaneSplitController.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDDebugAreaViewController : NSViewController <NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate>

- (instancetype)init;

@property (nonatomic, strong, nullable) UDDebugSession *session;
/// The store whose watch expressions show: the session's, once it is set.
@property (nonatomic, strong, nullable) UDBreakpointStore *breakpoints;

/// The watch expressions, then the scopes and their variables (UDDebugVariable);
/// columns "name" and "value".
@property (nonatomic, weak, readonly) IBOutlet NSOutlineView *variablesView;
@property (nonatomic, weak, readonly) IBOutlet NSTextView *consoleView;
@property (nonatomic, weak, readonly) IBOutlet NSTextField *evaluateField;
@property (nonatomic, weak, readonly) IBOutlet NSButton *addExpressionButton;
@property (nonatomic, weak, readonly) IBOutlet NSButton *removeExpressionButton;
@property (nonatomic, weak, readonly) IBOutlet NSSearchField *filterField;
/// Variables | console.
@property (nonatomic, strong, readonly) IBOutlet UDPaneSplitController *paneSplit;

/// The watch expression @a row shows, NSNotFound when it shows none.
- (NSUInteger)watchIndexOfRow:(NSInteger)row;
/// The variable @a row shows (a watch's value, or a scope's variable), nil
/// for a watch not evaluated.
- (nullable UDDebugVariable *)variableOfRow:(NSInteger)row;

/// The evaluate field's line, to the session's console.
- (IBAction)evaluate:(nullable id)sender;
/// Empties the console view (the session keeps what it had).
- (IBAction)clearConsole:(nullable id)sender;
/// The filter field's text: the variables shown.
- (IBAction)filterVariables:(nullable id)sender;
/// Whether @a variable's value changed since the last stop (as shown).
- (BOOL)valueChanged:(UDDebugVariable *)variable;

/// The watch expressions: a new one, edited in place; the clicked (or
/// selected) one edited, removed; all removed.
- (IBAction)addExpression:(nullable id)sender;
- (IBAction)editExpression:(nullable id)sender;
- (IBAction)removeExpression:(nullable id)sender;
- (IBAction)removeAllExpressions:(nullable id)sender;
/// The clicked (or selected) variable's: its value, its evaluateName, a
/// watch of it, its value edited in place.
- (IBAction)copyValue:(nullable id)sender;
- (IBAction)copyAsExpression:(nullable id)sender;
- (IBAction)addToWatch:(nullable id)sender;
- (IBAction)setValue:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
