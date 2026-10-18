/*---------------------------------------------------------------------------------------------
 *  UDDebugAreaViewController.h
 *
 *  Xcode's debug area, below the editors: the variables view (the selected
 *  frame's scopes, an outline whose variables load as they are expanded)
 *  beside the console (what the adapter prints, and a line that evaluates
 *  in the selected frame).
 *
 *    ┌ Variables ──────────────┬ Console ───────────────────────────┐
 *    │ ▼ Locals                │ Running script.script               │
 *    │     line     12         │ text                                │
 *    │   ▶ info     {length=5} │ "third"                             │
 *    │ ▶ Globals               │ ─────────────────────────────────── │
 *    │                         │ Evaluate                            │
 *    └─────────────────────────┴─────────────────────────────────────┘
 *
 *  What was expanded is expanded again at the next stop (by the names on
 *  the way to it), as Xcode keeps it. The first scope opens by itself.
 *
 *  Laid out in UDDebugArea.xib; the split between the two keeps the
 *  variables' width (UDPaneSplitController), remembered under
 *  "UDCodeKit Debug Area". A host puts its view below its editors (with
 *  UDDebugBarViewController's above it) and gives it the session.
 *--------------------------------------------------------------------------------------------*/

#import <Cocoa/Cocoa.h>
#import "UDDebugSession.h"
#import "UDPaneSplitController.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDDebugAreaViewController : NSViewController <NSOutlineViewDataSource, NSOutlineViewDelegate>

- (instancetype)init;

@property (nonatomic, strong, nullable) UDDebugSession *session;

/// Scopes and variables (UDDebugVariable); columns "name" and "value".
@property (nonatomic, weak, readonly) IBOutlet NSOutlineView *variablesView;
@property (nonatomic, weak, readonly) IBOutlet NSTextView *consoleView;
@property (nonatomic, weak, readonly) IBOutlet NSTextField *evaluateField;
/// Variables | console.
@property (nonatomic, strong, readonly) IBOutlet UDPaneSplitController *paneSplit;

/// The evaluate field's line, to the session's console.
- (IBAction)evaluate:(nullable id)sender;
/// Empties the console view (the session keeps what it had).
- (IBAction)clearConsole:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
