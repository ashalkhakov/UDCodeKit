//
//  DAPClient.m
//  LSPKit
//
//  Requests are numbered (seq) from 1; a response names its request's
//  (request_seq), and goes to what that request named. Requests the adapter
//  sends (runInTerminal, startDebugging) are refused: this client runs
//  nothing on the adapter's behalf.
//

#import "DAPClient.h"

NSErrorDomain const DAPErrorDomain = @"DAPErrorDomain";

// ---------------------------------------------------------------------------
// MARK: - Responses and pending requests
// ---------------------------------------------------------------------------

@interface DAPResponse ()
@property (readwrite) NSInteger requestSeq;
@property (readwrite, copy) NSString *command;
@property (readwrite) BOOL success;
@property (readwrite, nullable) id body;
@property (readwrite, nullable) NSError *error;
@end

@implementation DAPResponse
@end

/// A request waiting for its response: who to tell.
@interface DAPPendingRequest : NSObject
@property (copy) NSString *command;
@property (weak) id target;
@property SEL action;
@end

@implementation DAPPendingRequest
@end

// ---------------------------------------------------------------------------
// MARK: - The client
// ---------------------------------------------------------------------------

@interface DAPClient () <LSPTransportDelegate> {
    LSPTransport *_transport;
    NSInteger _seq;
    NSMutableDictionary<NSNumber *, DAPPendingRequest *> *_pending;
    BOOL _ended;
}
@end

@implementation DAPClient

- (instancetype)initWithCommand:(NSArray<NSString *> *)command currentDirectoryPath:(NSString *)directory {
    self = [super init];
    if (!self) return nil;
    _pending = [NSMutableDictionary dictionary];
    _capabilities = [NSDictionary dictionary];
    NSArray *arguments = [command count] > 1 ? [command subarrayWithRange:NSMakeRange(1, [command count] - 1)]
                                             : [NSArray array];
    _transport = [[LSPTransport alloc] initWithLaunchPath:[command firstObject] ?: @""
                                                arguments:arguments
                                     currentDirectoryPath:directory];
    _transport.delegate = self;
    return self;
}

- (instancetype)initWithReadHandle:(NSFileHandle *)readHandle writeHandle:(NSFileHandle *)writeHandle {
    self = [super init];
    if (!self) return nil;
    _pending = [NSMutableDictionary dictionary];
    _capabilities = [NSDictionary dictionary];
    _transport = [[LSPTransport alloc] initWithReadHandle:readHandle writeHandle:writeHandle];
    _transport.delegate = self;
    return self;
}

- (void)dealloc {
    [_transport close];
}

- (NSError *)launchError {
    return _transport.launchError;
}

- (BOOL)isRunning {
    return !_ended && [_transport isOpen];
}

- (void)close {
    _ended = YES;
    [_pending removeAllObjects];
    [_transport close];
}

#pragma mark Capabilities

- (BOOL)_capability:(NSString *)name {
    id value = [_capabilities objectForKey:name];
    return [value respondsToSelector:@selector(boolValue)] && [value boolValue];
}

- (BOOL)supportsConfigurationDoneRequest { return [self _capability:@"supportsConfigurationDoneRequest"]; }
- (BOOL)supportsTerminateRequest         { return [self _capability:@"supportsTerminateRequest"]; }
- (BOOL)supportsEvaluateForHovers        { return [self _capability:@"supportsEvaluateForHovers"]; }
- (BOOL)supportsConditionalBreakpoints   { return [self _capability:@"supportsConditionalBreakpoints"]; }

#pragma mark Messages from the adapter

- (void)transport:(LSPTransport *)transport didReceiveMessage:(NSDictionary *)message {
    NSString *type = [message objectForKey:@"type"];
    if ([type isEqual:@"response"]) {
        [self _handleResponse:message];
    } else if ([type isEqual:@"event"]) {
        [self _handleEvent:message];
    } else if ([type isEqual:@"request"]) {
        [self _refuseRequest:message];
    }
}

- (void)transport:(LSPTransport *)transport didReceiveErrorOutput:(NSString *)text {
    id<DAPClientDelegate> delegate = _delegate;
    if ([delegate respondsToSelector:@selector(debugAdapter:didWriteErrorOutput:)]) {
        [delegate debugAdapter:self didWriteErrorOutput:text];
    } else {
        NSLog(@"debug adapter: %@", text);
    }
}

- (void)transportDidClose:(LSPTransport *)transport {
    if (_ended) return;
    _ended = YES;
    // What is still waiting will not be answered.
    NSDictionary *pending = [_pending copy];
    [_pending removeAllObjects];
    for (NSNumber *seq in [[pending allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        DAPPendingRequest *request = [pending objectForKey:seq];
        DAPResponse *response = [[DAPResponse alloc] init];
        response.requestSeq = [seq integerValue];
        response.command = request.command;
        response.error = [NSError errorWithDomain:DAPErrorDomain code:DAPErrorAdapterEnded
                                         userInfo:[NSDictionary dictionaryWithObject:@"The debug adapter ended."
                                                                              forKey:NSLocalizedDescriptionKey]];
        [self _send:request response:response];
    }
    id<DAPClientDelegate> delegate = _delegate;
    if ([delegate respondsToSelector:@selector(debugAdapterDidEnd:)]) {
        [delegate debugAdapterDidEnd:self];
    }
}

- (void)_handleResponse:(NSDictionary *)message {
    NSNumber *requestSeq = [message objectForKey:@"request_seq"];
    if (![requestSeq isKindOfClass:[NSNumber class]]) return;
    DAPPendingRequest *request = [_pending objectForKey:requestSeq];
    if (request == nil) return;
    [_pending removeObjectForKey:requestSeq];

    DAPResponse *response = [[DAPResponse alloc] init];
    response.requestSeq = [requestSeq integerValue];
    response.command = [message objectForKey:@"command"] ?: request.command;
    response.success = [[message objectForKey:@"success"] boolValue];
    id body = [message objectForKey:@"body"];
    response.body = body == [NSNull null] ? nil : body;
    if (!response.success) {
        // The message, or the body's error's format (a Message).
        NSString *text = [message objectForKey:@"message"];
        NSDictionary *errorBody = [response.body isKindOfClass:[NSDictionary class]] ? [response.body objectForKey:@"error"] : nil;
        if ([errorBody isKindOfClass:[NSDictionary class]] && [[errorBody objectForKey:@"format"] isKindOfClass:[NSString class]]) {
            text = [errorBody objectForKey:@"format"];
        }
        if (![text isKindOfClass:[NSString class]]) text = [NSString stringWithFormat:@"%@ failed", response.command];
        response.error = [NSError errorWithDomain:DAPErrorDomain code:DAPErrorRequestFailed
                                         userInfo:[NSDictionary dictionaryWithObject:text forKey:NSLocalizedDescriptionKey]];
    }
    if ([response.command isEqual:@"initialize"] && response.success && [response.body isKindOfClass:[NSDictionary class]]) {
        _capabilities = [response.body copy];
    }
    [self _send:request response:response];
}

- (void)_send:(DAPPendingRequest *)request response:(DAPResponse *)response {
    id target = request.target;
    if (target && request.action && [target respondsToSelector:request.action]) {
        // One object argument, as LSPClient's replies.
        IMP imp = [target methodForSelector:request.action];
        ((void (*)(id, SEL, DAPResponse *))imp)(target, request.action, response);
    }
}

- (void)_handleEvent:(NSDictionary *)message {
    NSString *event = [message objectForKey:@"event"];
    NSDictionary *body = [message objectForKey:@"body"];
    if (![body isKindOfClass:[NSDictionary class]]) body = [NSDictionary dictionary];
    id<DAPClientDelegate> delegate = _delegate;
    if ([event isEqual:@"capabilities"]) {
        // Capabilities that changed.
        NSDictionary *changed = [body objectForKey:@"capabilities"];
        if ([changed isKindOfClass:[NSDictionary class]]) {
            NSMutableDictionary *capabilities = [_capabilities mutableCopy];
            [capabilities addEntriesFromDictionary:changed];
            _capabilities = [capabilities copy];
        }
    }
    if ([event isEqual:@"initialized"]) {
        if ([delegate respondsToSelector:@selector(debugAdapterDidInitialize:)]) [delegate debugAdapterDidInitialize:self];
    } else if ([event isEqual:@"stopped"]) {
        if ([delegate respondsToSelector:@selector(debugAdapter:didStop:)]) [delegate debugAdapter:self didStop:body];
    } else if ([event isEqual:@"continued"]) {
        if ([delegate respondsToSelector:@selector(debugAdapter:didContinue:)]) [delegate debugAdapter:self didContinue:body];
    } else if ([event isEqual:@"thread"]) {
        if ([delegate respondsToSelector:@selector(debugAdapter:threadDidChange:)]) [delegate debugAdapter:self threadDidChange:body];
    } else if ([event isEqual:@"output"]) {
        if ([delegate respondsToSelector:@selector(debugAdapter:didOutput:)]) [delegate debugAdapter:self didOutput:body];
    } else if ([event isEqual:@"breakpoint"]) {
        if ([delegate respondsToSelector:@selector(debugAdapter:breakpointDidChange:)]) [delegate debugAdapter:self breakpointDidChange:body];
    } else if ([event isEqual:@"terminated"]) {
        if ([delegate respondsToSelector:@selector(debugAdapter:didTerminate:)]) [delegate debugAdapter:self didTerminate:body];
    } else if ([event isEqual:@"exited"]) {
        if ([delegate respondsToSelector:@selector(debugAdapter:debuggeeDidExit:)]) [delegate debugAdapter:self debuggeeDidExit:body];
    } else if ([event isKindOfClass:[NSString class]]) {
        if ([delegate respondsToSelector:@selector(debugAdapter:didReceiveEvent:body:)]) {
            [delegate debugAdapter:self didReceiveEvent:event body:body];
        }
    }
}

/// A request from the adapter: answered, unsuccessfully.
- (void)_refuseRequest:(NSDictionary *)message {
    NSString *command = [message objectForKey:@"command"];
    NSNumber *seq = [message objectForKey:@"seq"];
    if (![seq isKindOfClass:[NSNumber class]]) return;
    _seq++;
    NSDictionary *response = [NSDictionary dictionaryWithObjectsAndKeys:
                              [NSNumber numberWithInteger:_seq], @"seq",
                              @"response", @"type",
                              seq, @"request_seq",
                              [NSNumber numberWithBool:NO], @"success",
                              [command isKindOfClass:[NSString class]] ? command : @"", @"command",
                              @"Not supported by this client.", @"message",
                              nil];
    [_transport sendMessage:response];
}

#pragma mark Requests

- (NSInteger)sendRequest:(NSString *)command arguments:(NSDictionary *)arguments target:(id)target action:(SEL)action {
    if (_ended) return 0;
    _seq++;
    NSMutableDictionary *request = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                    [NSNumber numberWithInteger:_seq], @"seq",
                                    @"request", @"type",
                                    command, @"command",
                                    nil];
    if (arguments) [request setObject:arguments forKey:@"arguments"];
    DAPPendingRequest *pending = [[DAPPendingRequest alloc] init];
    pending.command = command;
    pending.target = target;
    pending.action = action;
    [_pending setObject:pending forKey:[NSNumber numberWithInteger:_seq]];
    [_transport sendMessage:request];
    return _seq;
}

- (NSInteger)initializeWithAdapterID:(NSString *)adapterID clientName:(NSString *)clientName target:(id)target action:(SEL)action {
    NSNumber *yes = [NSNumber numberWithBool:YES], *no = [NSNumber numberWithBool:NO];
    NSDictionary *arguments = [NSDictionary dictionaryWithObjectsAndKeys:
                               @"udcodekit", @"clientID",
                               clientName, @"clientName",
                               adapterID, @"adapterID",
                               @"en-US", @"locale",
                               yes, @"linesStartAt1",
                               yes, @"columnsStartAt1",
                               @"path", @"pathFormat",
                               yes, @"supportsVariableType",
                               no, @"supportsVariablePaging",
                               no, @"supportsRunInTerminalRequest",
                               no, @"supportsStartDebuggingRequest",
                               no, @"supportsMemoryReferences",
                               no, @"supportsProgressReporting",
                               no, @"supportsInvalidatedEvent",
                               nil];
    return [self sendRequest:@"initialize" arguments:arguments target:target action:action];
}

- (NSInteger)launchWithArguments:(NSDictionary *)arguments target:(id)target action:(SEL)action {
    return [self sendRequest:@"launch" arguments:arguments target:target action:action];
}

- (NSInteger)attachWithArguments:(NSDictionary *)arguments target:(id)target action:(SEL)action {
    return [self sendRequest:@"attach" arguments:arguments target:target action:action];
}

- (NSInteger)setBreakpointsInFile:(NSString *)path breakpoints:(NSArray<NSDictionary *> *)breakpoints
                           target:(id)target action:(SEL)action {
    NSMutableArray *lines = [NSMutableArray arrayWithCapacity:[breakpoints count]];
    for (NSDictionary *breakpoint in breakpoints) {
        id line = [breakpoint objectForKey:@"line"];
        if (line) [lines addObject:line];
    }
    NSDictionary *source = [NSDictionary dictionaryWithObjectsAndKeys:
                            [path lastPathComponent], @"name",
                            path, @"path",
                            nil];
    NSDictionary *arguments = [NSDictionary dictionaryWithObjectsAndKeys:
                               source, @"source",
                               breakpoints, @"breakpoints",
                               lines, @"lines",
                               [NSNumber numberWithBool:NO], @"sourceModified",
                               nil];
    return [self sendRequest:@"setBreakpoints" arguments:arguments target:target action:action];
}

- (NSInteger)configurationDoneWithTarget:(id)target action:(SEL)action {
    if (![self supportsConfigurationDoneRequest]) return 0;
    return [self sendRequest:@"configurationDone" arguments:nil target:target action:action];
}

- (NSInteger)threadsWithTarget:(id)target action:(SEL)action {
    return [self sendRequest:@"threads" arguments:nil target:target action:action];
}

- (NSDictionary *)_threadArguments:(NSInteger)threadID {
    return [NSDictionary dictionaryWithObject:[NSNumber numberWithInteger:threadID] forKey:@"threadId"];
}

- (NSInteger)stackTraceOfThread:(NSInteger)threadID startFrame:(NSInteger)startFrame levels:(NSInteger)levels
                         target:(id)target action:(SEL)action {
    NSDictionary *arguments = [NSDictionary dictionaryWithObjectsAndKeys:
                               [NSNumber numberWithInteger:threadID], @"threadId",
                               [NSNumber numberWithInteger:startFrame], @"startFrame",
                               [NSNumber numberWithInteger:levels], @"levels",
                               nil];
    return [self sendRequest:@"stackTrace" arguments:arguments target:target action:action];
}

- (NSInteger)scopesOfFrame:(NSInteger)frameID target:(id)target action:(SEL)action {
    NSDictionary *arguments = [NSDictionary dictionaryWithObject:[NSNumber numberWithInteger:frameID] forKey:@"frameId"];
    return [self sendRequest:@"scopes" arguments:arguments target:target action:action];
}

- (NSInteger)variablesOfReference:(NSInteger)variablesReference target:(id)target action:(SEL)action {
    NSDictionary *arguments = [NSDictionary dictionaryWithObject:[NSNumber numberWithInteger:variablesReference]
                                                          forKey:@"variablesReference"];
    return [self sendRequest:@"variables" arguments:arguments target:target action:action];
}

- (NSInteger)evaluate:(NSString *)expression inFrame:(NSInteger)frameID context:(NSString *)context
               target:(id)target action:(SEL)action {
    NSMutableDictionary *arguments = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                      expression, @"expression",
                                      context, @"context",
                                      nil];
    if (frameID > 0) [arguments setObject:[NSNumber numberWithInteger:frameID] forKey:@"frameId"];
    return [self sendRequest:@"evaluate" arguments:arguments target:target action:action];
}

- (NSInteger)continueThread:(NSInteger)threadID target:(id)target action:(SEL)action {
    return [self sendRequest:@"continue" arguments:[self _threadArguments:threadID] target:target action:action];
}

- (NSInteger)nextInThread:(NSInteger)threadID target:(id)target action:(SEL)action {
    return [self sendRequest:@"next" arguments:[self _threadArguments:threadID] target:target action:action];
}

- (NSInteger)stepInThread:(NSInteger)threadID target:(id)target action:(SEL)action {
    return [self sendRequest:@"stepIn" arguments:[self _threadArguments:threadID] target:target action:action];
}

- (NSInteger)stepOutThread:(NSInteger)threadID target:(id)target action:(SEL)action {
    return [self sendRequest:@"stepOut" arguments:[self _threadArguments:threadID] target:target action:action];
}

- (NSInteger)pauseThread:(NSInteger)threadID target:(id)target action:(SEL)action {
    return [self sendRequest:@"pause" arguments:[self _threadArguments:threadID] target:target action:action];
}

- (NSInteger)terminateDebuggeeWithTarget:(id)target action:(SEL)action {
    if (![self supportsTerminateRequest]) return 0;
    return [self sendRequest:@"terminate" arguments:nil target:target action:action];
}

- (NSInteger)disconnectTerminatingDebuggee:(BOOL)terminate target:(id)target action:(SEL)action {
    NSDictionary *arguments = [NSDictionary dictionaryWithObjectsAndKeys:
                               [NSNumber numberWithBool:NO], @"restart",
                               [NSNumber numberWithBool:terminate], @"terminateDebuggee",
                               nil];
    return [self sendRequest:@"disconnect" arguments:arguments target:target action:action];
}

@end
