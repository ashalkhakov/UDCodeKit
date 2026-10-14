//
//  UDFindBarTests.m
//
//  The find bar, driven in a window over a real editor: loading from its
//  XIB, finding as you type, "N of M", next and previous, the options,
//  replacing one and all (one undo step), and closing.
//

#import <XCTest/XCTest.h>
#import "UDCodeTestCase.h"
#import <UDCodeKit/UDCodeKit.h>

@interface UDFindBarTests : UDCodeTestCase
@property (nonatomic, strong) NSWindow *window;
@property (nonatomic, strong) UDCodeEditorViewController *editor;
@property (nonatomic, strong) UDTextModelTextStorage *storage;
@end

@implementation UDFindBarTests

- (void)setUp {
    [super setUp];
    NSString *text = @"alpha beta\nBeta gamma beta\nalphabet\n";
    _storage = [[UDTextModelTextStorage alloc] initWithText:text];
    _storage.textModel.undoManager = [[NSUndoManager alloc] init];
    _storage.textModel.undoManager.groupsByEvent = NO;
    _editor = [[UDCodeEditorViewController alloc] initWithTextStorage:_storage];
    _window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 900, 600)
                                          styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable
                                            backing:NSBackingStoreBuffered
                                              defer:NO];
    _window.releasedWhenClosed = NO;
    _window.contentView = _editor.view;
    [_window orderFront:nil];
}

- (void)tearDown {
    [_window orderOut:nil];
    _window = nil;
}

- (NSString *)selectedText {
    return [_storage.string substringWithRange:_editor.textView.selectedRange];
}

- (void)type:(NSString *)query {
    UDFindBarViewController *bar = _editor.findBar;
    bar.findField.stringValue = query;
    [bar findFieldChanged:bar.findField];
}

- (void)testTheBarLoadsFromItsXIBWithEveryOutlet {
    XCTAssertFalse(_editor.isFindBarVisible);
    [_editor showFindBarReplacing:NO];
    UDFindBarViewController *bar = _editor.findBar;
    XCTAssertTrue(_editor.isFindBarVisible);
    for (NSString *outlet in @[@"modeControl", @"findField", @"statusLabel", @"navigationControl", @"matchCaseButton",
                               @"wholeWordButton", @"regexButton", @"doneButton", @"replaceRow", @"replaceField",
                               @"replaceButton", @"replaceAllButton"]) {
        XCTAssertNotNil([bar valueForKey:outlet], @"%@ is connected in UDFindBar.xib", outlet);
    }
    XCTAssertTrue([bar.replaceRow isHidden], @"finding: one row");
    XCTAssertEqualWithAccuracy(NSHeight(bar.view.superview.frame), UDFindBarFindHeight, 0.5);
    XCTAssertEqual(_window.firstResponder, bar.findField.currentEditor, @"the cursor is in the search field");

    [_editor showFindBarReplacing:YES];
    XCTAssertFalse([bar.replaceRow isHidden], @"replacing: two rows");
    XCTAssertEqualWithAccuracy(NSHeight(bar.view.superview.frame), UDFindBarReplaceHeight, 0.5);
    XCTAssertEqual(bar.modeControl.selectedSegment, 1);
}

- (void)testFindingAsYouTypeAndNavigating {
    [_editor showFindBarReplacing:NO];
    UDFindBarViewController *bar = _editor.findBar;

    [self type:@"beta"];
    XCTAssertEqual(_editor.findModel.matchCount, 3u, @"case-insensitive: beta, Beta, beta");
    XCTAssertEqualObjects([self selectedText], @"beta");
    XCTAssertEqualObjects(bar.statusLabel.stringValue, @"1 of 3");

    [bar findNext:nil];
    XCTAssertEqualObjects([self selectedText], @"Beta");
    XCTAssertEqualObjects(bar.statusLabel.stringValue, @"2 of 3");
    [bar findNext:nil];
    [bar findNext:nil];                                   // wraps
    XCTAssertEqualObjects(bar.statusLabel.stringValue, @"1 of 3");
    [bar findPrevious:nil];                               // wraps back
    XCTAssertEqualObjects(bar.statusLabel.stringValue, @"3 of 3");

    bar.matchCaseButton.state = NSControlStateValueOn;
    [bar optionsChanged:bar.matchCaseButton];
    XCTAssertEqual(_editor.findModel.matchCount, 2u);

    [self type:@"alpha"];
    XCTAssertEqual(_editor.findModel.matchCount, 2u, @"alpha, alphabet");
    bar.wholeWordButton.state = NSControlStateValueOn;
    [bar optionsChanged:bar.wholeWordButton];
    XCTAssertEqual(_editor.findModel.matchCount, 1u, @"whole words: alpha only");

    [self type:@"zeta"];
    XCTAssertEqualObjects(bar.statusLabel.stringValue, @"No results");
    XCTAssertFalse([bar.replaceButton isEnabled]);

    bar.regexButton.state = NSControlStateValueOn;
    [bar optionsChanged:bar.regexButton];
    [self type:@"("];
    XCTAssertEqualObjects(bar.statusLabel.stringValue, @"Invalid pattern");
}

- (void)testReplacingOneAndAll {
    [_editor showFindBarReplacing:YES];
    UDFindBarViewController *bar = _editor.findBar;
    UDTextModel *model = _storage.textModel;
    NSString *before = [model getValue];

    bar.regexButton.state = NSControlStateValueOn;
    [bar optionsChanged:bar.regexButton];
    [self type:@"(b)eta"];
    bar.replaceField.stringValue = @"$1ay";
    [model.undoManager beginUndoGrouping];
    [bar replace:bar.replaceButton];                       // the selected first match
    [model.undoManager endUndoGrouping];
    XCTAssertEqualObjects([model getLineContent:1], @"alpha bay");
    XCTAssertEqualObjects([self selectedText], @"Beta", @"the next match is selected");
    XCTAssertEqualObjects(bar.statusLabel.stringValue, @"1 of 2");

    [bar replaceAll:bar.replaceAllButton];
    XCTAssertEqualObjects([model getValue], @"alpha bay\nBay gamma bay\nalphabet\n");
    XCTAssertEqualObjects(bar.statusLabel.stringValue, @"No results");

    [model.undoManager undo];
    XCTAssertEqualObjects([model getValue], @"alpha bay\nBeta gamma beta\nalphabet\n", @"Replace All is one undo step");
    [model.undoManager undo];
    XCTAssertEqualObjects([model getValue], before);
}

- (void)testTheFindMenuAndDone {
    NSMenuItem *find = [[NSMenuItem alloc] initWithTitle:@"Find…" action:@selector(performTextFinderAction:) keyEquivalent:@"f"];
    find.tag = 1;   // NSTextFinderActionShowFindInterface
    XCTAssertTrue([_editor.textView validateUserInterfaceItem:find]);
    [_editor.textView performTextFinderAction:find];
    XCTAssertTrue(_editor.isFindBarVisible, @"Find… shows the bar");

    [self type:@"gamma"];
    XCTAssertGreaterThan(_editor.findModel.matchCount, 0u);
    [_editor.findBar done:nil];
    XCTAssertFalse(_editor.isFindBarVisible);
    XCTAssertEqual(_editor.findModel.matchCount, 0u, @"closing forgets the matches");
    XCTAssertEqualWithAccuracy(NSHeight(_editor.textView.enclosingScrollView.superview.frame), NSHeight(_editor.view.bounds), 0.5,
                               @"the editor takes the bar's room back");
}

@end
