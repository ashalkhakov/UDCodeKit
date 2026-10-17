/*---------------------------------------------------------------------------------------------
 *  UDJumpToLineViewController.m
 *--------------------------------------------------------------------------------------------*/

#import "UDJumpToLineViewController.h"
#import <objc/runtime.h>

/// How far below the top of the editor the box floats.
static const CGFloat UDJumpToLineInset = 8.0;

@implementation UDJumpToLinePanel
- (BOOL)canBecomeKeyWindow { return YES; }
- (BOOL)canBecomeMainWindow { return NO; }
@end

/// The box: a rounded panel of the window's colour, outlined.
@interface UDJumpToLineBox : NSView
@end

@implementation UDJumpToLineBox
- (void)drawRect:(NSRect)dirtyRect {
    [[NSColor clearColor] setFill];
    NSRectFill(dirtyRect);
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

- (void)viewDidLoad {
    [super viewDidLoad];
    UDJumpToLinePanel *panel = self.panel;
    panel.opaque = NO;
    panel.backgroundColor = [NSColor clearColor];
    panel.hasShadow = YES;
    // the keyboard gone elsewhere (a click in the text, another window):
    // put away, as Xcode's
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_panelDidResignKey:)
                                                 name:NSWindowDidResignKeyNotification object:panel];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (BOOL)isShown {
    return self.panel.parentWindow != nil;
}

- (void)showOverView:(NSView *)view lineCount:(NSInteger)lineCount {
    (void)self.view;
    NSWindow *window = view.window;
    UDJumpToLinePanel *panel = self.panel;
    if (window == nil || panel == nil) return;
    self.lineField.stringValue = @"";
    self.rangeLabel.stringValue = [NSString stringWithFormat:@"1–%ld", (long)lineCount];

    NSRect area = [window convertRectToScreen:[view convertRect:view.bounds toView:nil]];
    NSRect frame = panel.frame;
    frame.origin.x = NSMidX(area) - NSWidth(frame) / 2;
    frame.origin.y = NSMaxY(area) - UDJumpToLineInset - NSHeight(frame);
    [panel setFrame:frame display:NO];
    if (panel.parentWindow != window) {
        [panel.parentWindow removeChildWindow:panel];
        [window addChildWindow:panel ordered:NSWindowAbove];
    }
    [panel makeKeyAndOrderFront:nil];
    [panel makeFirstResponder:self.lineField];
}

- (void)close {
    UDJumpToLinePanel *panel = self.panel;
    NSWindow *parent = panel.parentWindow;
    if (parent == nil) return;
    [parent removeChildWindow:panel];
    [panel orderOut:nil];
    [parent makeKeyWindow];
}

- (void)_panelDidResignKey:(NSNotification *)notification {
    if (self.isShown) {
        [self.delegate jumpToLineDidCancel:self];
    }
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
