//
//  UDDebugSessionTests.m
//
//  The debug session over the demo adapter, in this process: starting it
//  (initialize, launch, the enabled breakpoints per file, configurationDone),
//  a stop (threads, the stopped thread's frames, the top frame selected and
//  shown, the instruction pointer), scopes and variables loaded when asked,
//  stepping, continuing to the end, pausing, the breakpoints changed or
//  moved while it runs sent again, the console, and stopping it.
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
    XCTAssertEqualObjects([commands subarrayWithRange:NSMakeRange(0, 4)],
                          (@[ @"initialize", @"launch", @"setBreakpoints", @"configurationDone" ]));
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

@end
