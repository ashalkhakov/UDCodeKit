/*---------------------------------------------------------------------------------------------
 *  UDEditorTypingTests.m
 *
 *  The editor as typing drives it: text through -insertText:, keys through
 *  -keyDown:, in a window, as on either system.
 *--------------------------------------------------------------------------------------------*/

#import <XCTest/XCTest.h>
#import "UDCodeTestCase.h"
#import <UDCodeKit/UDCodeKit.h>
#import <UDPieceTable/UDPieceTable.h>

@interface UDEditorTypingTests : UDCodeTestCase <UDDiagnosticTextViewDelegate>
@property (nonatomic) NSInteger hoverAskedAt;     // -1: not asked
@property (nonatomic) NSInteger hoverEnded;
@property (nonatomic, copy) NSString *typed;          // what -shouldChangeTextInRange:… heard
@property (nonatomic) NSInteger changes;              // NSTextDidChangeNotifications
@property (nonatomic) BOOL completesCalls;            // completions insert calls with placeholders
@end

@implementation UDEditorTypingTests {
    UDTextModelTextStorage *_storage;
    UDCodeEditorViewController *_editor;
    NSWindow *_window;
}

- (void)setUp {
    [super setUp];
    _storage = [[UDTextModelTextStorage alloc] initWithText:@"\tone\n\ttwo\n"];
    _editor = [[UDCodeEditorViewController alloc] initWithTextStorage:_storage];
    _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 600, 400)
                                          styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable
                                            backing:NSBackingStoreBuffered
                                              defer:NO];
    _window.releasedWhenClosed = NO;
    _window.contentView = _editor.view;
    [_window orderFront:nil];
    [_window makeFirstResponder:_editor.textView];
}

- (void)tearDown {
    [_window orderOut:nil];
    _window = nil;
    [super tearDown];
}

- (void)pressKey:(NSString *)characters code:(unsigned short)keyCode {
    NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0
                                     timestamp:0 windowNumber:_window.windowNumber context:nil
                                    characters:characters charactersIgnoringModifiers:characters isARepeat:NO keyCode:keyCode];
    [_editor.textView keyDown:event];
}

- (void)pressReturn {
    [self pressKey:@"\r" code:36];
}

/// Return goes in where the caret is after typing, however the system moved
/// it there (GNUstep's typing never reaches -setSelectedRanges:…).
- (void)testReturnGoesWhereTheCaretIsAfterTyping {
    NSTextView *textView = _editor.textView;
    [textView setSelectedRange:NSMakeRange(4, 0)];          // after "\tone"
    [textView insertText:@" abc"];
    [self pressReturn];
    [textView insertText:@"def"];
    XCTAssertEqualObjects([_storage.textModel getValue], @"\tone abc\n\tdef\n\ttwo\n");

    [textView setSelectedRange:NSMakeRange([_storage.string rangeOfString:@"two"].location, 0)];
    [self pressReturn];
    XCTAssertEqualObjects([_storage.textModel getValue], @"\tone abc\n\tdef\n\t\n\ttwo\n");
}

#pragma mark - Hover

- (void)textView:(UDDiagnosticTextView *)textView requestTooltipAtIndex:(NSUInteger)characterIndex point:(NSPoint)point {
    self.hoverAskedAt = (NSInteger)characterIndex;
}

- (void)textViewHoverDidEnd:(UDDiagnosticTextView *)textView {
    self.hoverEnded++;
}

/// The mouse moved over the text view to the middle of character @a index,
/// or to the empty space right of the text.
- (void)moveMouseTo:(NSUInteger)index {
    UDDiagnosticTextView *textView = _editor.textView;
    NSPoint point;
    if (index == NSNotFound) {
        point = NSMakePoint(NSMaxX(textView.bounds) - 5, textView.textContainerOrigin.y + 5);
    } else {
        NSLayoutManager *lm = textView.layoutManager;
        NSRange glyphs = [lm glyphRangeForCharacterRange:NSMakeRange(index, 1) actualCharacterRange:NULL];
        NSRect rect = [lm boundingRectForGlyphRange:glyphs inTextContainer:textView.textContainer];
        point = NSMakePoint(NSMidX(rect) + textView.textContainerOrigin.x, NSMidY(rect) + textView.textContainerOrigin.y);
    }
    NSEvent *event = [NSEvent mouseEventWithType:NSEventTypeMouseMoved
                                        location:[textView convertPoint:point toView:nil]
                                   modifierFlags:0 timestamp:0 windowNumber:_window.windowNumber
                                         context:nil eventNumber:0 clickCount:0 pressure:0];
    [textView mouseMoved:event];
}

- (void)spin:(NSTimeInterval)seconds {
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:seconds]];
}

/// The mouse resting on a word asks what is there; leaving the word, or a
/// key, ends it. No click, no modifier.
- (void)testTheMouseRestingOnAWordAsksWhatIsThere {
    UDDiagnosticTextView *textView = _editor.textView;
    textView.delegate = self;
    textView.hoverDelay = 0.05;
    self.hoverAskedAt = -1;
    [textView.layoutManager ensureLayoutForTextContainer:textView.textContainer];

    [self moveMouseTo:2];                                 // "\to|ne"
    [self spin:0.2];
    XCTAssertEqual(self.hoverAskedAt, 2);

    [self moveMouseTo:3];                                 // still "one": nothing new
    [self spin:0.2];
    XCTAssertEqual(self.hoverEnded, 0);

    [self moveMouseTo:NSNotFound];                        // off the text
    XCTAssertEqual(self.hoverEnded, 1);
    self.hoverAskedAt = -1;
    [self spin:0.2];
    XCTAssertEqual(self.hoverAskedAt, -1, @"no text there, nothing to ask");

    [self moveMouseTo:7];                                 // "two"
    [self spin:0.2];
    XCTAssertEqual(self.hoverAskedAt, 7);
    [textView insertText:@"x"];
    [self pressReturn];
    XCTAssertEqual(self.hoverEnded, 2, @"a key ends it");
}

#pragma mark - Completion

- (NSArray<NSString *> *)textView:(NSTextView *)textView completions:(NSArray<NSString *> *)words
              forPartialWordRange:(NSRange)charRange indexOfSelectedItem:(NSInteger *)index {
    NSString *partial = [textView.string substringWithRange:charRange];
    NSMutableArray *matches = [NSMutableArray array];
    for (NSString *item in @[ @"alpha", @"alphabet", @"beta" ]) {
        if (partial.length == 0 || [item hasPrefix:partial]) [matches addObject:item];   // hasPrefix:@"" is NO
    }
    return matches;
}

/// The list shows at the word, the keys stay with the text: arrows choose,
/// Return accepts, typing narrows, Escape closes.
- (void)testTheCompletionListTakesItsKeysAndReplacesTheWord {
    UDDiagnosticTextView *textView = _editor.textView;
    textView.delegate = self;
    [textView setSelectedRange:NSMakeRange(4, 0)];
    [textView insertText:@" al"];
    [textView showCompleteList:nil];
    XCTAssertTrue(textView.isShowingCompletions);
    XCTAssertEqual(_window.firstResponder, textView, @"the keyboard stays with the text");

    [self pressKey:[NSString stringWithFormat:@"%C", (unichar)NSDownArrowFunctionKey] code:125];
    [self pressReturn];
    XCTAssertFalse(textView.isShowingCompletions);
    XCTAssertEqualObjects([_storage.textModel getValue], @"\tone alphabet\n\ttwo\n", @"the second item, in place of \"al\"");

    [textView insertText:@" "];
    [textView showCompleteList:nil];                     // nothing typed: every item
    XCTAssertTrue(textView.isShowingCompletions);
    [textView insertText:@"b"];                          // narrowed to one
    XCTAssertTrue(textView.isShowingCompletions);
    [self pressKey:@"\t" code:48];
    XCTAssertEqualObjects([_storage.textModel getValue], @"\tone alphabet beta\n\ttwo\n");

    [textView insertText:@" "];
    [textView showCompleteList:nil];
    [self pressKey:@"\e" code:53];
    XCTAssertFalse(textView.isShowingCompletions, @"Escape closes it");
    [textView showCompleteList:nil];
    [textView insertText:@"z"];
    XCTAssertFalse(textView.isShowingCompletions, @"and nothing matching does");
}

/// A hover is a child of the editor's window, just below its word.
- (void)testAHoverSitsBelowItsWord {
    UDDiagnosticTextView *textView = _editor.textView;
    [textView.layoutManager ensureLayoutForTextContainer:textView.textContainer];
    UDHoverViewController *hover = [[UDHoverViewController alloc] init];
    [hover showText:@"void two()" atCharacterIndex:7 ofTextView:textView];
    XCTAssertTrue(hover.isShown);
    XCTAssertEqual(hover.panel.parentWindow, _window);

    NSLayoutManager *lm = textView.layoutManager;
    NSRect word = [lm boundingRectForGlyphRange:[lm glyphRangeForCharacterRange:NSMakeRange(7, 1) actualCharacterRange:NULL]
                                inTextContainer:textView.textContainer];
    word = NSOffsetRect(word, textView.textContainerOrigin.x, textView.textContainerOrigin.y);
    NSRect onScreen = [_window convertRectToScreen:[textView convertRect:word toView:nil]];
    NSRect panel = hover.panel.frame;
    XCTAssertEqualWithAccuracy(NSMinX(panel), NSMinX(onScreen), 1.0);
    XCTAssertTrue(fabs(NSMaxY(panel) - NSMinY(onScreen)) < 1.0 || fabs(NSMinY(panel) - NSMaxY(onScreen)) < 1.0,
                  @"right below the word (or above it): %@ vs %@", NSStringFromRect(panel), NSStringFromRect(onScreen));
    [hover close];
    XCTAssertFalse(hover.isShown);
}

#pragma mark - Keys the auto-indenter types

- (BOOL)textView:(NSTextView *)textView shouldChangeTextInRange:(NSRange)range replacementString:(NSString *)string {
    self.typed = [(self.typed ?: @"") stringByAppendingString:string ?: @""];
    return YES;
}

- (void)textDidChange:(NSNotification *)notification {
    self.changes++;
}

/// A key the auto-indenter handles ('(' closed by ')', Return indented) is
/// heard by the delegate as typing: what was typed, and that the text changed.
- (void)testTheDelegateHearsTheKeysTheAutoIndenterTypes {
    UDLanguageMode *c = [[UDLanguageModeRegistry sharedRegistry] modeForIdentifier:@"c"];
    XCTAssertNotNil(c, @"the C grammar bundle, from the plug-ins the tests load");
    if (c == nil) return;
    [_editor configureForLanguageMode:c];
    UDDiagnosticTextView *textView = _editor.textView;
    textView.delegate = self;
    [textView setSelectedRange:NSMakeRange(4, 0)];

    [self pressKey:@"(" code:25];
    XCTAssertEqualObjects([_storage.textModel getValue], @"\tone()\n\ttwo\n", @"the auto-indenter closed it");
    XCTAssertEqualObjects(self.typed, @"(");
    XCTAssertEqual(self.changes, 1);
}

#pragma mark - Placeholders

- (NSString *)textView:(UDDiagnosticTextView *)textView insertTextForCompletion:(NSString *)completion {
    if (!self.completesCalls || ![completion isEqualToString:@"alphabet"]) return nil;
    return UDPlaceholderTextFromSnippet(@"alphabet(${1:int a}, ${2:int b})$0");
}

- (void)testSnippetsBecomePlaceholders {
    XCTAssertEqualObjects(UDPlaceholderTextFromSnippet(@"wait(${1:float time})"), @"wait(<#float time#>)");
    XCTAssertEqualObjects(UDPlaceholderTextFromSnippet(@"f($1, ${2})$0"), @"f(<#…#>, <#…#>)");
    XCTAssertEqualObjects(UDPlaceholderTextFromSnippet(@"cost \\$5 ${1:a\\}b}"), @"cost $5 <#a}b#>");
    XCTAssertEqualObjects(UDPlaceholderTextFromSnippet(@"plain"), @"plain");
}

/// A completed call's arguments are placeholders: the first selected,
/// typing replaces it, Tab and Shift-Tab go between them, a click takes one
/// whole; each is a pill once the edit is done.
- (void)testACompletedCallsArgumentsArePlaceholders {
    UDDiagnosticTextView *textView = _editor.textView;
    textView.delegate = self;
    self.completesCalls = YES;
    [textView setSelectedRange:NSMakeRange(4, 0)];
    [textView insertText:@" alphab"];
    [textView showCompleteList:nil];
    [self pressReturn];
    XCTAssertEqualObjects([_storage.textModel getValue], @"\tone alphabet(<#int a#>, <#int b#>)\n\ttwo\n");
    NSString *text = _storage.string;
    XCTAssertEqualObjects([text substringWithRange:textView.selectedRange], @"<#int a#>", @"the first one selected");

    // A pill, once the edit is done: its text has the attribute the layout
    // manager draws it by.
    [self spin:0.05];
    NSUInteger inner = [text rangeOfString:@"int b"].location;
    XCTAssertNotNil([_storage attribute:UDPlaceholderAttributeName atIndex:inner effectiveRange:NULL]);

    // Only the delimiters are hidden: the next line keeps its text.
    for (NSUInteger i = [_storage.string rangeOfString:@"\ttwo"].location; i < _storage.length; i++) {
        NSFont *font = [_storage attribute:NSFontAttributeName atIndex:i effectiveRange:NULL];
        XCTAssertGreaterThan(font.pointSize, 1.0, @"'%C' at %lu is hidden", [_storage.string characterAtIndex:i], (unsigned long)i);
    }

    [textView insertText:@"1"];
    XCTAssertEqualObjects([_storage.textModel getValue], @"\tone alphabet(1, <#int b#>)\n\ttwo\n");
    [self pressKey:@"\t" code:48];
    XCTAssertEqualObjects([_storage.string substringWithRange:textView.selectedRange], @"<#int b#>", @"Tab: the next");
    [textView setSelectedRange:NSMakeRange(0, 0)];
    XCTAssertTrue([textView selectPlaceholderForward:NO], @"Shift-Tab, wrapping around");
    XCTAssertEqualObjects([_storage.string substringWithRange:textView.selectedRange], @"<#int b#>");

    [textView insertText:@"2"];
    XCTAssertEqualObjects([_storage.textModel getValue], @"\tone alphabet(1, 2)\n\ttwo\n");
    XCTAssertFalse([textView selectPlaceholderForward:YES], @"none left");
    [self spin:0.05];
    XCTAssertNil([_storage attribute:UDPlaceholderAttributeName atIndex:[_storage.string rangeOfString:@"2)"].location effectiveRange:NULL],
                 @"no pill where none is");
}

/// A click inside a placeholder selects the whole of it.
- (void)testAClickInAPlaceholderSelectsIt {
    UDDiagnosticTextView *textView = _editor.textView;
    [textView setSelectedRange:NSMakeRange(4, 0)];
    [textView insertText:@" f(<#x#>)"];
    [textView.layoutManager ensureLayoutForTextContainer:textView.textContainer];
    NSUInteger x = [_storage.string rangeOfString:@"x#>"].location;
    NSLayoutManager *lm = textView.layoutManager;
    NSRect rect = [lm boundingRectForGlyphRange:[lm glyphRangeForCharacterRange:NSMakeRange(x, 1) actualCharacterRange:NULL]
                                inTextContainer:textView.textContainer];
    NSPoint point = NSMakePoint(NSMidX(rect) + textView.textContainerOrigin.x, NSMidY(rect) + textView.textContainerOrigin.y);
    NSPoint inWindow = [textView convertPoint:point toView:nil];
    NSEvent *down = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:inWindow modifierFlags:0 timestamp:0
                                   windowNumber:_window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
    NSEvent *up = [NSEvent mouseEventWithType:NSEventTypeLeftMouseUp location:inWindow modifierFlags:0 timestamp:0
                                 windowNumber:_window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:0];
    [NSApp postEvent:up atStart:NO];                       // the click's mouse-up, for its tracking loop
    [textView mouseDown:down];
    XCTAssertEqualObjects([_storage.string substringWithRange:textView.selectedRange], @"<#x#>");
}

#pragma mark - Quotes

/// A quote typed inside a call's parentheses goes in, closed by its pair;
/// typing on and the closing quote over it leave one pair. (Key code 48 is
/// X's quote key and the Mac's Tab: keys are told by their characters.)
- (void)testAQuoteGoesInAfterAParenthesis {
    UDLanguageMode *c = [[UDLanguageModeRegistry sharedRegistry] modeForIdentifier:@"c"];
    XCTAssertNotNil(c);
    if (c == nil) return;
    [_editor configureForLanguageMode:c];
    [_storage setLanguageFunc:c.languageFunc withHighlightsQuery:c.highlightsQuery ?: @""];   // a parse, to know a string by
    UDDiagnosticTextView *textView = _editor.textView;
    [textView setSelectedRange:NSMakeRange(4, 0)];
    [self pressKey:@"(" code:25];
    XCTAssertEqualObjects([_storage.textModel getValue], @"\tone()\n\ttwo\n");
    NSEvent *quote = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:NSEventModifierFlagShift
                                     timestamp:0 windowNumber:_window.windowNumber context:nil
                                    characters:@"\"" charactersIgnoringModifiers:@"\"" isARepeat:NO keyCode:48];   // X's quote key; the Mac's Tab
    [textView keyDown:quote];
    XCTAssertEqualObjects([_storage.textModel getValue], @"\tone(\"\")\n\ttwo\n");
    [textView insertText:@"Reload"];
    [textView keyDown:quote];
    XCTAssertEqualObjects([_storage.textModel getValue], @"\tone(\"Reload\")\n\ttwo\n", @"the closing quote types over");
}

@end
