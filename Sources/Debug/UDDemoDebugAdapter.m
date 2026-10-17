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
    NSMutableDictionary<NSNumber *, NSNumber *> *_breakpoints;   // line → id
    NSInteger _nextBreakpointID;
    NSInteger _line;                         // where main is (about to run it)
    NSMutableArray<NSNumber *> *_callers;    // the lines it stepped in from
    BOOL _running, _pauseRequested, _exited;
}

- (instancetype)initWithReadHandle:(NSFileHandle *)readHandle writeHandle:(NSFileHandle *)writeHandle {
    self = [super init];
    if (!self) return nil;
    _requests = [NSMutableArray array];
    _breakpoints = [NSMutableDictionary dictionary];
    _callers = [NSMutableArray array];
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

+ (int)runOnStandardStreams {
    UDDemoDebugAdapter *adapter =
        [[self alloc] initWithReadHandle:[NSFileHandle fileHandleWithStandardInput]
                             writeHandle:[NSFileHandle fileHandleWithStandardOutput]];
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
    [self _respond:request body:@{ @"supportsConfigurationDoneRequest": @YES,
                                   @"supportsTerminateRequest": @YES,
                                   @"supportsEvaluateForHovers": @YES }];
    [self _event:@"initialized" body:nil];
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

- (void)_setBreakpoints:(NSDictionary *)request arguments:(NSDictionary *)arguments {
    NSString *path = [arguments[@"source"][@"path"] stringByStandardizingPath];
    BOOL ours = _program && [path isEqualToString:_program];
    if (ours) [_breakpoints removeAllObjects];
    NSMutableArray *results = [NSMutableArray array];
    for (NSDictionary *breakpoint in arguments[@"breakpoints"]) {
        NSInteger line = [breakpoint[@"line"] integerValue];
        NSInteger identifier = ++_nextBreakpointID;
        BOOL verified = ours && line >= 1 && line <= (NSInteger)_lines.count;
        if (verified) _breakpoints[@(line)] = @(identifier);
        NSMutableDictionary *result = [@{ @"id": @(identifier), @"verified": @(verified), @"line": @(line) } mutableCopy];
        if (!verified) result[@"message"] = ours ? @"The line is not in the program." : @"Not in the program.";
        [results addObject:result];
    }
    [self _respond:request body:@{ @"breakpoints": results }];
}

- (void)_configurationDone:(NSDictionary *)request arguments:(NSDictionary *)arguments {
    [self _respond:request body:nil];
    if (!_program) return;
    [self _output:[NSString stringWithFormat:@"Running %@\n", [_program lastPathComponent]] category:@"console"];
    [self _event:@"thread" body:@{ @"reason": @"started", @"threadId": @(UDMainThread) }];
    _line = 1;
    if (_stopOnEntry) {
        [self _stop:@"entry"];
    } else if (_breakpoints[@(_line)]) {
        [self _stop:@"breakpoint"];
    } else {
        [self _run];
    }
}

// ---------------------------------------------------------------------------
// MARK: - Running
// ---------------------------------------------------------------------------

- (void)_stop:(NSString *)reason {
    _running = NO;
    _pauseRequested = NO;
    NSMutableDictionary *body = [@{ @"reason": reason, @"threadId": @(UDMainThread), @"allThreadsStopped": @YES } mutableCopy];
    NSNumber *hit = _breakpoints[@(_line)];
    if ([reason isEqualToString:@"breakpoint"] && hit) body[@"hitBreakpointIds"] = @[ hit ];
    [self _event:@"stopped" body:body];
}

/// Runs the line it is at and moves to the next; NO when that was the last.
- (BOOL)_runLine {
    NSString *text = _line >= 1 && _line <= (NSInteger)_lines.count ? _lines[(NSUInteger)_line - 1] : @"";
    if ([text hasPrefix:@"print "]) {
        [self _output:[[text substringFromIndex:6] stringByAppendingString:@"\n"] category:@"stdout"];
    }
    _line++;
    if (_line <= (NSInteger)_lines.count) return YES;
    [self _exit:0];
    return NO;
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
        if (![self _runLine]) return;
        if (_breakpoints[@(_line)]) {
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

- (void)_next:(NSDictionary *)request arguments:(NSDictionary *)arguments {
    [self _respond:request body:nil];
    if ([self _runLine]) [self _stop:@"step"];
}

- (void)_stepIn:(NSDictionary *)request arguments:(NSDictionary *)arguments {
    [self _respond:request body:nil];
    [_callers addObject:@(_line)];
    if ([self _runLine]) [self _stop:@"step"];
}

- (void)_stepOut:(NSDictionary *)request arguments:(NSDictionary *)arguments {
    [self _respond:request body:nil];
    if (!_callers.count) {
        if ([self _runLine]) [self _stop:@"step"];
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

- (void)_pause:(NSDictionary *)request arguments:(NSDictionary *)arguments {
    [self _respond:request body:nil];
    if (_running) _pauseRequested = YES;
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

- (NSArray *)_variablesOfReference:(NSInteger)reference {
    if (reference == UDGlobalsReference) {
        return @[ @{ @"name": @"program", @"value": [NSString stringWithFormat:@"\"%@\"", [_program lastPathComponent]],
                     @"type": @"string", @"variablesReference": @0 },
                  @{ @"name": @"lineCount", @"value": [@(_lines.count) stringValue], @"type": @"int", @"variablesReference": @0 } ];
    }
    NSInteger frameID = reference / 10, line = [self _lineOfFrame:frameID];
    NSString *text = [self _textOfLine:line];
    if (reference % 10 == 3) {
        BOOL blank = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]].length == 0;
        return @[ @{ @"name": @"length", @"value": [@(text.length) stringValue], @"type": @"int", @"variablesReference": @0 },
                  @{ @"name": @"blank", @"value": blank ? @"true" : @"false", @"type": @"bool", @"variablesReference": @0 } ];
    }
    return @[ @{ @"name": @"line", @"value": [@(line) stringValue], @"type": @"int", @"variablesReference": @0 },
              @{ @"name": @"text", @"value": [NSString stringWithFormat:@"\"%@\"", text], @"type": @"string",
                 @"variablesReference": @0 },
              @{ @"name": @"info", @"value": [NSString stringWithFormat:@"{length=%lu}", (unsigned long)text.length],
                 @"type": @"struct", @"variablesReference": @(frameID * 10 + 3) } ];
}

- (void)_variables:(NSDictionary *)request arguments:(NSDictionary *)arguments {
    [self _respond:request body:@{ @"variables": [self _variablesOfReference:[arguments[@"variablesReference"] integerValue]] }];
}

- (void)_evaluate:(NSDictionary *)request arguments:(NSDictionary *)arguments {
    NSString *expression = arguments[@"expression"];
    NSInteger frameID = [arguments[@"frameId"] integerValue] ?: 1000 + (NSInteger)_callers.count;
    NSMutableArray *variables = [[self _variablesOfReference:frameID * 10 + 1] mutableCopy];
    [variables addObjectsFromArray:[self _variablesOfReference:UDGlobalsReference]];
    for (NSDictionary *variable in variables) {
        if (![variable[@"name"] isEqual:expression]) continue;
        [self _respond:request body:@{ @"result": variable[@"value"], @"type": variable[@"type"],
                                       @"variablesReference": variable[@"variablesReference"] }];
        return;
    }
    [self _fail:request message:[NSString stringWithFormat:@"error: use of undeclared identifier '%@'", expression]];
}

@end
