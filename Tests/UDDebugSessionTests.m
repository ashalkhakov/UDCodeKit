//
//  UDDebugSessionTests.m
//
//  The debug session over the demo adapter, in this process: starting it
//  (initialize, launch, the enabled breakpoints per file, configurationDone),
//  a stop (threads, the stopped thread's frames, the top frame selected and
//  shown, the instruction pointer), scopes and variables loaded when asked,
//  stepping, continuing to the end, pausing, the breakpoints changed or
//  moved while it runs sent again, the console, and stopping it. And what
//  VS Code does besides: breakpoints with conditions, hit counts and log
//  messages (sent as far as the adapter takes them, the rest marked), the
//  exception filters, the watch expressions, evaluating for a hover,
//  setting a variable, Run to Cursor, Jump to Cursor and stepping back.
//

#import <XCTest/XCTest.h>
#import "UDCodeTestCase.h"
#import <UDCodeKit/UDCodeKit.h>
#import "UDDemoDebugAdapter.h"

static NSString * const UDProgram =
    @"start\n"            // 1
    @"print hello\n"      // 2
    @"third\n"            // 3
    @"fourth\n"           // 4
    @"fifth\n"            // 5
    @"\n"                 // 6
    @"seventh\n"          // 7
    @"print bye\n"        // 8
    @"last\n";            // 9

@interface UDDebugSessionTests : UDCodeTestCase <UDDebugSessionDelegate>
@property (nonatomic, strong) NSString *program;
@property (nonatomic, strong) UDBreakpointStore *store;
@property (nonatomic, strong) UDDemoDebugAdapter *adapter;
@property (nonatomic, strong) UDDebugSession *session;
@property (nonatomic, copy) NSString *shownFile;
@property (nonatomic) NSInteger shownLine;
@property (nonatomic) NSUInteger shows;
@property (nonatomic) BOOL ended;
@property (nonatomic, strong) UDDebugVariable *evaluated;
@property (nonatomic) NSUInteger watchEvaluations;
@end

@implementation UDDebugSessionTests

- (void)setUp {
    [super setUp];
    _program = [UDCodeTestCase temporaryFileNamed:@"session.demo" text:UDProgram];
    _store = [[UDBreakpointStore alloc] init];
    UDDemoDebugAdapter *adapter = nil;
    DAPClient *client = [UDCodeTestCase clientOfAdapter:&adapter];
    _adapter = adapter;
    _session = [[UDDebugSession alloc] initWithClient:client breakpoints:_store];
    _session.delegate = self;
    _shows = 0;
    _ended = NO;
}

- (void)tearDown {
    [_session stop];
    UDRunUntil(_session.state == UDDebugSessionStateEnded, 5);
    _session = nil;
    [super tearDown];
}

- (void)debugSession:(UDDebugSession *)session showFile:(NSString *)path line:(NSInteger)line {
    _shownFile = path;
    _shownLine = line;
    _shows++;
}

- (void)debugSessionDidEnd:(UDDebugSession *)session {
    _ended = YES;
}

- (void)didEvaluate:(UDDebugVariable *)variable {
    _evaluated = variable;
}

- (void)watchesEvaluated:(NSNotification *)note {
    _watchEvaluations++;
}

/// The arguments of the adapter's last @a command request.
- (NSDictionary *)lastArgumentsOf:(NSString *)command {
    for (NSDictionary *request in _adapter.requests.reverseObjectEnumerator) {
        if ([request[@"command"] isEqual:command]) return request[@"arguments"];
    }
    return nil;
}

/// The lines of the adapter's last setBreakpoints.
- (NSArray *)sentLines {
    for (NSDictionary *request in _adapter.requests.reverseObjectEnumerator) {
        if ([request[@"command"] isEqual:@"setBreakpoints"]) return [request[@"arguments"][@"breakpoints"] valueForKey:@"line"];
    }
    return nil;
}

- (NSArray<NSString *> *)commands {
    return [_adapter.requests valueForKey:@"command"];
}

- (void)launchStoppingOnEntry:(BOOL)stopOnEntry {
    [_session launchWithArguments:@{ @"program": _program, @"stopOnEntry": @(stopOnEntry) }];
    UDRunUntil(_session.state == UDDebugSessionStateStopped && _session.selectedFrame, 5);
    XCTAssertEqual(_session.state, UDDebugSessionStateStopped);
}

- (void)waitForStopAfter:(NSUInteger)shows {
    UDRunUntil(_shows > shows && _session.state == UDDebugSessionStateStopped, 5);
}

// ---------------------------------------------------------------------------

- (void)testItStartsAndStopsAtABreakpoint {
    [_store addBreakpointAtLine:3 inFile:_program];
    [_store setBreakpoint:[_store addBreakpointAtLine:4 inFile:_program] enabled:NO];
    XCTAssertEqual(_session.state, UDDebugSessionStateStarting);
    [self launchStoppingOnEntry:NO];

    NSArray *commands = [self commands];
    XCTAssertEqualObjects([commands subarrayWithRange:NSMakeRange(0, 5)],
                          (@[ @"initialize", @"launch", @"setBreakpoints", @"setExceptionBreakpoints", @"configurationDone" ]));
    XCTAssertEqualObjects([self sentLines], @[ @3 ], @"the enabled ones");
    XCTAssertEqualObjects(_session.threads.firstObject.name, @"main");
    XCTAssertEqual(_session.threads.count, 2u);
    XCTAssertEqualObjects(_session.selectedThread.stopReason, @"breakpoint");
    XCTAssertTrue(_session.threads.lastObject.stopped, @"all threads stopped");
    XCTAssertEqual(_session.selectedThread.frames.count, 1u);
    XCTAssertEqual(_session.selectedFrame, _session.selectedThread.frames.firstObject, @"the top frame");
    XCTAssertEqual(_session.selectedFrame.line, 3);
    XCTAssertEqualObjects(_shownFile, _program, @"the host is asked to show it");
    XCTAssertEqual(_shownLine, 3);
    XCTAssertEqualObjects(_store.instructionPointerFile, _program);
    XCTAssertEqual(_store.instructionPointerLine, 3);
    XCTAssertTrue([_session.consoleText containsString:@"Running session.demo\n"]);
    XCTAssertTrue([_session.consoleText containsString:@"hello\n"], @"line 2 ran");
    XCTAssertTrue([_store breakpointAtLine:3 inFile:_program].verified);
    XCTAssertTrue(_session.canContinue && _session.canStep && !_session.canPause);
}

- (void)testScopesAndVariablesLoadWhenAsked {
    [self launchStoppingOnEntry:YES];
    UDRunUntil(_session.scopes, 5);
    XCTAssertEqualObjects([_session.scopes valueForKey:@"name"], (@[ @"Locals", @"Globals" ]));
    UDDebugVariable *locals = _session.scopes.firstObject;
    XCTAssertTrue(_session.scopes.lastObject.expensive);
    XCTAssertTrue(locals.hasChildren);
    XCTAssertNil(locals.children, @"not before they are asked for");

    [_session loadChildrenOfVariable:locals];
    UDRunUntil(locals.children, 5);
    XCTAssertEqualObjects([locals.children valueForKey:@"name"], (@[ @"line", @"text", @"info" ]));
    XCTAssertEqualObjects(locals.children[1].value, @"\"start\"");
    XCTAssertEqualObjects(locals.children[0].type, @"int");
    UDDebugVariable *info = locals.children[2];
    XCTAssertTrue(info.hasChildren);
    XCTAssertEqual(info.parent, locals);
    [_session loadChildrenOfVariable:info];
    UDRunUntil(info.children, 5);
    XCTAssertEqualObjects([info.children valueForKey:@"value"], (@[ @"5", @"false" ]));
}

- (void)testSteppingMovesThePointer {
    [self launchStoppingOnEntry:YES];
    XCTAssertEqual(_session.selectedFrame.line, 1);
    XCTAssertEqualObjects(_session.selectedThread.stopReason, @"entry");

    NSUInteger shows = _shows;
    [_session stepOver];
    XCTAssertEqual(_session.state, UDDebugSessionStateRunning, @"running until it stops again");
    XCTAssertNil(_session.selectedFrame);
    XCTAssertNil(_store.instructionPointerFile, @"no pointer while it runs");
    [self waitForStopAfter:shows];
    XCTAssertEqual(_session.selectedFrame.line, 2);

    shows = _shows;
    [_session stepInto];
    [self waitForStopAfter:shows];
    XCTAssertEqual(_session.selectedThread.frames.count, 2u, @"a frame deeper");
    XCTAssertEqualObjects(_session.selectedFrame.name, @"level1");
    XCTAssertEqual(_session.selectedFrame.line, 3);
    XCTAssertEqual(_session.selectedThread.frames.lastObject.line, 2, @"the caller, where it stepped in");

    // Choosing the caller's frame shows it, and moves the pointer there.
    shows = _shows;
    [_session selectFrame:_session.selectedThread.frames.lastObject];
    XCTAssertEqual(_shows, shows + 1);
    XCTAssertEqual(_shownLine, 2);
    XCTAssertEqual(_store.instructionPointerLine, 2);

    shows = _shows;
    [_session stepOut];
    [self waitForStopAfter:shows];
    XCTAssertEqual(_session.selectedThread.frames.count, 1u);
    XCTAssertEqual(_session.selectedFrame.line, 3);

    [_session continueExecution];
    UDRunUntil(_ended, 5);
    XCTAssertTrue(_ended, @"ran to the end; the adapter's terminated ends the session");
    XCTAssertEqual(_session.state, UDDebugSessionStateEnded);
    XCTAssertTrue([_session.consoleText containsString:@"bye\n"]);
    XCTAssertTrue([_session.consoleText containsString:@"Program ended with exit code: 0\n"]);
    XCTAssertTrue([[self commands] containsObject:@"disconnect"]);
    XCTAssertFalse(_session.canStop);
}

- (void)testAnotherThreadsFramesLoadWhenAsked {
    [self launchStoppingOnEntry:YES];
    UDDebugThread *worker = _session.threads.lastObject;
    XCTAssertEqualObjects(worker.name, @"worker");
    XCTAssertNil(worker.frames);
    [_session loadFramesOfThread:worker];
    UDRunUntil(worker.frames, 5);
    XCTAssertEqualObjects(worker.frames.firstObject.name, @"idle");
    [_session selectFrame:worker.frames.firstObject];
    XCTAssertEqual(_session.selectedThread, worker);
    XCTAssertEqual(_store.instructionPointerLine, 1);
}

- (void)testBreakpointsChangedWhileItRunsAreSentAgain {
    [_store addBreakpointAtLine:3 inFile:_program];
    [self launchStoppingOnEntry:YES];
    [_store addBreakpointAtLine:7 inFile:_program];
    UDRunUntil([[self sentLines] isEqual:(@[ @3, @7 ])], 5);
    XCTAssertEqualObjects([self sentLines], (@[ @3, @7 ]));
    [_store setBreakpoint:[_store breakpointAtLine:3 inFile:_program] enabled:NO];
    UDRunUntil([[self sentLines] isEqual:@[ @7 ]], 5);
    XCTAssertEqualObjects([self sentLines], @[ @7 ], @"a disabled one is not");

    // Verified by the adapter's answer: a line past the end is not.
    UDBreakpoint *past = [_store addBreakpointAtLine:40 inFile:_program];
    UDRunUntil(!past.verified, 5);
    XCTAssertFalse(past.verified);
    XCTAssertEqualObjects(past.message, @"The line is not in the program.");

    // An edit moves one: sent again, at its new line.
    UDTextModel *model = [[UDTextModel alloc] initWithText:UDProgram];
    [_store attachTextModel:model toFile:_program];
    [model applyEdits:@[ [[UDTextModelEdit alloc] initWithRange:PTRangeMake(1, 1, 1, 1) text:@"\n"] ]];
    UDRunUntil([[self sentLines] isEqual:(@[ @8, @11 ])], 5);
    XCTAssertEqualObjects([self sentLines], (@[ @8, @11 ]), @"the one past the end kept to the last line");

    // Continuing stops at the next one.
    NSUInteger shows = _shows;
    [_store removeBreakpoint:past];
    [_session continueExecution];
    [self waitForStopAfter:shows];
    XCTAssertEqual(_session.selectedFrame.line, 8);
    XCTAssertEqualObjects(_session.selectedThread.stopReason, @"breakpoint");
}

- (void)testPausing {
    NSMutableString *longer = [NSMutableString string];
    for (NSInteger i = 0; i < 20000; i++) [longer appendFormat:@"line %ld\n", (long)i];
    _program = [UDCodeTestCase temporaryFileNamed:@"long.demo" text:longer];
    [_session launchWithArguments:@{ @"program": _program }];
    UDRunUntil(_session.state == UDDebugSessionStateRunning, 5);
    XCTAssertTrue(_session.canPause);
    XCTAssertFalse(_session.canStep);
    UDRunUntil(NO, 0.1);                    // a few lines on
    [_session pause];
    UDRunUntil(_session.selectedFrame, 5);
    XCTAssertEqualObjects(_session.selectedThread.stopReason, @"pause");
    XCTAssertGreaterThan(_session.selectedFrame.line, 1);
}

- (void)testTheConsoleEvaluates {
    [_store addBreakpointAtLine:3 inFile:_program];
    [self launchStoppingOnEntry:NO];
    NSUInteger before = _session.consoleText.length;
    [_session evaluate:@"text"];
    UDRunUntil([_session.consoleText hasSuffix:@"\"third\"\n"], 5);
    XCTAssertEqualObjects([_session.consoleText substringFromIndex:before], @"text\n\"third\"\n");
    [_session evaluate:@"nope "];
    UDRunUntil([_session.consoleText hasSuffix:@"'nope'\n"], 5);
    XCTAssertTrue([_session.consoleText hasSuffix:@"nope\nerror: use of undeclared identifier 'nope'\n"]);
}

- (void)testStoppingEndsIt {
    [_store addBreakpointAtLine:3 inFile:_program];
    [self launchStoppingOnEntry:NO];
    [_store setBreakpoint:[_store breakpointAtLine:3 inFile:_program] verified:NO message:@"x"];
    [_session stop];
    XCTAssertFalse(_session.canStop, @"once asked");
    UDRunUntil(_ended, 5);
    XCTAssertTrue(_ended);
    XCTAssertEqual(_session.state, UDDebugSessionStateEnded);
    NSDictionary *disconnect = _adapter.requests.lastObject;
    XCTAssertEqualObjects(disconnect[@"command"], @"disconnect");
    XCTAssertEqualObjects(disconnect[@"arguments"][@"terminateDebuggee"], @YES, @"a launched debuggee goes too");
    XCTAssertNil(_store.instructionPointerFile);
    XCTAssertTrue([_store breakpointAtLine:3 inFile:_program].verified, @"no session says otherwise");
    XCTAssertEqual(_session.threads.count, 0u);
}

- (void)testAProgramThatCannotLaunch {
    [_session launchWithArguments:@{ @"program": @"/nonexistent/program.demo" }];
    UDRunUntil(_ended, 5);
    XCTAssertTrue(_ended);
    XCTAssertTrue([_session.consoleText containsString:@"Could not launch: Cannot read the program"]);
}

- (void)testAModeWithoutAnAdapterHasNoSession {
    UDLanguageMode *plain = [[UDLanguageModeRegistry sharedRegistry] modeForIdentifier:@"plaintext"];
    XCTAssertNil(plain.debugAdapterCommand);
    XCTAssertNil([UDDebugSession sessionForLanguageMode:plain breakpoints:_store]);
    XCTAssertEqualObjects([plain debugLaunchArgumentsForFileURL:[NSURL fileURLWithPath:@"/w/a.txt"]],
                          @{ @"program": @"/w/a.txt" });
}

// ---------------------------------------------------------------------------
// MARK: - VS Code's features
// ---------------------------------------------------------------------------

- (void)testConditionsHitCountsAndLogMessagesAreSent {
    [_store setBreakpoint:[_store addBreakpointAtLine:3 inFile:_program] condition:@"line == 99" hitCondition:nil logMessage:nil];
    [_store setBreakpoint:[_store addBreakpointAtLine:4 inFile:_program] condition:nil hitCondition:nil
               logMessage:@"at {line}: {text}"];
    [_store setBreakpoint:[_store addBreakpointAtLine:5 inFile:_program] condition:nil hitCondition:@"2" logMessage:nil];
    [_store setBreakpoint:[_store addBreakpointAtLine:7 inFile:_program] condition:@"text == \"seventh\"" hitCondition:nil
               logMessage:nil];
    [self launchStoppingOnEntry:NO];

    NSArray *sent = [self lastArgumentsOf:@"setBreakpoints"][@"breakpoints"];
    XCTAssertEqualObjects(sent, (@[ @{ @"line": @3, @"condition": @"line == 99" },
                                    @{ @"line": @4, @"logMessage": @"at {line}: {text}" },
                                    @{ @"line": @5, @"hitCondition": @"2" },
                                    @{ @"line": @7, @"condition": @"text == \"seventh\"" } ]));
    XCTAssertEqual(_session.selectedFrame.line, 7, @"3's condition never holds, 4 logs, 5 is hit once");
    XCTAssertTrue([_session.consoleText containsString:@"at 4: \"fourth\"\n"], @"the logpoint's message");
    for (UDBreakpoint *breakpoint in [_store breakpointsInFile:_program]) XCTAssertTrue(breakpoint.verified);

    // An edited condition is sent again.
    [_store setBreakpoint:[_store breakpointAtLine:3 inFile:_program] condition:@"line == 3" hitCondition:nil logMessage:nil];
    UDRunUntil([[self lastArgumentsOf:@"setBreakpoints"][@"breakpoints"][0][@"condition"] isEqual:@"line == 3"], 5);
    XCTAssertEqualObjects([self lastArgumentsOf:@"setBreakpoints"][@"breakpoints"][0][@"condition"], @"line == 3");
}

- (void)testWhatTheAdapterCannotTakeIsNotSentAndMarked {
    _adapter.withheldCapabilities = @[ @"supportsLogPoints", @"supportsHitConditionalBreakpoints" ];
    UDBreakpoint *logpoint = [_store addBreakpointAtLine:4 inFile:_program];
    [_store setBreakpoint:logpoint condition:nil hitCondition:nil logMessage:@"at {line}"];
    UDBreakpoint *counted = [_store addBreakpointAtLine:6 inFile:_program];
    [_store setBreakpoint:counted condition:@"line == 6" hitCondition:@"3" logMessage:nil];
    [self launchStoppingOnEntry:YES];
    UDRunUntil(!logpoint.verified && !counted.verified, 5);
    NSArray *sent = [self lastArgumentsOf:@"setBreakpoints"][@"breakpoints"];
    XCTAssertEqualObjects(sent, (@[ @{ @"line": @4 }, @{ @"line": @6, @"condition": @"line == 6" } ]),
                          @"what it supports, and nothing else");
    XCTAssertFalse(logpoint.verified, @"shown as not bound, as VS Code shows it");
    XCTAssertEqualObjects(logpoint.message, @"Logpoints are not supported by this debugger.");
    XCTAssertEqualObjects(counted.message, @"Hit counts are not supported by this debugger.");
}

- (void)testExceptionFilters {
    _program = [UDCodeTestCase temporaryFileNamed:@"raise.demo" text:@"one\nwarn careful\nthrow boom\nfour\n"];
    [self launchStoppingOnEntry:NO];
    XCTAssertEqualObjects([_store.exceptionFilters valueForKey:@"filter"], (@[ @"throw", @"warn" ]), @"the adapter's");
    NSArray *commands = [self commands];
    XCTAssertLessThan([commands indexOfObject:@"setExceptionBreakpoints"], [commands indexOfObject:@"configurationDone"]);
    XCTAssertEqualObjects([self lastArgumentsOf:@"setExceptionBreakpoints"], @{ @"filters": @[ @"throw" ] }, @"the default");
    XCTAssertEqualObjects(_session.selectedThread.stopReason, @"exception");
    XCTAssertEqualObjects(_session.selectedThread.stopDescription, @"Error: boom");
    XCTAssertEqual(_session.selectedFrame.line, 3);
    XCTAssertTrue([_session.consoleText containsString:@"warning: careful\n"], @"the warning's filter is off");

    [_store setExceptionFilter:@"warn" enabled:YES];
    UDRunUntil([[self lastArgumentsOf:@"setExceptionBreakpoints"][@"filters"] count] == 2, 5);
    XCTAssertEqualObjects([self lastArgumentsOf:@"setExceptionBreakpoints"], (@{ @"filters": @[ @"throw", @"warn" ] }));
}

- (void)testWatchesAreEvaluatedInTheSelectedFrame {
    [_store addWatchExpression:@"text"];
    [_store addWatchExpression:@"nope"];
    [_store addWatchExpression:@"info"];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(watchesEvaluated:)
                                                 name:UDDebugSessionDidEvaluateWatchesNotification object:_session];
    XCTAssertNil(_session.watches, @"not before it stops");
    [self launchStoppingOnEntry:YES];
    UDRunUntil(_watchEvaluations > 0 && _session.watches, 5);
    NSArray<UDDebugVariable *> *watches = _session.watches;
    XCTAssertEqualObjects([watches valueForKey:@"name"], (@[ @"text", @"nope", @"info" ]));
    XCTAssertEqualObjects(watches[0].value, @"\"start\"");
    XCTAssertFalse(watches[0].failed);
    XCTAssertTrue(watches[1].failed);
    XCTAssertEqualObjects(watches[1].value, @"error: use of undeclared identifier 'nope'");
    XCTAssertTrue(watches[2].hasChildren, @"a structured value opens");
    XCTAssertEqualObjects([self lastArgumentsOf:@"evaluate"][@"context"], @"watch");
    XCTAssertEqualObjects([self lastArgumentsOf:@"evaluate"][@"frameId"], @(_session.selectedFrame.frameID));
    [_session loadChildrenOfVariable:watches[2]];
    UDRunUntil(watches[2].children, 5);
    XCTAssertEqualObjects([watches[2].children valueForKey:@"name"], (@[ @"length", @"blank" ]));
    XCTAssertEqualObjects([watches[2].children valueForKey:@"evaluateName"], (@[ @"info.length", @"info.blank" ]));
    XCTAssertGreaterThanOrEqual(_watchEvaluations, 1u);

    // Changed while stopped: evaluated again.
    [_store replaceWatchExpressionAtIndex:1 withExpression:@"line"];
    UDRunUntil([_session.watches[1].value isEqual:@"1"], 5);
    XCTAssertEqualObjects(_session.watches[1].value, @"1");

    // Running: none; stopped again: the new frame's.
    NSUInteger shows = _shows;
    [_session stepOver];
    XCTAssertNil(_session.watches);
    [self waitForStopAfter:shows];
    UDRunUntil([_session.watches[0].value isEqual:@"\"print hello\""], 5);
    XCTAssertEqualObjects(_session.watches[0].value, @"\"print hello\"");
}

- (void)testEvaluatingForAHover {
    [self launchStoppingOnEntry:YES];
    [_session evaluate:@"info.length" context:@"hover" target:self action:@selector(didEvaluate:)];
    UDRunUntil(_evaluated, 5);
    XCTAssertEqualObjects(_evaluated.name, @"info.length");
    XCTAssertEqualObjects(_evaluated.value, @"5");
    XCTAssertEqualObjects(_evaluated.type, @"int");
    NSDictionary *arguments = [self lastArgumentsOf:@"evaluate"];
    XCTAssertEqualObjects(arguments[@"context"], @"hover");
    XCTAssertEqualObjects(arguments[@"frameId"], @(_session.selectedFrame.frameID));
    XCTAssertTrue(_session.client.supportsEvaluateForHovers);

    // An answer that comes after it ran on is dropped.
    _evaluated = nil;
    [_session evaluate:@"text" context:@"hover" target:self action:@selector(didEvaluate:)];
    [_session stepOver];
    UDRunUntil(NO, 0.2);
    XCTAssertNil(_evaluated);
}

- (void)testSettingAVariable {
    [self launchStoppingOnEntry:YES];
    UDRunUntil(_session.scopes, 5);
    UDDebugVariable *locals = _session.scopes.firstObject;
    [_session loadChildrenOfVariable:locals];
    UDRunUntil(locals.children, 5);
    UDDebugVariable *text = locals.children[1];
    XCTAssertTrue(_session.canSetVariables);
    XCTAssertTrue([_session canSetVariable:text]);
    XCTAssertFalse([_session canSetVariable:locals], @"a scope is not a variable");
    [_store addWatchExpression:@"text"];
    UDRunUntil([_session.watches.firstObject.value isEqual:@"\"start\""], 5);

    [_session setValue:@"\"changed\"" ofVariable:text];
    UDRunUntil([text.value isEqual:@"\"changed\""], 5);
    XCTAssertEqualObjects(text.value, @"\"changed\"");
    XCTAssertEqualObjects([self lastArgumentsOf:@"setVariable"],
                          (@{ @"variablesReference": @(locals.variablesReference), @"name": @"text", @"value": @"\"changed\"" }));
    UDRunUntil([_session.watches.firstObject.value isEqual:@"\"changed\""], 5);
    XCTAssertEqualObjects(_session.watches.firstObject.value, @"\"changed\"", @"the watches again");

    [_session setValue:@"\"not a number\"" ofVariable:locals.children[0]];
    UDRunUntil([_session.consoleText containsString:@"Not a value for line"], 5);
    XCTAssertTrue([_session.consoleText containsString:@"Not a value for line (int): \"not a number\"\n"]);
}

- (void)testRunToCursor {
    UDBreakpoint *logpoint = [_store addBreakpointAtLine:5 inFile:_program];
    [_store setBreakpoint:logpoint condition:nil hitCondition:nil logMessage:@"five"];
    [self launchStoppingOnEntry:YES];
    NSUInteger shows = _shows;
    [_session runToLine:5 inFile:_program];
    [self waitForStopAfter:shows];
    XCTAssertEqual(_session.selectedFrame.line, 5, @"a breakpoint for once, where only a logpoint stood");
    // The last breakpoints sent before it continued.
    NSArray *sentDuring = nil;
    for (NSDictionary *request in _adapter.requests) {
        if ([request[@"command"] isEqual:@"continue"]) break;
        if ([request[@"command"] isEqual:@"setBreakpoints"]) sentDuring = request[@"arguments"][@"breakpoints"];
    }
    XCTAssertEqualObjects(sentDuring, (@[ @{ @"line": @5 } ]), @"set before it continued");
    NSArray *restored = @[ @{ @"line": @5, @"logMessage": @"five" } ];
    UDRunUntil([[self lastArgumentsOf:@"setBreakpoints"][@"breakpoints"] isEqual:restored], 5);
    XCTAssertEqualObjects([self lastArgumentsOf:@"setBreakpoints"][@"breakpoints"], (@[ @{ @"line": @5, @"logMessage": @"five" } ]),
                          @"gone at the stop");
    XCTAssertTrue(logpoint.verified);

    // Where a breakpoint stops anyway: just continued.
    [_store addBreakpointAtLine:8 inFile:_program];
    UDRunUntil([[self lastArgumentsOf:@"setBreakpoints"][@"breakpoints"] count] == 2, 5);
    NSUInteger requests = _adapter.requests.count;
    shows = _shows;
    [_session runToLine:8 inFile:_program];
    [self waitForStopAfter:shows];
    XCTAssertEqual(_session.selectedFrame.line, 8);
    XCTAssertEqualObjects(_adapter.requests[requests][@"command"], @"continue");
}

- (void)testJumpToCursor {
    [self launchStoppingOnEntry:YES];
    XCTAssertTrue(_session.canJump);
    NSUInteger shows = _shows;
    [_session jumpToLine:4 inFile:_program];
    [self waitForStopAfter:shows];
    XCTAssertEqual(_session.selectedFrame.line, 4);
    XCTAssertEqualObjects(_session.selectedThread.stopReason, @"goto");
    XCTAssertEqualObjects([self lastArgumentsOf:@"goto"], (@{ @"threadId": @1, @"targetId": @4 }));
    XCTAssertFalse([_session.consoleText containsString:@"hello"], @"what was between did not run");
}

- (void)testSteppingBack {
    [_store addBreakpointAtLine:2 inFile:_program];
    [_store addBreakpointAtLine:4 inFile:_program];
    [self launchStoppingOnEntry:NO];
    NSUInteger shows = _shows;
    [_session continueExecution];
    [self waitForStopAfter:shows];
    XCTAssertEqual(_session.selectedFrame.line, 4);
    XCTAssertTrue(_session.canStepBack);
    shows = _shows;
    [_session stepBack];
    [self waitForStopAfter:shows];
    XCTAssertEqual(_session.selectedFrame.line, 3);
    shows = _shows;
    [_session reverseContinue];
    [self waitForStopAfter:shows];
    XCTAssertEqual(_session.selectedFrame.line, 2, @"back to the breakpoint before");
}

- (void)testNoSteppingBackOrJumpingWithoutTheCapabilities {
    _adapter.withheldCapabilities = @[ @"supportsStepBack", @"supportsGotoTargetsRequest", @"supportsSetVariable" ];
    [self launchStoppingOnEntry:YES];
    XCTAssertTrue(_session.canStep);
    XCTAssertFalse(_session.canStepBack);
    XCTAssertFalse(_session.canJump);
    XCTAssertFalse(_session.canSetVariables);
    UDRunUntil([[self commands] containsObject:@"scopes"], 5);     // what the stop asks for, in
    NSUInteger requests = _adapter.requests.count;
    [_session stepBack];
    [_session jumpToLine:3 inFile:_program];
    UDRunUntil(NO, 0.1);
    XCTAssertEqual(_adapter.requests.count, requests, @"nothing sent");
    XCTAssertEqual(_store.debugSession, _session, @"the store knows the session that runs");
}

@end
