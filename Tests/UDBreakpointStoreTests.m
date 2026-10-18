//
//  UDBreakpointStoreTests.m
//
//  The breakpoints of a workspace's files: a click adds, disables and
//  enables, Toggle Breakpoint adds and removes; an open file's breakpoints
//  follow its edits (and two that meet are one); a closed file's stay where
//  they were; the instruction pointer, placed in an open file and when it
//  opens; and the changes posted.
//

#import <XCTest/XCTest.h>
#import "UDCodeTestCase.h"
#import <UDCodeKit/UDCodeKit.h>

@interface UDBreakpointStoreTests : UDCodeTestCase
@property (nonatomic, strong) UDBreakpointStore *store;
@property (nonatomic, strong) NSMutableArray<NSString *> *changedFiles;
@property (nonatomic) NSUInteger pointerMoves;
@end

@implementation UDBreakpointStoreTests

- (void)setUp {
    [super setUp];
    _store = [[UDBreakpointStore alloc] init];
    _changedFiles = [NSMutableArray array];
    _pointerMoves = 0;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(breakpointsChanged:)
                                                 name:UDBreakpointStoreDidChangeNotification object:_store];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(pointerMoved:)
                                                 name:UDBreakpointStoreDidMoveInstructionPointerNotification object:_store];
}

- (void)tearDown {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super tearDown];
}

- (void)breakpointsChanged:(NSNotification *)note {
    [_changedFiles addObject:note.userInfo[UDBreakpointStoreFileKey]];
}

- (void)pointerMoved:(NSNotification *)note {
    _pointerMoves++;
}

- (NSArray<NSNumber *> *)linesIn:(NSString *)path {
    return [[_store breakpointsInFile:path] valueForKey:@"line"];
}

- (void)testClickingAddsDisablesAndEnables {
    [_store clickBreakpointAtLine:4 inFile:@"/w/a.script"];
    UDBreakpoint *breakpoint = [_store breakpointAtLine:4 inFile:@"/w/a.script"];
    XCTAssertNotNil(breakpoint);
    XCTAssertTrue(breakpoint.enabled);
    XCTAssertTrue(breakpoint.verified, @"nothing says otherwise");
    XCTAssertEqualObjects(_changedFiles, @[ @"/w/a.script" ]);

    [_store clickBreakpointAtLine:4 inFile:@"/w/a.script"];
    XCTAssertFalse(breakpoint.enabled, @"a second click disables it");
    [_store clickBreakpointAtLine:4 inFile:@"/w/./a.script"];
    XCTAssertTrue(breakpoint.enabled, @"a third enables it; the path is standardized");
    XCTAssertEqual([_store breakpointsInFile:@"/w/a.script"].count, 1u);

    [_store clickBreakpointAtLine:2 inFile:@"/w/a.script"];
    [_store clickBreakpointAtLine:9 inFile:@"/w/b.script"];
    XCTAssertEqualObjects([self linesIn:@"/w/a.script"], (@[ @2, @4 ]), @"by line");
    XCTAssertEqualObjects(_store.files, (@[ @"/w/a.script", @"/w/b.script" ]));
    XCTAssertEqual(_changedFiles.count, 5u);
}

- (void)testToggleAddsAndRemoves {
    [_store toggleBreakpointAtLine:3 inFile:@"/w/a.script"];
    XCTAssertNotNil([_store breakpointAtLine:3 inFile:@"/w/a.script"]);
    [_store setBreakpoint:[_store breakpointAtLine:3 inFile:@"/w/a.script"] enabled:NO];
    [_store toggleBreakpointAtLine:3 inFile:@"/w/a.script"];
    XCTAssertNil([_store breakpointAtLine:3 inFile:@"/w/a.script"], @"removed, enabled or not");
    XCTAssertEqualObjects(_store.files, @[]);
}

- (void)testAnOpenFilesBreakpointsFollowItsEdits {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"a\nb\nc\nd\ne\n"];
    [_store addBreakpointAtLine:3 inFile:@"/w/a.script"];
    [_store addBreakpointAtLine:5 inFile:@"/w/a.script"];
    [_store attachTextModel:model toFile:@"/w/a.script"];
    XCTAssertEqual([model decorationsForOwner:UDBreakpointDecorationOwner].count, 2u, @"a decoration each");
    [_changedFiles removeAllObjects];

    // Two lines above: both move down.
    [model applyEdits:@[ [[UDTextModelEdit alloc] initWithRange:PTRangeMake(1, 1, 1, 1) text:@"x\ny\n"] ]];
    XCTAssertEqualObjects([self linesIn:@"/w/a.script"], (@[ @5, @7 ]));
    XCTAssertEqualObjects(_changedFiles, @[ @"/w/a.script" ], @"posted");

    // Typing at the end of a breakpoint's line leaves it; a Return at its start pushes it down.
    [_changedFiles removeAllObjects];
    [model applyEdits:@[ [[UDTextModelEdit alloc] initWithRange:PTRangeMake(5, 2, 5, 2) text:@"zz"] ]];
    XCTAssertEqualObjects([self linesIn:@"/w/a.script"], (@[ @5, @7 ]));
    XCTAssertEqual(_changedFiles.count, 0u, @"nothing moved, nothing posted");
    [model applyEdits:@[ [[UDTextModelEdit alloc] initWithRange:PTRangeMake(5, 1, 5, 1) text:@"\n"] ]];
    XCTAssertEqualObjects([self linesIn:@"/w/a.script"], (@[ @6, @8 ]));

    // The lines between deleted, and the breakpoints' own: they meet, and are one.
    [model applyEdits:@[ [[UDTextModelEdit alloc] initWithRange:PTRangeMake(6, 1, 8, 1) text:@""] ]];
    XCTAssertEqual([_store breakpointsInFile:@"/w/a.script"].count, 1u);
    XCTAssertEqual([model decorationsForOwner:UDBreakpointDecorationOwner].count, 1u);

    // Removing one removes its decoration.
    [_store removeBreakpoint:[_store breakpointsInFile:@"/w/a.script"].firstObject];
    XCTAssertEqual([model decorationsForOwner:UDBreakpointDecorationOwner].count, 0u);
}

- (void)testAFileNotOpenKeepsItsLines {
    [_store addBreakpointAtLine:3 inFile:@"/w/a.script"];
    UDTextModel *other = [[UDTextModel alloc] initWithText:@"1\n2\n3\n"];
    [_store attachTextModel:other toFile:@"/w/b.script"];
    [other applyEdits:@[ [[UDTextModelEdit alloc] initWithRange:PTRangeMake(1, 1, 1, 1) text:@"\n\n"] ]];
    XCTAssertEqualObjects([self linesIn:@"/w/a.script"], @[ @3 ]);
    XCTAssertEqual([other decorationsForOwner:UDBreakpointDecorationOwner].count, 0u);
}

- (void)testTheInstructionPointer {
    UDTextModel *model = [[UDTextModel alloc] initWithText:@"a\nb\nc\n"];
    [_store setInstructionPointerFile:@"/w/a.script" line:2];
    XCTAssertEqual(_pointerMoves, 1u);
    XCTAssertEqualObjects(_store.instructionPointerFile, @"/w/a.script");
    XCTAssertEqual(_store.instructionPointerLine, 2);

    // The file opens: the pointer shows in it, and follows its edits.
    [_store attachTextModel:model toFile:@"/w/a.script"];
    XCTAssertEqual([model decorationsForOwner:UDInstructionPointerDecorationOwner].count, 1u);
    XCTAssertEqual(_pointerMoves, 2u, @"its file opening is told");
    [model applyEdits:@[ [[UDTextModelEdit alloc] initWithRange:PTRangeMake(1, 1, 1, 1) text:@"\n"] ]];
    XCTAssertEqual(_store.instructionPointerLine, 3);

    [_store setInstructionPointerFile:nil line:0];
    XCTAssertNil(_store.instructionPointerFile);
    XCTAssertEqual([model decorationsForOwner:UDInstructionPointerDecorationOwner].count, 0u);
    XCTAssertEqual(_pointerMoves, 3u);
}

- (void)testVerification {
    UDBreakpoint *breakpoint = [_store addBreakpointAtLine:3 inFile:@"/w/a.script"];
    [_changedFiles removeAllObjects];
    [_store setBreakpoint:breakpoint verified:NO message:@"No code at this line."];
    XCTAssertFalse(breakpoint.verified);
    XCTAssertEqualObjects(breakpoint.message, @"No code at this line.");
    XCTAssertEqual(_changedFiles.count, 1u);
    [_store setBreakpoint:breakpoint verified:NO message:@"No code at this line."];
    XCTAssertEqual(_changedFiles.count, 1u, @"the same again: nothing posted");
    [_store resetVerification];
    XCTAssertTrue(breakpoint.verified);
    XCTAssertNil(breakpoint.message);
}

@end
