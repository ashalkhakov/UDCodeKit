/*---------------------------------------------------------------------------------------------
 *  UDGit.m
 *--------------------------------------------------------------------------------------------*/

#import "UDGit.h"
#import <UDCodeKit/UDCodeKit.h>
#import <LSPKit/LSPKit.h>

// ---------------------------------------------------------------------------
// MARK: - A command's result
// ---------------------------------------------------------------------------

@interface UDGitResult ()
- (instancetype)initWithArguments:(NSArray<NSString *> *)arguments status:(int)status
                           output:(NSData *)output errorOutput:(NSData *)errorOutput
                        cancelled:(BOOL)cancelled context:(nullable id)context;
@end

@implementation UDGitResult {
    BOOL _cancelled;
}

- (instancetype)initWithArguments:(NSArray<NSString *> *)arguments status:(int)status
                           output:(NSData *)output errorOutput:(NSData *)errorOutput
                        cancelled:(BOOL)cancelled context:(id)context {
    self = [super init];
    if (self) {
        _arguments = [arguments copy];
        _terminationStatus = status;
        _outputData = [output copy];
        _output = [[NSString alloc] initWithData:output encoding:NSUTF8StringEncoding]
               ?: [[NSString alloc] initWithData:output encoding:NSISOLatin1StringEncoding] ?: @"";
        _errorOutput = [[NSString alloc] initWithData:errorOutput encoding:NSUTF8StringEncoding]
                    ?: [[NSString alloc] initWithData:errorOutput encoding:NSISOLatin1StringEncoding] ?: @"";
        _cancelled = cancelled;
        _context = context;
        _errorCode = status == 0 ? UDGitErrorNone
                   : [UDGit errorCodeOfOutput:_errorOutput command:[self _command]];
    }
    return self;
}

/// The git command: the first argument that is not an option (-c name=value aside).
- (nullable NSString *)_command {
    for (NSUInteger i = 0; i < _arguments.count; i++) {
        NSString *argument = _arguments[i];
        if ([argument isEqualToString:@"-c"]) {
            i++;
            continue;
        }
        if (![argument hasPrefix:@"-"]) return argument;
    }
    return nil;
}

- (BOOL)succeeded {
    return _terminationStatus == 0 && !_cancelled;
}

- (NSString *)message {
    NSString *text = [_errorOutput stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    for (NSString *line in [[text componentsSeparatedByString:@"\n"] reverseObjectEnumerator]) {
        if ([line hasPrefix:@"fatal: "] || [line hasPrefix:@"error: "]) return [line substringFromIndex:[line rangeOfString:@": "].location + 2];
    }
    return text.length ? text : [NSString stringWithFormat:@"git %@ failed (%d).", [self _command] ?: @"", _terminationStatus];
}

@end

// ---------------------------------------------------------------------------
// MARK: - A command running
// ---------------------------------------------------------------------------

@interface UDGitProcess ()
@property (nonatomic, strong) NSTask *task;
@property (nonatomic, copy) NSArray<NSString *> *arguments;
@property (nonatomic, strong, nullable) id context;
@property (nonatomic, strong, nullable) id target;     // until it is told
@property (nonatomic) SEL action;
@property (nonatomic, strong, nullable) NSData *output, *errorOutput;
@property (nonatomic) BOOL cancelled;
@end

/// The commands running: kept until they end.
static NSMutableSet<UDGitProcess *> *UDRunningProcesses(void) {
    static NSMutableSet *running;
    if (!running) running = [NSMutableSet set];
    return running;
}

/// The run loop modes git's output is read in: a sheet's (modal) too.
static NSArray<NSString *> *UDReadingModes(void) {
    return @[ NSDefaultRunLoopMode, @"NSModalPanelRunLoopMode", @"NSEventTrackingRunLoopMode" ];
}

@implementation UDGitProcess

- (void)cancel {
    _cancelled = YES;
    if (_task.isRunning) [_task terminate];
}

- (void)_didReadToEnd:(NSNotification *)note {
    NSData *data = note.userInfo[NSFileHandleNotificationDataItem] ?: [NSData data];
    NSFileHandle *handle = note.object;
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSFileHandleReadToEndOfFileCompletionNotification object:handle];
    if (handle == [(NSPipe *)_task.standardOutput fileHandleForReading]) {
        _output = data;
    } else {
        _errorOutput = data;
    }
    if (!_output || !_errorOutput) return;
    [_task waitUntilExit];
    UDGitResult *result = [[UDGitResult alloc] initWithArguments:_arguments status:_task.terminationStatus
                                                          output:_output errorOutput:_errorOutput
                                                       cancelled:_cancelled context:_context];
    id target = _target;
    SEL action = _action;
    [UDRunningProcesses() removeObject:self];
    if (target && action) {
        void (*send)(id, SEL, UDGitResult *) = (void (*)(id, SEL, UDGitResult *))[target methodForSelector:action];
        send(target, action, result);
    }
}

@end

/// Reads a pipe to its end on a thread of its own (-runAndWait:'s error output).
@interface UDPipeDrain : NSObject
@property (nonatomic, strong) NSFileHandle *handle;
@property (atomic, strong, nullable) NSData *data;
@end

@implementation UDPipeDrain
- (void)drain {
    @autoreleasepool {
        self.data = [_handle readDataToEndOfFile] ?: [NSData data];
    }
}
@end

// ---------------------------------------------------------------------------
// MARK: - git
// ---------------------------------------------------------------------------

@implementation UDGit

+ (UDGit *)sharedGit {
    static UDGit *git;
    static BOOL located;
    if (!located) {
        located = YES;
        NSString *path = [self locate];
        git = path ? [[UDGit alloc] initWithPath:path] : nil;
    }
    return git;
}

+ (NSString *)locate {
#ifdef __APPLE__
    // /usr/bin/git without the command line tools only offers to install them
    NSString *found = [UDToolLocator pathOfTool:@"git"];
    if ([found isEqualToString:@"/usr/bin/git"] && ![UDToolLocator outputOf:@"/usr/bin/xcode-select" arguments:@[ @"-p" ]]) {
        return nil;
    }
    return found;
#elif defined(_WIN32)
    NSDictionary *environment = [[NSProcessInfo processInfo] environment];
    NSMutableArray<NSString *> *candidates = [NSMutableArray array];
    for (NSString *variable in @[ @"ProgramW6432", @"ProgramFiles(x86)", @"ProgramFiles" ]) {
        NSString *folder = environment[variable];
        if (folder) [candidates addObject:[folder stringByAppendingPathComponent:@"Git/cmd/git.exe"]];
    }
    NSString *local = environment[@"LocalAppData"];
    if (local) [candidates addObject:[local stringByAppendingPathComponent:@"Programs/Git/cmd/git.exe"]];
    NSString *found = [UDToolLocator pathOfTool:@"git"];
    if (found) return found;
    for (NSString *candidate in candidates) {
        if ([[NSFileManager defaultManager] isExecutableFileAtPath:candidate]) return candidate;
    }
    return nil;
#else
    return [UDToolLocator pathOfTool:@"git"];
#endif
}

- (instancetype)initWithPath:(NSString *)path {
    self = [super init];
    if (self) {
        _path = [path copy];
        _environment = @{};
        UDGitResult *result = [self runAndWait:@[ @"--version" ] inFolder:NSTemporaryDirectory() input:nil];
        NSString *output = [result.output stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!result.succeeded || ![output hasPrefix:@"git version "]) return nil;
        NSString *version = [output substringFromIndex:@"git version ".length];
        NSRange space = [version rangeOfString:@" "];
        _version = space.location == NSNotFound ? version : [version substringToIndex:space.location];
    }
    return self;
}

/// The app's environment (the machine's), git's messages in English, no
/// pager, and what the app adds.
- (NSDictionary<NSString *, NSString *> *)_environmentOfCommand:(NSString *)command {
    NSMutableDictionary *environment = [[LSPTransport hostEnvironment] mutableCopy];
    environment[@"LANGUAGE"] = @"en";
    environment[@"LC_ALL"] = @"en_US.UTF-8";
    environment[@"LANG"] = @"en_US.UTF-8";
    environment[@"GIT_PAGER"] = @"cat";
    environment[@"UDCODE_GIT_COMMAND"] = command ?: @"";
    // credentials asked by the app (its askpass), then the git's own
    [environment addEntriesFromDictionary:UDSourceControlCredentialEnvironment()];
    [environment addEntriesFromDictionary:_environment];
    return environment;
}

- (NSTask *)_taskRunning:(NSArray<NSString *> *)arguments inFolder:(NSString *)folder hasInput:(BOOL)hasInput {
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = _path;
    task.arguments = arguments;
    task.currentDirectoryPath = folder;
    NSString *command = nil;
    for (NSString *argument in arguments) {
        if (![argument hasPrefix:@"-"] && ![argument containsString:@"="]) {
            command = argument;
            break;
        }
    }
    task.environment = [self _environmentOfCommand:command];
    task.standardOutput = [NSPipe pipe];
    task.standardError = [NSPipe pipe];
    task.standardInput = hasInput ? [NSPipe pipe] : [NSFileHandle fileHandleWithNullDevice];
    return task;
}

static void UDWriteInput(NSTask *task, NSData *input) {
    if (!input) return;
    NSFileHandle *writing = [(NSPipe *)task.standardInput fileHandleForWriting];
    @try {
        [writing writeData:input];
    } @catch (NSException *exception) {
        // (git ended without reading it)
    }
    [writing closeFile];
}

- (UDGitProcess *)run:(NSArray<NSString *> *)arguments inFolder:(NSString *)folder input:(NSData *)input
              context:(id)context target:(id)target action:(SEL)action {
    UDGitProcess *process = [[UDGitProcess alloc] init];
    process.arguments = arguments;
    process.context = context;
    process.target = target;
    process.action = action;
    NSTask *task = [self _taskRunning:arguments inFolder:folder hasInput:input != nil];
    process.task = task;
    NSFileHandle *output = [(NSPipe *)task.standardOutput fileHandleForReading];
    NSFileHandle *errorOutput = [(NSPipe *)task.standardError fileHandleForReading];
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:process selector:@selector(_didReadToEnd:) name:NSFileHandleReadToEndOfFileCompletionNotification object:output];
    [center addObserver:process selector:@selector(_didReadToEnd:) name:NSFileHandleReadToEndOfFileCompletionNotification object:errorOutput];
    [UDRunningProcesses() addObject:process];
    @try {
        [task launch];
    } @catch (NSException *exception) {
        // as a command that failed: its error, why
        [center removeObserver:process];
        [UDRunningProcesses() removeObject:process];
        UDGitResult *result = [[UDGitResult alloc] initWithArguments:arguments status:-1 output:[NSData data]
                                                         errorOutput:[exception.reason ?: @"git did not run" dataUsingEncoding:NSUTF8StringEncoding]
                                                           cancelled:NO context:context];
        // (told as the run loop turns, as when it runs)
        [target performSelector:action withObject:result afterDelay:0 inModes:UDReadingModes()];
        return process;
    }
    [output readToEndOfFileInBackgroundAndNotifyForModes:UDReadingModes()];
    [errorOutput readToEndOfFileInBackgroundAndNotifyForModes:UDReadingModes()];
    UDWriteInput(task, input);
    return process;
}

- (UDGitResult *)runAndWait:(NSArray<NSString *> *)arguments inFolder:(NSString *)folder input:(NSData *)input {
    NSTask *task = [self _taskRunning:arguments inFolder:folder hasInput:input != nil];
    UDPipeDrain *errors = [[UDPipeDrain alloc] init];
    errors.handle = [(NSPipe *)task.standardError fileHandleForReading];
    @try {
        [task launch];
    } @catch (NSException *exception) {
        return [[UDGitResult alloc] initWithArguments:arguments status:-1 output:[NSData data]
                                          errorOutput:[exception.reason ?: @"git did not run" dataUsingEncoding:NSUTF8StringEncoding]
                                            cancelled:NO context:nil];
    }
    [NSThread detachNewThreadSelector:@selector(drain) toTarget:errors withObject:nil];
    UDWriteInput(task, input);
    NSData *output = [[(NSPipe *)task.standardOutput fileHandleForReading] readDataToEndOfFile];
    [task waitUntilExit];
    while (!errors.data) [NSThread sleepForTimeInterval:0.001];
    return [[UDGitResult alloc] initWithArguments:arguments status:task.terminationStatus output:output
                                      errorOutput:errors.data cancelled:NO context:nil];
}

// ---------------------------------------------------------------------------
// MARK: - What went wrong (git.ts's getGitErrorCode, and the commands' own)
// ---------------------------------------------------------------------------

static BOOL UDMatches(NSString *text, NSString *pattern, NSRegularExpressionOptions options) {
    NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:pattern options:options error:NULL];
    return [expression firstMatchInString:text options:0 range:NSMakeRange(0, text.length)] != nil;
}

+ (UDGitErrorCode)errorCodeOfOutput:(NSString *)stderr command:(NSString *)command {
    // the command's own first
    if ([command isEqualToString:@"commit"]) {
        if (UDMatches(stderr, @"Please tell me who you are|unable to auto-detect email address", 0)) return UDGitErrorNoUserNameConfigured;
        if (UDMatches(stderr, @"Aborting commit due to empty commit message", 0)) return UDGitErrorEmptyCommitMessage;
    }
    if ([command isEqualToString:@"push"]) {
        if (UDMatches(stderr, @"! \\[rejected\\].*\\(non-fast-forward\\)|! \\[rejected\\].*\\(fetch first\\)", 0)) return UDGitErrorPushRejected;
        if (UDMatches(stderr, @"has no upstream branch", 0)) return UDGitErrorNoUpstreamBranch;
        if (UDMatches(stderr, @"Could not read from remote repository", 0)) return UDGitErrorRemoteConnectionError;
    }
    if ([command isEqualToString:@"pull"] || [command isEqualToString:@"merge"] || [command isEqualToString:@"rebase"] ||
        [command isEqualToString:@"cherry-pick"]) {
        if (UDMatches(stderr, @"^CONFLICT \\(", NSRegularExpressionAnchorsMatchLines) ||
            UDMatches(stderr, @"Automatic merge failed; fix conflicts", 0)) {
            return UDGitErrorConflict;
        }
        if (UDMatches(stderr, @"Your local changes to the following files would be overwritten", 0)) return UDGitErrorLocalChangesOverwritten;
        if (UDMatches(stderr, @"Could not read from remote repository", 0)) return UDGitErrorRemoteConnectionError;
        if (UDMatches(stderr, @"Couldn't find remote ref", 0)) return UDGitErrorNoRemoteReference;
    }
    if ([command isEqualToString:@"fetch"]) {
        if (UDMatches(stderr, @"Could not read from remote repository", 0)) return UDGitErrorRemoteConnectionError;
    }
    if ([command isEqualToString:@"stash"]) {
        if (UDMatches(stderr, @"No local changes to save", 0)) return UDGitErrorNoLocalChanges;
        if (UDMatches(stderr, @"No stash entries found|No stash found", 0)) return UDGitErrorNoStashFound;
        if (UDMatches(stderr, @"^CONFLICT \\(|conflict", NSRegularExpressionAnchorsMatchLines)) return UDGitErrorStashConflict;
    }
    if ([command isEqualToString:@"checkout"] || [command isEqualToString:@"switch"]) {
        if (UDMatches(stderr, @"Your local changes to the following files would be overwritten", 0)) return UDGitErrorDirtyWorkTree;
    }

    // getGitErrorCode
    if (UDMatches(stderr, @"Another git process seems to be running in this repository|If no other git process is currently running", 0)) {
        return UDGitErrorRepositoryIsLocked;
    }
    if (UDMatches(stderr, @"cannot lock ref|unable to update local ref", 0)) return UDGitErrorCantLockRef;
    if (UDMatches(stderr, @"Authentication failed", NSRegularExpressionCaseInsensitive)) return UDGitErrorAuthenticationFailed;
    if (UDMatches(stderr, @"Not a git repository", NSRegularExpressionCaseInsensitive)) return UDGitErrorNotAGitRepository;
    if (UDMatches(stderr, @"detected dubious ownership in repository at", 0)) return UDGitErrorNotASafeGitRepository;
    if (UDMatches(stderr, @"bad config file", 0)) return UDGitErrorBadConfigFile;
    if (UDMatches(stderr, @"Repository not found", 0)) return UDGitErrorRepositoryNotFound;
    if (UDMatches(stderr, @"unable to access", 0)) return UDGitErrorCantAccessRemote;
    if (UDMatches(stderr, @"branch '.+' is not fully merged", 0)) return UDGitErrorBranchNotFullyMerged;
    if (UDMatches(stderr, @"Couldn't find remote ref", 0)) return UDGitErrorNoRemoteReference;
    if (UDMatches(stderr, @"A branch named '.+' already exists", 0)) return UDGitErrorBranchAlreadyExists;
    if (UDMatches(stderr, @"'.+' is not a valid branch name", 0)) return UDGitErrorInvalidBranchName;
    if (UDMatches(stderr, @"Please,? commit your changes or stash them", 0)) return UDGitErrorDirtyWorkTree;
    if (UDMatches(stderr, @"needs merge|you need to resolve your current index first", 0)) return UDGitErrorUnmergedChanges;
    return UDGitErrorUnknown;
}

@end
