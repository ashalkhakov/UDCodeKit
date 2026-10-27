/*---------------------------------------------------------------------------------------------
 *  UDTerminalViewController.m
 *--------------------------------------------------------------------------------------------*/

#import "UDTerminalViewController.h"
#import "UDShell.h"
#import <LSPKit/LSPKit.h>

@interface UDTerminalViewController ()
@property (nonatomic, weak) IBOutlet UDTerminalView *terminalView;
@property (nonatomic, strong, nullable) UDPseudoTerminal *pseudoTerminal;
@end

@implementation UDTerminalViewController

- (instancetype)init {
    return [super initWithNibName:@"UDTerminal" bundle:[NSBundle bundleForClass:[UDTerminalViewController class]]];
}

- (void)dealloc {
    [_pseudoTerminal hangUp];
}

+ (NSString *)defaultShell {
    return UDLoginShellArguments().firstObject;
}

- (BOOL)isRunning {
    return _pseudoTerminal.running;
}

- (BOOL)startShellInDirectory:(NSString *)directory environment:(NSDictionary<NSString *, NSString *> *)environment {
    return [self startArguments:UDLoginShellArguments() directory:directory environment:environment];
}

- (BOOL)startArguments:(NSArray<NSString *> *)arguments directory:(NSString *)directory
           environment:(NSDictionary<NSString *, NSString *> *)environment {
    (void)self.view;
    if (_pseudoTerminal.running) return NO;
    [_terminalView reset];
    NSMutableDictionary *env = [UDShellEnvironment(environment ?: [LSPTransport hostEnvironment]) mutableCopy];
    env[@"TERM"] = @"xterm-256color";
    env[@"COLORTERM"] = @"truecolor";
    env[@"TERM_PROGRAM"] = @"UDCode";
    _pseudoTerminal = [[UDPseudoTerminal alloc] initWithArguments:arguments environment:env currentDirectory:directory];
    _pseudoTerminal.delegate = self;
    return [_pseudoTerminal startWithRows:_terminalView.rows columns:_terminalView.columns];
}

- (void)stop {
    [_pseudoTerminal hangUp];
}

- (void)terminalView:(UDTerminalView *)view writeData:(NSData *)data {
    [_pseudoTerminal writeData:data];
}

- (void)terminalView:(UDTerminalView *)view didResizeToRows:(NSUInteger)rows columns:(NSUInteger)columns {
    [_pseudoTerminal setRows:rows columns:columns];
}

- (void)pseudoTerminal:(UDPseudoTerminal *)terminal didReadData:(NSData *)data {
    [_terminalView feedData:data];
}

- (void)pseudoTerminalDidEnd:(UDPseudoTerminal *)terminal {
    NSString *status = terminal.exitStatus >= 0 ? [NSString stringWithFormat:@", exit status %d", terminal.exitStatus] : @"";
    NSString *ended = [NSString stringWithFormat:@"\r\n\x1b[90m[Process completed%@]\x1b[0m\r\n", status];
    [_terminalView feedData:[ended dataUsingEncoding:NSUTF8StringEncoding]];
}

@end
