/*---------------------------------------------------------------------------------------------
 *  UDJumpToLineViewController.m
 *--------------------------------------------------------------------------------------------*/

#import "UDJumpToLineViewController.h"
#import <objc/runtime.h>

const CGFloat UDJumpToLineHeight = 30.0;

/// The strip's own background, so the text it covers does not show through.
@interface UDJumpToLineBar : NSView
@end

@implementation UDJumpToLineBar
- (BOOL)isOpaque { return YES; }
- (void)drawRect:(NSRect)dirtyRect {
    [[NSColor windowBackgroundColor] setFill];
    NSRectFill(dirtyRect);
}
@end

@implementation UDJumpToLineViewController

- (instancetype)init {
    return [super initWithNibName:@"UDJumpToLine" bundle:[NSBundle bundleForClass:[UDJumpToLineViewController class]]];
}

- (void)focusWithLineCount:(NSInteger)lineCount {
    (void)self.view;
    self.lineField.stringValue = @"";
    self.rangeLabel.stringValue = [NSString stringWithFormat:@"1–%ld", (long)lineCount];
    [self.view.window makeFirstResponder:self.lineField];
}

- (IBAction)jump:(nullable id)sender {
    NSInteger line = self.lineField.integerValue;
    if (line <= 0) {
        NSBeep();
        return;
    }
    [self.delegate jumpToLine:self didChooseLine:line];
}

// Escape in the field: put away.
- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)command {
    if (sel_isEqual(command, @selector(cancelOperation:))) {
        [self.delegate jumpToLineDidCancel:self];
        return YES;
    }
    return NO;
}

@end
