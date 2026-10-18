/*---------------------------------------------------------------------------------------------
 *  UDDebugSession.m
 *
 *  Replies are matched to what asked for them by their sequence numbers.
 *  Each stop and each resumption starts a new generation: a reply about
 *  frames or variables of an earlier one is dropped.
 *--------------------------------------------------------------------------------------------*/

#import <AppKit/AppKit.h>
#import "UDDebugSession.h"
#import "UDLanguageMode.h"

NSNotificationName const UDDebugSessionDidChangeStateNotification = @"UDDebugSessionDidChangeStateNotification";
NSNotificationName const UDDebugSessionDidChangeThreadsNotification = @"UDDebugSessionDidChangeThreadsNotification";
NSNotificationName const UDDebugSessionDidSelectFrameNotification = @"UDDebugSessionDidSelectFrameNotification";
NSNotificationName const UDDebugSessionDidLoadVariablesNotification = @"UDDebugSessionDidLoadVariablesNotification";
NSNotificationName const UDDebugSessionDidOutputNotification = @"UDDebugSessionDidOutputNotification";

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
@property (nonatomic, copy, nullable) NSArray<UDDebugStackFrame *> *frames;
@end

@implementation UDDebugThread
@end

@interface UDDebugVariable ()
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *value;
@property (nonatomic, copy, nullable) NSString *type;
@property (nonatomic) NSInteger variablesReference;
@property (nonatomic, getter=isExpensive) BOOL expensive;
@property (nonatomic, copy, nullable) NSArray<UDDebugVariable *> *children;
@property (nonatomic, weak, nullable) UDDebugVariable *parent;
@property (nonatomic) BOOL loading;
@end

@implementation UDDebugVariable

- (BOOL)hasChildren {
    return _variablesReference > 0;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@ %@ = %@>", NSStringFromClass([self class]), _name, _value];
}

@end

// ---------------------------------------------------------------------------
// MARK: - The session
// ---------------------------------------------------------------------------

@interface UDDebugSession () <DAPClientDelegate>
@property (nonatomic) UDDebugSessionState state;
@end

@implementation UDDebugSession {
    NSString *_request;                  // "launch" or "attach"
    NSDictionary *_requestArguments;
    BOOL _configured;                    // the adapter has had its breakpoints
    BOOL _disconnecting;
    NSInteger _generation;
    NSInteger _stoppedThreadID;
    NSString *_stopReason;
    BOOL _allThreadsStopped;
    NSMutableArray<UDDebugThread *> *_threads;
    NSMutableString *_console;
    // What is waiting for an answer, by its request's sequence number.
    NSMutableDictionary<NSNumber *, NSArray<UDBreakpoint *> *> *_breakpointRequests;
    NSMutableDictionary<NSNumber *, UDDebugThread *> *_frameRequests;
    NSMutableDictionary<NSNumber *, UDDebugStackFrame *> *_scopeRequests;
    NSMutableDictionary<NSNumber *, UDDebugVariable *> *_variableRequests;
    NSMutableDictionary<NSNumber *, NSNumber *> *_requestGenerations;
    // The lines last sent for each file, and the adapter's ids for them.
    NSMutableDictionary<NSString *, NSArray<NSNumber *> *> *_sentLines;
    NSMapTable<NSNumber *, UDBreakpoint *> *_adapterBreakpoints;
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
    _requestGenerations = [NSMutableDictionary dictionary];
    _sentLines = [NSMutableDictionary dictionary];
    _adapterBreakpoints = [NSMapTable strongToWeakObjectsMapTable];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_breakpointsDidChange:)
                                                 name:UDBreakpointStoreDidChangeNotification object:breakpoints];
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

/// The adapter is ready for the breakpoints, then configurationDone.
- (void)debugAdapterDidInitialize:(DAPClient *)client {
    if (_configured || _state == UDDebugSessionStateEnded) return;
    _configured = YES;
    for (NSString *path in _breakpoints.files) [self _sendBreakpointsOfFile:path];
    if ([_client configurationDoneWithTarget:self action:@selector(_didConfigure:)] == 0) {
        [self _didConfigure:nil];
    }
}

- (void)_didConfigure:(DAPResponse *)response {
    if (_state == UDDebugSessionStateStarting) self.state = UDDebugSessionStateRunning;
}

// ---------------------------------------------------------------------------
// MARK: - Breakpoints
// ---------------------------------------------------------------------------

- (void)_breakpointsDidChange:(NSNotification *)note {
    if (!_configured || _state == UDDebugSessionStateEnded) return;
    [self _sendBreakpointsOfFile:note.userInfo[UDBreakpointStoreFileKey]];
}

/// The enabled breakpoints of @a path, unless the adapter has these lines already.
- (void)_sendBreakpointsOfFile:(NSString *)path {
    if (!path) return;
    NSMutableArray<UDBreakpoint *> *enabled = [NSMutableArray array];
    NSMutableArray<NSNumber *> *lines = [NSMutableArray array];
    NSMutableArray<NSDictionary *> *sourceBreakpoints = [NSMutableArray array];
    for (UDBreakpoint *breakpoint in [_breakpoints breakpointsInFile:path]) {
        if (!breakpoint.enabled) continue;
        [enabled addObject:breakpoint];
        [lines addObject:@(breakpoint.line)];
        [sourceBreakpoints addObject:@{ @"line": @(breakpoint.line) }];
    }
    NSArray *sent = _sentLines[path];
    if ((sent && [sent isEqualToArray:lines]) || (!sent && !lines.count)) return;
    _sentLines[path] = lines;
    NSInteger seq = [_client setBreakpointsInFile:path breakpoints:sourceBreakpoints
                                           target:self action:@selector(_didSetBreakpoints:)];
    if (seq) _breakpointRequests[@(seq)] = enabled;
}

- (void)_didSetBreakpoints:(DAPResponse *)response {
    NSArray<UDBreakpoint *> *breakpoints = _breakpointRequests[@(response.requestSeq)];
    [_breakpointRequests removeObjectForKey:@(response.requestSeq)];
    if (response.error) {
        for (UDBreakpoint *breakpoint in breakpoints) {
            [_breakpoints setBreakpoint:breakpoint verified:NO message:response.error.localizedDescription];
        }
        return;
    }
    NSArray *results = [response.body isKindOfClass:[NSDictionary class]] ? response.body[@"breakpoints"] : nil;
    if (![results isKindOfClass:[NSArray class]]) return;
    // In the order they were sent.
    for (NSUInteger i = 0; i < MIN(results.count, breakpoints.count); i++) {
        NSDictionary *result = results[i];
        if (![result isKindOfClass:[NSDictionary class]]) continue;
        UDBreakpoint *breakpoint = breakpoints[i];
        if (result[@"id"]) [_adapterBreakpoints setObject:breakpoint forKey:@(UDInteger(result[@"id"]))];
        [_breakpoints setBreakpoint:breakpoint verified:[result[@"verified"] boolValue] message:UDString(result[@"message"])];
    }
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
    NSNumber *generation = _requestGenerations[@(response.requestSeq)];
    [_requestGenerations removeObjectForKey:@(response.requestSeq)];
    return generation && generation.integerValue == _generation && !response.error;
}

- (void)debugAdapter:(DAPClient *)client didStop:(NSDictionary *)body {
    if (_state == UDDebugSessionStateEnded) return;
    _generation++;
    _stoppedThreadID = body[@"threadId"] ? UDInteger(body[@"threadId"]) : 0;
    BOOL all = [body[@"allThreadsStopped"] boolValue] || !body[@"threadId"];
    _allThreadsStopped = all;
    NSString *reason = UDString(body[@"reason"]) ?: @"pause";
    for (UDDebugThread *thread in _threads) {
        thread.frames = nil;
        if (all || thread.threadID == _stoppedThreadID) {
            thread.stopped = YES;
            thread.stopReason = reason;
        }
    }
    _stopReason = [reason copy];
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
        frame.path = [source isKindOfClass:[NSDictionary class]] ? UDString(source[@"path"]) : nil;
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
}

static NSArray<UDDebugVariable *> *UDVariablesFromList(id list, UDDebugVariable *parent, BOOL scopes) {
    NSMutableArray<UDDebugVariable *> *variables = [NSMutableArray array];
    for (NSDictionary *item in [list isKindOfClass:[NSArray class]] ? list : @[]) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        UDDebugVariable *variable = [[UDDebugVariable alloc] init];
        variable.name = UDString(item[@"name"]) ?: @"";
        variable.value = scopes ? @"" : (UDString(item[@"value"]) ?: [item[@"value"] description] ?: @"");
        variable.type = UDString(item[@"type"]);
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

- (void)debugAdapter:(DAPClient *)client didContinue:(NSDictionary *)body {
    if (_state == UDDebugSessionStateStopped) [self _resumed];
}

/// Running again: what was known of the stop goes.
- (void)_resumed {
    _generation++;
    for (UDDebugThread *thread in _threads) {
        thread.stopped = NO;
        thread.stopReason = nil;
        thread.frames = nil;
    }
    _selectedFrame = nil;
    _scopes = nil;
    _stopReason = nil;
    [_breakpoints setInstructionPointerFile:nil line:0];
    self.state = UDDebugSessionStateRunning;
    [self _post:UDDebugSessionDidChangeThreadsNotification userInfo:nil];
    [self _post:UDDebugSessionDidSelectFrameNotification userInfo:nil];
    [self _post:UDDebugSessionDidLoadVariablesNotification userInfo:nil];
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
    [_breakpoints setInstructionPointerFile:nil line:0];
    [_breakpoints resetVerification];
    self.state = UDDebugSessionStateEnded;
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
