//
//  DAPClient.h
//  LSPKit
//
//  A client of the Debug Adapter Protocol
//  (https://microsoft.github.io/debug-adapter-protocol/specification): an
//  adapter's process, started from its command line, or an adapter over two
//  file handles, spoken to in requests whose responses go to a target and an
//  action, and heard from in events, which go to the delegate. Its messages
//  are framed as LSP's are (LSPTransport). Everything happens on the main
//  run loop.
//
//  The usual order (the specification's "Debug session start"):
//
//    -initializeWithAdapterID:…     capabilities come back
//    -launchWithArguments:… or -attachWithArguments:…
//    initialized event              -debugAdapterDidInitialize:
//    -setBreakpointsInFile:…        for each file with breakpoints
//    -configurationDoneWithTarget:… when the adapter supports it
//    stopped, continued, output, ... events; threads, stackTrace, scopes,
//    variables, evaluate and the stepping requests
//    -disconnectTerminatingDebuggee:…, and the adapter ends
//

#import <Foundation/Foundation.h>

#import <LSPKit/LSPTransport.h>

NS_ASSUME_NONNULL_BEGIN

@class DAPClient;

/// Errors: a request the adapter answered unsuccessfully, or one it never
/// answered because it ended.
FOUNDATION_EXPORT NSErrorDomain const DAPErrorDomain;

typedef NS_ENUM(NSInteger, DAPErrorCode) {
    /// The adapter answered success: false; the error's description is its message.
    DAPErrorRequestFailed = 1,
    /// The adapter ended before answering.
    DAPErrorAdapterEnded = 2,
};

/**
 * What a request came back with, handed to the action the request named.
 */
@interface DAPResponse : NSObject
/// The request's sequence number (what the request method returned).
@property (readonly) NSInteger requestSeq;
@property (readonly, copy) NSString *command;
@property (readonly) BOOL success;
/// The adapter's body: an object for most requests (see the specification's
/// "...Response" for each).
@property (readonly, nullable) id body;
/// Not successful: why, its description the adapter's message.
@property (readonly, nullable) NSError *error;
@end

/**
 * The events, each with its body as the adapter sent it (an empty
 * dictionary when it sent none). All optional.
 */
@protocol DAPClientDelegate <NSObject>
@optional
/// "initialized": the adapter takes breakpoints now, then configurationDone.
- (void)debugAdapterDidInitialize:(DAPClient *)client;
/// "stopped": body.reason, body.threadId, body.allThreadsStopped, ...
- (void)debugAdapter:(DAPClient *)client didStop:(NSDictionary *)body;
/// "continued": body.threadId, body.allThreadsContinued.
- (void)debugAdapter:(DAPClient *)client didContinue:(NSDictionary *)body;
/// "thread": body.reason ("started", "exited"), body.threadId.
- (void)debugAdapter:(DAPClient *)client threadDidChange:(NSDictionary *)body;
/// "output": body.category, body.output, body.source, body.line, ...
- (void)debugAdapter:(DAPClient *)client didOutput:(NSDictionary *)body;
/// "breakpoint": body.reason ("changed", "new", "removed"), body.breakpoint.
- (void)debugAdapter:(DAPClient *)client breakpointDidChange:(NSDictionary *)body;
/// "terminated": the debugging is over; disconnect follows.
- (void)debugAdapter:(DAPClient *)client didTerminate:(NSDictionary *)body;
/// "exited": the debuggee ended, with body.exitCode.
- (void)debugAdapter:(DAPClient *)client debuggeeDidExit:(NSDictionary *)body;
/// Any other event ("module", "process", "capabilities", ...).
- (void)debugAdapter:(DAPClient *)client didReceiveEvent:(NSString *)event body:(NSDictionary *)body;
/// The adapter's process ended, or its output did: nothing more comes.
/// Requests still waiting are answered with DAPErrorAdapterEnded first.
- (void)debugAdapterDidEnd:(DAPClient *)client;
/// What the adapter's process wrote to its standard error.
- (void)debugAdapter:(DAPClient *)client didWriteErrorOutput:(NSString *)text;
@end

@interface DAPClient : NSObject

/// Starts the adapter: @a command's first element is the executable (an
/// absolute path), the rest its arguments, as an extension's
/// -debugAdapterCommandForIdentifier: gives them. When it cannot start,
/// -launchError says why and the delegate hears -debugAdapterDidEnd:.
- (instancetype)initWithCommand:(NSArray<NSString *> *)command
           currentDirectoryPath:(nullable NSString *)directory;

/// An adapter on the other end of two file handles: in this process, or one
/// started some other way.
- (instancetype)initWithReadHandle:(NSFileHandle *)readHandle
                       writeHandle:(NSFileHandle *)writeHandle;


@property (nonatomic, weak, nullable) id<DAPClientDelegate> delegate;

/// Why the adapter's process did not start.
@property (nonatomic, readonly, nullable) NSError *launchError;
/// Whether the adapter is still there.
@property (nonatomic, readonly, getter=isRunning) BOOL running;

#pragma mark Capabilities

/// The adapter's capabilities, as the initialize response gave them; empty before.
@property (nonatomic, readonly, copy) NSDictionary *capabilities;
@property (nonatomic, readonly) BOOL supportsConfigurationDoneRequest;
@property (nonatomic, readonly) BOOL supportsTerminateRequest;
@property (nonatomic, readonly) BOOL supportsEvaluateForHovers;
@property (nonatomic, readonly) BOOL supportsConditionalBreakpoints;

#pragma mark Requests

/*
 * Each request returns its sequence number and sends @a action to @a target
 * with a DAPResponse when the adapter answers (the target is not retained).
 * Lines and columns are 1-based (initialize says so); paths are file paths.
 */

/// Any request: @a command with its @a arguments.
- (NSInteger)sendRequest:(NSString *)command arguments:(nullable NSDictionary *)arguments
                  target:(nullable id)target action:(nullable SEL)action;

/// "initialize", with this client's own capabilities; keeps the adapter's.
- (NSInteger)initializeWithAdapterID:(NSString *)adapterID clientName:(NSString *)clientName
                              target:(nullable id)target action:(nullable SEL)action;
/// "launch" with the adapter's own arguments (program, ... whatever it wants).
- (NSInteger)launchWithArguments:(NSDictionary *)arguments target:(nullable id)target action:(nullable SEL)action;
/// "attach", likewise.
- (NSInteger)attachWithArguments:(NSDictionary *)arguments target:(nullable id)target action:(nullable SEL)action;
/// "setBreakpoints": every breakpoint of the file at @a path, replacing what
/// it had; @a breakpoints are SourceBreakpoints ({line, condition?, ...}).
/// The response's body.breakpoints are in the same order.
- (NSInteger)setBreakpointsInFile:(NSString *)path breakpoints:(NSArray<NSDictionary *> *)breakpoints
                           target:(nullable id)target action:(nullable SEL)action;
/// "configurationDone", when the adapter supports it (0, and nothing sent, when not).
- (NSInteger)configurationDoneWithTarget:(nullable id)target action:(nullable SEL)action;
/// "threads": body.threads, [{id, name}].
- (NSInteger)threadsWithTarget:(nullable id)target action:(nullable SEL)action;
/// "stackTrace" of @a threadID: body.stackFrames, from @a startFrame,
/// @a levels of them (0: all).
- (NSInteger)stackTraceOfThread:(NSInteger)threadID startFrame:(NSInteger)startFrame levels:(NSInteger)levels
                         target:(nullable id)target action:(nullable SEL)action;
/// "scopes" of a frame: body.scopes, [{name, variablesReference, expensive}].
- (NSInteger)scopesOfFrame:(NSInteger)frameID target:(nullable id)target action:(nullable SEL)action;
/// "variables" a reference names: body.variables, [{name, value, type?, variablesReference}].
- (NSInteger)variablesOfReference:(NSInteger)variablesReference target:(nullable id)target action:(nullable SEL)action;
/// "evaluate" @a expression in a frame (0: none) and @a context ("repl",
/// "watch", "hover"): body.result, body.variablesReference.
- (NSInteger)evaluate:(NSString *)expression inFrame:(NSInteger)frameID context:(NSString *)context
               target:(nullable id)target action:(nullable SEL)action;
/// "continue", "next" (step over), "stepIn", "stepOut", "pause", for @a threadID.
- (NSInteger)continueThread:(NSInteger)threadID target:(nullable id)target action:(nullable SEL)action;
- (NSInteger)nextInThread:(NSInteger)threadID target:(nullable id)target action:(nullable SEL)action;
- (NSInteger)stepInThread:(NSInteger)threadID target:(nullable id)target action:(nullable SEL)action;
- (NSInteger)stepOutThread:(NSInteger)threadID target:(nullable id)target action:(nullable SEL)action;
- (NSInteger)pauseThread:(NSInteger)threadID target:(nullable id)target action:(nullable SEL)action;
/// "terminate": the debuggee is asked to end, when the adapter supports it
/// (0, and nothing sent, when not).
- (NSInteger)terminateDebuggeeWithTarget:(nullable id)target action:(nullable SEL)action;
/// "disconnect": the session ends; the debuggee too when @a terminate (a
/// launched one) — an attached one is left running when not.
- (NSInteger)disconnectTerminatingDebuggee:(BOOL)terminate target:(nullable id)target action:(nullable SEL)action;

/// Ends the adapter's process (and stops listening to it), without asking.
- (void)close;

@end

NS_ASSUME_NONNULL_END
