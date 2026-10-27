/*---------------------------------------------------------------------------------------------
 *  UDDebugSession.h
 *
 *  One debugging session over a debug adapter (DAPClient): what the
 *  debugger's views show, and the actions they take.
 *
 *    - its state: starting, running, stopped, ended;
 *    - the threads, and the stopped thread's call stack (another thread's
 *      when asked for, -loadFramesOfThread:);
 *    - the selected frame (the stopped thread's top one, or the one chosen)
 *      and its scopes, each a variable whose children load when asked
 *      (-loadChildrenOfVariable:), as an outline expands;
 *    - the console: what the adapter prints, and what -evaluate: answers;
 *    - the watch expressions (the store's), evaluated in the selected
 *      frame, and any expression evaluated for a hover or a copy;
 *    - continue, pause, step over, into and out (and back, when the adapter
 *      can), Run to Cursor and Jump to Cursor, and stop;
 *    - the breakpoints (UDBreakpointStore): sent per file when the adapter
 *      is ready and whenever a file's change, with their conditions, hit
 *      counts and log messages as far as the adapter takes them, verified
 *      by its answers; the exception filters that are on; and the
 *      instruction pointer, set in the store at the selected frame.
 *
 *  Who shows the selected frame's file is the delegate's business: the host
 *  opens it (-debugSession:showFile:line:).
 *
 *  Starting it:
 *
 *      UDDebugSession *session =
 *          [[UDDebugSession alloc] initWithAdapterCommand:@[@"/path/to/adapter", @"--stdio"]
 *                                    currentDirectoryPath:nil
 *                                             breakpoints:store];
 *      session.delegate = self;
 *      [session launchWithArguments:@{ @"program": path }];   // the adapter's own
 *
 *  Its changes are posted (the notifications below; the object is the
 *  session), on the main thread.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import <LSPKit/LSPKit.h>
#import "UDBreakpointStore.h"

/* UDCodeKit's own: exported where it is built for Windows (its GNUmakefile),
   imported everywhere else, as FOUNDATION_EXPORT. */
#ifndef UDCODEKIT_EXPORT
#define UDCODEKIT_EXPORT FOUNDATION_EXPORT
#endif

@class UDDebugSession, UDDebugThread, UDLanguageMode;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, UDDebugSessionState) {
    /// initialize, launch or attach, the breakpoints and configurationDone.
    UDDebugSessionStateStarting,
    UDDebugSessionStateRunning,
    UDDebugSessionStateStopped,
    UDDebugSessionStateEnded,
};

/// The state changed.
UDCODEKIT_EXPORT NSNotificationName const UDDebugSessionDidChangeStateNotification;
/// The threads changed, or a thread's frames loaded.
UDCODEKIT_EXPORT NSNotificationName const UDDebugSessionDidChangeThreadsNotification;
/// Another frame (or none) is selected; its scopes are on their way.
UDCODEKIT_EXPORT NSNotificationName const UDDebugSessionDidSelectFrameNotification;
/// Variables loaded: the selected frame's scopes (no UDDebugSessionVariableKey),
/// or a variable's children (the variable under UDDebugSessionVariableKey).
UDCODEKIT_EXPORT NSNotificationName const UDDebugSessionDidLoadVariablesNotification;
/// The watch expressions were evaluated (or their values went: the session
/// runs, or ended).
UDCODEKIT_EXPORT NSNotificationName const UDDebugSessionDidEvaluateWatchesNotification;
/// Text went to the console: UDDebugSessionOutputKey, and its category
/// (DAP's: "console", "stdout", "stderr"; "input" for what was evaluated,
/// "result" for its answer) under UDDebugSessionOutputCategoryKey.
UDCODEKIT_EXPORT NSNotificationName const UDDebugSessionDidOutputNotification;

UDCODEKIT_EXPORT NSString * const UDDebugSessionVariableKey;
UDCODEKIT_EXPORT NSString * const UDDebugSessionOutputKey;
UDCODEKIT_EXPORT NSString * const UDDebugSessionOutputCategoryKey;

/// A frame of a thread's call stack.
@interface UDDebugStackFrame : NSObject
@property (nonatomic, readonly) NSInteger frameID;
@property (nonatomic, readonly, copy) NSString *name;
/// The file it is in, nil when the adapter has no source for it.
@property (nonatomic, readonly, copy, nullable) NSString *path;
@property (nonatomic, readonly) NSInteger line;
@property (nonatomic, readonly) NSInteger column;
@property (nonatomic, readonly, weak) UDDebugThread *thread;
@end

@interface UDDebugThread : NSObject
@property (nonatomic, readonly) NSInteger threadID;
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, getter=isStopped) BOOL stopped;
/// Why it stopped ("breakpoint", "step", "pause", "entry", "exception", ...).
@property (nonatomic, readonly, copy, nullable) NSString *stopReason;
/// What the adapter said of it (an exception's message, say).
@property (nonatomic, readonly, copy, nullable) NSString *stopDescription;
/// Its call stack, top first, when stopped and loaded; nil before.
@property (nonatomic, readonly, copy, nullable) NSArray<UDDebugStackFrame *> *frames;
@end

/// A scope or a variable: a name, a value, and children when it has any
/// (variablesReference), loaded when asked. Or what an expression
/// evaluated to: named by the expression, its value the result.
@interface UDDebugVariable : NSObject
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, copy) NSString *value;
/// An expression that evaluates to it ("info.length"), when the adapter
/// gives one: what Copy as Expression copies and Add to Watch watches.
@property (nonatomic, readonly, copy, nullable) NSString *evaluateName;
/// An expression that did not evaluate: its value is the adapter's message.
@property (nonatomic, readonly, getter=isFailed) BOOL failed;
@property (nonatomic, readonly, copy, nullable) NSString *type;
@property (nonatomic, readonly) NSInteger variablesReference;
/// A scope the adapter calls expensive (not loaded unless asked).
@property (nonatomic, readonly, getter=isExpensive) BOOL expensive;
@property (nonatomic, readonly) BOOL hasChildren;
/// nil until loaded.
@property (nonatomic, readonly, copy, nullable) NSArray<UDDebugVariable *> *children;
@property (nonatomic, readonly, weak, nullable) UDDebugVariable *parent;
@end

@protocol UDDebugSessionDelegate <NSObject>
@optional
/// A frame was selected (the stopped thread's top one, or one chosen in the
/// navigator): show @a path at @a line, opening it when it is not open.
- (void)debugSession:(UDDebugSession *)session showFile:(NSString *)path line:(NSInteger)line;
/// The session ended: stopped, or the adapter ended.
- (void)debugSessionDidEnd:(UDDebugSession *)session;
@end

@interface UDDebugSession : NSObject

/// A session over the adapter @a command starts (the executable's path,
/// then its arguments).
- (instancetype)initWithAdapterCommand:(NSArray<NSString *> *)command
                  currentDirectoryPath:(nullable NSString *)directory
                           breakpoints:(UDBreakpointStore *)breakpoints;
/// A session over an adapter the host has a client of already.
- (instancetype)initWithClient:(DAPClient *)client
                   breakpoints:(UDBreakpointStore *)breakpoints NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// A session over the debug adapter @a mode's extension gives
/// (-debugAdapterCommandForIdentifier:), nil when it gives none.
+ (nullable instancetype)sessionForLanguageMode:(UDLanguageMode *)mode
                                    breakpoints:(UDBreakpointStore *)breakpoints;

@property (nonatomic, weak, nullable) id<UDDebugSessionDelegate> delegate;
@property (nonatomic, readonly) DAPClient *client;
@property (nonatomic, readonly) UDBreakpointStore *breakpoints;

/// initialize's adapterID (the adapter's type: "udscript", say); "udcodekit"
/// unless set before launching.
@property (nonatomic, copy) NSString *adapterID;
/// initialize's clientName: the application's name unless set.
@property (nonatomic, copy) NSString *clientName;

/// Starts the debugging: initialize, then launch (or attach) with the
/// adapter's own @a arguments; the breakpoints and configurationDone when
/// it is ready.
- (void)launchWithArguments:(NSDictionary *)arguments;
- (void)attachWithArguments:(NSDictionary *)arguments;

@property (nonatomic, readonly) UDDebugSessionState state;
/// The debuggee's process, as the adapter's process event says it (its
/// systemProcessId); 0 until it says, or when it does not: what a host
/// brings forward when the debuggee runs.
@property (nonatomic, readonly) pid_t processID;

@property (nonatomic, readonly, copy) NSArray<UDDebugThread *> *threads;
@property (nonatomic, readonly, nullable) UDDebugThread *selectedThread;
@property (nonatomic, readonly, nullable) UDDebugStackFrame *selectedFrame;
/// The selected frame's scopes; nil before they load.
@property (nonatomic, readonly, copy, nullable) NSArray<UDDebugVariable *> *scopes;

/// Selects @a frame (and its thread), loads its scopes and has the
/// delegate show it.
- (void)selectFrame:(UDDebugStackFrame *)frame;
/// Loads a stopped thread's call stack (a thread other than the one that stopped).
- (void)loadFramesOfThread:(UDDebugThread *)thread;
/// Loads @a variable's children; posted when they are in.
- (void)loadChildrenOfVariable:(UDDebugVariable *)variable;

/// Evaluates @a expression in the selected frame, in @a context ("hover",
/// "watch", "repl", "clipboard"), and sends @a action to @a target with a
/// UDDebugVariable: named by the expression, its value the result (or,
/// failed, the adapter's message), its children loaded by
/// -loadChildrenOfVariable: as any variable's. Nothing is sent when the
/// session has moved on (run, or another frame) before the answer.
- (void)evaluate:(NSString *)expression context:(NSString *)context target:(nullable id)target action:(nullable SEL)action;

/// The store's watch expressions, in its order, as evaluated in the
/// selected frame (context "watch"): evaluated whenever it stops, another
/// frame is selected or they change; nil while it is not stopped.
@property (nonatomic, readonly, copy, nullable) NSArray<UDDebugVariable *> *watches;

/// Whether a variable can be set (setVariable): stopped, and the adapter
/// supports it; and @a variable is one of a scope or of a structured value.
@property (nonatomic, readonly) BOOL canSetVariables;
- (BOOL)canSetVariable:(UDDebugVariable *)variable;
/// Sets @a variable to @a value (an expression in the adapter's language):
/// it takes the adapter's answer (posted as UDDebugSessionDidLoadVariables
/// with it), and the watches are evaluated again; a refusal goes to the
/// console.
- (void)setValue:(NSString *)value ofVariable:(UDDebugVariable *)variable;

/// The actions, on the selected thread. Each does nothing when it may not.
- (void)continueExecution;
- (void)pause;
- (void)stepOver;
- (void)stepInto;
- (void)stepOut;
/// Step back and reverse continue: an adapter that supports stepping back.
- (void)stepBack;
- (void)reverseContinue;
/// Run to Cursor, as VS Code's: a breakpoint at @a line of @a path for this
/// once (unless an enabled one is there), and continue; it goes at the next
/// stop.
- (void)runToLine:(NSInteger)line inFile:(NSString *)path;
/// Jump to Cursor (gotoTargets, then goto), when the adapter supports it:
/// the selected thread goes on from @a line, without running what is
/// between, and stops there.
- (void)jumpToLine:(NSInteger)line inFile:(NSString *)path;
/// Ends the session: the debuggee (a launched one) and the adapter.
- (void)stop;
@property (nonatomic, readonly) BOOL canContinue;   // stopped
@property (nonatomic, readonly) BOOL canPause;      // running
@property (nonatomic, readonly) BOOL canStep;       // stopped
@property (nonatomic, readonly) BOOL canStepBack;   // stopped, and the adapter supports stepping back
@property (nonatomic, readonly) BOOL canJump;       // stopped, and the adapter supports gotoTargets
@property (nonatomic, readonly) BOOL canStop;       // not ended

/// Everything the console has shown.
@property (nonatomic, readonly, copy) NSString *consoleText;
/// The console's line: @a expression is evaluated in the selected frame
/// (context "repl"), and it and its answer go to the console.
- (void)evaluate:(NSString *)expression;

@end

NS_ASSUME_NONNULL_END
