//
//  UDDebuggerWindowTests.m
//
//  The debugger in the workspace window, driven through its own views: the
//  XIBs (the debug navigator, the debug bar, the debug area); breakpoints
//  set, disabled and removed with clicks in the gutter, and drawn there;
//  Debug > Run with the demo adapter (UDCode itself, as a process), its stop
//  shown in the navigator, the bar, the gutter, the variables and the
//  console; stepping from the bar, choosing a frame in the navigator,
//  evaluating in the console, stopping; and a frame in a file that is not
//  open, opened.
//

#import <XCTest/XCTest.h>
#import "UDCodeTestCase.h"
#import <UDCodeKit/UDCodeKit.h>
#import "UDDocument.h"
#import "UDDocumentWindowController.h"
#import "UDDemoDebugAdapter.h"

static NSString * const UDProgram =
    @"start\n"            // 1
    @"print hello\n"      // 2
    @"third\n"            // 3
    @"fourth\n"           // 4
    @"fifth\n"            // 5
    @"print bye\n"        // 6
    @"last\n";            // 7

@interface UDDocumentWindowController (DebuggerTesting)
@property (nonatomic, strong) UDPaneSplitController  *paneSplit;
@property (nonatomic, strong) UDEditorTabsController *editorTabs;
@property (nonatomic, weak) NSSegmentedControl *navigatorControl;
@property (nonatomic, weak) NSTabView          *navigatorTabView;
@property (nonatomic, weak) NSView             *debugNavigatorHost;
@property (nonatomic, weak) NSView             *debugBarHost;
@property (nonatomic, weak) NSView             *debugAreaHost;
@property (nonatomic, strong) UDPaneSplitController *debugSplit;
@property (nonatomic, strong) UDDebugNavigatorViewController *debugNavigator;
@property (nonatomic, strong) UDDebugBarViewController       *debugBar;
@property (nonatomic, strong) UDDebugAreaViewController      *debugArea;
- (IBAction)closeEditorTab:(id)sender;
- (IBAction)toggleBreakpoint:(id)sender;
- (IBAction)debugStepOver:(id)sender;
@end

@interface UDDebuggerWindowTests : UDCodeTestCase
@property (nonatomic, strong) UDWorkspace *workspace;
@property (nonatomic, strong) UDDocumentWindowController *controller;
@property (nonatomic, copy) NSString *program;
@end

@implementation UDDebuggerWindowTests

- (void)forgetPanes {
    for (NSString *name in @[ @"UDCode Workspace", @"UDCode Debug Area", @"UDCodeKit Debug Area" ]) {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:[@"UDPaneSplit " stringByAppendingString:name]];
    }
}

- (void)setUp {
    [super setUp];
    [self forgetPanes];
    _program = [UDCodeTestCase temporaryFileNamed:@"debugged.demo" text:UDProgram];
    _workspace = [[UDWorkspace alloc] init];
    [_workspace makeWindowControllers];
    _controller = (UDDocumentWindowController *)_workspace.windowControllers.firstObject;
    [_controller.window setFrame:NSMakeRect(0, 0, 1200, 760) display:NO];
    [_controller showWindow:nil];
    _controller.debugAdapterCommand = @[ [UDCodeTestCase udcodeExecutablePath], UDDemoDebugAdapterOption ];
    [_controller openURLInNewTab:[NSURL fileURLWithPath:_program]];
}

- (void)tearDown {
    [_controller.debugSession stop];
    UDRunUntil(!_controller.debugSession || _controller.debugSession.state == UDDebugSessionStateEnded, 5);
    [_controller close];
    [_workspace close];
    [self forgetPanes];
    [super tearDown];
}

- (UDCodeEditorViewController *)editor {
    UDEditorTabsController *tabs = _controller.editorTabs;
    return (UDCodeEditorViewController *)[tabs viewControllerForItem:tabs.selectedItem];
}

- (UDLineNumberGutterView *)gutter {
    return [[self editor] valueForKey:@"lineNumberGutterView"];
}

/// The middle of line @a line's number, in the window.
- (NSPoint)pointOfLine:(NSInteger)line {
    UDDiagnosticTextView *textView = [self editor].textView;
    NSLayoutManager *lm = textView.layoutManager;
    [lm ensureLayoutForTextContainer:textView.textContainer];
    UDTextModel *model = [(UDTextModelTextStorage *)textView.textStorage textModel];
    NSUInteger offset = (NSUInteger)[model getOffsetAt:line column:1];
    NSUInteger glyph = [lm glyphRangeForCharacterRange:NSMakeRange(offset, 1) actualCharacterRange:NULL].location;
    NSRect frag = [lm lineFragmentRectForGlyphAtIndex:glyph effectiveRange:NULL];
    NSPoint inText = NSMakePoint(0, NSMidY(frag) + textView.textContainerOrigin.y);
    NSPoint inGutter = [[self gutter] convertPoint:[textView convertPoint:inText toView:nil] fromView:nil];
    return [[self gutter] convertPoint:NSMakePoint(12, inGutter.y) toView:nil];
}

- (void)clickGutterAt:(NSPoint)down releasingAt:(NSPoint)up {
    NSWindow *window = _controller.window;
    NSEvent *press = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:down modifierFlags:0 timestamp:0
                                    windowNumber:window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
    NSEvent *release = [NSEvent mouseEventWithType:NSEventTypeLeftMouseUp location:up modifierFlags:0 timestamp:0
                                      windowNumber:window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:0];
    [[self gutter] mouseDown:press];
    [[self gutter] mouseUp:release];
}

- (void)clickLine:(NSInteger)line {
    NSPoint point = [self pointOfLine:line];
    [self clickGutterAt:point releasingAt:point];
}

/// The colour the gutter draws at line @a line, left of its number.
- (NSColor *)gutterColorAtLine:(NSInteger)line {
    UDLineNumberGutterView *gutter = [self gutter];
    NSPoint inGutter = [gutter convertPoint:[self pointOfLine:line] fromView:nil];
    [gutter display];
    NSBitmapImageRep *bitmap = [gutter bitmapImageRepForCachingDisplayInRect:gutter.bounds];
    [gutter cacheDisplayInRect:gutter.bounds toBitmapImageRep:bitmap];
    NSInteger y = gutter.isFlipped ? (NSInteger)inGutter.y : (NSInteger)(NSHeight(gutter.bounds) - inGutter.y);
    y = (NSInteger)((CGFloat)y * (CGFloat)bitmap.pixelsHigh / NSHeight(gutter.bounds));
    NSInteger x = (NSInteger)(12.0 * (CGFloat)bitmap.pixelsWide / NSWidth(gutter.bounds));
    return [[bitmap colorAtX:x y:y] colorUsingColorSpace:[NSColorSpace genericRGBColorSpace]];
}

- (BOOL)isBlue:(NSColor *)color {
    return color.blueComponent > color.redComponent + 0.3;
}

- (NSString *)textOfRow:(NSInteger)row in:(NSOutlineView *)outline column:(NSString *)identifier {
    NSTableColumn *column = [outline tableColumnWithIdentifier:identifier];
    return [outline.dataSource outlineView:outline objectValueForTableColumn:column byItem:[outline itemAtRow:row]];
}

/// The row of the variable named @a name, -1 when none shows.
- (NSInteger)rowOfVariable:(NSString *)name {
    NSOutlineView *outline = _controller.debugArea.variablesView;
    for (NSInteger row = 0; row < outline.numberOfRows; row++) {
        if ([[self textOfRow:row in:outline column:@"name"] isEqualToString:name]) return row;
    }
    return -1;
}

- (void)runToTheBreakpointAtLine:(NSInteger)line {
    [self clickLine:line];
    [_controller startDebugging:nil];
    UDRunUntil(_controller.debugSession.state == UDDebugSessionStateStopped && _controller.debugSession.selectedFrame, 20);
    XCTAssertEqual(_controller.debugSession.state, UDDebugSessionStateStopped);
}

- (void)waitForStopAtLine:(NSInteger)line {
    UDDebugSession *session = _controller.debugSession;
    UDRunUntil(session.state == UDDebugSessionStateStopped && session.selectedFrame.line == line, 10);
    XCTAssertEqual(session.selectedFrame.line, line);
}

// ---------------------------------------------------------------------------

- (void)testTheDebuggerLoadsFromItsXIBs {
    XCTAssertEqual(_controller.debugNavigatorHost.subviews.count, 1u);
    XCTAssertEqual(_controller.debugBarHost.subviews.count, 1u);
    XCTAssertEqual(_controller.debugAreaHost.subviews.count, 1u);
    XCTAssertNotNil(_controller.debugSplit.splitView);
    XCTAssertEqual(_controller.navigatorControl.segmentCount, 3);
    UDDebugBarViewController *bar = _controller.debugBar;
    for (NSString *outlet in @[ @"continueButton", @"stepOverButton", @"stepIntoButton", @"stepOutButton", @"stopButton", @"statusLabel" ]) {
        XCTAssertNotNil([bar valueForKey:outlet], @"%@ is connected in UDDebugBar.xib", outlet);
    }
    for (NSString *outlet in @[ @"variablesView", @"consoleView", @"evaluateField", @"paneSplit" ]) {
        XCTAssertNotNil([_controller.debugArea valueForKey:outlet], @"%@ is connected in UDDebugArea.xib", outlet);
    }
    XCTAssertNotNil(_controller.debugNavigator.outlineView);
    XCTAssertFalse([_controller.debugSplit isPaneVisible:1], @"no debug area before debugging");
    XCTAssertFalse([bar.continueButton isEnabled], @"nothing to do without a session");
    XCTAssertFalse([bar.stopButton isEnabled]);
    XCTAssertEqualWithAccuracy(NSWidth([(NSView *)_controller.debugArea.paneSplit.splitView.subviews[0] frame]), 300, 1,
                               @"the variables keep their width");

    [_controller toggleDebugArea:nil];
    XCTAssertTrue([_controller.debugSplit isPaneVisible:1]);
    XCTAssertEqualWithAccuracy(NSHeight([(NSView *)_controller.debugSplit.splitView.subviews[1] frame]), 220, 1);
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"" action:@selector(toggleDebugArea:) keyEquivalent:@""];
    [_controller validateMenuItem:item];
    XCTAssertEqualObjects(item.title, @"Hide Debug Area");
}

- (void)testTheGutterSetsDisablesAndRemovesBreakpoints {
    UDBreakpointStore *store = _controller.breakpoints;
    [self clickLine:3];
    UDBreakpoint *breakpoint = [store breakpointAtLine:3 inFile:_program];
    XCTAssertNotNil(breakpoint, @"a click on a line number sets one");
    XCTAssertTrue(breakpoint.enabled);
    XCTAssertTrue([self isBlue:[self gutterColorAtLine:3]], @"drawn blue");
    XCTAssertFalse([self isBlue:[self gutterColorAtLine:2]]);

    [self clickLine:3];
    XCTAssertFalse(breakpoint.enabled, @"a second click disables it");
    NSColor *pale = [self gutterColorAtLine:3];
    XCTAssertTrue(pale.blueComponent > pale.redComponent, @"pale blue: %@", pale);
    [self clickLine:3];
    XCTAssertTrue(breakpoint.enabled, @"a third enables it");

    // Dragged off the gutter and let go: gone.
    NSPoint off = NSMakePoint(NSMidX([(NSView *)_controller.window.contentView bounds]), [self pointOfLine:3].y);
    [self clickGutterAt:[self pointOfLine:3] releasingAt:off];
    XCTAssertNil([store breakpointAtLine:3 inFile:_program]);

    // Debug > Toggle Breakpoint, at the caret's line.
    UDDiagnosticTextView *textView = [self editor].textView;
    textView.selectedRange = NSMakeRange([UDProgram rangeOfString:@"fourth"].location + 2, 0);
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"" action:@selector(toggleBreakpoint:) keyEquivalent:@""];
    XCTAssertTrue([_controller validateMenuItem:item]);
    [_controller toggleBreakpoint:nil];
    XCTAssertNotNil([store breakpointAtLine:4 inFile:_program]);
    [_controller toggleBreakpoint:nil];
    XCTAssertNil([store breakpointAtLine:4 inFile:_program]);

    // Typing above it moves it.
    [self clickLine:5];
    textView.selectedRange = NSMakeRange(0, 0);
    [textView insertText:@"new line\n"];
    XCTAssertNotNil([store breakpointAtLine:6 inFile:_program], @"it follows its line");
    XCTAssertNil([store breakpointAtLine:5 inFile:_program]);
}

- (void)testRunningStopsAtABreakpointAndShowsWhere {
    [self runToTheBreakpointAtLine:3];
    UDDebugSession *session = _controller.debugSession;

    // The panes: the debug area, the debug navigator.
    XCTAssertTrue([_controller.debugSplit isPaneVisible:1]);
    XCTAssertEqual(_controller.navigatorControl.selectedSegment, 2);
    XCTAssertEqualObjects(_controller.navigatorTabView.selectedTabViewItem.identifier, @"debug");

    // The navigator: the threads, the stopped one's frames, its top one chosen.
    NSOutlineView *threads = _controller.debugNavigator.outlineView;
    XCTAssertEqual(threads.numberOfRows, 3, @"Thread 1, its frame, Thread 2");
    XCTAssertEqualObjects([self textOfRow:0 in:threads column:@"frame"], @"Thread 1  main   (breakpoint)");
    XCTAssertEqualObjects([self textOfRow:1 in:threads column:@"frame"], @"0  main   debugged.demo:3");
    XCTAssertEqual(threads.selectedRow, 1);

    // The bar.
    UDDebugBarViewController *bar = _controller.debugBar;
    XCTAssertEqualObjects(bar.continueButton.title, @"▶");
    XCTAssertTrue([bar.stepOverButton isEnabled]);
    XCTAssertTrue([bar.stopButton isEnabled]);
    XCTAssertEqualObjects(bar.statusLabel.stringValue, @"main › main — debugged.demo:3 (breakpoint)");

    // The editor: the instruction pointer in the gutter, the green line.
    XCTAssertEqual([(id<UDLineNumberGutterBreakpointSource>)[self editor] instructionPointerLine], 3);
    UDTextModel *model = [(UDTextModelTextStorage *)[self editor].textView.textStorage textModel];
    XCTAssertEqual([model decorationsForOwner:UDInstructionPointerDecorationOwner].count, 1u);
    NSColor *here = [self gutterColorAtLine:3];
    XCTAssertTrue(here.greenComponent > here.blueComponent, @"green over the blue: %@", here);

    // The variables: Locals open by itself, its variables loaded.
    UDRunUntil([self rowOfVariable:@"text"] >= 0, 5);
    NSOutlineView *variables = _controller.debugArea.variablesView;
    XCTAssertEqualObjects([self textOfRow:0 in:variables column:@"name"], @"Locals");
    XCTAssertEqualObjects([self textOfRow:[self rowOfVariable:@"text"] in:variables column:@"value"], @"\"third\"");
    XCTAssertEqualObjects([self textOfRow:variables.numberOfRows - 1 in:variables column:@"name"], @"Globals",
                          @"Globals, expensive, closed");

    // The console.
    UDRunUntil([_controller.debugArea.consoleView.string containsString:@"hello"], 5);
    XCTAssertTrue([_controller.debugArea.consoleView.string containsString:@"Running debugged.demo\n"]);
    XCTAssertTrue([_controller.debugArea.consoleView.string containsString:@"hello\n"]);

    NSMenuItem *run = [[NSMenuItem alloc] initWithTitle:@"" action:@selector(startDebugging:) keyEquivalent:@""];
    XCTAssertFalse([_controller validateMenuItem:run], @"one session at a time");
    NSMenuItem *pause = [[NSMenuItem alloc] initWithTitle:@"" action:@selector(debugContinueOrPause:) keyEquivalent:@""];
    XCTAssertTrue([_controller validateMenuItem:pause]);
    XCTAssertEqualObjects(pause.title, @"Continue");
    XCTAssertEqualObjects(session.selectedFrame.path, _program);
}

- (void)testSteppingChoosingFramesEvaluatingAndStopping {
    [self runToTheBreakpointAtLine:3];
    UDDebugSession *session = _controller.debugSession;
    UDDebugBarViewController *bar = _controller.debugBar;
    NSOutlineView *variables = _controller.debugArea.variablesView;

    // Open "info"; it stays open at the next stop.
    UDRunUntil([self rowOfVariable:@"info"] >= 0, 5);
    [variables expandItem:[variables itemAtRow:[self rowOfVariable:@"info"]]];
    UDRunUntil([self rowOfVariable:@"length"] >= 0, 5);
    XCTAssertGreaterThanOrEqual([self rowOfVariable:@"length"], 0);

    [bar.stepOverButton performClick:nil];
    [self waitForStopAtLine:4];
    XCTAssertEqualObjects(bar.statusLabel.stringValue, @"main › main — debugged.demo:4 (step)");
    XCTAssertEqual(_controller.breakpoints.instructionPointerLine, 4);
    UDRunUntil([self rowOfVariable:@"length"] >= 0, 5);
    XCTAssertGreaterThanOrEqual([self rowOfVariable:@"length"], 0, @"what was open is open again");
    XCTAssertEqualObjects([self textOfRow:[self rowOfVariable:@"length"] in:variables column:@"value"], @"6");

    // Into: two frames; the caller chosen in the navigator.
    [bar.stepIntoButton performClick:nil];
    [self waitForStopAtLine:5];
    NSOutlineView *threads = _controller.debugNavigator.outlineView;
    UDRunUntil(threads.numberOfRows == 4, 5);
    XCTAssertEqualObjects([self textOfRow:1 in:threads column:@"frame"], @"0  level1   debugged.demo:5");
    XCTAssertEqualObjects([self textOfRow:2 in:threads column:@"frame"], @"1  main   debugged.demo:4");
    [threads selectRowIndexes:[NSIndexSet indexSetWithIndex:2] byExtendingSelection:NO];
    XCTAssertEqualObjects(session.selectedFrame.name, @"main");
    XCTAssertEqual(_controller.breakpoints.instructionPointerLine, 4, @"the pointer goes to the frame chosen");
    UDRunUntil([[self textOfRow:[self rowOfVariable:@"line"] in:variables column:@"value"] isEqual:@"4"], 5);
    XCTAssertEqualObjects([self textOfRow:[self rowOfVariable:@"line"] in:variables column:@"value"], @"4");

    // Over again, from the menu.
    [_controller debugStepOver:nil];
    [self waitForStopAtLine:6];

    // The console's line evaluates in the selected frame.
    NSTextField *field = _controller.debugArea.evaluateField;
    XCTAssertTrue([field isEnabled]);
    field.stringValue = @"text";
    [field sendAction:field.action to:field.target];
    XCTAssertEqualObjects(field.stringValue, @"");
    UDRunUntil([_controller.debugArea.consoleView.string hasSuffix:@"\"print bye\"\n"], 5);
    XCTAssertTrue([_controller.debugArea.consoleView.string hasSuffix:@"text\n\"print bye\"\n"]);

    // Stop.
    [bar.stopButton performClick:nil];
    UDRunUntil(session.state == UDDebugSessionStateEnded, 10);
    XCTAssertEqual(session.state, UDDebugSessionStateEnded);
    XCTAssertEqualObjects(bar.statusLabel.stringValue, @"Finished");
    XCTAssertFalse([bar.stopButton isEnabled]);
    XCTAssertFalse([bar.stepOverButton isEnabled]);
    XCTAssertFalse([field isEnabled]);
    XCTAssertEqual([(id<UDLineNumberGutterBreakpointSource>)[self editor] instructionPointerLine], 0, @"no green line");
    XCTAssertEqual(_controller.debugNavigator.outlineView.numberOfRows, 0);
    NSMenuItem *run = [[NSMenuItem alloc] initWithTitle:@"" action:@selector(startDebugging:) keyEquivalent:@""];
    XCTAssertTrue([_controller validateMenuItem:run], @"it can run again");
}

- (void)testAFrameInAFileNotOpenOpensIt {
    [self runToTheBreakpointAtLine:3];
    UDEditorTabsController *tabs = _controller.editorTabs;
    // The program's tab closed, another file's open.
    [_controller closeEditorTab:nil];
    NSString *other = [UDCodeTestCase temporaryFileNamed:@"other.demo" text:@"other\n"];
    [_controller openURLInNewTab:[NSURL fileURLWithPath:other]];
    XCTAssertEqualObjects([tabs.selectedItem.representedObject displayName], @"other.demo");

    [_controller.debugBar.stepOverButton performClick:nil];
    [self waitForStopAtLine:4];
    UDRunUntil([[tabs.selectedItem.representedObject displayName] isEqual:@"debugged.demo"], 5);
    XCTAssertEqualObjects([tabs.selectedItem.representedObject displayName], @"debugged.demo", @"opened, by the host");
    XCTAssertEqual([(id<UDLineNumberGutterBreakpointSource>)[self editor] instructionPointerLine], 4,
                   @"its gutter shows where the debugger is");
    XCTAssertNotNil([_controller.breakpoints breakpointAtLine:3 inFile:_program], @"and its breakpoints");
}

@end
