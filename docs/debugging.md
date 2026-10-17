# Debugging

UDCodeKit is a client of the
[Debug Adapter Protocol](https://microsoft.github.io/debug-adapter-protocol/specification)
with Xcode's debugger UI. It knows no language: a debug adapter (a program
that speaks DAP on its standard input and output, each message a
`Content-Length` header and JSON, as LSP's) does the debugging, and comes
from a grammar bundle or from the host application.

---

## The pieces

| Piece | Where | What |
|-------|-------|------|
| `LSPTransport` | LSPKit | Content-Length framed JSON over a process it starts, or two file handles; LSP's and DAP's |
| `DAPClient` | LSPKit | the protocol: requests (seq) answered to a target and action, events to a delegate, capabilities |
| `UDBreakpointStore` | UDCodeKit `Debug/` | a workspace's breakpoints by file; the debugger's line |
| `UDDebugSession` | UDCodeKit `Debug/` | one session: state, threads, frames, scopes and variables, stepping, console |
| `UDDebugBarViewController` | UDCodeKit `Debug/`, `UDDebugBar.xib` | continue/pause, step over, into, out, stop, where it stands |
| `UDDebugNavigatorViewController` | UDCodeKit `Debug/`, `UDDebugNavigator.xib` | threads and their call stacks |
| `UDDebugAreaViewController` | UDCodeKit `Debug/`, `UDDebugArea.xib` | variables beside the console and its evaluate line |
| `UDCodeEditorViewController` | UDCodeKit | breakpoints in the gutter, the green line |

The breakpoints follow their lines as the file is edited (each one is a
decoration in the open file's text model), and are sent to the adapter
again, per file, when they change or move. A click on a line number adds
one, a second disables it, a third enables it; dragging one off the gutter
removes it; Toggle Breakpoint (⌘\) adds or removes one at the caret.

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
them (Xcode: the navigator on the left, the bar and the area below the
editors):

```objc
UDDebugNavigatorViewController *navigator = [[UDDebugNavigatorViewController alloc] init];
UDDebugBarViewController *bar = [[UDDebugBarViewController alloc] init];
UDDebugAreaViewController *area = [[UDDebugAreaViewController alloc] init];
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
soon as it is given the store. The menu items (Run, Stop, Continue or Pause,
Step Over/Into/Out) send the bar's actions (`-continueOrPause:`,
`-stepOver:`, `-stepInto:`, `-stepOut:`, `-stop:`) and validate with
`-[UDDebugBarViewController canPerformAction:]`.

### What the session sends

1. `initialize` (lines and columns 1-based, paths as paths; no
   runInTerminal), then `launch` or `attach` with the host's arguments.
2. On the `initialized` event: `setBreakpoints` for each file with
   breakpoints (the enabled ones), then `configurationDone` when the
   adapter supports it.
3. On `stopped`: `threads`, then `stackTrace` of the thread that stopped;
   its top frame (the first with a source) is selected, and its `scopes`
   asked for; `variables` as the variables view opens them. Another
   thread's frames when it is opened in the navigator.
4. `continue`, `next`, `stepIn`, `stepOut`, `pause` on the selected thread;
   `evaluate` (context "repl") from the console's line.
5. On `terminated`, or Stop: `disconnect` (terminating a launched debuggee,
   leaving an attached one), and the adapter is ended.

Requests the adapter sends (`runInTerminal`, `startDebugging`) are answered
unsuccessfully.

---

## UDCode

Debug > Run (⌘R) debugs the selected file (saved: the adapter reads it from
disk) with its language's adapter, or with the demo adapter: UDCode itself,
started as `UDCode --debug-adapter`, which "runs" a text file a line at a
time — each line a statement, `print …` lines printing — with two threads,
frames for each step into, Locals (with a structured variable) and Globals,
and evaluate for a variable's name. The tests use the same adapter, in
their own process over pipes and as a process.
