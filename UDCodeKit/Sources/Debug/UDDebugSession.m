/*---------------------------------------------------------------------------------------------
 *  UDDebugSession.m
 *
 *  Replies are matched to what asked for them by their sequence numbers.
 *  Each stop and each resumption starts a new generation: a reply about
 *  frames or variables of an earlier one is dropped.
 *--------------------------------------------------------------------------------------------*/

#import <AppKit/AppKit.h>
#import "UDDebugSession.h"
#import "UDPaths.h"
#import "UDLanguageMode.h"

NSNotificationName const UDDebugSessionDidChangeStateNotification = @"UDDebugSessionDidChangeStateNotification";
NSNotificationName const UDDebugSessionDidChangeThreadsNotification = @"UDDebugSessionDidChangeThreadsNotification";
NSNotificationName const UDDebugSessionDidSelectFrameNotification = @"UDDebugSessionDidSelectFrameNotification";
NSNotificationName const UDDebugSessionDidLoadVariablesNotification = @"UDDebugSessionDidLoadVariablesNotification";
NSNotificationName const UDDebugSessionDidOutputNotification = @"UDDebugSessionDidOutputNotification";
NSNotificationName const UDDebugSessionDidEvaluateWatchesNotification = @"UDDebugSessionDidEvaluateWatchesNotification";

NSString * const UDDebugSessionVariableKey = @"UDDebugSessionVariableKey";
NSString * const UDDebugSessionOutputKey = @"UDDebugSessionOutputKey";
NSString * const UDDebugSessionOutputCategoryKey = @"UDDebugSessionOutputCategoryKey";

/// How long a stopped session waits for the adapter to answer disconnect
/// before ending it anyway.
static const NSTimeInterval UDDisconnectTimeout = 3.0;

static NSString *UDString(id value) {
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

static NSInteger UDInteger(id value) {
    return [value respondsToSelector:@selector(integerValue)] ? [value integerValue] : 0;
}

// ---------------------------------------------------------------------------
// MARK: - Frames, threads, variables
// ---------------------------------------------------------------------------

@interface UDDebugStackFrame ()
@property (nonatomic) NSInteger frameID;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy, nullable) NSString *path;
@property (nonatomic) NSInteger line;
@property (nonatomic) NSInteger column;
@property (nonatomic, weak) UDDebugThread *thread;
@end

@implementation UDDebugStackFrame

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@ %@ %@:%ld>", NSStringFromClass([self class]), _name,
            [_path lastPathComponent], (long)_line];
}

@end

@interface UDDebugThread ()
@property (nonatomic) NSInteger threadID;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, getter=isStopped) BOOL stopped;
@property (nonatomic, copy, nullable) NSString *stopReason;
@property (nonatomic, copy, nullable) NSString *stopDescription;
@property (nonatomic, copy, nullable) NSArray<UDDebugStackFrame *> *frames;
@end

@implementation UDDebugThread
@end

@interface UDDebugVariable ()
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *value;
@property (nonatomic, copy, nullable) NSString *type;
@property (nonatomic, copy, nullable) NSString *evaluateName;
@property (nonatomic, getter=isFailed) BOOL failed;
@property (nonatomic) NSInteger variablesReference;
@property (nonatomic, getter=isExpensive) BOOL expensive;
@property (nonatomic, copy, nullable) NSArray<UDDebugVariable *> *children;
@property (nonatomic, weak, nullable) UDDebugVariable *parent;
@property (nonatomic) BOOL loading;
@end

@implementation UDDebugVariable

/// What evaluating @a expression answered (an evaluate response).
+ (instancetype)variableOfExpression:(NSString *)expression response:(DAPResponse *)response {
    UDDebugVariable *variable = [[self alloc] init];
    variable.name = expression;
    NSDictionary *body = [response.body isKindOfClass:[NSDictionary class]] ? response.body : nil;
    if (response.error || !body) {
        variable.failed = YES;
        variable.value = response.error.localizedDescription ?: @"";
        return variable;
    }
    id result = body[@"result"];
    variable.value = [result isKindOfClass:[NSString class]] ? result : [result description] ?: @"";
    variable.type = [body[@"type"] isKindOfClass:[NSString class]] ? body[@"type"] : nil;
    variable.variablesReference = [body[@"variablesReference"] respondsToSelector:@selector(integerValue)]
        ? [body[@"variablesReference"] integerValue] : 0;
    variable.evaluateName = expression;
    return variable;
}

- (BOOL)hasChildren {
    return _variablesReference > 0;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@ %@ = %@>", NSStringFromClass([self class]), _name, _value];
}

@end

/// An evaluate request waiting for its answer, and who to tell.
@interface UDDebugEvaluation : NSObject
@property (nonatomic, copy) NSString *expression;
@property (nonatomic, weak) id target;
@property (nonatomic) SEL action;
@property (nonatomic, weak) UDDebugStackFrame *frame;
/// A watch's: its place among them, of which evaluation of them (0: not a watch).
@property (nonatomic) NSUInteger watchIndex;
@property (nonatomic) NSInteger watchGeneration;
@end

@implementation UDDebugEvaluation
@end

// ---------------------------------------------------------------------------
// MARK: - The session
// ---------------------------------------------------------------------------

@interface UDDebugSession () <DAPClientDelegate>
@property (nonatomic) UDDebugSessionState state;
@end

@implementation UDDebugSession {
    NSUInteger _breakpointsBeforeRunning;   // setBreakpoints not yet answered, before configurationDone
    BOOL _launchSent;
    NSString *_request;                  // "launch" or "attach"
    NSDictionary *_requestArguments;
    BOOL _configured;                    // the adapter has had its breakpoints
    BOOL _disconnecting;
    NSInteger _generation;
    NSInteger _stoppedThreadID;
    NSString *_stopReason;
    NSString *_stopDescription;
    BOOL _allThreadsStopped;
    NSMutableArray<UDDebugThread *> *_threads;
    NSMutableString *_console;
    // What is waiting for an answer, by its request's sequence number.
    // setBreakpoints: what was sent for (UDBreakpoints), why some were not
    // sent whole, and what to do with the answer.
    NSMutableDictionary<NSNumber *, NSArray *> *_breakpointRequests;
    NSMutableDictionary<NSNumber *, UDDebugThread *> *_frameRequests;
    NSMutableDictionary<NSNumber *, UDDebugStackFrame *> *_scopeRequests;
    NSMutableDictionary<NSNumber *, UDDebugVariable *> *_variableRequests;
    NSMutableDictionary<NSNumber *, UDDebugEvaluation *> *_evaluations;
    NSMutableDictionary<NSNumber *, NSNumber *> *_requestGenerations;
    // The SourceBreakpoints last sent for each file, and the adapter's ids for them.
    NSMutableDictionary<NSString *, NSArray<NSDictionary *> *> *_sent;
    NSMapTable<NSNumber *, UDBreakpoint *> *_adapterBreakpoints;
    // Run to Cursor's breakpoint, there until the next stop.
    NSString *_runToPath;
    NSInteger _runToLine;
    // The watches: their values so far, and how many are still out.
    NSMutableArray<UDDebugVariable *> *_watches;
    NSInteger _watchGeneration, _watchesOut;
}

- (instancetype)initWithAdapterCommand:(NSArray<NSString *> *)command
                  currentDirectoryPath:(NSString *)directory
                           breakpoints:(UDBreakpointStore *)breakpoints {
    return [self initWithClient:[[DAPClient alloc] initWithCommand:command currentDirectoryPath:directory]
                    breakpoints:breakpoints];
}

- (instancetype)initWithClient:(DAPClient *)client breakpoints:(UDBreakpointStore *)breakpoints {
    self = [super init];
    if (!self) return nil;
    _client = client;
    _client.delegate = self;
    _breakpoints = breakpoints;
    _adapterID = @"udcodekit";
    _clientName = [[NSProcessInfo processInfo] processName] ?: @"UDCodeKit";
    _threads = [NSMutableArray array];
    _console = [NSMutableString string];
    _breakpointRequests = [NSMutableDictionary dictionary];
    _frameRequests = [NSMutableDictionary dictionary];
    _scopeRequests = [NSMutableDictionary dictionary];
    _variableRequests = [NSMutableDictionary dictionary];
    _evaluations = [NSMutableDictionary dictionary];
    _requestGenerations = [NSMutableDictionary dictionary];
    _sent = [NSMutableDictionary dictionary];
    _adapterBreakpoints = [NSMapTable strongToWeakObjectsMapTable];
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(_breakpointsDidChange:)
                   name:UDBreakpointStoreDidChangeNotification object:breakpoints];
    [center addObserver:self selector:@selector(_exceptionFiltersDidChange:)
                   name:UDBreakpointStoreDidChangeExceptionFiltersNotification object:breakpoints];
    [center addObserver:self selector:@selector(_watchExpressionsDidChange:)
                   name:UDBreakpointStoreDidChangeWatchExpressionsNotification object:breakpoints];
    return self;
}

+ (instancetype)sessionForLanguageMode:(UDLanguageMode *)mode breakpoints:(UDBreakpointStore *)breakpoints {
    NSArray<NSString *> *command = mode.debugAdapterCommand;
    if (!command.count) return nil;
    UDDebugSession *session = [[self alloc] initWithAdapterCommand:command currentDirectoryPath:nil
                                                        breakpoints:breakpoints];
    session.adapterID = mode.identifier;
    return session;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    if (_breakpoints.debugSession == self) _breakpoints.debugSession = nil;
    _client.delegate = nil;
    [_client close];
}

- (NSArray<UDDebugThread *> *)threads {
    return [_threads copy];
}

- (void)_post:(NSNotificationName)name userInfo:(NSDictionary *)userInfo {
    [[NSNotificationCenter defaultCenter] postNotificationName:name object:self userInfo:userInfo];
}

- (void)setState:(UDDebugSessionState)state {
    if (_state == state) return;
    _state = state;
    [self _post:UDDebugSessionDidChangeStateNotification userInfo:nil];
}

// ---------------------------------------------------------------------------
// MARK: - Starting
// ---------------------------------------------------------------------------

- (void)launchWithArguments:(NSDictionary *)arguments {
    [self _startRequest:@"launch" arguments:arguments];
}

- (void)attachWithArguments:(NSDictionary *)arguments {
    [self _startRequest:@"attach" arguments:arguments];
}

- (void)_startRequest:(NSString *)request arguments:(NSDictionary *)arguments {
    if (_request) return;
    _request = [request copy];
    _requestArguments = [arguments copy];
    _breakpoints.debugSession = self;
    if (_client.launchError) {
        [self _output:[NSString stringWithFormat:@"%@\n", _client.launchError.localizedDescription] category:@"stderr"];
        [self _end];
        return;
    }
    [_client initializeWithAdapterID:_adapterID clientName:_clientName
                              target:self action:@selector(_didInitialize:)];
}

- (void)_didInitialize:(DAPResponse *)response {
    if (response.error) {
        [self _output:[NSString stringWithFormat:@"The debug adapter did not start: %@\n",
                       response.error.localizedDescription] category:@"stderr"];
        [self stop];
        return;
    }
    // Its exception filters, which the breakpoint navigator shows.
    _breakpoints.exceptionFilters = _client.exceptionBreakpointFilters;
    // Launched at once, as the protocol has it (the breakpoints follow, then
    // configurationDone) — but gdb's: gdb 15 runs the program as it is asked
    // to launch, configurationDone or not, so it has the breakpoints first
    // when it says it is initialized at once (it does), else in a moment.
    if (![_adapterID isEqualToString:@"gdb"]) {
        [self _sendLaunch];
        return;
    }
    [self performSelector:@selector(_sendLaunch) withObject:nil afterDelay:0.25
                  inModes:@[ NSDefaultRunLoopMode, NSModalPanelRunLoopMode, NSEventTrackingRunLoopMode ]];
}

- (void)_sendLaunch {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(_sendLaunch) object:nil];
    if (_launchSent || _state == UDDebugSessionStateEnded) return;
    _launchSent = YES;
    if ([_request isEqualToString:@"attach"]) {
        [_client attachWithArguments:_requestArguments target:self action:@selector(_didLaunch:)];
    } else {
        [_client launchWithArguments:_requestArguments target:self action:@selector(_didLaunch:)];
    }
}

- (void)_didLaunch:(DAPResponse *)response {
    if (!response.error) return;
    [self _output:[NSString stringWithFormat:@"Could not %@: %@\n", _request, response.error.localizedDescription]
         category:@"stderr"];
    [self stop];
}

/// The adapter is ready for the breakpoints, then configurationDone — once
/// they are answered, as VS Code waits: gdb's adapter may otherwise run the
/// program (configurationDone) before it has set them.
- (void)debugAdapterDidInitialize:(DAPClient *)client {
    if (_configured || _state == UDDebugSessionStateEnded) return;
    _configured = YES;
    // said before the launch: the launch waits for the configuration
    if (!_launchSent) [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(_sendLaunch) object:nil];
    _breakpointsBeforeRunning = 0;
    for (NSString *path in _breakpoints.files) {
        if ([self _sendBreakpointsOfFile:path then:@selector(_breakpointsSetBeforeRunning:)]) _breakpointsBeforeRunning++;
    }
    [self _sendExceptionFilters];
    if (!_breakpointsBeforeRunning) [self _configurationDone];
}

- (void)_breakpointsSetBeforeRunning:(DAPResponse *)response {
    if (_breakpointsBeforeRunning && --_breakpointsBeforeRunning == 0) [self _configurationDone];
}

- (void)_configurationDone {
    if (_state == UDDebugSessionStateEnded) return;
    if ([_client configurationDoneWithTarget:self action:@selector(_didConfigure:)] == 0) {
        [self _didConfigure:nil];
    }
}

- (void)_didConfigure:(DAPResponse *)response {
    if (!_launchSent) [self _sendLaunch];
    if (_state == UDDebugSessionStateStarting) self.state = UDDebugSessionStateRunning;
}

// ---------------------------------------------------------------------------
// MARK: - Breakpoints
// ---------------------------------------------------------------------------

- (void)_breakpointsDidChange:(NSNotification *)note {
    if (!_configured || _state == UDDebugSessionStateEnded) return;
    [self _sendBreakpointsOfFile:note.userInfo[UDBreakpointStoreFileKey]];
}

/// @a breakpoint as setBreakpoints sends it: its line, and its condition,
/// hit count and log message as far as the adapter takes them (VS Code's
/// messages for the rest, in @a unsupported).
- (NSDictionary *)_sourceBreakpoint:(UDBreakpoint *)breakpoint unsupported:(NSString **)unsupported {
    NSMutableDictionary *source = [NSMutableDictionary dictionaryWithObject:@(breakpoint.line) forKey:@"line"];
    if (breakpoint.condition) {
        if (_client.supportsConditionalBreakpoints) source[@"condition"] = breakpoint.condition;
        else *unsupported = @"Conditional breakpoints are not supported by this debugger.";
    }
    if (breakpoint.hitCondition) {
        if (_client.supportsHitConditionalBreakpoints) source[@"hitCondition"] = breakpoint.hitCondition;
        else *unsupported = @"Hit counts are not supported by this debugger.";
    }
    if (breakpoint.logMessage) {
        if (_client.supportsLogPoints) source[@"logMessage"] = breakpoint.logMessage;
        else *unsupported = @"Logpoints are not supported by this debugger.";
    }
    return source;
}

/// The enabled breakpoints of @a path (and Run to Cursor's, when it is
/// there), unless the adapter has them already. Whether they were sent;
/// @a action is sent the answer as well, when they were.
- (BOOL)_sendBreakpointsOfFile:(NSString *)path then:(SEL)action {
    if (!path) return NO;
    NSMutableArray *sentFor = [NSMutableArray array];        // UDBreakpoint, or NSNull for Run to Cursor's
    NSMutableArray *unsupported = [NSMutableArray array];    // why, or NSNull
    NSMutableArray<NSDictionary *> *sourceBreakpoints = [NSMutableArray array];
    BOOL runTo = [_runToPath isEqualToString:path];
    for (UDBreakpoint *breakpoint in [_breakpoints breakpointsInFile:path]) {
        if (!breakpoint.enabled) continue;
        // Run to Cursor's stops at its line whatever stands there.
        if (runTo && breakpoint.line == _runToLine) continue;
        NSString *why = nil;
        [sourceBreakpoints addObject:[self _sourceBreakpoint:breakpoint unsupported:&why]];
        [sentFor addObject:breakpoint];
        [unsupported addObject:why ?: (id)[NSNull null]];
    }
    if (runTo) {
        [sourceBreakpoints addObject:@{ @"line": @(_runToLine) }];
        [sentFor addObject:[NSNull null]];
        [unsupported addObject:[NSNull null]];
    }
    NSArray *sent = _sent[path];
    if ((sent && [sent isEqualToArray:sourceBreakpoints]) || (!sent && !sourceBreakpoints.count)) return NO;
    _sent[path] = sourceBreakpoints;
    // the file's real path, as a compiler records it (a debugger matches its
    // breakpoints against that: macOS's /var is /private/var, a project may
    // be opened through a link)
    NSString *real = UDRealPath(path);
    NSInteger seq = [_client setBreakpointsInFile:real breakpoints:sourceBreakpoints
                                           target:self action:@selector(_didSetBreakpoints:)];
    if (seq) _breakpointRequests[@(seq)] = @[ sentFor, unsupported, action ? NSStringFromSelector(action) : @"" ];
    return seq != 0;
}

- (void)_sendBreakpointsOfFile:(NSString *)path {
    [self _sendBreakpointsOfFile:path then:NULL];
}

- (void)_didSetBreakpoints:(DAPResponse *)response {
    NSArray *request = _breakpointRequests[@(response.requestSeq)];
    [_breakpointRequests removeObjectForKey:@(response.requestSeq)];
    NSArray *breakpoints = request[0], *unsupported = request[1];
    NSArray *results = [response.body isKindOfClass:[NSDictionary class]] ? response.body[@"breakpoints"] : nil;
    if (![results isKindOfClass:[NSArray class]]) results = @[];
    for (NSUInteger i = 0; i < breakpoints.count; i++) {
        UDBreakpoint *breakpoint = breakpoints[i];
        if (![breakpoint isKindOfClass:[UDBreakpoint class]]) continue;
        if (response.error) {
            [_breakpoints setBreakpoint:breakpoint verified:NO message:response.error.localizedDescription];
            continue;
        }
        // In the order they were sent.
        NSDictionary *result = i < results.count && [results[i] isKindOfClass:[NSDictionary class]] ? results[i] : nil;
        if (!result) continue;
        if (result[@"id"]) [_adapterBreakpoints setObject:breakpoint forKey:@(UDInteger(result[@"id"]))];
        NSString *why = UDString(unsupported[i]);
        [_breakpoints setBreakpoint:breakpoint verified:!why && [result[@"verified"] boolValue]
                            message:why ?: UDString(result[@"message"])];
    }
    NSString *then = request.count > 2 ? request[2] : nil;
    if (then.length) {
        IMP imp = [self methodForSelector:NSSelectorFromString(then)];
        ((void (*)(id, SEL, DAPResponse *))imp)(self, NSSelectorFromString(then), response);
    }
}

/// The exception filters that are on, when the adapter has any.
- (void)_sendExceptionFilters {
    NSArray<NSDictionary *> *filters = _client.exceptionBreakpointFilters;
    if (!filters.count) return;
    NSMutableArray *on = [NSMutableArray array];
    for (NSDictionary *filter in filters) {
        if ([_breakpoints isExceptionFilterEnabled:filter[@"filter"]]) [on addObject:filter[@"filter"]];
    }
    [_client setExceptionBreakpoints:on target:nil action:NULL];
}

- (void)_exceptionFiltersDidChange:(NSNotification *)note {
    if (!_configured || _state == UDDebugSessionStateEnded) return;
    [self _sendExceptionFilters];
}

- (void)debugAdapter:(DAPClient *)client breakpointDidChange:(NSDictionary *)body {
    NSDictionary *result = body[@"breakpoint"];
    if (![result isKindOfClass:[NSDictionary class]] || !result[@"id"]) return;
    UDBreakpoint *breakpoint = [_adapterBreakpoints objectForKey:@(UDInteger(result[@"id"]))];
    if (!breakpoint) return;
    if ([body[@"reason"] isEqual:@"removed"]) {
        [_adapterBreakpoints removeObjectForKey:@(UDInteger(result[@"id"]))];
        return;
    }
    [_breakpoints setBreakpoint:breakpoint verified:[result[@"verified"] boolValue] message:UDString(result[@"message"])];
}

// ---------------------------------------------------------------------------
// MARK: - Stopping and resuming
// ---------------------------------------------------------------------------

- (UDDebugThread *)_threadWithID:(NSInteger)threadID {
    for (UDDebugThread *thread in _threads) {
        if (thread.threadID == threadID) return thread;
    }
    return nil;
}

- (NSInteger)_request:(NSInteger)seq {
    if (seq) _requestGenerations[@(seq)] = @(_generation);
    return seq;
}

/// Whether @a response answers a request of this generation (and forgets it).
- (BOOL)_isCurrent:(DAPResponse *)response {
    return [self _isCurrentAnswer:response] && !response.error;
}

/// An answer to a request of this stop's, a refusal too.
- (BOOL)_isCurrentAnswer:(DAPResponse *)response {
    NSNumber *generation = _requestGenerations[@(response.requestSeq)];
    [_requestGenerations removeObjectForKey:@(response.requestSeq)];
    return generation && generation.integerValue == _generation;
}

- (void)debugAdapter:(DAPClient *)client didStop:(NSDictionary *)body {
    if (_state == UDDebugSessionStateEnded) return;
    _generation++;
    // Run to Cursor's breakpoint has done its work, however it stopped.
    if (_runToPath) {
        NSString *path = _runToPath;
        _runToPath = nil;
        [self _sendBreakpointsOfFile:path];
    }
    NSString *description = UDString(body[@"description"]) ?: UDString(body[@"text"]);
    _stoppedThreadID = body[@"threadId"] ? UDInteger(body[@"threadId"]) : 0;
    BOOL all = [body[@"allThreadsStopped"] boolValue] || !body[@"threadId"];
    _allThreadsStopped = all;
    NSString *reason = UDString(body[@"reason"]) ?: @"pause";
    for (UDDebugThread *thread in _threads) {
        thread.frames = nil;
        if (all || thread.threadID == _stoppedThreadID) {
            thread.stopped = YES;
            thread.stopReason = reason;
            thread.stopDescription = thread.threadID == _stoppedThreadID ? description : nil;
        }
    }
    _stopReason = [reason copy];
    _stopDescription = [description copy];
    self.state = UDDebugSessionStateStopped;
    // Which threads there are, then the stopped one's frames.
    [self _request:[_client threadsWithTarget:self action:@selector(_didLoadThreads:)]];
}

- (void)_didLoadThreads:(DAPResponse *)response {
    BOOL current = [self _isCurrent:response];
    NSArray *list = [response.body isKindOfClass:[NSDictionary class]] ? response.body[@"threads"] : nil;
    if (![list isKindOfClass:[NSArray class]] || _state == UDDebugSessionStateEnded) return;
    NSMutableArray<UDDebugThread *> *threads = [NSMutableArray array];
    for (NSDictionary *item in list) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        NSInteger threadID = UDInteger(item[@"id"]);
        UDDebugThread *thread = [self _threadWithID:threadID];
        if (!thread) {
            thread = [[UDDebugThread alloc] init];
            thread.threadID = threadID;
            // A thread first seen while everything is stopped is stopped too.
            thread.stopped = _state == UDDebugSessionStateStopped && (_allThreadsStopped || threadID == _stoppedThreadID);
            thread.stopReason = thread.stopped ? _stopReason : nil;
            thread.stopDescription = threadID == _stoppedThreadID ? _stopDescription : nil;
        }
        thread.name = UDString(item[@"name"]) ?: [NSString stringWithFormat:@"Thread %ld", (long)threadID];
        [threads addObject:thread];
    }
    _threads = threads;
    if (_selectedThread && ![_threads containsObject:_selectedThread]) _selectedThread = nil;
    [self _post:UDDebugSessionDidChangeThreadsNotification userInfo:nil];

    if (!current || _state != UDDebugSessionStateStopped) return;
    UDDebugThread *stopped = [self _threadWithID:_stoppedThreadID];
    if (!stopped) {
        for (UDDebugThread *thread in _threads) if (thread.stopped) { stopped = thread; break; }
    }
    if (!stopped) return;
    _selectedThread = stopped;
    [self loadFramesOfThread:stopped];
}

- (void)loadFramesOfThread:(UDDebugThread *)thread {
    if (!thread.stopped || thread.frames || _state != UDDebugSessionStateStopped) return;
    NSInteger seq = [self _request:[_client stackTraceOfThread:thread.threadID startFrame:0 levels:0
                                                        target:self action:@selector(_didLoadFrames:)]];
    if (seq) _frameRequests[@(seq)] = thread;
}

- (void)_didLoadFrames:(DAPResponse *)response {
    UDDebugThread *thread = _frameRequests[@(response.requestSeq)];
    [_frameRequests removeObjectForKey:@(response.requestSeq)];
    if (![self _isCurrent:response] || !thread) return;
    NSArray *list = [response.body isKindOfClass:[NSDictionary class]] ? response.body[@"stackFrames"] : nil;
    NSMutableArray<UDDebugStackFrame *> *frames = [NSMutableArray array];
    for (NSDictionary *item in [list isKindOfClass:[NSArray class]] ? list : @[]) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        UDDebugStackFrame *frame = [[UDDebugStackFrame alloc] init];
        frame.frameID = UDInteger(item[@"id"]);
        frame.name = UDString(item[@"name"]) ?: @"";
        NSDictionary *source = item[@"source"];
        // as the editors and the store name files (standardized)
        frame.path = [[source isKindOfClass:[NSDictionary class]] ? UDString(source[@"path"]) : nil stringByStandardizingPath];
        frame.line = UDInteger(item[@"line"]);
        frame.column = UDInteger(item[@"column"]);
        frame.thread = thread;
        [frames addObject:frame];
    }
    thread.frames = frames;
    [self _post:UDDebugSessionDidChangeThreadsNotification userInfo:nil];

    // The thread that stopped: its first frame with a source is where it is.
    if (thread == _selectedThread && !_selectedFrame) {
        UDDebugStackFrame *top = frames.firstObject;
        for (UDDebugStackFrame *frame in frames) if (frame.path) { top = frame; break; }
        if (top) [self selectFrame:top];
    }
}

- (void)selectFrame:(UDDebugStackFrame *)frame {
    if (_state != UDDebugSessionStateStopped || !frame.thread) return;
    _selectedThread = frame.thread;
    _selectedFrame = frame;
    _scopes = nil;
    [_breakpoints setInstructionPointerFile:frame.path line:frame.line];
    [self _post:UDDebugSessionDidSelectFrameNotification userInfo:nil];
    if (frame.path) {
        id<UDDebugSessionDelegate> delegate = _delegate;
        if ([delegate respondsToSelector:@selector(debugSession:showFile:line:)]) {
            [delegate debugSession:self showFile:frame.path line:frame.line];
        }
    }
    NSInteger seq = [self _request:[_client scopesOfFrame:frame.frameID target:self action:@selector(_didLoadScopes:)]];
    if (seq) _scopeRequests[@(seq)] = frame;
    [self _evaluateWatches];
}

static NSArray<UDDebugVariable *> *UDVariablesFromList(id list, UDDebugVariable *parent, BOOL scopes) {
    NSMutableArray<UDDebugVariable *> *variables = [NSMutableArray array];
    for (NSDictionary *item in [list isKindOfClass:[NSArray class]] ? list : @[]) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        UDDebugVariable *variable = [[UDDebugVariable alloc] init];
        variable.name = UDString(item[@"name"]) ?: @"";
        variable.value = scopes ? @"" : (UDString(item[@"value"]) ?: [item[@"value"] description] ?: @"");
        variable.type = UDString(item[@"type"]);
        variable.evaluateName = UDString(item[@"evaluateName"]);
        variable.variablesReference = UDInteger(item[@"variablesReference"]);
        variable.expensive = [item[@"expensive"] boolValue];
        variable.parent = parent;
        [variables addObject:variable];
    }
    return variables;
}

- (void)_didLoadScopes:(DAPResponse *)response {
    UDDebugStackFrame *frame = _scopeRequests[@(response.requestSeq)];
    [_scopeRequests removeObjectForKey:@(response.requestSeq)];
    if (![self _isCurrent:response] || frame != _selectedFrame) return;
    _scopes = UDVariablesFromList([response.body isKindOfClass:[NSDictionary class]] ? response.body[@"scopes"] : nil,
                                  nil, YES);
    [self _post:UDDebugSessionDidLoadVariablesNotification userInfo:nil];
}

- (void)loadChildrenOfVariable:(UDDebugVariable *)variable {
    if (!variable.hasChildren || variable.children || variable.loading || _state != UDDebugSessionStateStopped) return;
    variable.loading = YES;
    NSInteger seq = [self _request:[_client variablesOfReference:variable.variablesReference
                                                          target:self action:@selector(_didLoadVariables:)]];
    if (seq) _variableRequests[@(seq)] = variable;
}

- (void)_didLoadVariables:(DAPResponse *)response {
    UDDebugVariable *variable = _variableRequests[@(response.requestSeq)];
    [_variableRequests removeObjectForKey:@(response.requestSeq)];
    variable.loading = NO;
    if (![self _isCurrent:response] || !variable) return;
    variable.children = UDVariablesFromList([response.body isKindOfClass:[NSDictionary class]] ? response.body[@"variables"] : nil,
                                            variable, NO);
    [self _post:UDDebugSessionDidLoadVariablesNotification userInfo:@{ UDDebugSessionVariableKey: variable }];
}

// ---------------------------------------------------------------------------
// MARK: - Evaluating: hovers, watches, setting variables
// ---------------------------------------------------------------------------

- (void)evaluate:(NSString *)expression context:(NSString *)context target:(id)target action:(SEL)action {
    if (!expression.length || _state != UDDebugSessionStateStopped) return;
    UDDebugEvaluation *evaluation = [[UDDebugEvaluation alloc] init];
    evaluation.expression = expression;
    evaluation.target = target;
    evaluation.action = action;
    [self _evaluate:evaluation context:context];
}

- (void)_evaluate:(UDDebugEvaluation *)evaluation context:(NSString *)context {
    evaluation.frame = _selectedFrame;
    NSInteger seq = [self _request:[_client evaluate:evaluation.expression inFrame:_selectedFrame.frameID context:context
                                              target:self action:@selector(_didEvaluateExpression:)]];
    if (seq) _evaluations[@(seq)] = evaluation;
}

- (void)_didEvaluateExpression:(DAPResponse *)response {
    UDDebugEvaluation *evaluation = _evaluations[@(response.requestSeq)];
    [_evaluations removeObjectForKey:@(response.requestSeq)];
    NSNumber *generation = _requestGenerations[@(response.requestSeq)];
    [_requestGenerations removeObjectForKey:@(response.requestSeq)];
    // An error is an answer here; an answer about an earlier stop or frame is not.
    if (!evaluation || generation.integerValue != _generation || evaluation.frame != _selectedFrame) return;
    UDDebugVariable *variable = [UDDebugVariable variableOfExpression:evaluation.expression response:response];
    if (evaluation.watchGeneration) {
        [self _didEvaluateWatch:variable of:evaluation];
        return;
    }
    id target = evaluation.target;
    if (!target || !evaluation.action || ![target respondsToSelector:evaluation.action]) return;
    IMP imp = [target methodForSelector:evaluation.action];
    ((void (*)(id, SEL, UDDebugVariable *))imp)(target, evaluation.action, variable);
}

- (NSArray<UDDebugVariable *> *)watches {
    return [_watches copy];
}

/// The store's watch expressions, in the selected frame: what each was
/// evaluated to so far is kept until its new value is in.
- (void)_evaluateWatches {
    _watchGeneration++;
    NSArray<NSString *> *expressions = _breakpoints.watchExpressions;
    if (_state != UDDebugSessionStateStopped || !_selectedFrame) {
        _watches = nil;
        _watchesOut = 0;
        [self _post:UDDebugSessionDidEvaluateWatchesNotification userInfo:nil];
        return;
    }
    NSMutableArray<UDDebugVariable *> *watches = [NSMutableArray array];
    for (NSString *expression in expressions) {
        UDDebugVariable *pending = [[UDDebugVariable alloc] init];
        pending.name = expression;
        pending.value = @"";
        [watches addObject:pending];
    }
    _watches = watches;
    _watchesOut = (NSInteger)expressions.count;
    if (!expressions.count) [self _post:UDDebugSessionDidEvaluateWatchesNotification userInfo:nil];
    for (NSUInteger index = 0; index < expressions.count; index++) {
        UDDebugEvaluation *evaluation = [[UDDebugEvaluation alloc] init];
        evaluation.expression = expressions[index];
        evaluation.watchIndex = index;
        evaluation.watchGeneration = _watchGeneration;
        [self _evaluate:evaluation context:@"watch"];
    }
}

/// Each answer in its place; posted when they are all in.
- (void)_didEvaluateWatch:(UDDebugVariable *)variable of:(UDDebugEvaluation *)evaluation {
    if (evaluation.watchGeneration != _watchGeneration || evaluation.watchIndex >= _watches.count) return;
    _watches[evaluation.watchIndex] = variable;
    if (--_watchesOut == 0) [self _post:UDDebugSessionDidEvaluateWatchesNotification userInfo:nil];
}

- (void)_watchExpressionsDidChange:(NSNotification *)note {
    if (_state == UDDebugSessionStateStopped) [self _evaluateWatches];
}

- (BOOL)canSetVariables {
    return _state == UDDebugSessionStateStopped && _client.supportsSetVariable;
}

- (BOOL)canSetVariable:(UDDebugVariable *)variable {
    return self.canSetVariables && variable.parent.variablesReference > 0;
}

- (void)setValue:(NSString *)value ofVariable:(UDDebugVariable *)variable {
    if (![self canSetVariable:variable] || !value) return;
    NSInteger seq = [self _request:[_client setVariable:variable.name inReference:variable.parent.variablesReference
                                                  value:value target:self action:@selector(_didSetVariable:)]];
    if (seq) _variableRequests[@(seq)] = variable;
}

- (void)_didSetVariable:(DAPResponse *)response {
    UDDebugVariable *variable = _variableRequests[@(response.requestSeq)];
    [_variableRequests removeObjectForKey:@(response.requestSeq)];
    NSNumber *generation = _requestGenerations[@(response.requestSeq)];
    [_requestGenerations removeObjectForKey:@(response.requestSeq)];
    if (!variable || generation.integerValue != _generation) return;
    if (response.error) {
        [self _output:[response.error.localizedDescription stringByAppendingString:@"\n"] category:@"stderr"];
        return;
    }
    NSDictionary *body = [response.body isKindOfClass:[NSDictionary class]] ? response.body : @{};
    variable.value = UDString(body[@"value"]) ?: [body[@"value"] description] ?: variable.value;
    if (UDString(body[@"type"])) variable.type = body[@"type"];
    if (body[@"variablesReference"]) {
        variable.variablesReference = UDInteger(body[@"variablesReference"]);
        variable.children = nil;
    }
    [self _post:UDDebugSessionDidLoadVariablesNotification userInfo:@{ UDDebugSessionVariableKey: variable }];
    [self _evaluateWatches];
}

- (void)debugAdapter:(DAPClient *)client didContinue:(NSDictionary *)body {
    if (_state == UDDebugSessionStateStopped) [self _resumed];
}

/// Running again: what was known of the stop goes.
- (void)_resumed {
    _generation++;
    for (UDDebugThread *thread in _threads) {
        thread.stopped = NO;
        thread.stopReason = nil;
        thread.stopDescription = nil;
        thread.frames = nil;
    }
    _selectedFrame = nil;
    _scopes = nil;
    _stopReason = nil;
    _stopDescription = nil;
    [_breakpoints setInstructionPointerFile:nil line:0];
    self.state = UDDebugSessionStateRunning;
    [self _post:UDDebugSessionDidChangeThreadsNotification userInfo:nil];
    [self _post:UDDebugSessionDidSelectFrameNotification userInfo:nil];
    [self _post:UDDebugSessionDidLoadVariablesNotification userInfo:nil];
    [self _evaluateWatches];
}

- (void)debugAdapter:(DAPClient *)client threadDidChange:(NSDictionary *)body {
    if (_state == UDDebugSessionStateEnded) return;
    if ([body[@"reason"] isEqual:@"exited"]) {
        UDDebugThread *thread = [self _threadWithID:UDInteger(body[@"threadId"])];
        if (thread) {
            [_threads removeObject:thread];
            if (_selectedThread == thread) _selectedThread = nil;
            [self _post:UDDebugSessionDidChangeThreadsNotification userInfo:nil];
        }
        return;
    }
    [_client threadsWithTarget:self action:@selector(_didLoadThreads:)];
}

// ---------------------------------------------------------------------------
// MARK: - Actions
// ---------------------------------------------------------------------------

- (BOOL)canContinue { return _state == UDDebugSessionStateStopped; }
- (BOOL)canPause    { return _state == UDDebugSessionStateRunning; }
- (BOOL)canStep     { return _state == UDDebugSessionStateStopped && [self _actionThreadID] > 0; }
- (BOOL)canStepBack { return self.canStep && _client.supportsStepBack; }
- (BOOL)canJump     { return self.canStep && _client.supportsGotoTargetsRequest; }
- (BOOL)canStop     { return _state != UDDebugSessionStateEnded && !_disconnecting; }

/// The thread the actions are for: the selected one, or the one that stopped.
- (NSInteger)_actionThreadID {
    if (_selectedThread) return _selectedThread.threadID;
    if (_stoppedThreadID) return _stoppedThreadID;
    return _threads.firstObject.threadID;
}

- (void)continueExecution {
    if (!self.canContinue) return;
    [_client continueThread:[self _actionThreadID] target:nil action:NULL];
    [self _resumed];
}

- (void)pause {
    if (!self.canPause) return;
    [_client pauseThread:[self _actionThreadID] ?: 1 target:nil action:NULL];
}

- (void)stepOver {
    if (!self.canStep) return;
    [_client nextInThread:[self _actionThreadID] target:nil action:NULL];
    [self _resumed];
}

- (void)stepInto {
    if (!self.canStep) return;
    [_client stepInThread:[self _actionThreadID] target:nil action:NULL];
    [self _resumed];
}

- (void)stepOut {
    if (!self.canStep) return;
    [_client stepOutThread:[self _actionThreadID] target:nil action:NULL];
    [self _resumed];
}

- (void)stepBack {
    if (!self.canStepBack) return;
    [_client stepBackInThread:[self _actionThreadID] target:nil action:NULL];
    [self _resumed];
}

- (void)reverseContinue {
    if (!self.canStepBack) return;
    [_client reverseContinueThread:[self _actionThreadID] target:nil action:NULL];
    [self _resumed];
}

- (void)runToLine:(NSInteger)line inFile:(NSString *)path {
    if (!self.canContinue || !path || line < 1) return;
    path = [path stringByStandardizingPath];
    UDBreakpoint *there = [_breakpoints breakpointAtLine:line inFile:path];
    BOOL stopsThere = there.enabled && !there.conditional && !there.logpoint;
    if (!stopsThere) {
        _runToPath = [path copy];
        _runToLine = line;
        // Continued once the adapter has it, as VS Code awaits it.
        if ([self _sendBreakpointsOfFile:path then:@selector(_runToBreakpointIsSet:)]) return;
    }
    [self continueExecution];
}

- (void)_runToBreakpointIsSet:(DAPResponse *)response {
    if (_state == UDDebugSessionStateStopped) [self continueExecution];
}

- (void)jumpToLine:(NSInteger)line inFile:(NSString *)path {
    if (!self.canJump || !path) return;
    [self _request:[_client gotoTargetsInFile:[path stringByStandardizingPath] line:line
                                       target:self action:@selector(_didFindGotoTargets:)]];
}

/// The first target the adapter gives (VS Code's, without a choice).
- (void)_didFindGotoTargets:(DAPResponse *)response {
    if (![self _isCurrentAnswer:response]) return;
    // refused: the adapter's reason, as VS Code shows it
    if (response.error) {
        [self _output:[response.error.localizedDescription stringByAppendingString:@"\n"] category:@"stderr"];
        return;
    }
    NSArray *targets = [response.body isKindOfClass:[NSDictionary class]] ? response.body[@"targets"] : nil;
    NSDictionary *target = [targets isKindOfClass:[NSArray class]] ? targets.firstObject : nil;
    if (![target isKindOfClass:[NSDictionary class]] || !target[@"id"]) {
        [self _output:@"There is nowhere to jump to on that line.\n" category:@"stderr"];
        return;
    }
    [self _request:[_client gotoTarget:UDInteger(target[@"id"]) inThread:[self _actionThreadID]
                                target:self action:@selector(_didGoto:)]];
}

/// Gone: it runs until the adapter says where it stopped (a goto's stop);
/// refused, it stays stopped, and says why.
- (void)_didGoto:(DAPResponse *)response {
    if (![self _isCurrentAnswer:response]) return;
    if (response.error) {
        [self _output:[response.error.localizedDescription stringByAppendingString:@"\n"] category:@"stderr"];
        return;
    }
    [self _resumed];
}

- (void)stop {
    if (!self.canStop) return;
    _disconnecting = YES;
    [self _post:UDDebugSessionDidChangeStateNotification userInfo:nil];
    // A launched debuggee goes with the session; an attached one is left.
    BOOL launched = ![_request isEqualToString:@"attach"];
    if ([_client disconnectTerminatingDebuggee:launched target:self action:@selector(_didDisconnect:)] == 0) {
        [self _end];
        return;
    }
    [self performSelector:@selector(_didDisconnect:) withObject:nil afterDelay:UDDisconnectTimeout
                  inModes:@[ NSDefaultRunLoopMode, NSModalPanelRunLoopMode, NSEventTrackingRunLoopMode ]];
}

- (void)_didDisconnect:(DAPResponse *)response {
    [_client close];
    [self _end];
}

/// The debuggee ended: the adapter ends the debugging, and is let go.
- (void)debugAdapter:(DAPClient *)client didTerminate:(NSDictionary *)body {
    [self stop];
}

- (void)debugAdapter:(DAPClient *)client debuggeeDidExit:(NSDictionary *)body {
    [self _output:[NSString stringWithFormat:@"Program ended with exit code: %ld\n", (long)UDInteger(body[@"exitCode"])]
         category:@"console"];
}

/// The debuggee's process (DAP's process event).
- (void)debugAdapter:(DAPClient *)client didReceiveEvent:(NSString *)event body:(NSDictionary *)body {
    if ([event isEqualToString:@"process"]) _processID = (pid_t)UDInteger(body[@"systemProcessId"]);
}

- (void)debugAdapterDidEnd:(DAPClient *)client {
    [self _end];
}

- (void)_end {
    if (_state == UDDebugSessionStateEnded) return;
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    _generation++;
    [_threads removeAllObjects];
    _selectedThread = nil;
    _selectedFrame = nil;
    _scopes = nil;
    _runToPath = nil;
    [_breakpoints setInstructionPointerFile:nil line:0];
    [_breakpoints resetVerification];
    if (_breakpoints.debugSession == self) _breakpoints.debugSession = nil;
    self.state = UDDebugSessionStateEnded;
    [self _evaluateWatches];
    [self _post:UDDebugSessionDidChangeThreadsNotification userInfo:nil];
    [self _post:UDDebugSessionDidSelectFrameNotification userInfo:nil];
    id<UDDebugSessionDelegate> delegate = _delegate;
    if ([delegate respondsToSelector:@selector(debugSessionDidEnd:)]) [delegate debugSessionDidEnd:self];
}

// ---------------------------------------------------------------------------
// MARK: - The console
// ---------------------------------------------------------------------------

- (NSString *)consoleText {
    return [_console copy];
}

- (void)_output:(NSString *)text category:(NSString *)category {
    if (!text.length) return;
    [_console appendString:text];
    [self _post:UDDebugSessionDidOutputNotification
       userInfo:@{ UDDebugSessionOutputKey: text, UDDebugSessionOutputCategoryKey: category ?: @"console" }];
}

- (void)debugAdapter:(DAPClient *)client didOutput:(NSDictionary *)body {
    NSString *category = UDString(body[@"category"]) ?: @"console";
    if ([category isEqualToString:@"telemetry"]) return;
    [self _output:UDString(body[@"output"]) category:category];
}

- (void)evaluate:(NSString *)expression {
    expression = [expression stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!expression.length || _state == UDDebugSessionStateEnded) return;
    [self _output:[expression stringByAppendingString:@"\n"] category:@"input"];
    [_client evaluate:expression inFrame:_selectedFrame.frameID context:@"repl"
               target:self action:@selector(_didEvaluate:)];
}

- (void)_didEvaluate:(DAPResponse *)response {
    if (response.error) {
        [self _output:[response.error.localizedDescription stringByAppendingString:@"\n"] category:@"stderr"];
        return;
    }
    NSString *result = [response.body isKindOfClass:[NSDictionary class]] ? UDString(response.body[@"result"]) : nil;
    [self _output:[(result ?: @"") stringByAppendingString:@"\n"] category:@"result"];
}

@end
