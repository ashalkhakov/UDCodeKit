/*---------------------------------------------------------------------------------------------
 *  UDDemoDebugAdapter.m
 *--------------------------------------------------------------------------------------------*/

#import "UDDemoDebugAdapter.h"
#import <LSPKit/LSPTransport.h>

NSString * const UDDemoDebugAdapterOption = @"--debug-adapter";

static const NSInteger UDMainThread = 1;
static const NSInteger UDWorkerThread = 2;
/// The worker's one frame; main's are 1000 + their depth (0: main itself).
static const NSInteger UDWorkerFrame = 2000;
static const NSInteger UDGlobalsReference = 2;
/// Lines run per turn of the run loop while running.
static const NSInteger UDLinesPerTurn = 20;

@interface UDDemoDebugAdapter () <LSPTransportDelegate>
@end

@implementation UDDemoDebugAdapter {
    LSPTransport *_transport;
    NSInteger _seq;
    NSMutableArray<NSDictionary *> *_requests;
    NSString *_program;
    NSArray<NSString *> *_lines;
    BOOL _stopOnEntry;
    /// line → the SourceBreakpoint it was given, with its "id".
    NSMutableDictionary<NSNumber *, NSDictionary *> *_breakpoints;
    NSMutableDictionary<NSNumber *, NSNumber *> *_hits;          // id → times reached
    NSInteger _nextBreakpointID;
    NSSet<NSString *> *_exceptionFilters;
    NSInteger _line;                         // where main is (about to run it)
    NSMutableArray<NSNumber *> *_callers;    // the lines it stepped in from
    /// The line whose error or warning stopped it: run on, it is printed.
    NSInteger _raisedLine;
    NSString *_raised;                       // what it raised, to stop for
    NSMutableDictionary<NSString *, NSString *> *_setValues;   // "reference/name" → value
    BOOL _running, _pauseRequested, _exited;
}

- (instancetype)initWithReadHandle:(NSFileHandle *)readHandle writeHandle:(NSFileHandle *)writeHandle {
    self = [super init];
    if (!self) return nil;
    _requests = [NSMutableArray array];
    _breakpoints = [NSMutableDictionary dictionary];
    _hits = [NSMutableDictionary dictionary];
    _callers = [NSMutableArray array];
    _setValues = [NSMutableDictionary dictionary];
    _withheldCapabilities = @[];
    _exceptionFilters = [NSSet setWithObject:@"throw"];
    _transport = [[LSPTransport alloc] initWithReadHandle:readHandle writeHandle:writeHandle];
    _transport.delegate = self;
    return self;
}

- (void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
}

- (NSArray<NSDictionary *> *)requests {
    return [_requests copy];
}

+ (int)runOnStandardStreamsWithArguments:(NSArray<NSString *> *)arguments {
    UDDemoDebugAdapter *adapter =
        [[self alloc] initWithReadHandle:[NSFileHandle fileHandleWithStandardInput]
                             writeHandle:[NSFileHandle fileHandleWithStandardOutput]];
    for (NSString *argument in arguments) {
        if (![argument hasPrefix:@"--without="]) continue;
        adapter.withheldCapabilities = [[argument substringFromIndex:10] componentsSeparatedByString:@","];
    }
    while (!adapter.finished) {
        @autoreleasepool {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
        }
    }
    return 0;
}

// ---------------------------------------------------------------------------
// MARK: - Messages
// ---------------------------------------------------------------------------

- (void)_send:(NSDictionary *)message {
    NSMutableDictionary *framed = [message mutableCopy];
    framed[@"seq"] = @(++_seq);
    [_transport sendMessage:framed];
}

- (void)_respond:(NSDictionary *)request body:(NSDictionary *)body {
    [self _send:@{ @"type": @"response", @"request_seq": request[@"seq"] ?: @0, @"command": request[@"command"] ?: @"",
                   @"success": @YES, @"body": body ?: @{} }];
}

- (void)_fail:(NSDictionary *)request message:(NSString *)message {
    [self _send:@{ @"type": @"response", @"request_seq": request[@"seq"] ?: @0, @"command": request[@"command"] ?: @"",
                   @"success": @NO, @"message": message }];
}

- (void)_event:(NSString *)event body:(NSDictionary *)body {
    [self _send:@{ @"type": @"event", @"event": event, @"body": body ?: @{} }];
}

- (void)_output:(NSString *)text category:(NSString *)category {
    [self _event:@"output" body:@{ @"category": category, @"output": text }];
}

- (void)transportDidClose:(LSPTransport *)transport {
    _running = NO;
    _finished = YES;
}

- (void)transport:(LSPTransport *)transport didReceiveMessage:(NSDictionary *)message {
    if (![message[@"type"] isEqual:@"request"]) return;
    NSString *command = message[@"command"];
    NSDictionary *arguments = [message[@"arguments"] isKindOfClass:[NSDictionary class]] ? message[@"arguments"] : @{};
    [_requests addObject:@{ @"command": command ?: @"", @"arguments": arguments }];
    NSString *selector = [NSString stringWithFormat:@"_%@:arguments:", command];
    SEL handler = NSSelectorFromString(selector);
    if (![command isKindOfClass:[NSString class]] || ![self respondsToSelector:handler]) {
        [self _fail:message message:[NSString stringWithFormat:@"Unknown request: %@", command]];
        return;
    }
    IMP imp = [self methodForSelector:handler];
    ((void (*)(id, SEL, NSDictionary *, NSDictionary *))imp)(self, handler, message, arguments);
}

// ---------------------------------------------------------------------------
// MARK: - Starting
// ---------------------------------------------------------------------------

- (void)_initialize:(NSDictionary *)request arguments:(NSDictionary *)arguments {
    NSMutableDictionary *capabilities = [@{
        @"supportsConfigurationDoneRequest": @YES,
        @"supportsTerminateRequest": @YES,
        @"supportsEvaluateForHovers": @YES,
        @"supportsConditionalBreakpoints": @YES,
        @"supportsHitConditionalBreakpoints": @YES,
        @"supportsLogPoints": @YES,
        @"supportsSetVariable": @YES,
        @"supportsGotoTargetsRequest": @YES,
        @"supportsClipboardContext": @YES,
        @"supportsStepBack": @YES,
        @"exceptionBreakpointFilters": @[
            @{ @"filter": @"throw", @"label": @"Errors", @"description": @"Stops where an error is thrown.",
               @"default": @YES },
            @{ @"filter": @"warn", @"label": @"Warnings", @"default": @NO },
        ],
    } mutableCopy];
    [capabilities removeObjectsForKeys:_withheldCapabilities];
    [self _respond:request body:capabilities];
    [self _event:@"initialized" body:nil];
}

- (BOOL)_has:(NSString *)capability {
    return ![_withheldCapabilities containsObject:capability];
}

- (void)_launch:(NSDictionary *)request arguments:(NSDictionary *)arguments {
    NSString *program = arguments[@"program"];
    NSString *text = [program isKindOfClass:[NSString class]]
        ? [NSString stringWithContentsOfFile:program encoding:NSUTF8StringEncoding error:NULL] : nil;
    if (!text) {
        [self _fail:request message:[NSString stringWithFormat:@"Cannot read the program “%@”.", program]];
        return;
    }
    _program = [program stringByStandardizingPath];
    NSMutableArray *lines = [[text componentsSeparatedByString:@"\n"] mutableCopy];
    if (lines.count > 1 && [lines.lastObject length] == 0) [lines removeLastObject];
    _lines = lines;
    _stopOnEntry = [arguments[@"stopOnEntry"] boolValue];
    [self _respond:request body:nil];
}

- (void)_attach:(NSDictionary *)request arguments:(NSDictionary *)arguments {
    [self _launch:request arguments:arguments];
}

static NSString *UDStringArgument(id value) {
    return [value isKindOfClass:[NSString class]] && [value length] ? value : nil;
}

- (void)_setBreakpoints:(NSDictionary *)request arguments:(NSDictionary *)arguments {
    NSString *path = [arguments[@"source"][@"path"] stringByStandardizingPath];
    BOOL ours = _program && [path isEqualToString:_program];
    if (ours) [_breakpoints removeAllObjects];
    NSMutableArray *results = [NSMutableArray array];
    for (NSDictionary *breakpoint in arguments[@"breakpoints"]) {
        NSInteger line = [breakpoint[@"line"] integerValue];
        NSInteger identifier = ++_nextBreakpointID;
        BOOL verified = ours && line >= 1 && line <= (NSInteger)_lines.count;
        NSString *message = verified ? nil : ours ? @"The line is not in the program." : @"Not in the program.";
        NSString *hitCondition = UDStringArgument(breakpoint[@"hitCondition"]);
        if (verified && hitCondition && ![self _parseHitCondition:hitCondition count:NULL]) {
            verified = NO;
            message = [NSString stringWithFormat:@"Not a hit count: %@", hitCondition];
        }
        if (verified) {
            NSMutableDictionary *kept = [breakpoint mutableCopy];
            kept[@"id"] = @(identifier);
            _breakpoints[@(line)] = kept;
        }
        NSMutableDictionary *result = [@{ @"id": @(identifier), @"verified": @(verified), @"line": @(line) } mutableCopy];
        if (message) result[@"message"] = message;
        [results addObject:result];
    }
    [self _respond:request body:@{ @"breakpoints": results }];
}

- (void)_setExceptionBreakpoints:(NSDictionary *)request arguments:(NSDictionary *)arguments {
    NSArray *filters = [arguments[@"filters"] isKindOfClass:[NSArray class]] ? arguments[@"filters"] : @[];
    _exceptionFilters = [NSSet setWithArray:filters];
    [self _respond:request body:nil];
}

- (void)_configurationDone:(NSDictionary *)request arguments:(NSDictionary *)arguments {
    [self _respond:request body:nil];
    if (!_program) return;
    [self _output:[NSString stringWithFormat:@"Running %@\n", [_program lastPathComponent]] category:@"console"];
    [self _event:@"thread" body:@{ @"reason": @"started", @"threadId": @(UDMainThread) }];
    _line = 1;
    if (_stopOnEntry) {
        [self _stop:@"entry"];
    } else if ([self _breaksAtLine]) {
        [self _stop:@"breakpoint"];
    } else {
        [self _run];
    }
}

// ---------------------------------------------------------------------------
// MARK: - Breakpoints: conditions, hit counts, log messages
// ---------------------------------------------------------------------------

/// "N" (at least N), or an operator and N: whether it is one; with @a count,
/// whether that many hits pass it.
- (BOOL)_parseHitCondition:(NSString *)condition count:(NSInteger *)count {
    NSScanner *scanner = [NSScanner scannerWithString:condition];
    NSString *op = @">=";
    for (NSString *candidate in @[ @"==", @">=", @"<=", @">", @"<", @"%" ]) {
        if ([scanner scanString:candidate intoString:NULL]) { op = candidate; break; }
    }
    NSInteger n = 0;
    if (![scanner scanInteger:&n] || !scanner.isAtEnd) return NO;
    if (!count) return YES;
    NSInteger hits = *count;
    if ([op isEqualToString:@"=="]) return hits == n;
    if ([op isEqualToString:@">="]) return hits >= n;
    if ([op isEqualToString:@"<="]) return hits <= n;
    if ([op isEqualToString:@">"])  return hits > n;
    if ([op isEqualToString:@"<"])  return hits < n;
    return n > 0 && hits % n == 0;
}

/// Whether the breakpoint at the line main is at stops it: it is reached
/// (and counted) when its condition holds, and stops when its hit count is
/// reached; a log message is printed instead.
- (BOOL)_breaksAtLine {
    NSDictionary *breakpoint = _breakpoints[@(_line)];
    if (!breakpoint) return NO;
    NSString *condition = [self _has:@"supportsConditionalBreakpoints"] ? UDStringArgument(breakpoint[@"condition"]) : nil;
    if (condition) {
        NSString *error = nil;
        NSDictionary *value = [self _evaluate:condition inFrame:[self _topFrame] error:&error];
        if (error) {
            [self _output:[NSString stringWithFormat:@"The breakpoint's condition failed: %@\n", error] category:@"stderr"];
        } else if (![value[@"value"] isEqualToString:@"true"]) {
            return NO;
        }
    }
    NSNumber *identifier = breakpoint[@"id"];
    NSInteger hits = _hits[identifier].integerValue + 1;
    _hits[identifier] = @(hits);
    NSString *hitCondition = [self _has:@"supportsHitConditionalBreakpoints"] ? UDStringArgument(breakpoint[@"hitCondition"]) : nil;
    if (hitCondition && ![self _parseHitCondition:hitCondition count:&hits]) return NO;
    NSString *log = [self _has:@"supportsLogPoints"] ? UDStringArgument(breakpoint[@"logMessage"]) : nil;
    if (log) {
        [self _output:[[self _interpolate:log] stringByAppendingString:@"\n"] category:@"console"];
        return NO;
    }
    return YES;
}

/// A log message with each "{expression}" in it evaluated.
- (NSString *)_interpolate:(NSString *)message {
    NSMutableString *text = [NSMutableString string];
    NSScanner *scanner = [NSScanner scannerWithString:message];
    scanner.charactersToBeSkipped = nil;
    while (!scanner.isAtEnd) {
        NSString *part = nil;
        if ([scanner scanUpToString:@"{" intoString:&part]) [text appendString:part];
        if (![scanner scanString:@"{" intoString:NULL]) break;
        NSString *expression = nil;
        [scanner scanUpToString:@"}" intoString:&expression];
        [scanner scanString:@"}" intoString:NULL];
        NSString *error = nil;
        NSDictionary *value = [self _evaluate:expression ?: @"" inFrame:[self _topFrame] error:&error];
        [text appendString:value ? value[@"value"] : [NSString stringWithFormat:@"<%@>", error]];
    }
    return text;
}

// ---------------------------------------------------------------------------
// MARK: - Running
// ---------------------------------------------------------------------------

- (void)_stop:(NSString *)reason {
    [self _stop:reason description:nil];
}

- (void)_stop:(NSString *)reason description:(NSString *)description {
    _running = NO;
    _pauseRequested = NO;
    [_setValues removeAllObjects];
    NSMutableDictionary *body = [@{ @"reason": reason, @"threadId": @(UDMainThread), @"allThreadsStopped": @YES } mutableCopy];
    NSNumber *hit = _breakpoints[@(_line)][@"id"];
    if ([reason isEqualToString:@"breakpoint"] && hit) body[@"hitBreakpointIds"] = @[ hit ];
    if (description) {
        body[@"description"] = description;
        body[@"text"] = description;
    }
    [self _event:@"stopped" body:body];
}

/// Runs the line it is at and moves to the next. NO when it did not: the
/// program ended, or the line raised what a filter stops at (_raised).
- (BOOL)_runLine {
    NSString *text = [self _textOfLine:_line];
    for (NSString *raise in @[ @"throw", @"warn" ]) {
        if (![text hasPrefix:[raise stringByAppendingString:@" "]]) continue;
        NSString *what = [text substringFromIndex:raise.length + 1];
        BOOL error = [raise isEqualToString:@"throw"];
        BOOL filtered = [self _has:@"exceptionBreakpointFilters"] && [_exceptionFilters containsObject:raise];
        if (filtered && _raisedLine != _line) {
            _raisedLine = _line;
            _raised = [NSString stringWithFormat:@"%@: %@", error ? @"Error" : @"Warning", what];
            return NO;
        }
        [self _output:[NSString stringWithFormat:@"%@: %@\n", error ? @"error" : @"warning", what] category:@"stderr"];
    }
    _raisedLine = 0;
    if ([text hasPrefix:@"print "]) {
        [self _output:[[text substringFromIndex:6] stringByAppendingString:@"\n"] category:@"stdout"];
    }
    _line++;
    if (_line <= (NSInteger)_lines.count) return YES;
    [self _exit:0];
    return NO;
}

/// Stopped for what the line raised, when that is why it did not run.
- (void)_stopForRaised {
    if (!_raised) return;
    NSString *raised = _raised;
    _raised = nil;
    [self _stop:@"exception" description:raised];
}

- (void)_run {
    _running = YES;
    [self performSelector:@selector(_runSome) withObject:nil afterDelay:0.01];
}

- (void)_runSome {
    if (!_running) return;
    for (NSInteger i = 0; i < UDLinesPerTurn; i++) {
        if (_pauseRequested) {
            [self _stop:@"pause"];
            return;
        }
        if (![self _runLine]) {
            [self _stopForRaised];
            return;
        }
        if ([self _breaksAtLine]) {
            [self _stop:@"breakpoint"];
            return;
        }
    }
    [self performSelector:@selector(_runSome) withObject:nil afterDelay:0.01];
}

- (void)_exit:(NSInteger)code {
    if (_exited) return;
    _exited = YES;
    _running = NO;
    [self _event:@"thread" body:@{ @"reason": @"exited", @"threadId": @(UDMainThread) }];
    [self _event:@"exited" body:@{ @"exitCode": @(code) }];
    [self _event:@"terminated" body:nil];
}

- (void)_continue:(NSDictionary *)request arguments:(NSDictionary *)arguments {
    [self _respond:request body:@{ @"allThreadsContinued": @YES }];
    [self _run];
}

/// A step's line run: stopped after it, or for what it raised.
- (void)_stepLine {
    if ([self _runLine]) [self _stop:@"step"];
    else [self _stopForRaised];
}

- (void)_next:(NSDictionary *)request arguments:(NSDictionary *)arguments {
    [self _respond:request body:nil];
    [self _stepLine];
}

- (void)_stepIn:(NSDictionary *)request arguments:(NSDictionary *)arguments {
    [self _respond:request body:nil];
    [_callers addObject:@(_line)];
    [self _stepLine];
}

- (void)_stepOut:(NSDictionary *)request arguments:(NSDictionary *)arguments {
    [self _respond:request body:nil];
    if (!_callers.count) {
        [self _stepLine];
        return;
    }
    // Back in the caller, past the line it stepped in at.
    _line = _callers.lastObject.integerValue + 1;
    [_callers removeLastObject];
    if (_line > (NSInteger)_lines.count) {
        [self _exit:0];
        return;
    }
    [self _stop:@"step"];
}

- (void)_stepBack:(NSDictionary *)request arguments:(NSDictionary *)arguments {
    [self _respond:request body:nil];
    if (_line > 1) _line--;
    [self _stop:@"step"];
}

/// Back, a line at a time, to a breakpoint, or to the first line.
- (void)_reverseContinue:(NSDictionary *)request arguments:(NSDictionary *)arguments {
    [self _respond:request body:nil];
    while (_line > 1) {
        _line--;
        if (_breakpoints[@(_line)]) {
            [self _stop:@"breakpoint"];
            return;
        }
    }
    [self _stop:@"entry"];
}

- (void)_pause:(NSDictionary *)request arguments:(NSDictionary *)arguments {
    [self _respond:request body:nil];
    if (_running) _pauseRequested = YES;
}

- (void)_gotoTargets:(NSDictionary *)request arguments:(NSDictionary *)arguments {
    NSString *path = [arguments[@"source"][@"path"] stringByStandardizingPath];
    NSInteger line = [arguments[@"line"] integerValue];
    NSMutableArray *targets = [NSMutableArray array];
    if ([path isEqualToString:_program] && line >= 1 && line <= (NSInteger)_lines.count) {
        [targets addObject:@{ @"id": @(line), @"label": [NSString stringWithFormat:@"Line %ld", (long)line], @"line": @(line) }];
    }
    [self _respond:request body:@{ @"targets": targets }];
}

/// Main's top frame goes on from the target's line, which has not run.
- (void)_goto:(NSDictionary *)request arguments:(NSDictionary *)arguments {
    NSInteger line = [arguments[@"targetId"] integerValue];
    if (line < 1 || line > (NSInteger)_lines.count) {
        [self _fail:request message:@"No such target."];
        return;
    }
    [self _respond:request body:nil];
    _line = line;
    [self _stop:@"goto"];
}

- (void)_terminate:(NSDictionary *)request arguments:(NSDictionary *)arguments {
    [self _respond:request body:nil];
    [self _exit:1];
}

- (void)_disconnect:(NSDictionary *)request arguments:(NSDictionary *)arguments {
    [self _respond:request body:nil];
    _running = NO;
    _finished = YES;
    [_transport close];
}

// ---------------------------------------------------------------------------
// MARK: - What is there when stopped
// ---------------------------------------------------------------------------

- (void)_threads:(NSDictionary *)request arguments:(NSDictionary *)arguments {
    NSMutableArray *threads = [NSMutableArray array];
    if (!_exited) [threads addObject:@{ @"id": @(UDMainThread), @"name": @"main" }];
    [threads addObject:@{ @"id": @(UDWorkerThread), @"name": @"worker" }];
    [self _respond:request body:@{ @"threads": threads }];
}

- (NSInteger)_topFrame {
    return 1000 + (NSInteger)_callers.count;
}

/// The line of main's frame @a frameID (1000 + depth), or the worker's.
- (NSInteger)_lineOfFrame:(NSInteger)frameID {
    NSInteger depth = frameID - 1000;
    if (frameID == UDWorkerFrame || depth < 0 || depth > (NSInteger)_callers.count) return 1;
    return depth == (NSInteger)_callers.count ? _line : _callers[(NSUInteger)depth].integerValue;
}

- (NSDictionary *)_frame:(NSInteger)frameID name:(NSString *)name {
    return @{ @"id": @(frameID), @"name": name, @"line": @([self _lineOfFrame:frameID]), @"column": @1,
              @"source": @{ @"name": [_program lastPathComponent] ?: @"", @"path": _program ?: @"" } };
}

- (void)_stackTrace:(NSDictionary *)request arguments:(NSDictionary *)arguments {
    NSMutableArray *frames = [NSMutableArray array];
    if ([arguments[@"threadId"] integerValue] == UDWorkerThread) {
        [frames addObject:[self _frame:UDWorkerFrame name:@"idle"]];
    } else {
        for (NSInteger depth = (NSInteger)_callers.count; depth >= 0; depth--) {
            NSString *name = depth == 0 ? @"main" : [NSString stringWithFormat:@"level%ld", (long)depth];
            [frames addObject:[self _frame:1000 + depth name:name]];
        }
    }
    [self _respond:request body:@{ @"stackFrames": frames, @"totalFrames": @(frames.count) }];
}

- (void)_scopes:(NSDictionary *)request arguments:(NSDictionary *)arguments {
    NSInteger frameID = [arguments[@"frameId"] integerValue];
    [self _respond:request body:@{ @"scopes": @[
        @{ @"name": @"Locals", @"variablesReference": @(frameID * 10 + 1), @"expensive": @NO },
        @{ @"name": @"Globals", @"variablesReference": @(UDGlobalsReference), @"expensive": @YES },
    ] }];
}

- (NSString *)_textOfLine:(NSInteger)line {
    return line >= 1 && line <= (NSInteger)_lines.count ? _lines[(NSUInteger)line - 1] : @"";
}

static NSDictionary *UDVariable(NSString *name, NSString *value, NSString *type, NSInteger reference, NSString *evaluateName) {
    return @{ @"name": name, @"value": value, @"type": type, @"variablesReference": @(reference),
              @"evaluateName": evaluateName };
}

- (NSArray *)_variablesOfReference:(NSInteger)reference {
    NSArray *variables = nil;
    if (reference == UDGlobalsReference) {
        variables = @[ UDVariable(@"program", [NSString stringWithFormat:@"\"%@\"", [_program lastPathComponent]], @"string", 0,
                                  @"program"),
                       UDVariable(@"lineCount", [@(_lines.count) stringValue], @"int", 0, @"lineCount") ];
    } else {
        NSInteger frameID = reference / 10, line = [self _lineOfFrame:frameID];
        NSString *text = [self _textOfLine:line];
        if (reference % 10 == 3) {
            BOOL blank = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]].length == 0;
            variables = @[ UDVariable(@"length", [@(text.length) stringValue], @"int", 0, @"info.length"),
                           UDVariable(@"blank", blank ? @"true" : @"false", @"bool", 0, @"info.blank") ];
        } else {
            variables = @[ UDVariable(@"line", [@(line) stringValue], @"int", 0, @"line"),
                           UDVariable(@"text", [NSString stringWithFormat:@"\"%@\"", text], @"string", 0, @"text"),
                           UDVariable(@"info", [NSString stringWithFormat:@"{length=%lu}", (unsigned long)text.length],
                                      @"struct", frameID * 10 + 3, @"info") ];
        }
    }
    // What setVariable gave them, until it runs on.
    NSMutableArray *values = [NSMutableArray array];
    for (NSDictionary *variable in variables) {
        NSString *set = _setValues[[NSString stringWithFormat:@"%ld/%@", (long)reference, variable[@"name"]]];
        if (!set) {
            [values addObject:variable];
            continue;
        }
        NSMutableDictionary *changed = [variable mutableCopy];
        changed[@"value"] = set;
        [values addObject:changed];
    }
    return values;
}

- (void)_variables:(NSDictionary *)request arguments:(NSDictionary *)arguments {
    [self _respond:request body:@{ @"variables": [self _variablesOfReference:[arguments[@"variablesReference"] integerValue]] }];
}

- (void)_setVariable:(NSDictionary *)request arguments:(NSDictionary *)arguments {
    NSInteger reference = [arguments[@"variablesReference"] integerValue];
    NSString *name = arguments[@"name"], *value = arguments[@"value"];
    for (NSDictionary *variable in [self _variablesOfReference:reference]) {
        if (![variable[@"name"] isEqual:name]) continue;
        NSString *type = variable[@"type"];
        NSDictionary *given = [value isKindOfClass:[NSString class]] ? [self _operand:value inFrame:reference / 10 error:NULL] : nil;
        if (!given || [type isEqualToString:@"struct"] || ![given[@"type"] isEqualToString:type]) {
            [self _fail:request message:[NSString stringWithFormat:@"Not a value for %@ (%@): %@", name, type, value]];
            return;
        }
        _setValues[[NSString stringWithFormat:@"%ld/%@", (long)reference, name]] = given[@"value"];
        [self _respond:request body:@{ @"value": given[@"value"], @"type": type, @"variablesReference": @0 }];
        return;
    }
    [self _fail:request message:[NSString stringWithFormat:@"No variable %@.", name]];
}

/// A variable of frame @a frameID by its evaluateName ("info.length"), or
/// a literal: {value, type, variablesReference}.
- (NSDictionary *)_operand:(NSString *)text inFrame:(NSInteger)frameID error:(NSString **)error {
    text = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSScanner *scanner = [NSScanner scannerWithString:text];
    NSInteger number = 0;
    if ([scanner scanInteger:&number] && scanner.isAtEnd) {
        return @{ @"value": [@(number) stringValue], @"type": @"int", @"variablesReference": @0 };
    }
    if (text.length >= 2 && [text hasPrefix:@"\""] && [text hasSuffix:@"\""]) {
        return @{ @"value": text, @"type": @"string", @"variablesReference": @0 };
    }
    if ([text isEqualToString:@"true"] || [text isEqualToString:@"false"]) {
        return @{ @"value": text, @"type": @"bool", @"variablesReference": @0 };
    }
    NSMutableArray *candidates = [[self _variablesOfReference:frameID * 10 + 1] mutableCopy];
    [candidates addObjectsFromArray:[self _variablesOfReference:UDGlobalsReference]];
    for (NSDictionary *variable in candidates) {
        if ([variable[@"evaluateName"] isEqual:text]) return variable;
        NSInteger children = [variable[@"variablesReference"] integerValue];
        if (!children || ![text hasPrefix:[variable[@"evaluateName"] stringByAppendingString:@"."]]) continue;
        for (NSDictionary *child in [self _variablesOfReference:children]) {
            if ([child[@"evaluateName"] isEqual:text]) return child;
        }
    }
    if (error) *error = [NSString stringWithFormat:@"error: use of undeclared identifier '%@'", text];
    return nil;
}

static NSString *UDUnquoted(NSString *value) {
    return value.length >= 2 && [value hasPrefix:@"\""] && [value hasSuffix:@"\""]
        ? [value substringWithRange:NSMakeRange(1, value.length - 2)] : value;
}

/// An operand, or two compared: {value, type, variablesReference}.
- (NSDictionary *)_evaluate:(NSString *)expression inFrame:(NSInteger)frameID error:(NSString **)error {
    for (NSString *op in @[ @"==", @"!=", @"<=", @">=", @"<", @">" ]) {
        NSRange at = [expression rangeOfString:op];
        if (at.location == NSNotFound) continue;
        NSDictionary *left = [self _operand:[expression substringToIndex:at.location] inFrame:frameID error:error];
        if (!left) return nil;
        NSDictionary *right = [self _operand:[expression substringFromIndex:NSMaxRange(at)] inFrame:frameID error:error];
        if (!right) return nil;
        NSString *a = UDUnquoted(left[@"value"]), *b = UDUnquoted(right[@"value"]);
        BOOL numbers = [left[@"type"] isEqual:@"int"] && [right[@"type"] isEqual:@"int"];
        NSComparisonResult order = numbers ? [@(a.integerValue) compare:@(b.integerValue)] : [a compare:b];
        BOOL holds = [op isEqualToString:@"=="] ? order == NSOrderedSame
                   : [op isEqualToString:@"!="] ? order != NSOrderedSame
                   : [op isEqualToString:@"<="] ? order != NSOrderedDescending
                   : [op isEqualToString:@">="] ? order != NSOrderedAscending
                   : [op isEqualToString:@"<"]  ? order == NSOrderedAscending
                   :                              order == NSOrderedDescending;
        return @{ @"value": holds ? @"true" : @"false", @"type": @"bool", @"variablesReference": @0 };
    }
    return [self _operand:expression inFrame:frameID error:error];
}

- (void)_evaluate:(NSDictionary *)request arguments:(NSDictionary *)arguments {
    NSString *expression = arguments[@"expression"];
    NSInteger frameID = [arguments[@"frameId"] integerValue] ?: [self _topFrame];
    NSString *error = nil;
    NSDictionary *value = [expression isKindOfClass:[NSString class]] ? [self _evaluate:expression inFrame:frameID error:&error] : nil;
    if (!value) {
        [self _fail:request message:error ?: @"Nothing to evaluate."];
        return;
    }
    // The clipboard's: a string without its quotes.
    NSString *result = [arguments[@"context"] isEqual:@"clipboard"] ? UDUnquoted(value[@"value"]) : value[@"value"];
    [self _respond:request body:@{ @"result": result, @"type": value[@"type"],
                                   @"variablesReference": value[@"variablesReference"] }];
}

@end
