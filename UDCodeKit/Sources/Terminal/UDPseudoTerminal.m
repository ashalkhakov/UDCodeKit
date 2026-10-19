/*---------------------------------------------------------------------------------------------
 *  UDPseudoTerminal.m
 *--------------------------------------------------------------------------------------------*/

#import "UDPseudoTerminal.h"
#include <errno.h>
#include <signal.h>
#include <stdlib.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <termios.h>
#include <unistd.h>
#ifdef __APPLE__
#include <util.h>
#else
#include <pty.h>
#endif

@implementation UDPseudoTerminal {
    NSArray<NSString *> *_arguments;
    NSDictionary<NSString *, NSString *> *_environment;
    NSString *_directory;
    int _master;
    NSFileHandle *_reading;
}

- (instancetype)initWithArguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment
                 currentDirectory:(NSString *)directory {
    if (!(self = [super init])) return nil;
    _arguments = [arguments copy];
    NSMutableDictionary *env = [environment mutableCopy];
    if (!env[@"TERM"]) env[@"TERM"] = @"xterm-256color";
    _environment = env;
    _directory = [directory copy];
    _master = -1;
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self hangUp];
}

- (BOOL)startWithRows:(NSUInteger)rows columns:(NSUInteger)columns {
    if (_running || !_arguments.count) return NO;
    // Everything the child needs, made before it is forked: between fork and
    // exec it may only make async-signal-safe calls.
    NSUInteger argc = _arguments.count;
    char **argv = calloc(argc + 1, sizeof(char *));
    for (NSUInteger i = 0; i < argc; i++) argv[i] = strdup(_arguments[i].fileSystemRepresentation ?: "");
    NSUInteger envc = _environment.count, e = 0;
    char **envp = calloc(envc + 1, sizeof(char *));
    for (NSString *key in _environment) {
        envp[e++] = strdup([NSString stringWithFormat:@"%@=%@", key, _environment[key]].UTF8String);
    }
    const char *directory = _directory.length ? strdup(_directory.fileSystemRepresentation) : NULL;
    struct winsize size = { (unsigned short)rows, (unsigned short)columns, 0, 0 };

    int master = -1;
    pid_t pid = forkpty(&master, NULL, NULL, &size);
    if (pid == 0) {
        if (directory) chdir(directory);
        // what the parent ignores, the shell must not
        signal(SIGPIPE, SIG_DFL);
        execve(argv[0], argv, envp);
        _exit(127);
    }
    for (NSUInteger i = 0; i < argc; i++) free(argv[i]);
    free(argv);
    for (NSUInteger i = 0; i < envc; i++) free(envp[i]);
    free(envp);
    free((void *)directory);
    if (pid < 0) return NO;

    _processIdentifier = pid;
    _master = master;
    _running = YES;
    // the handle owns the descriptor: it closes it when it goes
    _reading = [[NSFileHandle alloc] initWithFileDescriptor:master closeOnDealloc:YES];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_didRead:)
                                                 name:NSFileHandleReadCompletionNotification object:_reading];
    [_reading readInBackgroundAndNotify];
    return YES;
}

/// What it wrote; nothing (or an error: Linux's EIO once the other end is
/// closed) is its end.
- (void)_didRead:(NSNotification *)note {
    NSData *data = note.userInfo[NSFileHandleNotificationDataItem];
    if (data.length && !note.userInfo[@"NSFileHandleError"]) {
        [_delegate pseudoTerminal:self didReadData:data];
        if (_running) [_reading readInBackgroundAndNotify];
        return;
    }
    [self _ended];
}

- (void)_ended {
    if (!_running) return;
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSFileHandleReadCompletionNotification object:_reading];
    // GNUstep's NSTask, once one has run, reaps every child (waitpid(-1))
    // and keeps the statuses of its own only: then this one's is not known
    int status = 0;
    _exitStatus = -1;
    if (waitpid(_processIdentifier, &status, 0) == _processIdentifier) {
        _exitStatus = WIFEXITED(status) ? WEXITSTATUS(status) : WIFSIGNALED(status) ? 128 + WTERMSIG(status) : -1;
    }
    _running = NO;
    _reading = nil;
    _master = -1;
    [_delegate pseudoTerminalDidEnd:self];
}

- (void)writeData:(NSData *)data {
    if (!_running) return;
    const char *bytes = data.bytes;
    NSUInteger left = data.length;
    while (left > 0) {
        ssize_t written = write(_master, bytes, left);
        if (written < 0) {
            if (errno == EINTR || errno == EAGAIN) continue;
            return;
        }
        bytes += written;
        left -= (NSUInteger)written;
    }
}

- (void)setRows:(NSUInteger)rows columns:(NSUInteger)columns {
    if (!_running) return;
    struct winsize size = { (unsigned short)rows, (unsigned short)columns, 0, 0 };
    ioctl(_master, TIOCSWINSZ, &size);
}

- (void)hangUp {
    if (_running) kill(_processIdentifier, SIGHUP);
}

@end
