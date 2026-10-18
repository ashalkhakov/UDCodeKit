# Debugging

UDCodeKit is a client of the
[Debug Adapter Protocol](https://microsoft.github.io/debug-adapter-protocol/specification)
with Xcode's debugger UI and
[VS Code's debugging](https://code.visualstudio.com/docs/debugtest/debugging)
behind it: breakpoints with conditions, hit counts and log messages,
exception filters, watch expressions, the debug hover, Run to Cursor. It
knows no language: a debug adapter (a program that speaks DAP on its
standard input and output, each message a `Content-Length` header and JSON,
as LSP's) does the debugging, and comes from a grammar bundle or from the
host application. What the adapter's capabilities do not offer is not sent,
and is greyed or hidden, as VS Code does.

---

## The pieces

| Piece | Where | What |
|-------|-------|------|
| `LSPTransport` | LSPKit | Content-Length framed JSON over a process it starts, or two file handles; LSP's and DAP's |
| `DAPClient` | LSPKit | the protocol: requests (seq) answered to a target and action, events to a delegate, capabilities |
| `UDBreakpointStore` | UDCodeKit `Debug/` | a workspace's breakpoints by file (with their conditions), its watch expressions and exception filters; the debugger's line |
| `UDDebugSession` | UDCodeKit `Debug/` | one session: state, threads, frames, scopes and variables, watches, stepping, console |
| `UDDebugBarViewController` | UDCodeKit `Debug/`, `UDDebugBar.xib` | continue/pause, step over, into, out (back), stop, where it stands |
| `UDDebugNavigatorViewController` | UDCodeKit `Debug/`, `UDDebugNavigator.xib` | threads and their call stacks |
| `UDBreakpointNavigatorViewController` | UDCodeKit `Debug/`, `UDBreakpointNavigator.xib` | the exception filters and every breakpoint (VS Code's BREAKPOINTS, as Xcode's breakpoint navigator) |
| `UDDebugAreaViewController` | UDCodeKit `Debug/`, `UDDebugArea.xib` | the watch expressions and the variables beside the console and its evaluate line |
| `UDBreakpointEditorViewController` | UDCodeKit `Debug/`, `UDBreakpointEditor.xib` | a breakpoint's condition, hit count and log message (VS Code's breakpoint widget) |
| `UDDebugHoverViewController` | UDCodeKit `Debug/`, `UDDebugHover.xib` | an expression's value at the mouse (VS Code's debug hover) |
| `UDCodeEditorViewController` | UDCodeKit | breakpoints in the gutter and its menus, the green line, the hover, Run to Cursor |

The breakpoints follow their lines as the file is edited (each one is a
decoration in the open file's text model), and are sent to the adapter
again, per file, when they change or move. A click on a line number adds
one, a second disables it, a third enables it; dragging one off the gutter
removes it; Toggle Breakpoint (⌘\) adds or removes one at the caret.

---

## VS Code's features

**Breakpoints.** A breakpoint may have a condition (an expression), a hit
count (the adapter's syntax: "5", ">= 5", ...) and a log message (a
logpoint: printed, with the adapter's `{expression}`s evaluated, instead of
stopping), sent in `setBreakpoints`' SourceBreakpoint as VS Code sends them,
each only when the adapter says it takes it (`supportsConditionalBreakpoints`,
`supportsHitConditionalBreakpoints`, `supportsLogPoints`); one that has what
the adapter cannot take is sent without it and shown as not bound, with VS
Code's reason ("Logpoints are not supported by this debugger."). The gutter
marks a conditional one with "=" and a logpoint with a diamond on its tag.
A right click (or a control click) on a line number gives VS Code's gutter
menu: on a breakpoint Edit Breakpoint…, Disable/Enable Breakpoint, Delete
Breakpoint; on a line Add Breakpoint, Add Conditional Breakpoint…, Add
Logpoint…, Run to Line. Edit Breakpoint… opens VS Code's breakpoint widget
the native way: a box laid over the editor just below the line (where VS
Code's widget and Xcode's popover open), a popup for Expression, Hit Count or
Log Message and one field; Return keeps all three, Escape none, a click
elsewhere keeps them; what the running session's adapter cannot do is greyed
in the popup.

**Breakpoint navigator.** VS Code's BREAKPOINTS, where Xcode has its
breakpoint navigator (⌘8 in UDCode): the exception filters first (when the
adapter offers `exceptionBreakpointFilters`; kept after the session, as VS
Code keeps them), then every breakpoint by file, each with a check box; a
breakpoint not bound grey, why in its tooltip. A double click shows its line;
its menu has Edit Breakpoint…, Disable/Enable, Delete, Reveal in Editor, and
Enable All, Disable All, Delete All Breakpoints; − deletes the selected one.
The filters that are on go in `setExceptionBreakpoints` (before
`configurationDone`, and again when one is turned on or off).

**Watch expressions.** VS Code's WATCH, where Xcode puts its watch
expressions: the first rows of the debug area's variables view, above the
scopes. Each is evaluated (context "watch") in the selected frame at every
stop and frame chosen, and opens when its value is structured; one that does
not evaluate shows the adapter's message, grey. + (or Add Expression… in the
variables' menu) adds one, written in place; a double click, or Edit
Expression, edits one (emptied, it goes); − or Delete Expression removes it,
Delete All Expressions all. Add to Watch is in the variables' menu (by a
variable's `evaluateName`) and in the text's menu (the selection, or the
expression at the caret).

**The variables' menu.** Copy Value (evaluated with context "clipboard" when
the adapter `supportsClipboardContext` and the variable has an
`evaluateName`, as VS Code does; its value otherwise), Copy as Expression and
Add to Watch (its `evaluateName`), Set Value… (`setVariable`, when the
adapter `supportsSetVariable`; a double click on a value too). After a value
is set, the watches are evaluated again.

**The variables view, as Xcode's.** What was expanded is expanded again at
the next stop. A value that changed since the last stop (the same frame's,
the same name's) shows blue. The filter field under the variables leaves the
watches and variables whose name has its text, or that have such a child
loaded; the scopes stay.

**The debuggee's process.** The adapter's `process` event gives the session
its `processID`, which a host brings forward as the debuggee runs (Xcode's
behaviors); the demo adapter says its own.

**The debug hover.** While the session is stopped in the file, and the
adapter `supportsEvaluateForHovers`, the mouse resting on an identifier
evaluates the expression VS Code would there (its
`getExactExpressionStartAndEnd`: "a.b" of "a.b.c" over the b, `p->x`, `A::b`),
or the selection when the mouse is in it, with context "hover" in the selected
frame, and shows "expression = value" below it, a structured value's
children under that (they open). The language server's hover is not asked
then. What does not evaluate shows nothing. The mouse can go into it; it goes
when the mouse leaves it, or the session runs on.

**Run to Cursor and Jump to Cursor.** In the text's menu while debugging (on
top, as VS Code has them; the caret goes to the click first) and in a host's
Debug menu (`runToCursor:`, `jumpToCursor:` to the first responder). Run to
Cursor is VS Code's, client-side: a breakpoint at the line for this once
(sent with the file's others, unless an enabled one that always stops is
there), then `continue` once the adapter has it; it goes at the next stop.
Jump to Cursor is VS Code's too: `gotoTargets` at the line, then `goto` to its
first target, only when the adapter `supportsGotoTargetsRequest`.

**Stepping back.** Step Back and Reverse Continue (`stepBack`,
`reverseContinue`) show in the debug bar only when the adapter
`supportsStepBack`, as in VS Code.

Not done (yet): function and data breakpoints, breakpoint modes and
exception filter conditions (`supportsExceptionFilterOptions`), Restart Frame,
the exceptionInfo widget (the stop's description shows in the debug bar),
inline values, Toggle Activate Breakpoints, `setExpression` for watches,
variable paging, the debug console's completions and multi-session.

---

## A grammar bundle's adapter

A bundle gives its language's adapter from its principal class
(`UDExtension.h`); both methods are optional:

```objc
/// The adapter's command line: its executable's absolute path, then its arguments.
- (nullable NSArray<NSString *> *)debugAdapterCommandForIdentifier:(NSString *)identifier;

/// The launch request's arguments for debugging the file at fileURL; nil
/// for { "program": its path }.
- (nullable NSDictionary *)debugLaunchArgumentsForIdentifier:(NSString *)identifier
                                                     fileURL:(NSURL *)fileURL;
```

`UDLanguageMode` asks for them each time (`debugAdapterCommand`,
`-debugLaunchArgumentsForFileURL:`), and
`+[UDDebugSession sessionForLanguageMode:breakpoints:]` makes a session over
the mode's adapter, with the mode's identifier as `initialize`'s adapterID.

---

## A host

One breakpoint store per window, shared by its editors:

```objc
UDBreakpointStore *breakpoints = [[UDBreakpointStore alloc] init];
// each editor of a file:
[editor showBreakpointsOfStore:breakpoints forFile:fileURL.path];
```

The debugger's views, each from its XIB, wherever the window has room for
them (Xcode: the navigators on the left, the bar and the area below the
editors):

```objc
UDDebugNavigatorViewController *navigator = [[UDDebugNavigatorViewController alloc] init];
UDBreakpointNavigatorViewController *breakpointNavigator = [[UDBreakpointNavigatorViewController alloc] init];
breakpointNavigator.breakpoints = breakpoints;
breakpointNavigator.delegate = self;      // shows a breakpoint's line, its editor's box
UDDebugBarViewController *bar = [[UDDebugBarViewController alloc] init];
UDDebugAreaViewController *area = [[UDDebugAreaViewController alloc] init];
area.breakpoints = breakpoints;           // the watch expressions, before a session
```

The breakpoint navigator's delegate:

```objc
- (void)breakpointNavigator:(UDBreakpointNavigatorViewController *)navigator showBreakpoint:(UDBreakpoint *)breakpoint;
- (void)breakpointNavigator:(UDBreakpointNavigatorViewController *)navigator editBreakpoint:(UDBreakpoint *)breakpoint;
    // the file shown, then [editor editBreakpointAtLine:breakpoint.line]
```

What the store holds (the breakpoints with their conditions, the watch
expressions, the exception filters and which are on) is the workspace's to
keep: `-propertyList` and `-restorePropertyList:` for a workspace file, or
`autosaveName` for the user defaults (restored when it is set, saved at
every change):

```objc
breakpoints.autosaveName = [@"MyApp Debugger " stringByAppendingString:workspacePath];
```

A session, over the adapter the host chooses and with the arguments it
builds (the game's paths, say), or the bundle's:

```objc
UDDebugSession *session =
    [[UDDebugSession alloc] initWithAdapterCommand:@[ adapterPath, @"--stdio" ]
                              currentDirectoryPath:nil
                                       breakpoints:breakpoints];
session.adapterID = @"udscript";
session.delegate = self;                  // shows the selected frame's file
navigator.session = bar.session = area.session = session;
[session launchWithArguments:@{ @"program": ..., ... }];   // or -attachWithArguments:
```

or, over an adapter the host talks to some other way,
`-[UDDebugSession initWithClient:breakpoints:]` with a `DAPClient` made with
`-initWithReadHandle:writeHandle:`.

The delegate shows the file of the frame chosen (the stopped thread's top
one, or one picked in the navigator), opening it when it is not open:

```objc
- (void)debugSession:(UDDebugSession *)session showFile:(NSString *)path line:(NSInteger)line;
- (void)debugSessionDidEnd:(UDDebugSession *)session;
```

An editor opened for that file shows the breakpoints and the green line as
soon as it is given the store; the session it runs is the store's
`debugSession` while it runs, which the editors ask for the hover and Run to
Cursor. The menu items (Run, Stop, Continue or Pause, Step Over/Into/Out,
Step Back) send the bar's actions (`-continueOrPause:`, `-stepOver:`,
`-stepInto:`, `-stepOut:`, `-stepBack:`, `-reverseContinue:`, `-stop:`) and
validate with `-[UDDebugBarViewController canPerformAction:]`; Run to Cursor
and Jump to Cursor send `runToCursor:` and `jumpToCursor:` to the first
responder (the editor's text view hands them to its editor).

### What the session sends

1. `initialize` (lines and columns 1-based, paths as paths; no
   runInTerminal), then `launch` or `attach` with the host's arguments.
2. On the `initialized` event: `setBreakpoints` for each file with
   breakpoints (the enabled ones: `line`, and `condition`, `hitCondition`,
   `logMessage` as the adapter takes them), `setExceptionBreakpoints` with
   the filters that are on (when the adapter has any), then
   `configurationDone` when the adapter supports it.
3. On `stopped`: `threads`, then `stackTrace` of the thread that stopped;
   its top frame (the first with a source) is selected, and its `scopes`
   asked for, and the watch expressions evaluated (`evaluate`, context
   "watch"); `variables` as the variables view opens them. Another thread's
   frames when it is opened in the navigator.
4. `continue`, `next`, `stepIn`, `stepOut`, `pause` (and `stepBack`,
   `reverseContinue`) on the selected thread; `evaluate` with context "repl"
   from the console's line, "hover" for the debug hover, "clipboard" for
   Copy Value; `setVariable` for Set Value; `setBreakpoints` with Run to
   Cursor's line, then `continue`; `gotoTargets` and `goto` for Jump to
   Cursor.
5. On `terminated`, or Stop: `disconnect` (terminating a launched debuggee,
   leaving an attached one), and the adapter is ended.

Requests the adapter sends (`runInTerminal`, `startDebugging`) are answered
unsuccessfully.

---

## UDCode

Debug > Run (⌘R) debugs the selected file (saved: the adapter reads it from
disk) with its language's adapter, or with the demo adapter: UDCode itself,
started as `UDCode --debug-adapter`, which "runs" a text file a line at a
time — each line a statement, `print …` lines printing, `throw …` and
`warn …` raising what its exception filters (Errors, on by default;
Warnings) stop at — with two threads, frames for each step into, Locals
(with a structured variable) and Globals, evaluate for a variable (by its
`evaluateName`, "info.length") or two compared, and every capability the
features above take: conditions, hit counts, log messages, setVariable,
gotoTargets, the clipboard context, stepping back. `--without=a,b` after the
option leaves those capabilities out. The tests use the same adapter, in
their own process over pipes and as a process. Its breakpoints, watch
expressions and filters are kept in the user defaults by the workspace's
path; View > Breakpoints (⌘8) shows the breakpoint navigator, Debug > Run to
Cursor (⌃⌘C), Jump to Cursor and Step Back are in the Debug menu.
