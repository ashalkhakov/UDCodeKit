/*---------------------------------------------------------------------------------------------
 *  UDPseudoTerminal.h
 *
 *  A program (a shell) on a pseudo-terminal of its own (forkpty): what it
 *  writes, as it comes; what is typed, written to it; the terminal's size,
 *  which it is told of (SIGWINCH). When it ends, its exit status.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class UDPseudoTerminal;

@protocol UDPseudoTerminalDelegate <NSObject>
/// The program wrote @a data.
- (void)pseudoTerminal:(UDPseudoTerminal *)terminal didReadData:(NSData *)data;
/// It ended (its terminal closed).
- (void)pseudoTerminalDidEnd:(UDPseudoTerminal *)terminal;
@end

@interface UDPseudoTerminal : NSObject

/// @a arguments' first is the program's path; @a environment is its whole
/// environment (TERM is set when it has none).
- (instancetype)initWithArguments:(NSArray<NSString *> *)arguments
                      environment:(NSDictionary<NSString *, NSString *> *)environment
                 currentDirectory:(nullable NSString *)directory NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, weak, nullable) id<UDPseudoTerminalDelegate> delegate;

/// Starts it, @a rows by @a columns. NO when it could not be.
- (BOOL)startWithRows:(NSUInteger)rows columns:(NSUInteger)columns;
@property (nonatomic, readonly, getter=isRunning) BOOL running;
@property (nonatomic, readonly) pid_t processIdentifier;
/// Its exit status (as the shell's $?: 128 + the signal, when one ended it);
/// -1 when it is not known (on GNUstep, once an NSTask has run, NSTask reaps it).
@property (nonatomic, readonly) int exitStatus;

- (void)writeData:(NSData *)data;
- (void)setRows:(NSUInteger)rows columns:(NSUInteger)columns;
/// Hangs up on it (SIGHUP), as a terminal window closing does.
- (void)hangUp;

@end

NS_ASSUME_NONNULL_END
