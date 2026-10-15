/*---------------------------------------------------------------------------------------------
 *  UDHoverTests.m
 *
 *  A hover shown, closed and shown again: GNUstep's NSPopover frees its
 *  panel when it closes, so the controller must not show a closed one again.
 *--------------------------------------------------------------------------------------------*/

#import <XCTest/XCTest.h>
#import "UDCodeTestCase.h"
#import <UDCodeKit/UDCodeKit.h>

@interface UDHoverTests : UDCodeTestCase
@end

@implementation UDHoverTests

/// Whether the hover comes to be @a shown, given the run loop's turns
/// (AppKit shows and closes a popover there, animated).
static BOOL UDBecomesShown(UDHoverViewController *hover, BOOL shown) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:2.0];
    while (hover.isShown != shown && [until timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    return hover.isShown == shown;
}

- (void)testAHoverShowsClosesAndShowsAgain {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 300)
                                                   styleMask:NSWindowStyleMaskTitled
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.releasedWhenClosed = NO;
    NSTextView *textView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    textView.string = @"void wait( float seconds );";
    window.contentView = textView;
    [window makeKeyAndOrderFront:nil];
    [textView.layoutManager ensureLayoutForTextContainer:textView.textContainer];
    [window display];

    UDHoverViewController *hover = [[UDHoverViewController alloc] init];
    [hover showText:@"first" atCharacterIndex:5 ofTextView:textView];
    XCTAssertTrue(UDBecomesShown(hover, YES));
    XCTAssertEqualObjects(hover.textView.string, @"first");
    [hover close];
    XCTAssertTrue(UDBecomesShown(hover, NO));

    [hover showText:@"second" atCharacterIndex:10 ofTextView:textView];
    XCTAssertTrue(UDBecomesShown(hover, YES), @"shown again after closing");
    XCTAssertEqualObjects(hover.textView.string, @"second");
    [hover close];
    [window orderOut:nil];
}

@end
