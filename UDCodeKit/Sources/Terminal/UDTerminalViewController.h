/*---------------------------------------------------------------------------------------------
 *  UDTerminalViewController.h
 *
 *  A terminal in the window: a shell (the user's, a login shell) on a
 *  pseudo-terminal, its screen a UDTerminalView, laid out in UDTerminal.xib.
 *  When the shell ends, the screen says so; starting again resets it.
 *--------------------------------------------------------------------------------------------*/

#import <Cocoa/Cocoa.h>
#import "UDTerminalView.h"
#import "UDPseudoTerminal.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDTerminalViewController : NSViewController <UDTerminalViewDelegate, UDPseudoTerminalDelegate>

/// Loads UDTerminal.xib from UDCodeKit's bundle.
- (instancetype)init;

@property (nonatomic, weak, readonly) IBOutlet UDTerminalView *terminalView;

/// The shell this terminal runs: $SHELL, else the system's.
+ (NSString *)defaultShell;

/// The user's shell, a login one, in @a directory, with @a environment (the
/// process's own when nil).
- (BOOL)startShellInDirectory:(nullable NSString *)directory environment:(nullable NSDictionary<NSString *, NSString *> *)environment;
/// Any program, @a arguments' first its path.
- (BOOL)startArguments:(NSArray<NSString *> *)arguments directory:(nullable NSString *)directory
           environment:(nullable NSDictionary<NSString *, NSString *> *)environment;
@property (nonatomic, readonly, getter=isRunning) BOOL running;
@property (nonatomic, readonly, nullable) UDPseudoTerminal *pseudoTerminal;

/// Hangs up on the program.
- (void)stop;

@end

NS_ASSUME_NONNULL_END
