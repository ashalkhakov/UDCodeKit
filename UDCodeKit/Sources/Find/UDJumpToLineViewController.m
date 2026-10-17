/*---------------------------------------------------------------------------------------------
 *  UDJumpToLineViewController.m
 *--------------------------------------------------------------------------------------------*/

#import "UDJumpToLineViewController.h"
#import <objc/runtime.h>

/// How far below the top of the editor the box floats.
static const CGFloat UDJumpToLineInset = 8.0;

/// The box: a rounded panel of the window's colour, outlined; what is
/// around its corners is the text's.
@interface UDJumpToLineBox : NSView
@end

@implementation UDJumpToLineBox
- (BOOL)isOpaque { return NO; }
- (void)drawRect:(NSRect)dirtyRect {
    NSRect box = NSInsetRect(self.bounds, 0.5, 0.5);
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:box xRadius:8 yRadius:8];
    [[NSColor windowBackgroundColor] setFill];
    [path fill];
    [[NSColor gridColor] setStroke];
    [path stroke];
}
@end

@implementation UDJumpToLineViewController

- (instancetype)init {
    return [super initWithNibName:@"UDJumpToLine" bundle:[NSBundle bundleForClass:[UDJumpToLineViewController class]]];
}

- (BOOL)isShown {
    return self.isViewLoaded && self.view.superview != nil;
}

- (void)showOverView:(NSView *)view lineCount:(NSInteger)lineCount {
    NSView *box = self.view;
    NSView *host = view.superview;
    if (host == nil) return;
    self.lineField.stringValue = @"";
    self.rangeLabel.stringValue = [NSString stringWithFormat:@"1–%ld", (long)lineCount];

    NSRect area = view.frame;
    NSRect frame = box.frame;
    frame.origin.x = round(NSMidX(area) - NSWidth(frame) / 2);
    frame.origin.y = host.isFlipped ? NSMinY(area) + UDJumpToLineInset : NSMaxY(area) - UDJumpToLineInset - NSHeight(frame);
    box.frame = frame;
    // above the editor: last of its siblings
    [box removeFromSuperview];
    [host addSubview:box positioned:NSWindowAbove relativeTo:nil];
    [box.window makeFirstResponder:self.lineField];
}

- (void)close {
    if (!self.isShown) return;
    [self.view removeFromSuperview];
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

// The field no longer has the keyboard (a click in the text, say): put
// away, as Xcode's is. (After Return or Escape it is away already.)
- (void)controlTextDidEndEditing:(NSNotification *)notification {
    if (self.isShown) {
        [self.delegate jumpToLineDidCancel:self];
    }
}

@end
