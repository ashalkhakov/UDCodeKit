/*---------------------------------------------------------------------------------------------
 *  UDBreakpointEditorViewController.m
 *--------------------------------------------------------------------------------------------*/

#import "UDBreakpointEditorViewController.h"
#import <objc/runtime.h>

/// The field's placeholder for each of the three (VS Code's words).
static NSString *UDPlaceholder(UDBreakpointEditorKind kind) {
    switch (kind) {
        case UDBreakpointEditorCondition:    return @"Break when the expression evaluates to true";
        case UDBreakpointEditorHitCondition: return @"Break when the hit count condition is met";
        case UDBreakpointEditorLogMessage:   return @"Message to log when hit; {expressions} are interpolated";
    }
    return @"";
}

/// The box: a rounded panel of the window's colour, outlined, as Jump to
/// Line's.
@interface UDBreakpointEditorBox : NSView
@end

@implementation UDBreakpointEditorBox
- (BOOL)isOpaque { return NO; }
- (void)drawRect:(NSRect)dirtyRect {
    NSRect box = NSInsetRect(self.bounds, 0.5, 0.5);
    NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:box xRadius:6 yRadius:6];
    [[NSColor windowBackgroundColor] setFill];
    [path fill];
    [[NSColor gridColor] setStroke];
    [path stroke];
}
@end

@implementation UDBreakpointEditorViewController

- (instancetype)init {
    self = [super initWithNibName:@"UDBreakpointEditor" bundle:[NSBundle bundleForClass:[UDBreakpointEditorViewController class]]];
    if (self) {
        _condition = @"";
        _hitCondition = @"";
        _logMessage = @"";
    }
    return self;
}

- (BOOL)isShown {
    return self.isViewLoaded && self.view.superview != nil;
}

- (void)beginWithCondition:(NSString *)condition hitCondition:(NSString *)hitCondition
                logMessage:(NSString *)logMessage kind:(UDBreakpointEditorKind)kind {
    (void)self.view;
    _condition = [condition copy] ?: @"";
    _hitCondition = [hitCondition copy] ?: @"";
    _logMessage = [logMessage copy] ?: @"";
    if (kind == UDBreakpointEditorCondition) {
        if (_logMessage.length) kind = UDBreakpointEditorLogMessage;
        else if (_hitCondition.length && !_condition.length) kind = UDBreakpointEditorHitCondition;
    }
    // One the adapter cannot do, with nothing in it: the first it can.
    if (![self isKindEnabled:kind] && ![self _textOf:kind].length) {
        for (UDBreakpointEditorKind other = UDBreakpointEditorCondition; other <= UDBreakpointEditorLogMessage; other++) {
            if ([self isKindEnabled:other]) { kind = other; break; }
        }
    }
    _kind = kind;
    [self _showKind];
}

- (void)setKind:(UDBreakpointEditorKind)kind enabled:(BOOL)enabled {
    (void)self.view;
    ((NSMenuItem *)[_kindPopUp.menu itemWithTag:kind]).enabled = enabled;
}

- (BOOL)isKindEnabled:(UDBreakpointEditorKind)kind {
    (void)self.view;
    return ((NSMenuItem *)[_kindPopUp.menu itemWithTag:kind]).isEnabled;
}

- (NSString *)_textOf:(UDBreakpointEditorKind)kind {
    switch (kind) {
        case UDBreakpointEditorCondition:    return _condition;
        case UDBreakpointEditorHitCondition: return _hitCondition;
        case UDBreakpointEditorLogMessage:   return _logMessage;
    }
    return @"";
}

/// The field's text, where it belongs.
- (void)_keepField {
    NSString *text = _field.stringValue ?: @"";
    switch (_kind) {
        case UDBreakpointEditorCondition:    _condition = [text copy]; break;
        case UDBreakpointEditorHitCondition: _hitCondition = [text copy]; break;
        case UDBreakpointEditorLogMessage:   _logMessage = [text copy]; break;
    }
}

- (void)_showKind {
    [_kindPopUp selectItemWithTag:_kind];
    _field.stringValue = [self _textOf:_kind];
    _field.placeholderString = UDPlaceholder(_kind);
}

- (void)setKind:(UDBreakpointEditorKind)kind {
    if (self.isShown) [self _keepField];
    _kind = kind;
    [self _showKind];
}

- (NSString *)condition {
    if (self.isShown && _kind == UDBreakpointEditorCondition) [self _keepField];
    return _condition;
}

- (NSString *)hitCondition {
    if (self.isShown && _kind == UDBreakpointEditorHitCondition) [self _keepField];
    return _hitCondition;
}

- (NSString *)logMessage {
    if (self.isShown && _kind == UDBreakpointEditorLogMessage) [self _keepField];
    return _logMessage;
}

- (void)showOverView:(NSView *)view top:(CGFloat)top left:(CGFloat)left {
    NSView *box = self.view;
    NSView *host = view.superview;
    if (host == nil) return;
    NSRect area = view.frame;
    NSRect frame = box.frame;
    frame.size.width = MAX(240.0, MIN(560.0, NSMaxX(area) - left - 24.0));
    frame.origin.x = left;
    frame.origin.y = host.isFlipped ? top : top - NSHeight(frame);
    box.frame = frame;
    if (box.superview == host) return;
    // above the editor: last of its siblings
    [box removeFromSuperview];
    [host addSubview:box positioned:NSWindowAbove relativeTo:nil];
    [box.window makeFirstResponder:_field];
}

- (void)close {
    if (!self.isShown) return;
    [self _keepField];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(_keyboardLeft) object:nil];
    [self.view removeFromSuperview];
}

- (IBAction)kindChanged:(id)sender {
    self.kind = (UDBreakpointEditorKind)_kindPopUp.selectedTag;
    [self.view.window makeFirstResponder:_field];
}

- (IBAction)accept:(id)sender {
    [self _keepField];
    [self.delegate breakpointEditorDidAccept:self];
}

// Escape in the field: nothing kept.
- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)command {
    if (sel_isEqual(command, @selector(cancelOperation:))) {
        [self.delegate breakpointEditorDidCancel:self];
        return YES;
    }
    return NO;
}

// The field no longer has the keyboard: kept, and put away, unless the
// keyboard went to the box's own popup (GNUstep's takes it), which gives
// it back. Asked on the next turn, when it has gone where it goes.
- (void)controlTextDidEndEditing:(NSNotification *)notification {
    if (!self.isShown) return;
    [self _keepField];
    [self performSelector:@selector(_keyboardLeft) withObject:nil afterDelay:0
                  inModes:@[ NSDefaultRunLoopMode, NSModalPanelRunLoopMode, NSEventTrackingRunLoopMode ]];
}

- (void)_keyboardLeft {
    if (!self.isShown) return;
    NSResponder *responder = self.view.window.firstResponder;
    NSView *focused = [responder isKindOfClass:[NSView class]] ? (NSView *)responder : nil;
    // The field editor, or the popup: still the box's.
    if ([focused isKindOfClass:[NSText class]] && [(NSText *)focused delegate] == (id)_field) return;
    if (focused && [focused isDescendantOf:self.view]) return;
    [self.delegate breakpointEditorDidAccept:self];
}

@end
