//
//  UDTerminalTests.m
//  UDCodeTests
//
//  The terminal: what a program writes, read as a terminal reads it (libvterm);
//  keys and pastes sent as a terminal sends them; a program on a pseudo-terminal
//  of its own, its size and its end.
//

#import <XCTest/XCTest.h>
#import "UDCodeTestCase.h"
#import <UDCodeKit/UDCodeKit.h>

@interface UDTerminalTests : UDCodeTestCase <UDTerminalViewDelegate>
@property (nonatomic, strong) NSMutableData *written;
@end

@implementation UDTerminalTests

- (void)setUp {
    [super setUp];
    _written = [NSMutableData data];
}

- (void)terminalView:(UDTerminalView *)view writeData:(NSData *)data {
    [_written appendData:data];
}

- (NSString *)writtenText {
    return [[NSString alloc] initWithData:_written encoding:NSUTF8StringEncoding];
}

- (void)feed:(NSString *)text to:(UDTerminalView *)view {
    [view feedData:[text dataUsingEncoding:NSUTF8StringEncoding]];
}

- (NSEvent *)key:(NSString *)characters bare:(NSString *)bare modifiers:(NSEventModifierFlags)modifiers {
    return [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:modifiers timestamp:0
                        windowNumber:0 context:nil characters:characters charactersIgnoringModifiers:bare
                           isARepeat:NO keyCode:0];
}

/// Text, lines, colours, the cursor, clearing, the lines that scroll off the
/// top, and a full-screen program's screen of its own (vim's, less's).
- (void)testTheScreenIsReadAsATerminalReadsIt {
    UDTerminalView *view = [[UDTerminalView alloc] initWithFrame:NSMakeRect(0, 0, 600, 300)];
    XCTAssertEqual(view.rows, 24u);
    XCTAssertEqual(view.columns, 80u);
    [self feed:@"hello\r\nworld\r\n\x1b[31mred\x1b[0m plain" to:view];
    XCTAssertEqualObjects([view textOfScreenRow:0], @"hello");
    XCTAssertEqualObjects([view textOfScreenRow:1], @"world");
    XCTAssertEqualObjects([view textOfScreenRow:2], @"red plain");
    NSColor *red = [[view foregroundColorAtRow:2 column:0] colorUsingColorSpace:[NSColorSpace genericRGBColorSpace]];
    XCTAssertGreaterThan(red.redComponent, 0.5);
    XCTAssertLessThan(red.greenComponent, 0.3);
    XCTAssertEqual(view.cursorRow, 2u);
    XCTAssertEqual(view.cursorColumn, 9u);

    // a full-screen program's screen, and back to what was there
    [self feed:@"\x1b[?1049h\x1b[2J\x1b[Hfull screen" to:view];
    XCTAssertEqualObjects(view.screenText, @"full screen");
    [self feed:@"\x1b[?1049l" to:view];
    XCTAssertEqualObjects([view textOfScreenRow:0], @"hello");

    // cleared
    [self feed:@"\x1b[2J\x1b[H" to:view];
    XCTAssertEqualObjects(view.screenText, @"");

    // more lines than the screen has: the first kept above it
    NSMutableString *lines = [NSMutableString string];
    for (int i = 1; i <= 30; i++) [lines appendFormat:@"line %d\r\n", i];
    [self feed:lines to:view];
    XCTAssertGreaterThanOrEqual(view.scrollbackCount, 6u);
    XCTAssertEqualObjects([view textOfScreenRow:view.rows - 2], @"line 30");

    // UTF-8, a wide character among them
    [view reset];
    [self feed:@"naïve 日本 ok" to:view];
    XCTAssertEqualObjects([view textOfScreenRow:0], @"naïve 日本 ok");
}

/// A line longer than the terminal is wide, the terminal made narrower: the
/// line wraps again, none of it lost (a pane resized under a shell).
- (void)testALineWrapsAgainWhenTheTerminalNarrows {
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 600, 300)];
    UDTerminalView *view = [[UDTerminalView alloc] initWithFrame:scroll.contentView.bounds];
    scroll.documentView = view;
    NSUInteger wide = view.columns;
    NSMutableString *line = [NSMutableString string];
    while (line.length < wide + 10) [line appendFormat:@"%lu", (unsigned long)line.length % 10];
    [self feed:[line stringByAppendingString:@"\r\nnext"] to:view];
    XCTAssertEqualObjects(view.screenText, ([line stringByAppendingString:@"\nnext"]), @"wrapped once, rejoined");

    [scroll setFrameSize:NSMakeSize(400, 300)];
    XCTAssertLessThan(view.columns, wide, @"narrower");
    XCTAssertEqualObjects(view.screenText, ([line stringByAppendingString:@"\nnext"]), @"wrapped again, none of it lost");
}

/// Keys as a terminal sends them: characters, Return, the arrows, Control;
/// and a paste, in brackets when the program asked for them.
- (void)testKeysAreSentAsATerminalSendsThem {
    UDTerminalView *view = [[UDTerminalView alloc] initWithFrame:NSMakeRect(0, 0, 600, 300)];
    view.delegate = self;
    [view keyDown:[self key:@"a" bare:@"a" modifiers:0]];
    [view keyDown:[self key:@"é" bare:@"e" modifiers:NSEventModifierFlagOption]];
    [view keyDown:[self key:@"\r" bare:@"\r" modifiers:0]];
    unichar up = NSUpArrowFunctionKey;
    NSString *upString = [NSString stringWithCharacters:&up length:1];
    [view keyDown:[self key:upString bare:upString modifiers:0]];
    [view keyDown:[self key:@"\x03" bare:@"c" modifiers:NSEventModifierFlagControl]];
    unichar delete = 0x7F;
    NSString *deleteString = [NSString stringWithCharacters:&delete length:1];
    [view keyDown:[self key:deleteString bare:deleteString modifiers:0]];
    XCTAssertEqualObjects(self.writtenText, @"aé\r\x1b[A\x03\x7f");

    [_written setLength:0];
    [view pasteString:@"one\ntwo"];
    XCTAssertEqualObjects(self.writtenText, @"one\rtwo", @"no brackets until asked for");
    [_written setLength:0];
    [self feed:@"\x1b[?2004h" to:view];
    [view pasteString:@"one\ntwo"];
    XCTAssertEqualObjects(self.writtenText, @"\x1b[200~one\rtwo\x1b[201~");

    // the selection's text, copied
    [view reset];
    [self feed:@"first\r\nsecond" to:view];
    [view selectAll:nil];
    XCTAssertEqualObjects(view.selectedText, @"first\nsecond");
}

/// A program on a pseudo-terminal of its own: it is told the terminal's
/// size, what it writes is shown, and its end says how it ended.
- (void)testAProgramRunsOnATerminalOfItsOwn {
    UDTerminalViewController *terminal = [[UDTerminalViewController alloc] init];
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 640, 240) styleMask:NSWindowStyleMaskTitled
                                                     backing:NSBackingStoreBuffered defer:NO];
    window.releasedWhenClosed = NO;
    terminal.view.frame = [(NSView *)window.contentView bounds];
    [(NSView *)window.contentView addSubview:terminal.view];
    UDTerminalView *view = terminal.terminalView;
    XCTAssertGreaterThan(view.columns, 40u);
    NSArray *script = UDShellCommandArguments(nil, @"printf 'hi there\\n'; stty size; exit 3");
    XCTAssertTrue([terminal startArguments:script directory:NSTemporaryDirectory() environment:nil]);
    UDRunUntil(!terminal.running, 10);
    XCTAssertFalse(terminal.running);
    // its status, unless GNUstep's NSTask reaped it first (after an earlier test ran one)
    int status = terminal.pseudoTerminal.exitStatus;
    XCTAssertTrue(status == 3 || status == -1, @"%d", status);
    NSString *size = [NSString stringWithFormat:@"%lu %lu", (unsigned long)view.rows, (unsigned long)view.columns];
    XCTAssertTrue([view.screenText containsString:@"hi there"], @"%@", view.screenText);
    XCTAssertTrue([view.screenText containsString:size], @"stty sees %@: %@", size, view.screenText);
    NSString *completed = status == 3 ? @"[Process completed, exit status 3]" : @"[Process completed]";
    XCTAssertTrue([view.screenText containsString:completed], @"%@", view.screenText);

    // typed, echoed by the terminal and by cat; ^D ends it
    NSArray *cat = UDShellCommandArguments(nil, @"exec cat");
    XCTAssertTrue([terminal startArguments:cat directory:nil environment:nil]);
    XCTAssertEqualObjects(view.screenText, @"", @"started afresh");
    for (NSString *c in @[ @"a", @"b", @"c", @"\r" ]) [view keyDown:[self key:c bare:c modifiers:0]];
    UDRunUntil([view.screenText isEqualToString:@"abc\nabc"], 10);
    XCTAssertEqualObjects(view.screenText, @"abc\nabc");
    [view keyDown:[self key:@"\x04" bare:@"d" modifiers:NSEventModifierFlagControl]];
    UDRunUntil(!terminal.running, 10);
    XCTAssertFalse(terminal.running, @"^D ended cat");
    XCTAssertTrue(terminal.pseudoTerminal.exitStatus == 0 || terminal.pseudoTerminal.exitStatus == -1);
    [window close];
}

@end
