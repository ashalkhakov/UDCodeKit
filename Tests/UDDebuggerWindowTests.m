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
//  open, opened. And VS Code's features: the gutter's menus and the
//  breakpoint box (conditions, hit counts, log messages, greyed when the
//  adapter has not got them), conditional breakpoints and logpoints drawn;
//  the breakpoint navigator (enabling, disabling, removing, going to,
//  editing, the exception filters); the watch expressions in the variables
//  view and the variables' menu; the debug hover; Run to Cursor and Jump to
//  Cursor from the text's menu and the Debug menu; and stepping back.
//

#import <XCTest/XCTest.h>
#import "UDCodeTestCase.h"
#import <UDCodeKit/UDCodeKit.h>
#import "UDDocument.h"
#import "UDDocumentWindowController.h"
#import "UDDemoDebugAdapter.h"
#import <objc/runtime.h>

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
@property (nonatomic, weak) NSView             *breakpointNavigatorHost;
@property (nonatomic, strong) UDBreakpointNavigatorViewController *breakpointNavigator;
@property (nonatomic, weak) NSView             *debugBarHost;
@property (nonatomic, weak) NSView             *debugAreaHost;
@property (nonatomic, strong) UDPaneSplitController *debugSplit;
@property (nonatomic, strong) UDDebugNavigatorViewController *debugNavigator;
@property (nonatomic, strong) UDDebugBarViewController       *debugBar;
@property (nonatomic, strong) UDDebugAreaViewController      *debugArea;
- (IBAction)closeEditorTab:(id)sender;
- (IBAction)toggleBreakpoint:(id)sender;
- (IBAction)debugStepOver:(id)sender;
- (IBAction)debugStepBack:(id)sender;
- (IBAction)runToCursor:(id)sender;
- (IBAction)jumpToCursor:(id)sender;
@end

/// The controllers' own, which the tests call as their menus' items do.
@interface UDCodeEditorViewController (DebuggerTesting)
- (IBAction)addConditionalBreakpoint:(id)sender;
- (IBAction)addLogpoint:(id)sender;
@end

@interface UDDebugAreaViewController (DebuggerTesting)
- (IBAction)editClickedCell:(id)sender;
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
    // And the breakpoints and watches an untitled workspace keeps.
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"UDCode Debugger Untitled"];
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

/// The row of Locals' variable named @a name (not a watch's), -1 when none shows.
- (NSInteger)rowOfLocal:(NSString *)name {
    NSOutlineView *outline = _controller.debugArea.variablesView;
    BOOL locals = NO;
    for (NSInteger row = 0; row < outline.numberOfRows; row++) {
        NSString *text = [self textOfRow:row in:outline column:@"name"];
        if (locals && [text isEqualToString:name]) return row;
        locals = locals || [text isEqualToString:@"Locals"];
    }
    return -1;
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
    XCTAssertEqual(_controller.navigatorControl.segmentCount, 4);
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
    // Shown again after being nothing high: the bar on top, the area under it.
    NSRect barFrame = _controller.debugBarHost.frame, areaFrame = _controller.debugAreaHost.frame;
    XCTAssertEqualWithAccuracy(NSMaxY(barFrame), 220, 0.5);
    XCTAssertEqualWithAccuracy(NSHeight(barFrame), 26, 0.5);
    XCTAssertEqualWithAccuracy(NSMaxY(areaFrame), NSMinY(barFrame), 0.5, @"the area does not run under the bar");
    XCTAssertEqualWithAccuracy(NSHeight(areaFrame), 194, 0.5);
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

/// A value that changed since the last stop shows blue, as Xcode's; the
/// filter field leaves the variables whose name (or a loaded child's) has
/// its text, the scopes staying; the debuggee's process is the adapter's.
- (void)testChangedValuesTheFilterAndTheProcess {
    [self runToTheBreakpointAtLine:3];
    UDDebugSession *session = _controller.debugSession;
    UDDebugAreaViewController *area = _controller.debugArea;
    NSOutlineView *variables = area.variablesView;
    XCTAssertNotEqual(session.processID, 0, @"the demo adapter's process event");

    UDRunUntil([self rowOfVariable:@"info"] >= 0, 5);
    [variables expandItem:[variables itemAtRow:[self rowOfVariable:@"info"]]];
    UDRunUntil([self rowOfVariable:@"length"] >= 0, 5);
    UDDebugVariable *length = [area variableOfRow:[self rowOfVariable:@"length"]];
    XCTAssertFalse([area valueChanged:length], @"nothing to tell it from at the first stop");

    [_controller.debugBar.stepOverButton performClick:nil];
    [self waitForStopAtLine:4];
    UDRunUntil([[self textOfRow:[self rowOfVariable:@"length"] in:variables column:@"value"] isEqual:@"6"], 5);
    NSInteger row = [self rowOfVariable:@"length"];
    XCTAssertTrue([area valueChanged:[area variableOfRow:row]], @"5, then 6");
    NSTextFieldCell *cell = [[NSTextFieldCell alloc] initTextCell:@""];
    [variables.delegate outlineView:variables willDisplayCell:cell forTableColumn:[variables tableColumnWithIdentifier:@"value"]
                               item:[variables itemAtRow:row]];
    XCTAssertTrue([self isBlue:[cell.textColor colorUsingColorSpace:[NSColorSpace genericRGBColorSpace]]], @"%@", cell.textColor);
    XCTAssertFalse([area valueChanged:[area variableOfRow:[self rowOfVariable:@"blank"]]], @"false, then false");

    // the filter
    NSInteger all = variables.numberOfRows;
    area.filterField.stringValue = @"LEN";
    [area filterVariables:area.filterField];
    XCTAssertGreaterThanOrEqual([self rowOfVariable:@"length"], 0);
    XCTAssertGreaterThanOrEqual([self rowOfVariable:@"info"], 0, @"its child has the text");
    XCTAssertGreaterThanOrEqual([self rowOfVariable:@"Locals"], 0, @"the scopes stay");
    XCTAssertLessThan(variables.numberOfRows, all);
    area.filterField.stringValue = @"";
    [area filterVariables:area.filterField];
    XCTAssertEqual(variables.numberOfRows, all);
    [self stopDebugging];
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

// ---------------------------------------------------------------------------
// MARK: - VS Code's features
// ---------------------------------------------------------------------------

/// A right click on line @a line's number.
- (NSEvent *)rightClickAtLine:(NSInteger)line {
    return [NSEvent mouseEventWithType:NSEventTypeRightMouseDown location:[self pointOfLine:line] modifierFlags:0 timestamp:0
                          windowNumber:_controller.window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
}

/// A right click on character @a index of the editor's text.
- (NSEvent *)rightClickAtIndex:(NSUInteger)index {
    UDDiagnosticTextView *textView = [self editor].textView;
    NSPoint point = [self pointOfIndex:index];
    return [NSEvent mouseEventWithType:NSEventTypeRightMouseDown location:[textView convertPoint:point toView:nil]
                         modifierFlags:0 timestamp:0 windowNumber:_controller.window.windowNumber context:nil
                           eventNumber:0 clickCount:1 pressure:1];
}

/// The middle of character @a index, in the text view.
- (NSPoint)pointOfIndex:(NSUInteger)index {
    UDDiagnosticTextView *textView = [self editor].textView;
    NSLayoutManager *lm = textView.layoutManager;
    [lm ensureLayoutForTextContainer:textView.textContainer];
    NSRange glyphs = [lm glyphRangeForCharacterRange:NSMakeRange(index, 1) actualCharacterRange:NULL];
    NSRect rect = [lm boundingRectForGlyphRange:glyphs inTextContainer:textView.textContainer];
    return NSMakePoint(NSMidX(rect) + textView.textContainerOrigin.x, NSMidY(rect) + textView.textContainerOrigin.y);
}

/// The mouse moved over the editor's text to character @a index, or off it.
- (void)moveMouseTo:(NSUInteger)index {
    UDDiagnosticTextView *textView = [self editor].textView;
    NSPoint point = index == NSNotFound ? NSMakePoint(NSMaxX(textView.bounds) - 5, NSMaxY(textView.bounds) - 5)
                                        : [self pointOfIndex:index];
    NSEvent *event = [NSEvent mouseEventWithType:NSEventTypeMouseMoved location:[textView convertPoint:point toView:nil]
                                   modifierFlags:0 timestamp:0 windowNumber:_controller.window.windowNumber
                                         context:nil eventNumber:0 clickCount:0 pressure:0];
    [textView mouseMoved:event];
}

- (nullable NSMenuItem *)item:(SEL)action in:(NSMenu *)menu {
    for (NSMenuItem *item in menu.itemArray) if (sel_isEqual(item.action, action)) return item;
    return nil;
}

/// What the menu does with @a item: asks its target, then sends it. NO
/// when it is disabled.
- (BOOL)perform:(NSMenuItem *)item {
    id target = item.target;
    if ([target respondsToSelector:@selector(validateMenuItem:)] && ![target validateMenuItem:item]) return NO;
    [NSApp sendAction:item.action to:target from:item];
    return YES;
}

/// Typed into @a field, which has the keyboard; Return pressed when @a enter.
- (void)type:(NSString *)text into:(NSTextField *)field enter:(BOOL)enter {
    if (!field.currentEditor) [field.window makeFirstResponder:field];
    NSTextView *editor = (NSTextView *)field.currentEditor;
    XCTAssertNotNil(editor, @"%@ is being edited", field);
    [editor selectAll:nil];
    [editor insertText:text];
    if (enter) [editor insertNewline:nil];
}

/// The cell being edited in @a outline: typed into, and Return.
- (void)typeInOutline:(NSOutlineView *)outline text:(NSString *)text {
    NSTextView *editor = (NSTextView *)outline.currentEditor;
    XCTAssertNotNil(editor, @"a cell is being edited");
    [editor selectAll:nil];
    [editor insertText:text];
    [editor insertNewline:nil];
    UDRunUntil(NO, 0.05);                  // what is written is written on the next turn
}

- (NSInteger)gutterKindAtLine:(NSInteger)line {
    id<UDLineNumberGutterBreakpointSource> source = (id<UDLineNumberGutterBreakpointSource>)[self editor];
    return [[source breakpointsInLines:NSMakeRange((NSUInteger)line, 1)][@(line)] integerValue];
}

/// The colour the gutter draws at @a x, @a dy below the middle of line
/// @a line (in the gutter's points).
- (NSColor *)gutterColorAtLine:(NSInteger)line x:(CGFloat)x dy:(CGFloat)dy {
    UDLineNumberGutterView *gutter = [self gutter];
    NSPoint inGutter = [gutter convertPoint:[self pointOfLine:line] fromView:nil];
    [gutter display];
    NSBitmapImageRep *bitmap = [gutter bitmapImageRepForCachingDisplayInRect:gutter.bounds];
    [gutter cacheDisplayInRect:gutter.bounds toBitmapImageRep:bitmap];
    CGFloat y = gutter.isFlipped ? inGutter.y + dy : NSHeight(gutter.bounds) - inGutter.y + dy;
    NSInteger py = (NSInteger)(y * (CGFloat)bitmap.pixelsHigh / NSHeight(gutter.bounds));
    NSInteger px = (NSInteger)(x * (CGFloat)bitmap.pixelsWide / NSWidth(gutter.bounds));
    return [[bitmap colorAtX:px y:py] colorUsingColorSpace:[NSColorSpace genericRGBColorSpace]];
}

- (BOOL)isWhite:(NSColor *)color {
    return color.redComponent > 0.75 && color.greenComponent > 0.75 && color.blueComponent > 0.75;
}

- (void)startDebuggingAndWait {
    [_controller startDebugging:nil];
    UDRunUntil(_controller.debugSession.state == UDDebugSessionStateStopped && _controller.debugSession.selectedFrame, 20);
    XCTAssertEqual(_controller.debugSession.state, UDDebugSessionStateStopped);
}

- (void)stopDebugging {
    [_controller.debugSession stop];
    UDRunUntil(_controller.debugSession.state == UDDebugSessionStateEnded, 10);
}

// ---------------------------------------------------------------------------

- (void)testTheNewViewsLoadFromTheirXIBs {
    XCTAssertEqual(_controller.breakpointNavigatorHost.subviews.count, 1u);
    UDBreakpointNavigatorViewController *navigator = _controller.breakpointNavigator;
    XCTAssertNotNil(navigator.outlineView);
    XCTAssertNotNil(navigator.removeButton);
    XCTAssertNotNil(navigator.outlineView.menu, @"its menu, in UDBreakpointNavigator.xib");
    XCTAssertEqual(navigator.breakpoints, _controller.breakpoints);
    [_controller showBreakpointNavigator:nil];
    XCTAssertEqual(_controller.navigatorControl.selectedSegment, 3);
    XCTAssertEqualObjects(_controller.navigatorTabView.selectedTabViewItem.identifier, @"breakpoints");

    UDDebugAreaViewController *area = _controller.debugArea;
    XCTAssertNotNil(area.addExpressionButton);
    XCTAssertNotNil(area.removeExpressionButton);
    XCTAssertNotNil(area.variablesView.menu);
    XCTAssertTrue([area.addExpressionButton isEnabled], @"watches can be added before a session");
    XCTAssertFalse([area.removeExpressionButton isEnabled]);

    UDDebugBarViewController *bar = _controller.debugBar;
    XCTAssertNotNil(bar.stepBackButton);
    XCTAssertNotNil(bar.reverseContinueButton);
    XCTAssertTrue([bar.stepBackButton isHidden], @"no session, no stepping back");

    UDCodeEditorViewController *editor = [self editor];
    for (NSString *outlet in @[ @"breakpointMenu", @"lineMenu", @"debugTextMenu" ]) {
        XCTAssertNotNil([editor valueForKey:outlet], @"%@ is connected in UDCodeEditorViewController.xib", outlet);
    }
    UDBreakpointEditorViewController *box = [[UDBreakpointEditorViewController alloc] init];
    (void)box.view;
    XCTAssertEqual(box.kindPopUp.numberOfItems, 3);
    XCTAssertNotNil(box.field);
    UDDebugHoverViewController *hover = [[UDDebugHoverViewController alloc] init];
    (void)hover.view;
    XCTAssertNotNil(hover.panel);
    XCTAssertNotNil(hover.titleField);
    XCTAssertNotNil(hover.outlineView);
}

- (void)testTheGutterMenusEditBreakpoints {
    UDCodeEditorViewController *editor = [self editor];
    UDLineNumberGutterView *gutter = [self gutter];
    UDBreakpointStore *store = _controller.breakpoints;

    // A line without one: Add Conditional Breakpoint….
    NSMenu *menu = [gutter menuForEvent:[self rightClickAtLine:3]];
    XCTAssertEqual(menu, [editor valueForKey:@"lineMenu"]);
    XCTAssertTrue([self perform:[self item:@selector(addConditionalBreakpoint:) in:menu]]);
    UDBreakpointEditorViewController *box = editor.breakpointEditor;
    XCTAssertTrue(box.isShown);
    XCTAssertEqual(box.line, 3);
    XCTAssertEqual(box.kind, UDBreakpointEditorCondition);
    XCTAssertNotNil(box.field.currentEditor, @"the keyboard in its field");
    NSRect boxInWindow = [box.view convertRect:box.view.bounds toView:nil];
    XCTAssertLessThan(NSMaxY(boxInWindow), [self pointOfLine:3].y, @"below its line");
    XCTAssertGreaterThan(NSMaxY(boxInWindow), [self pointOfLine:5].y, @"just below");
    XCTAssertNil([store breakpointAtLine:3 inFile:_program], @"not before it is kept");
    [self type:@"line == 3" into:box.field enter:YES];
    UDBreakpoint *breakpoint = [store breakpointAtLine:3 inFile:_program];
    XCTAssertEqualObjects(breakpoint.condition, @"line == 3");
    XCTAssertFalse(box.isShown);
    XCTAssertEqual([self gutterKindAtLine:3], UDGutterBreakpointEnabled | UDGutterBreakpointConditional);
    XCTAssertTrue([self isWhite:[self gutterColorAtLine:3 x:7 dy:-1.75]], @"its '='");
    XCTAssertTrue([self isBlue:[self gutterColorAtLine:3 x:7 dy:0]], @"blue between the bars");

    // Its menu: Edit Breakpoint…, the log message added.
    menu = [gutter menuForEvent:[self rightClickAtLine:3]];
    XCTAssertEqual(menu, [editor valueForKey:@"breakpointMenu"]);
    NSMenuItem *toggle = [self item:@selector(toggleBreakpointEnabled:) in:menu];
    XCTAssertTrue([editor validateMenuItem:toggle]);
    XCTAssertEqualObjects(toggle.title, @"Disable Breakpoint");
    XCTAssertTrue([self perform:[self item:@selector(editBreakpoint:) in:menu]]);
    XCTAssertTrue(box.isShown);
    XCTAssertEqualObjects(box.field.stringValue, @"line == 3");
    [box.kindPopUp selectItemWithTag:UDBreakpointEditorLogMessage];
    [box.kindPopUp sendAction:box.kindPopUp.action to:box.kindPopUp.target];
    XCTAssertEqualObjects(box.field.stringValue, @"", @"the log message, none yet");
    [self type:@"at {line}" into:box.field enter:YES];
    XCTAssertEqualObjects(breakpoint.logMessage, @"at {line}");
    XCTAssertEqualObjects(breakpoint.condition, @"line == 3", @"the condition kept");
    XCTAssertEqual([self gutterKindAtLine:3], UDGutterBreakpointEnabled | UDGutterBreakpointLogpoint);
    XCTAssertTrue([self isWhite:[self gutterColorAtLine:3 x:7.5 dy:0]], @"its diamond");

    // Escape keeps nothing.
    [editor editBreakpointAtLine:3];
    XCTAssertEqual(box.kind, UDBreakpointEditorLogMessage, @"a logpoint opens on its message");
    [self type:@"changed" into:box.field enter:NO];
    NSTextView *fieldEditor = (NSTextView *)box.field.currentEditor;
    [box control:box.field textView:fieldEditor doCommandBySelector:@selector(cancelOperation:)];
    XCTAssertFalse(box.isShown);
    XCTAssertEqualObjects(breakpoint.logMessage, @"at {line}");

    // Disabled, enabled, from its menu.
    menu = [gutter menuForEvent:[self rightClickAtLine:3]];
    XCTAssertTrue([self perform:[self item:@selector(toggleBreakpointEnabled:) in:menu]]);
    XCTAssertFalse(breakpoint.enabled);
    XCTAssertTrue([editor validateMenuItem:toggle]);
    XCTAssertEqualObjects(toggle.title, @"Enable Breakpoint");

    // Add Logpoint… on another line; Delete Breakpoint.
    XCTAssertTrue([self perform:[self item:@selector(addLogpoint:) in:[gutter menuForEvent:[self rightClickAtLine:5]]]]);
    XCTAssertEqual(box.kind, UDBreakpointEditorLogMessage);
    [self type:@"five" into:box.field enter:YES];
    XCTAssertTrue([store breakpointAtLine:5 inFile:_program].logpoint);
    XCTAssertTrue([self perform:[self item:@selector(deleteBreakpoint:) in:[gutter menuForEvent:[self rightClickAtLine:5]]]]);
    XCTAssertNil([store breakpointAtLine:5 inFile:_program]);
}

- (void)testWhatTheAdapterHasNotGotIsGreyed {
    _controller.debugAdapterCommand = @[ [UDCodeTestCase udcodeExecutablePath], UDDemoDebugAdapterOption,
                                         @"--without=supportsLogPoints,supportsHitConditionalBreakpoints,supportsEvaluateForHovers" ];
    UDBreakpointStore *store = _controller.breakpoints;
    UDBreakpoint *logpoint = [store addBreakpointAtLine:2 inFile:_program];
    [store setBreakpoint:logpoint condition:nil hitCondition:nil logMessage:@"two"];
    [self startDebuggingAndWait];
    XCTAssertEqual(_controller.debugSession.selectedFrame.line, 2, @"sent as a breakpoint");
    UDRunUntil(!logpoint.verified, 5);
    XCTAssertFalse(logpoint.verified);
    XCTAssertEqualObjects(logpoint.message, @"Logpoints are not supported by this debugger.");
    XCTAssertEqual([self gutterKindAtLine:2], UDGutterBreakpointUnverified | UDGutterBreakpointLogpoint);

    UDCodeEditorViewController *editor = [self editor];
    [editor editBreakpointAtLine:4];
    UDBreakpointEditorViewController *box = editor.breakpointEditor;
    XCTAssertTrue([box isKindEnabled:UDBreakpointEditorCondition]);
    XCTAssertFalse([box isKindEnabled:UDBreakpointEditorHitCondition], @"greyed, as VS Code warns");
    XCTAssertFalse([box isKindEnabled:UDBreakpointEditorLogMessage]);
    [box control:box.field textView:(NSTextView *)box.field.currentEditor doCommandBySelector:@selector(cancelOperation:)];

    // No hover from the debugger: the language server's is asked, as ever.
    id<UDDebugTextHandler> handler = editor.textView.debugHandler;
    XCTAssertEqual(handler, (id)editor);
    XCTAssertFalse([handler textView:editor.textView showsDebugHoverAtIndex:[UDProgram rangeOfString:@"hello"].location]);
}

- (void)testTheBreakpointNavigator {
    UDBreakpointStore *store = _controller.breakpoints;
    NSString *other = [UDCodeTestCase temporaryFileNamed:@"other.demo" text:@"one\ntwo\nthree\n"];
    UDBreakpoint *three = [store addBreakpointAtLine:3 inFile:_program];
    [store setBreakpoint:[store addBreakpointAtLine:5 inFile:_program] condition:@"line == 5" hitCondition:nil logMessage:nil];
    [store setBreakpoint:[store addBreakpointAtLine:2 inFile:other] condition:nil hitCondition:nil logMessage:@"two"];
    [_controller showBreakpointNavigator:nil];
    UDBreakpointNavigatorViewController *navigator = _controller.breakpointNavigator;
    NSOutlineView *outline = navigator.outlineView;
    XCTAssertEqual(outline.numberOfRows, 5);
    NSArray *titles = @[ @"debugged.demo", @"Line 3", @"Line 5  ·  Condition: line == 5", @"other.demo", @"Line 2  ·  Log: two" ];
    for (NSInteger row = 0; row < 5; row++) {
        XCTAssertEqualObjects([self textOfRow:row in:outline column:@"breakpoint"], titles[(NSUInteger)row]);
    }
    XCTAssertEqual([navigator breakpointOfRow:1], three);
    XCTAssertNil([navigator breakpointOfRow:0], @"a file");

    // Its check box.
    NSTableColumn *enabled = [outline tableColumnWithIdentifier:@"enabled"];
    XCTAssertEqualObjects([outline.dataSource outlineView:outline objectValueForTableColumn:enabled byItem:three], @YES);
    [outline.dataSource outlineView:outline setObjectValue:@NO forTableColumn:enabled byItem:three];
    XCTAssertFalse(three.enabled);
    XCTAssertEqual([self gutterKindAtLine:3], UDGutterBreakpointDisabled, @"the gutter shows it");
    [outline.dataSource outlineView:outline setObjectValue:@YES forTableColumn:enabled byItem:three];
    XCTAssertTrue(three.enabled);

    // Chosen: its line; edited: its editor's box.
    [outline selectRowIndexes:[NSIndexSet indexSetWithIndex:2] byExtendingSelection:NO];
    XCTAssertTrue([navigator.removeButton isEnabled]);
    [navigator showBreakpoint:nil];
    UDTextModel *model = [(UDTextModelTextStorage *)[self editor].textView.textStorage textModel];
    XCTAssertEqual([model getPositionAt:(NSInteger)[self editor].textView.selectedRange.location].line, 5);
    [navigator editBreakpoint:nil];
    XCTAssertTrue([self editor].breakpointEditor.isShown);
    XCTAssertEqual([self editor].breakpointEditor.line, 5);
    XCTAssertEqualObjects([self editor].breakpointEditor.field.stringValue, @"line == 5");
    UDBreakpointEditorViewController *box = [self editor].breakpointEditor;
    [box control:box.field textView:(NSTextView *)box.field.currentEditor doCommandBySelector:@selector(cancelOperation:)];

    // Another file's: opened.
    [outline selectRowIndexes:[NSIndexSet indexSetWithIndex:4] byExtendingSelection:NO];
    [navigator showBreakpoint:nil];
    XCTAssertEqualObjects([_controller.editorTabs.selectedItem.representedObject displayName], @"other.demo");

    // − deletes the selected one.
    [outline selectRowIndexes:[NSIndexSet indexSetWithIndex:4] byExtendingSelection:NO];
    [navigator.removeButton performClick:nil];
    XCTAssertNil([store breakpointAtLine:2 inFile:other]);
    XCTAssertEqual(outline.numberOfRows, 3, @"its file goes with it");

    // Every one at once, from its menu.
    NSMenu *menu = outline.menu;
    XCTAssertTrue([self perform:[self item:@selector(disableAllBreakpoints:) in:menu]]);
    for (UDBreakpoint *breakpoint in store.allBreakpoints) XCTAssertFalse(breakpoint.enabled);
    XCTAssertTrue([self perform:[self item:@selector(enableAllBreakpoints:) in:menu]]);
    for (UDBreakpoint *breakpoint in store.allBreakpoints) XCTAssertTrue(breakpoint.enabled);
    XCTAssertTrue([self perform:[self item:@selector(deleteAllBreakpoints:) in:menu]]);
    XCTAssertEqual(store.allBreakpoints.count, 0u);
    XCTAssertEqual(outline.numberOfRows, 0);
    XCTAssertFalse([self perform:[self item:@selector(deleteAllBreakpoints:) in:menu]], @"nothing left to delete");
}

- (void)testTheExceptionFiltersInTheNavigator {
    NSString *raising = [UDCodeTestCase temporaryFileNamed:@"raising.demo" text:@"start\nwarn careful\nthrow boom\nlast\n"];
    [_controller openURLInNewTab:[NSURL fileURLWithPath:raising]];
    [self startDebuggingAndWait];
    UDDebugSession *session = _controller.debugSession;
    XCTAssertEqual(session.selectedFrame.line, 3, @"Errors is on by default");
    XCTAssertEqualObjects(_controller.debugBar.statusLabel.stringValue, @"main › main — raising.demo:3 (exception: Error: boom)");

    NSOutlineView *outline = _controller.breakpointNavigator.outlineView;
    UDRunUntil(outline.numberOfRows == 2, 5);
    XCTAssertEqualObjects([self textOfRow:0 in:outline column:@"breakpoint"], @"Errors");
    XCTAssertEqualObjects([self textOfRow:1 in:outline column:@"breakpoint"], @"Warnings");
    XCTAssertEqualObjects([self textOfRow:0 in:outline column:@"enabled"], @YES);
    XCTAssertEqualObjects([self textOfRow:1 in:outline column:@"enabled"], @NO);
    XCTAssertEqualObjects([_controller.breakpointNavigator exceptionFilterOfRow:1], @"warn");

    // Warnings on: the next run stops at the warning.
    [outline.dataSource outlineView:outline setObjectValue:@YES forTableColumn:[outline tableColumnWithIdentifier:@"enabled"]
                             byItem:[outline itemAtRow:1]];
    XCTAssertTrue([_controller.breakpoints isExceptionFilterEnabled:@"warn"]);
    [self stopDebugging];
    XCTAssertEqual(outline.numberOfRows, 2, @"kept when the session ends");
    [self startDebuggingAndWait];
    XCTAssertEqual(_controller.debugSession.selectedFrame.line, 2);
    XCTAssertEqualObjects(_controller.debugSession.selectedThread.stopDescription, @"Warning: careful");
}

- (void)testWatchExpressionsInTheVariablesView {
    UDDebugAreaViewController *area = _controller.debugArea;
    NSOutlineView *variables = area.variablesView;
    [_controller toggleDebugArea:nil];

    // Added before running: written in place.
    [area.addExpressionButton performClick:nil];
    XCTAssertEqual(variables.numberOfRows, 1, @"a new row, being written");
    [self typeInOutline:variables text:@"text"];
    XCTAssertEqualObjects(_controller.breakpoints.watchExpressions, @[ @"text" ]);
    XCTAssertEqualObjects([self textOfRow:0 in:variables column:@"name"], @"text");
    XCTAssertEqualObjects([self textOfRow:0 in:variables column:@"value"], @"", @"nothing to evaluate it in yet");

    [self runToTheBreakpointAtLine:3];
    UDRunUntil([[self textOfRow:0 in:variables column:@"value"] isEqual:@"\"third\""], 5);
    XCTAssertEqualObjects([self textOfRow:0 in:variables column:@"value"], @"\"third\"");
    XCTAssertEqual([area watchIndexOfRow:0], 0u);
    XCTAssertEqualObjects([self textOfRow:1 in:variables column:@"name"], @"Locals", @"the scopes under the watches");

    // A structured one opens; it stays open at the next stop.
    [_controller.breakpoints addWatchExpression:@"info"];
    UDRunUntil([[self textOfRow:1 in:variables column:@"value"] isEqual:@"{length=5}"], 5);
    [variables expandItem:[variables itemAtRow:1]];
    UDRunUntil([[self textOfRow:2 in:variables column:@"name"] isEqual:@"length"], 5);
    XCTAssertEqualObjects([self textOfRow:2 in:variables column:@"value"], @"5");
    [_controller.debugBar.stepOverButton performClick:nil];
    [self waitForStopAtLine:4];
    UDRunUntil([[self textOfRow:2 in:variables column:@"value"] isEqual:@"6"], 5);
    XCTAssertEqualObjects([self textOfRow:2 in:variables column:@"value"], @"6", @"info.length at line 4, open again");

    // Edited in place: a double click on it.
    [variables selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    [area editExpression:nil];
    [self typeInOutline:variables text:@"line"];
    XCTAssertEqualObjects(_controller.breakpoints.watchExpressions, (@[ @"line", @"info" ]));
    UDRunUntil([[self textOfRow:0 in:variables column:@"value"] isEqual:@"4"], 5);
    XCTAssertEqualObjects([self textOfRow:0 in:variables column:@"value"], @"4");

    // One that does not evaluate says why.
    [_controller.breakpoints addWatchExpression:@"nope"];
    NSInteger nope = 4;   // line, info, its two children, nope
    UDRunUntil([[self textOfRow:nope in:variables column:@"value"] hasPrefix:@"error:"], 5);
    XCTAssertEqualObjects([self textOfRow:nope in:variables column:@"value"], @"error: use of undeclared identifier 'nope'");
    XCTAssertTrue([area variableOfRow:nope].failed);

    // − removes the selected one.
    [variables selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)nope] byExtendingSelection:NO];
    XCTAssertTrue([area.removeExpressionButton isEnabled]);
    [area.removeExpressionButton performClick:nil];
    XCTAssertEqualObjects(_controller.breakpoints.watchExpressions, (@[ @"line", @"info" ]));

    // The variables' menu: a variable's value and expression copied, watched.
    NSInteger textRow = [self rowOfLocal:@"text"];
    XCTAssertGreaterThan(textRow, 0);
    [variables selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)textRow] byExtendingSelection:NO];
    NSMenu *menu = variables.menu;
    XCTAssertTrue([self perform:[self item:@selector(copyAsExpression:) in:menu]]);
    XCTAssertEqualObjects([[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString], @"text");
    XCTAssertTrue([self perform:[self item:@selector(copyValue:) in:menu]]);
    UDRunUntil([[[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString] isEqual:@"fourth"], 5);
    XCTAssertEqualObjects([[NSPasteboard generalPasteboard] stringForType:NSPasteboardTypeString], @"fourth",
                          @"the adapter's clipboard value: no quotes");
    // (Selected again: GNUstep's table forgets it when the rows reload.)
    [variables selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)[self rowOfLocal:@"text"]] byExtendingSelection:NO];
    XCTAssertFalse([area validateMenuItem:[self item:@selector(editExpression:) in:menu]], @"not a watch");
    XCTAssertTrue([self perform:[self item:@selector(addToWatch:) in:menu]]);
    XCTAssertEqualObjects(_controller.breakpoints.watchExpressions, (@[ @"line", @"info", @"text" ]));

    // Set Value…: the value edited in place.
    textRow = [self rowOfLocal:@"text"];
    [variables selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)textRow] byExtendingSelection:NO];
    XCTAssertTrue([self perform:[self item:@selector(setValue:) in:menu]]);
    [self typeInOutline:variables text:@"\"changed\""];
    UDRunUntil([[self textOfRow:[self rowOfLocal:@"text"] in:variables column:@"value"] isEqual:@"\"changed\""], 5);
    XCTAssertEqualObjects([self textOfRow:[self rowOfLocal:@"text"] in:variables column:@"value"], @"\"changed\"");

    // All of them, gone.
    XCTAssertTrue([self perform:[self item:@selector(removeAllExpressions:) in:menu]]);
    XCTAssertEqualObjects(_controller.breakpoints.watchExpressions, @[]);
    XCTAssertEqualObjects([self textOfRow:0 in:variables column:@"name"], @"Locals");
}

- (void)testTheDebugHover {
    NSString *hovered = [UDCodeTestCase temporaryFileNamed:@"hovered.demo" text:@"start\nprint hello\nshow info.length and text\nlast\n"];
    [_controller openURLInNewTab:[NSURL fileURLWithPath:hovered]];
    [self clickLine:3];
    [self startDebuggingAndWait];
    XCTAssertEqual(_controller.debugSession.selectedFrame.line, 3);
    UDCodeEditorViewController *editor = [self editor];
    UDDiagnosticTextView *textView = editor.textView;
    textView.hoverDelay = 0.05;
    NSString *text = textView.string;

    // "length" of "info.length": the expression up to it.
    [self moveMouseTo:[text rangeOfString:@"length"].location + 2];
    UDRunUntil(editor.debugHover.isShown, 5);
    UDDebugHoverViewController *hover = editor.debugHover;
    XCTAssertTrue(hover.isShown);
    XCTAssertEqualObjects(hover.titleField.stringValue, @"info.length = 25");
    XCTAssertEqual(hover.panel.parentWindow, _controller.window, @"at the text, in its window");
    XCTAssertTrue([hover.outlineView.enclosingScrollView isHidden], @"nothing to open");

    // Off it: gone.
    [self moveMouseTo:NSNotFound];
    XCTAssertFalse(hover.isShown);

    // A structured value: its children, below.
    [self moveMouseTo:[text rangeOfString:@"info"].location + 1];
    UDRunUntil(hover.isShown && hover.outlineView.numberOfRows == 2, 5);
    XCTAssertEqualObjects(hover.titleField.stringValue, @"info = {length=25}");
    XCTAssertEqual(hover.outlineView.numberOfRows, 2);
    XCTAssertFalse([hover.outlineView.enclosingScrollView isHidden]);
    [self moveMouseTo:NSNotFound];

    // What does not evaluate shows nothing.
    [self moveMouseTo:[text rangeOfString:@"and"].location + 1];
    UDRunUntil(NO, 0.3);
    XCTAssertFalse(hover.isShown);
    [self moveMouseTo:NSNotFound];

    // Running: none.
    [self moveMouseTo:[text rangeOfString:@" text"].location + 2];
    UDRunUntil(hover.isShown, 5);
    XCTAssertEqualObjects(hover.titleField.stringValue, @"text = \"show info.length and text\"");
    [_controller.debugBar.stepOverButton performClick:nil];
    XCTAssertFalse(hover.isShown, @"what it showed is gone");
}

- (void)testRunToCursorAndJumpToCursor {
    [self runToTheBreakpointAtLine:1];
    UDCodeEditorViewController *editor = [self editor];
    UDDiagnosticTextView *textView = editor.textView;

    // The text's menu: the debugger's items on top, the caret where it was clicked.
    NSUInteger fifth = [UDProgram rangeOfString:@"fifth"].location;
    NSMenu *menu = [textView menuForEvent:[self rightClickAtIndex:fifth + 1]];
    XCTAssertEqualObjects([menu itemAtIndex:0].title, @"Run to Cursor");
    XCTAssertEqualObjects([menu itemAtIndex:1].title, @"Jump to Cursor");
    XCTAssertEqualObjects([menu itemAtIndex:2].title, @"Add to Watch");
    UDTextModel *model = [(UDTextModelTextStorage *)textView.textStorage textModel];
    XCTAssertEqual([model getPositionAt:(NSInteger)textView.selectedRange.location].line, 5,
                   @"the caret moved to the click (macOS selects the word clicked)");
    XCTAssertTrue([self perform:[menu itemAtIndex:0]]);
    [self waitForStopAtLine:5];
    UDRunUntil([_controller.debugArea.consoleView.string containsString:@"hello"], 5);
    XCTAssertTrue([_controller.debugArea.consoleView.string containsString:@"hello\n"], @"what was before ran");
    XCTAssertEqual(_controller.breakpoints.allBreakpoints.count, 1u, @"no breakpoint left behind");

    // The Debug menu's Jump to Cursor: back to line 2, which is not run.
    textView.selectedRange = NSMakeRange([UDProgram rangeOfString:@"print hello"].location, 0);
    NSMenuItem *jump = [[NSMenuItem alloc] initWithTitle:@"" action:@selector(jumpToCursor:) keyEquivalent:@""];
    XCTAssertTrue([_controller validateMenuItem:jump]);
    [_controller jumpToCursor:nil];
    [self waitForStopAtLine:2];
    XCTAssertEqualObjects(_controller.debugSession.selectedThread.stopReason, @"goto");

    // Refused: the adapter's reason in the console, and still stopped.
    [_controller.debugSession jumpToLine:1 inFile:@"/elsewhere/other.demo"];
    UDRunUntil([_controller.debugArea.consoleView.string containsString:@"can be jumped to"], 5);
    XCTAssertTrue([_controller.debugArea.consoleView.string containsString:@"Only debugged.demo's lines can be jumped to.\n"], @"%@", _controller.debugArea.consoleView.string);
    XCTAssertEqual(_controller.debugSession.state, UDDebugSessionStateStopped);
    XCTAssertTrue(_controller.debugSession.canJump);

    // Add to Watch: the selection.
    textView.selectedRange = [UDProgram rangeOfString:@"hello"];
    menu = [textView menuForEvent:[self rightClickAtIndex:textView.selectedRange.location + 1]];
    XCTAssertEqual(textView.selectedRange.length, 5u, @"a click in the selection keeps it");
    XCTAssertTrue([self perform:[menu itemAtIndex:2]]);
    XCTAssertEqualObjects(_controller.breakpoints.watchExpressions, @[ @"hello" ]);

    // Not debugging: none of it.
    [self stopDebugging];
    menu = [textView menuForEvent:[self rightClickAtIndex:fifth]];
    XCTAssertNil([self item:@selector(runToCursor:) in:menu]);
    NSMenuItem *run = [[NSMenuItem alloc] initWithTitle:@"" action:@selector(runToCursor:) keyEquivalent:@""];
    XCTAssertFalse([_controller validateMenuItem:run]);
}

- (void)testSteppingBack {
    [self runToTheBreakpointAtLine:3];
    UDDebugBarViewController *bar = _controller.debugBar;
    XCTAssertFalse([bar.stepBackButton isHidden], @"the demo adapter steps back");
    XCTAssertTrue([bar.stepBackButton isEnabled]);
    [bar.stepBackButton performClick:nil];
    [self waitForStopAtLine:2];
    NSMenuItem *back = [[NSMenuItem alloc] initWithTitle:@"" action:@selector(debugStepBack:) keyEquivalent:@""];
    XCTAssertTrue([_controller validateMenuItem:back]);
#ifdef __APPLE__
    XCTAssertFalse([back isHidden]);
#endif
    [bar.reverseContinueButton performClick:nil];
    [self waitForStopAtLine:1];
    [self stopDebugging];

    // An adapter that cannot: no buttons, stop where step back was.
    _controller.debugAdapterCommand = @[ [UDCodeTestCase udcodeExecutablePath], UDDemoDebugAdapterOption,
                                         @"--without=supportsStepBack" ];
    [self startDebuggingAndWait];
    XCTAssertTrue([bar.stepBackButton isHidden]);
    XCTAssertTrue([bar.reverseContinueButton isHidden]);
    XCTAssertEqualWithAccuracy(NSMinX(bar.stopButton.frame), NSMinX(bar.stepBackButton.frame), 0.5);
    XCTAssertFalse([_controller validateMenuItem:back]);
#ifdef __APPLE__
    XCTAssertTrue([back isHidden], @"GNUstep's menu items do not hide");
#endif
}

@end
