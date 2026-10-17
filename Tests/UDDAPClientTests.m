//
//  UDDAPClientTests.m
//
//  The protocol layer: LSPTransport's framing (messages split and joined
//  however the pipe delivers them, lengths in bytes), over a process; and
//  DAPClient against the demo adapter, in this process and as a process of
//  its own: requests matched to their responses, the capabilities, the
//  events in order, failures, requests from the adapter refused, and what
//  happens when the adapter ends.
//

#import <XCTest/XCTest.h>
#import "UDCodeTestCase.h"
#import "UDDemoDebugAdapter.h"

@interface UDDAPClientTests : UDCodeTestCase <LSPTransportDelegate, DAPClientDelegate>
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *messages;
@property (nonatomic) BOOL closed;
@property (nonatomic, strong) NSMutableArray<NSString *> *events;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *eventBodies;
@property (nonatomic, strong) NSMutableDictionary<NSString *, DAPResponse *> *responses;
@property (nonatomic) BOOL ended;
@end

@implementation UDDAPClientTests

- (void)setUp {
    [super setUp];
    _messages = [NSMutableArray array];
    _events = [NSMutableArray array];
    _eventBodies = [NSMutableArray array];
    _responses = [NSMutableDictionary dictionary];
    _closed = NO;
    _ended = NO;
}

// ---------------------------------------------------------------------------
// MARK: - LSPTransportDelegate
// ---------------------------------------------------------------------------

- (void)transport:(LSPTransport *)transport didReceiveMessage:(NSDictionary *)message {
    [_messages addObject:message];
}

- (void)transportDidClose:(LSPTransport *)transport {
    _closed = YES;
}

- (void)transport:(LSPTransport *)transport didReceiveErrorOutput:(NSString *)text {
}

- (void)testTheTransportFramesMessagesHoweverTheyArrive {
    NSPipe *pipe = [NSPipe pipe], *unused = [NSPipe pipe];
    LSPTransport *transport = [[LSPTransport alloc] initWithReadHandle:[pipe fileHandleForReading]
                                                           writeHandle:[unused fileHandleForWriting]];
    transport.delegate = self;
    NSFileHandle *writer = [pipe fileHandleForWriting];

    // Two in one write; the lengths count bytes, not characters.
    NSMutableData *two = [NSMutableData dataWithData:[LSPTransport frameForMessage:@{ @"n": @1, @"s": @"héllo — ✓" }]];
    [two appendData:[LSPTransport frameForMessage:@{ @"n": @2 }]];
    [writer writeData:two];
    UDRunUntil(_messages.count == 2, 5);
    XCTAssertEqual(_messages.count, 2u);
    XCTAssertEqualObjects(_messages[0][@"s"], @"héllo — ✓");
    XCTAssertEqualObjects(_messages[1][@"n"], @2);

    // One in three writes, the header itself split.
    NSData *frame = [LSPTransport frameForMessage:@{ @"n": @3 }];
    [writer writeData:[frame subdataWithRange:NSMakeRange(0, 10)]];
    UDRunUntil(NO, 0.05);
    XCTAssertEqual(_messages.count, 2u, @"nothing until it is whole");
    [writer writeData:[frame subdataWithRange:NSMakeRange(10, 12)]];
    [writer writeData:[frame subdataWithRange:NSMakeRange(22, frame.length - 22)]];
    UDRunUntil(_messages.count == 3, 5);
    XCTAssertEqualObjects(_messages.lastObject[@"n"], @3);

    // The end of what is read is the end of the other side.
    [writer closeFile];
    UDRunUntil(_closed, 5);
    XCTAssertTrue(_closed);
    XCTAssertFalse(transport.open);
}

- (void)testTheTransportOverAProcess {
    LSPTransport *transport = [[LSPTransport alloc] initWithLaunchPath:@"/bin/cat" arguments:@[]
                                                  currentDirectoryPath:nil];
    transport.delegate = self;
    XCTAssertNil(transport.launchError);
    XCTAssertTrue([transport.task isRunning]);
    [transport sendMessage:@{ @"echo": @"back" }];
    UDRunUntil(_messages.count == 1, 5);
    XCTAssertEqualObjects(_messages.firstObject, @{ @"echo": @"back" });
    [transport terminate];
    UDRunUntil(_closed, 5);
    XCTAssertTrue(_closed, @"its end is told");
}

- (void)testATransportWhoseProcessCannotStart {
    LSPTransport *transport = [[LSPTransport alloc] initWithLaunchPath:@"/nonexistent/adapter" arguments:@[]
                                                  currentDirectoryPath:nil];
    transport.delegate = self;
    XCTAssertNotNil(transport.launchError);
    UDRunUntil(_closed, 5);
    XCTAssertTrue(_closed, @"told on the next turn of the run loop");
}

// ---------------------------------------------------------------------------
// MARK: - DAPClientDelegate
// ---------------------------------------------------------------------------

- (void)_event:(NSString *)name body:(NSDictionary *)body {
    [_events addObject:name];
    [_eventBodies addObject:body ?: @{}];
}

- (void)debugAdapterDidInitialize:(DAPClient *)client            { [self _event:@"initialized" body:nil]; }
- (void)debugAdapter:(DAPClient *)client didStop:(NSDictionary *)body          { [self _event:@"stopped" body:body]; }
- (void)debugAdapter:(DAPClient *)client didContinue:(NSDictionary *)body      { [self _event:@"continued" body:body]; }
- (void)debugAdapter:(DAPClient *)client threadDidChange:(NSDictionary *)body  { [self _event:@"thread" body:body]; }
- (void)debugAdapter:(DAPClient *)client didOutput:(NSDictionary *)body        { [self _event:@"output" body:body]; }
- (void)debugAdapter:(DAPClient *)client didTerminate:(NSDictionary *)body     { [self _event:@"terminated" body:body]; }
- (void)debugAdapter:(DAPClient *)client debuggeeDidExit:(NSDictionary *)body  { [self _event:@"exited" body:body]; }
- (void)debugAdapterDidEnd:(DAPClient *)client                    { _ended = YES; }

/// Responses, by their command.
- (void)didRespond:(DAPResponse *)response {
    _responses[response.command] = response;
}

- (NSUInteger)countOf:(NSString *)event {
    NSUInteger n = 0;
    for (NSString *e in _events) if ([e isEqualToString:event]) n++;
    return n;
}

- (void)testASessionWithTheAdapterInOrder {
    NSString *program = [UDCodeTestCase temporaryFileNamed:@"client.demo" text:@"one\nprint two\nthree\nfour\n"];
    UDDemoDebugAdapter *adapter = nil;
    DAPClient *client = [UDCodeTestCase clientOfAdapter:&adapter];
    client.delegate = self;
    SEL respond = @selector(didRespond:);

    NSInteger seq = [client initializeWithAdapterID:@"demo" clientName:@"UDCodeTests" target:self action:respond];
    XCTAssertEqual(seq, 1);
    UDRunUntil(_responses[@"initialize"] && [self countOf:@"initialized"], 5);
    XCTAssertTrue(_responses[@"initialize"].success);
    XCTAssertEqual(_responses[@"initialize"].requestSeq, 1);
    XCTAssertTrue(client.supportsConfigurationDoneRequest);
    XCTAssertTrue(client.supportsTerminateRequest);
    XCTAssertEqualObjects(adapter.requests.firstObject[@"arguments"][@"adapterID"], @"demo");
    XCTAssertEqualObjects(adapter.requests.firstObject[@"arguments"][@"linesStartAt1"], @YES);

    [client launchWithArguments:@{ @"program": program } target:self action:respond];
    [client setBreakpointsInFile:program breakpoints:@[ @{ @"line": @3 }, @{ @"line": @40 } ] target:self action:respond];
    UDRunUntil(_responses[@"setBreakpoints"], 5);
    XCTAssertTrue(_responses[@"launch"].success);
    NSArray *breakpoints = [_responses[@"setBreakpoints"].body objectForKey:@"breakpoints"];
    XCTAssertEqual(breakpoints.count, 2u, @"in the order sent");
    XCTAssertEqualObjects(breakpoints[0][@"verified"], @YES);
    XCTAssertEqualObjects(breakpoints[1][@"verified"], @NO, @"line 40 is not in the program");

    [client configurationDoneWithTarget:self action:respond];
    UDRunUntil([self countOf:@"stopped"] == 1, 5);
    XCTAssertEqualObjects(_eventBodies[[_events indexOfObject:@"stopped"]][@"reason"], @"breakpoint");
    NSUInteger output = [_events indexOfObject:@"output"];
    XCTAssertNotEqual(output, NSNotFound);
    XCTAssertEqualObjects(_eventBodies[output][@"output"], @"Running client.demo\n");
    XCTAssertLessThan(output, [_events indexOfObject:@"stopped"], @"in the order they came");
    XCTAssertEqualObjects(_eventBodies[[_events indexOfObject:@"output" inRange:NSMakeRange(output + 1, _events.count - output - 1)]][@"output"],
                          @"two\n", @"line 2 printed on the way");

    [client threadsWithTarget:self action:respond];
    [client stackTraceOfThread:1 startFrame:0 levels:0 target:self action:respond];
    UDRunUntil(_responses[@"stackTrace"], 5);
    XCTAssertEqual([[_responses[@"threads"].body objectForKey:@"threads"] count], 2u);
    NSDictionary *top = [[_responses[@"stackTrace"].body objectForKey:@"stackFrames"] firstObject];
    XCTAssertEqualObjects(top[@"line"], @3);
    XCTAssertEqualObjects(top[@"source"][@"path"], program);

    [client scopesOfFrame:[top[@"id"] integerValue] target:self action:respond];
    UDRunUntil(_responses[@"scopes"], 5);
    NSDictionary *locals = [[_responses[@"scopes"].body objectForKey:@"scopes"] firstObject];
    [client variablesOfReference:[locals[@"variablesReference"] integerValue] target:self action:respond];
    UDRunUntil(_responses[@"variables"], 5);
    NSArray *variables = [_responses[@"variables"].body objectForKey:@"variables"];
    XCTAssertEqualObjects([variables valueForKey:@"name"], (@[ @"line", @"text", @"info" ]));
    XCTAssertEqualObjects(variables[1][@"value"], @"\"three\"");

    // A request that fails says why.
    [client evaluate:@"nothing" inFrame:[top[@"id"] integerValue] context:@"repl" target:self action:respond];
    UDRunUntil(_responses[@"evaluate"], 5);
    XCTAssertFalse(_responses[@"evaluate"].success);
    XCTAssertEqualObjects(_responses[@"evaluate"].error.domain, DAPErrorDomain);
    XCTAssertEqualObjects(_responses[@"evaluate"].error.localizedDescription, @"error: use of undeclared identifier 'nothing'");

    [client nextInThread:1 target:self action:respond];
    UDRunUntil([self countOf:@"stopped"] == 2, 5);
    XCTAssertEqualObjects(_eventBodies[[_events indexOfObject:@"stopped" inRange:NSMakeRange([_events indexOfObject:@"stopped"] + 1, _events.count - [_events indexOfObject:@"stopped"] - 1)]][@"reason"], @"step");

    [client continueThread:1 target:self action:respond];
    UDRunUntil([self countOf:@"terminated"], 5);
    XCTAssertTrue(_responses[@"continue"].success);
    XCTAssertEqual([self countOf:@"exited"], 1u);
    XCTAssertEqualObjects(_eventBodies[[_events indexOfObject:@"exited"]][@"exitCode"], @0);

    [client disconnectTerminatingDebuggee:YES target:self action:respond];
    UDRunUntil(_ended, 5);
    XCTAssertTrue(_responses[@"disconnect"].success);
    XCTAssertTrue(_ended, @"the adapter's end is told");
    XCTAssertFalse(client.running);
    XCTAssertEqual([client threadsWithTarget:self action:respond], 0, @"nothing is sent once it has ended");
}

- (void)testRequestsWaitingWhenTheAdapterEndsFail {
    UDDemoDebugAdapter *adapter = nil;
    DAPClient *client = [UDCodeTestCase clientOfAdapter:&adapter];
    client.delegate = self;
    // A request the adapter does not know: answered, unsuccessfully.
    [client sendRequest:@"goto" arguments:@{ @"threadId": @1 } target:self action:@selector(didRespond:)];
    UDRunUntil(_responses[@"goto"], 5);
    XCTAssertFalse(_responses[@"goto"].success);
    XCTAssertEqualObjects(_responses[@"goto"].error.localizedDescription, @"Unknown request: goto");

    // One the adapter will never answer: it ends first.
    [client sendRequest:@"disconnect" arguments:nil target:nil action:NULL];
    [client threadsWithTarget:self action:@selector(didRespond:)];
    UDRunUntil(_ended, 5);
    XCTAssertTrue(_ended);
    XCTAssertTrue(adapter.finished);
    DAPResponse *threads = _responses[@"threads"];
    XCTAssertNotNil(threads, @"answered all the same");
    XCTAssertFalse(threads.success);
    XCTAssertEqual(threads.error.code, DAPErrorAdapterEnded);
}

- (void)testRequestsFromTheAdapterAreRefused {
    NSPipe *toAdapter = [NSPipe pipe], *toClient = [NSPipe pipe];
    LSPTransport *adapterSide = [[LSPTransport alloc] initWithReadHandle:[toAdapter fileHandleForReading]
                                                             writeHandle:[toClient fileHandleForWriting]];
    adapterSide.delegate = self;
    DAPClient *client = [[DAPClient alloc] initWithReadHandle:[toClient fileHandleForReading]
                                                  writeHandle:[toAdapter fileHandleForWriting]];
    client.delegate = self;
    [adapterSide sendMessage:@{ @"seq": @7, @"type": @"request", @"command": @"runInTerminal",
                                @"arguments": @{ @"args": @[ @"/bin/true" ] } }];
    [adapterSide sendMessage:@{ @"seq": @8, @"type": @"event", @"event": @"capabilities",
                                @"body": @{ @"capabilities": @{ @"supportsTerminateRequest": @YES } } }];
    UDRunUntil(_messages.count == 1 && client.supportsTerminateRequest, 5);
    NSDictionary *answer = _messages.firstObject;
    XCTAssertEqualObjects(answer[@"type"], @"response");
    XCTAssertEqualObjects(answer[@"request_seq"], @7);
    XCTAssertEqualObjects(answer[@"command"], @"runInTerminal");
    XCTAssertEqualObjects(answer[@"success"], @NO);
    XCTAssertTrue(client.supportsTerminateRequest, @"a capabilities event adds to them");
    [adapterSide close];
}

- (void)testConfigurationDoneOnlyWhenTheAdapterSupportsIt {
    NSPipe *toAdapter = [NSPipe pipe], *toClient = [NSPipe pipe];
    DAPClient *client = [[DAPClient alloc] initWithReadHandle:[toClient fileHandleForReading]
                                                  writeHandle:[toAdapter fileHandleForWriting]];
    XCTAssertFalse(client.supportsConfigurationDoneRequest, @"nothing is known before initialize");
    XCTAssertEqual([client configurationDoneWithTarget:self action:@selector(didRespond:)], 0, @"not sent");
    XCTAssertEqual([client terminateDebuggeeWithTarget:self action:@selector(didRespond:)], 0, @"not sent");
    [client close];
}

- (void)testTheAdapterAsAProcessOfItsOwn {
    NSString *udcode = [UDCodeTestCase udcodeExecutablePath];
    XCTAssertTrue([[NSFileManager defaultManager] isExecutableFileAtPath:udcode], @"%@", udcode);
    DAPClient *client = [[DAPClient alloc] initWithCommand:@[ udcode, UDDemoDebugAdapterOption ]
                                      currentDirectoryPath:NSTemporaryDirectory()];
    client.delegate = self;
    XCTAssertNil(client.launchError);
    [client initializeWithAdapterID:@"demo" clientName:@"UDCodeTests" target:self action:@selector(didRespond:)];
    UDRunUntil(_responses[@"initialize"] && [self countOf:@"initialized"], 20);
    XCTAssertTrue(_responses[@"initialize"].success);
    XCTAssertTrue(client.supportsConfigurationDoneRequest);
    [client disconnectTerminatingDebuggee:YES target:self action:@selector(didRespond:)];
    UDRunUntil(_ended, 10);
    XCTAssertTrue(_responses[@"disconnect"].success);
    XCTAssertTrue(_ended, @"the process ended when disconnected");
}

- (void)testAnAdapterThatCannotStart {
    DAPClient *client = [[DAPClient alloc] initWithCommand:@[ @"/nonexistent/adapter", @"--stdio" ]
                                      currentDirectoryPath:nil];
    client.delegate = self;
    XCTAssertNotNil(client.launchError);
    UDRunUntil(_ended, 5);
    XCTAssertTrue(_ended);
}

@end
