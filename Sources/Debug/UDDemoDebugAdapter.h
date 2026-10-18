/*---------------------------------------------------------------------------------------------
 *  UDDemoDebugAdapter.h
 *
 *  A debug adapter for trying the debugger out: it "runs" a text file a line
 *  at a time, as if each line were a statement. UDCode starts itself as one
 *  (UDCode --debug-adapter: its standard input and output) for Debug > Run,
 *  and the tests talk to one over pipes.
 *
 *  What it does, in the Debug Adapter Protocol:
 *
 *    launch { program, stopOnEntry }   the file to run
 *    setBreakpoints                    lines of the program; verified when
 *                                      they are in it; a condition, a hit
 *                                      count ("N" is ">= N"; ==, >, >=, <,
 *                                      <=, % N) and a log message ("{expr}"
 *                                      in it evaluated)
 *    setExceptionBreakpoints           its filters: "throw" (Errors, on by
 *                                      default) stops at a "throw …" line,
 *                                      "warn" (Warnings) at a "warn …" one
 *    configurationDone                 runs: stops at line 1 (stopOnEntry),
 *                                      at a breakpoint, or runs to the end
 *    threads                           1 "main", 2 "worker" (always idle)
 *    stackTrace                        main's: the line it is at, then the
 *                                      lines it stepped in from
 *    scopes, variables                 Locals (line, text, and info, which
 *                                      has children) and Globals (expensive)
 *    next, stepIn, stepOut             a line on; a frame deeper; back out
 *    stepBack, reverseContinue         a line back; back to a breakpoint
 *    continue, pause                   runs, a few lines per turn of the
 *                                      run loop, until a breakpoint or paused
 *    evaluate                          a variable's name ("info.length" for
 *                                      a child), a number or a string, or two
 *                                      compared (==, !=, <, <=, >, >=)
 *    setVariable                       a variable's value, until it runs on
 *    gotoTargets, goto                 any line of the program, in main's
 *                                      top frame
 *    terminate, disconnect             ends (the process, when it is one)
 *
 *  A line that starts with "print " prints the rest (an output event) when
 *  it runs; "throw " and "warn " lines raise an error and a warning, which
 *  stop it when their filter is on (and are printed when not).
 *
 *  It has every capability those take, unless told to leave some out:
 *  withheldCapabilities, or "--without=supportsLogPoints,…" after the
 *  option on UDCode's command line.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// The command-line option that makes UDCode its own debug adapter.
extern NSString * const UDDemoDebugAdapterOption;

@interface UDDemoDebugAdapter : NSObject

/// Requests read from @a readHandle, responses and events written to
/// @a writeHandle. Ends by closing @a writeHandle.
- (instancetype)initWithReadHandle:(NSFileHandle *)readHandle writeHandle:(NSFileHandle *)writeHandle;

/// Whether it has ended (disconnected).
@property (nonatomic, readonly, getter=isFinished) BOOL finished;

/// Every request it has had, in order ({command, arguments}), for tests.
@property (nonatomic, readonly) NSArray<NSDictionary *> *requests;

/// The capabilities it leaves out of its answer to initialize (their names:
/// "supportsLogPoints", "exceptionBreakpointFilters", ...).
@property (nonatomic, copy) NSArray<NSString *> *withheldCapabilities;

/// Runs one on standard input and output until it is disconnected; its
/// command line's @a arguments after the option ("--without=…").
+ (int)runOnStandardStreamsWithArguments:(NSArray<NSString *> *)arguments;

@end

NS_ASSUME_NONNULL_END
