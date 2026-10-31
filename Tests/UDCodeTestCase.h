/*---------------------------------------------------------------------------------------------
 *  UDCodeTestCase.h
 *
 *  The editor's test cases' base: the shared application exists before a
 *  case runs. On macOS UDCode hosts the tests and has made it already; on
 *  GNUstep xctest runs them hostless, and nothing that touches a font or a
 *  view may run before it.
 *
 *  For the debugger's tests: the demo debug adapter, in this process over
 *  pipes or as a process of its own, and a way to wait for its answers.
 *--------------------------------------------------------------------------------------------*/

#import <XCTest/XCTest.h>
#import <LSPKit/LSPKit.h>

@class UDDemoDebugAdapter;

/// Runs the run loop until @a condition holds, or @a seconds have passed.
#define UDRunUntil(condition, seconds)                                                              \
    for (NSDate *_deadline = [NSDate dateWithTimeIntervalSinceNow:(seconds)];                        \
         !(condition) && [_deadline timeIntervalSinceNow] > 0;)                                     \
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode                                    \
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]]

@interface UDCodeTestCase : XCTestCase

/// A client of a demo debug adapter in this process (returned in @a adapter).
+ (DAPClient *)clientOfAdapter:(UDDemoDebugAdapter * __strong *)adapter;

/// UDCode's executable, which is the demo debug adapter with --debug-adapter:
/// the test host on macOS; on GNUstep the UDCode.app the tree built (beside
/// the PlugIns folder $UD_PLUGINS_PATH names).
+ (NSString *)udcodeExecutablePath;

/// A file in the temporary folder with @a text.
+ (NSString *)temporaryFileNamed:(NSString *)name text:(NSString *)text;

/// A click (⌘ or not) on @a view's character at @a index, where it is drawn:
/// its mouse down sent to the window, its up waiting in the queue.
+ (void)clickTextView:(NSTextView *)view atIndex:(NSUInteger)index command:(BOOL)command;

@end
