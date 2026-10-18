//
//  UDBreakpointStoreTests.m
//
//  The breakpoints of a workspace's files: a click adds, disables and
//  enables, Toggle Breakpoint adds and removes; an open file's breakpoints
//  follow its edits (and two that meet are one); a closed file's stay where
//  they were; the instruction pointer, placed in an open file and when it
//  opens; and the changes posted. A breakpoint's condition, hit count and
//  log message; every one enabled, disabled or removed at once; the watch
//  expressions; the exception filters; and all of it kept, in a property
//  list and in the user defaults.
//

#import <XCTest/XCTest.h>
#import "UDCodeTestCase.h"
#import <UDCodeKit/UDCodeKit.h>

@interface UDBreakpointStoreTests : UDCodeTestCase
@property (nonatomic, strong) UDBreakpointStore *store;
@property (nonatomic, strong) NSMutableArray<NSString *> *changedFiles;
@property (nonatomic) NSUInteger pointerMoves;
@property (nonatomic) NSUInteger watchChanges;
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

- (void)watchesChanged:(NSNotification *)note {
    _watchChanges++;
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

// ---------------------------------------------------------------------------

- (void)testConditionsHitCountsAndLogMessages {
    UDBreakpoint *breakpoint = [_store addBreakpointAtLine:3 inFile:@"/w/a.script"];
    XCTAssertFalse(breakpoint.conditional);
    XCTAssertFalse(breakpoint.logpoint);
    [_changedFiles removeAllObjects];

    [_store setBreakpoint:breakpoint condition:@"i > 2" hitCondition:@"" logMessage:nil];
    XCTAssertEqualObjects(breakpoint.condition, @"i > 2");
    XCTAssertNil(breakpoint.hitCondition, @"empty is none");
    XCTAssertTrue(breakpoint.conditional);
    XCTAssertFalse(breakpoint.logpoint);
    XCTAssertEqualObjects(_changedFiles, @[ @"/w/a.script" ], @"posted, so it is sent again");
    [_store setBreakpoint:breakpoint condition:@"i > 2" hitCondition:nil logMessage:nil];
    XCTAssertEqual(_changedFiles.count, 1u, @"the same again: nothing posted");

    [_store setBreakpoint:breakpoint condition:nil hitCondition:@"5" logMessage:@"i is {i}"];
    XCTAssertNil(breakpoint.condition);
    XCTAssertEqualObjects(breakpoint.hitCondition, @"5");
    XCTAssertTrue(breakpoint.conditional, @"a hit count is a condition");
    XCTAssertTrue(breakpoint.logpoint);
    XCTAssertEqualObjects(breakpoint.logMessage, @"i is {i}");
}

- (void)testEverythingAtOnce {
    UDBreakpoint *a = [_store addBreakpointAtLine:3 inFile:@"/w/b.script"];
    UDBreakpoint *b = [_store addBreakpointAtLine:1 inFile:@"/w/a.script"];
    UDBreakpoint *c = [_store addBreakpointAtLine:9 inFile:@"/w/a.script"];
    XCTAssertEqualObjects(_store.allBreakpoints, (@[ b, c, a ]), @"by file, then line");
    [_store setBreakpoint:c enabled:NO];
    [_changedFiles removeAllObjects];

    [_store setAllBreakpointsEnabled:NO];
    XCTAssertFalse(a.enabled || b.enabled || c.enabled);
    XCTAssertEqualObjects(_changedFiles, (@[ @"/w/a.script", @"/w/b.script" ]), @"once a file");
    [_store setAllBreakpointsEnabled:YES];
    XCTAssertTrue(a.enabled && b.enabled && c.enabled);

    UDTextModel *model = [[UDTextModel alloc] initWithText:@"1\n2\n3\n4\n5\n6\n7\n8\n9\n"];
    [_store attachTextModel:model toFile:@"/w/a.script"];
    XCTAssertEqual([model decorationsForOwner:UDBreakpointDecorationOwner].count, 2u);
    [_changedFiles removeAllObjects];
    [_store removeAllBreakpoints];
    XCTAssertEqualObjects(_store.allBreakpoints, @[]);
    XCTAssertEqualObjects(_store.files, @[]);
    XCTAssertEqual([model decorationsForOwner:UDBreakpointDecorationOwner].count, 0u, @"their decorations go");
    XCTAssertEqualObjects(_changedFiles, (@[ @"/w/a.script", @"/w/b.script" ]));
}

- (void)testWatchExpressions {
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(watchesChanged:)
                                                 name:UDBreakpointStoreDidChangeWatchExpressionsNotification object:_store];
    [_store addWatchExpression:@" line "];
    [_store addWatchExpression:@"text"];
    [_store addWatchExpression:@"  "];
    XCTAssertEqualObjects(_store.watchExpressions, (@[ @"line", @"text" ]), @"trimmed; an empty one is none");
    XCTAssertEqual(_watchChanges, 2u);
    [_store replaceWatchExpressionAtIndex:0 withExpression:@"info.length"];
    XCTAssertEqualObjects(_store.watchExpressions, (@[ @"info.length", @"text" ]));
    [_store replaceWatchExpressionAtIndex:1 withExpression:@""];
    XCTAssertEqualObjects(_store.watchExpressions, @[ @"info.length" ], @"edited to nothing: removed");
    [_store addWatchExpression:@"line"];
    [_store removeWatchExpressionAtIndex:0];
    XCTAssertEqualObjects(_store.watchExpressions, @[ @"line" ]);
    [_store removeAllWatchExpressions];
    XCTAssertEqualObjects(_store.watchExpressions, @[]);
    XCTAssertEqual(_watchChanges, 7u);
}

- (void)testExceptionFilters {
    _store.exceptionFilters = @[ @{ @"filter": @"all", @"label": @"All Exceptions" },
                                 @{ @"filter": @"uncaught", @"label": @"Uncaught Exceptions", @"default": @YES } ];
    XCTAssertFalse([_store isExceptionFilterEnabled:@"all"], @"as the adapter has it");
    XCTAssertTrue([_store isExceptionFilterEnabled:@"uncaught"]);
    [_store setExceptionFilter:@"all" enabled:YES];
    [_store setExceptionFilter:@"uncaught" enabled:NO];
    XCTAssertTrue([_store isExceptionFilterEnabled:@"all"]);
    XCTAssertFalse([_store isExceptionFilterEnabled:@"uncaught"], @"as chosen");
    _store.exceptionFilters = @[ @{ @"filter": @"uncaught", @"label": @"Uncaught Exceptions", @"default": @YES } ];
    XCTAssertFalse([_store isExceptionFilterEnabled:@"uncaught"], @"the choice is kept when they come again");
}

- (void)testItIsKeptInAPropertyList {
    UDBreakpoint *conditional = [_store addBreakpointAtLine:3 inFile:@"/w/a.script"];
    [_store setBreakpoint:conditional condition:@"line == 3" hitCondition:@">= 2" logMessage:nil];
    UDBreakpoint *logpoint = [_store addBreakpointAtLine:5 inFile:@"/w/b.script"];
    [_store setBreakpoint:logpoint condition:nil hitCondition:nil logMessage:@"at {line}"];
    [_store setBreakpoint:logpoint enabled:NO];
    [_store addWatchExpression:@"text"];
    _store.exceptionFilters = @[ @{ @"filter": @"throw", @"label": @"Errors", @"default": @YES } ];
    [_store setExceptionFilter:@"throw" enabled:NO];

    // As it comes back from a file.
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:[_store propertyList]
                                                              format:NSPropertyListXMLFormat_v1_0 options:0 error:NULL];
    XCTAssertNotNil(data);
    NSDictionary *plist = [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable
                                                                     format:NULL error:NULL];
    UDBreakpointStore *other = [[UDBreakpointStore alloc] init];
    [other addBreakpointAtLine:9 inFile:@"/w/c.script"];
    [other restorePropertyList:plist];
    XCTAssertEqualObjects(other.files, (@[ @"/w/a.script", @"/w/b.script" ]), @"in place of what it had");
    UDBreakpoint *a = [other breakpointAtLine:3 inFile:@"/w/a.script"], *b = [other breakpointAtLine:5 inFile:@"/w/b.script"];
    XCTAssertEqualObjects(a.condition, @"line == 3");
    XCTAssertEqualObjects(a.hitCondition, @">= 2");
    XCTAssertTrue(a.enabled);
    XCTAssertEqualObjects(b.logMessage, @"at {line}");
    XCTAssertFalse(b.enabled);
    XCTAssertEqualObjects(other.watchExpressions, @[ @"text" ]);
    XCTAssertEqualObjects([other.exceptionFilters valueForKey:@"filter"], @[ @"throw" ]);
    XCTAssertFalse([other isExceptionFilterEnabled:@"throw"]);
    XCTAssertEqualObjects([other propertyList], plist);
}

- (void)testItIsKeptInTheUserDefaults {
    NSString *key = @"UDBreakpointStoreTests Autosave";
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:key];
    _store.autosaveName = key;
    [_store addBreakpointAtLine:4 inFile:@"/w/a.script"];
    [_store addWatchExpression:@"line"];
    UDRunUntil([[NSUserDefaults standardUserDefaults] dictionaryForKey:key], 2);

    UDBreakpointStore *later = [[UDBreakpointStore alloc] init];
    later.autosaveName = key;
    XCTAssertNotNil([later breakpointAtLine:4 inFile:@"/w/a.script"], @"restored when the name is set");
    XCTAssertEqualObjects(later.watchExpressions, @[ @"line" ]);
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:key];
}

@end
