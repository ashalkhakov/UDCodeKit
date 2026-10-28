/*---------------------------------------------------------------------------------------------
 *  UDPseudoTerminal.m (Windows: ConPTY)
 *
 *  The program on a pseudo console of its own (CreatePseudoConsole), its
 *  output read on a thread of its own and told to the delegate on the main
 *  thread; the console closed when the program ends, which ends the output.
 *--------------------------------------------------------------------------------------------*/

#import "../UDPseudoTerminal.h"
#include <windows.h>

/* An argument as CommandLineToArgvW reads it back: quoted when it has a
   space, a tab or a quote, its backslashes doubled before a quote. */
static NSString *UDQuotedArgument(NSString *argument) {
    if (argument.length && [argument rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@" \t\""]].location == NSNotFound)
        return argument;
    NSMutableString *quoted = [NSMutableString stringWithString:@"\""];
    NSUInteger backslashes = 0;
    for (NSUInteger i = 0; i < argument.length; i++) {
        unichar c = [argument characterAtIndex:i];
        if (c == '\\') {
            backslashes++;
            continue;
        }
        for (NSUInteger b = 0; b < (c == '"' ? backslashes * 2 + 1 : backslashes); b++) [quoted appendString:@"\\"];
        backslashes = 0;
        [quoted appendFormat:@"%C", c];
    }
    for (NSUInteger b = 0; b < backslashes * 2; b++) [quoted appendString:@"\\"];
    [quoted appendString:@"\""];
    return quoted;
}

@implementation UDPseudoTerminal {
    NSArray<NSString *> *_arguments;
    NSDictionary<NSString *, NSString *> *_environment;
    NSString *_directory;
    HPCON _console;
    HANDLE _writing;   /* what is typed, to the console */
    HANDLE _reading;   /* what the program writes, from it */
    HANDLE _process;
}

- (instancetype)initWithArguments:(NSArray<NSString *> *)arguments environment:(NSDictionary<NSString *, NSString *> *)environment
                 currentDirectory:(NSString *)directory {
    if (!(self = [super init])) return nil;
    _arguments = [arguments copy];
    NSMutableDictionary *env = [environment mutableCopy];
    if (!env[@"TERM"]) env[@"TERM"] = @"xterm-256color";
    _environment = env;
    _directory = [directory copy];
    return self;
}

- (void)dealloc {
    [self hangUp];
    if (_process) CloseHandle(_process);
}

- (BOOL)startWithRows:(NSUInteger)rows columns:(NSUInteger)columns {
    if (_running || !_arguments.count) return NO;
    HANDLE inRead = NULL, inWrite = NULL, outRead = NULL, outWrite = NULL;
    if (!CreatePipe(&inRead, &inWrite, NULL, 0)) return NO;
    if (!CreatePipe(&outRead, &outWrite, NULL, 0)) {
        CloseHandle(inRead);
        CloseHandle(inWrite);
        return NO;
    }
    COORD size = { (SHORT)columns, (SHORT)rows };
    HPCON console = NULL;
    HRESULT made = CreatePseudoConsole(size, inRead, outWrite, 0, &console);
    /* the console holds its own ends now */
    CloseHandle(inRead);
    CloseHandle(outWrite);
    if (FAILED(made)) {
        CloseHandle(inWrite);
        CloseHandle(outRead);
        return NO;
    }

    STARTUPINFOEXW startup;
    memset(&startup, 0, sizeof startup);
    startup.StartupInfo.cb = sizeof startup;
    /* No standard handles of its own: the program's are the pseudo console's.
       Without this it gets this process's, where they are redirected (a pipe,
       a file: an app started so, a test run), and the pseudo console sees
       nothing of it. */
    startup.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
    SIZE_T listSize = 0;
    InitializeProcThreadAttributeList(NULL, 1, 0, &listSize);
    startup.lpAttributeList = malloc(listSize);
    InitializeProcThreadAttributeList(startup.lpAttributeList, 1, 0, &listSize);
    UpdateProcThreadAttribute(startup.lpAttributeList, 0, PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE, console, sizeof console, NULL, NULL);

    NSMutableArray *quoted = [NSMutableArray array];
    for (NSString *argument in _arguments) [quoted addObject:UDQuotedArgument(argument)];
    NSString *commandLine = [quoted componentsJoinedByString:@" "];
    /* The environment as Windows wants it: NAME=value, each ended by a nul,
       the whole by another. */
    NSMutableString *block = [NSMutableString string];
    for (NSString *key in [_environment.allKeys sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)])
        [block appendFormat:@"%@=%@%C", key, _environment[key], (unichar)0];
    [block appendFormat:@"%C", (unichar)0];
    NSUInteger commandLength = commandLine.length, blockLength = block.length;
    unichar *command = calloc(commandLength + 1, sizeof(unichar));
    [commandLine getCharacters:command range:NSMakeRange(0, commandLength)];
    unichar *environment = calloc(blockLength + 1, sizeof(unichar));
    [block getCharacters:environment range:NSMakeRange(0, blockLength)];
    unichar *directory = NULL;
    if (_directory.length) {
        directory = calloc(_directory.length + 1, sizeof(unichar));
        [_directory getCharacters:directory range:NSMakeRange(0, _directory.length)];
    }

    PROCESS_INFORMATION process;
    memset(&process, 0, sizeof process);
    BOOL started = CreateProcessW(NULL, (LPWSTR)command, NULL, NULL, FALSE,
                                  EXTENDED_STARTUPINFO_PRESENT | CREATE_UNICODE_ENVIRONMENT,
                                  environment, (LPCWSTR)directory, &startup.StartupInfo, &process);
    DeleteProcThreadAttributeList(startup.lpAttributeList);
    free(startup.lpAttributeList);
    free(command);
    free(environment);
    free(directory);
    if (!started) {
        ClosePseudoConsole(console);
        CloseHandle(inWrite);
        CloseHandle(outRead);
        return NO;
    }
    CloseHandle(process.hThread);

    _console = console;
    _writing = inWrite;
    _reading = outRead;
    _process = process.hProcess;
    _processIdentifier = (pid_t)process.dwProcessId;
    _running = YES;
    [NSThread detachNewThreadSelector:@selector(_read:) toTarget:self withObject:nil];
    [NSThread detachNewThreadSelector:@selector(_wait:) toTarget:self withObject:nil];
    return YES;
}

/* On a thread of its own: what the program writes, as it comes; the end of
   it (the console closed) is its end. */
- (void)_read:(id)unused {
    HANDLE reading = _reading;
    char buffer[8192];
    for (;;) {
        DWORD got = 0;
        if (!ReadFile(reading, buffer, sizeof buffer, &got, NULL) || got == 0) break;
        @autoreleasepool {
            [self performSelectorOnMainThread:@selector(_didRead:) withObject:[NSData dataWithBytes:buffer length:got] waitUntilDone:NO];
        }
    }
    [self performSelectorOnMainThread:@selector(_ended) withObject:nil waitUntilDone:NO];
}

/* On a thread of its own: the program ending, after which the console is
   closed, which ends what is read from it. */
- (void)_wait:(id)unused {
    WaitForSingleObject(_process, INFINITE);
    [self performSelectorOnMainThread:@selector(_closeConsole) withObject:nil waitUntilDone:NO];
}

- (void)_didRead:(NSData *)data {
    if (_running) [_delegate pseudoTerminal:self didReadData:data];
}

- (void)_closeConsole {
    if (_console) {
        ClosePseudoConsole(_console);
        _console = NULL;
    }
}

- (void)_ended {
    if (!_running) return;
    [self _closeConsole];
    DWORD code = 0;
    _exitStatus = GetExitCodeProcess(_process, &code) && code != STILL_ACTIVE ? (int)code : -1;
    _running = NO;
    CloseHandle(_writing);
    CloseHandle(_reading);
    _writing = _reading = NULL;
    [_delegate pseudoTerminalDidEnd:self];
}

- (void)writeData:(NSData *)data {
    if (!_running) return;
    const char *bytes = data.bytes;
    NSUInteger left = data.length;
    while (left > 0) {
        DWORD written = 0;
        if (!WriteFile(_writing, bytes, (DWORD)MIN(left, (NSUInteger)UINT32_MAX), &written, NULL) || written == 0) return;
        bytes += written;
        left -= written;
    }
}

- (void)setRows:(NSUInteger)rows columns:(NSUInteger)columns {
    if (!_running || !_console) return;
    COORD size = { (SHORT)columns, (SHORT)rows };
    ResizePseudoConsole(_console, size);
}

/// The console closed, as a terminal window closing does: Windows tells its
/// programs so (CTRL_CLOSE_EVENT), and they end.
- (void)hangUp {
    if (_running) [self _closeConsole];
}

@end
