/*---------------------------------------------------------------------------------------------
 *  UDSQLConditionCell.m
 *--------------------------------------------------------------------------------------------*/

#import "UDSQLConditionCell.h"

static const CGFloat UDMenuWidth = 14;

@implementation UDSQLConditionCell

+ (CGFloat)menuWidth {
    return UDMenuWidth;
}

- (NSRect)_textFrameOf:(NSRect)frame {
    frame.size.width = MAX(0, frame.size.width - UDMenuWidth);
    return frame;
}

- (void)drawInteriorWithFrame:(NSRect)frame inView:(NSView *)view {
    [super drawInteriorWithFrame:[self _textFrameOf:frame] inView:view];
    // the ▾: a small triangle, in the middle of its strip
    CGFloat x = NSMaxX(frame) - UDMenuWidth / 2, y = NSMidY(frame), flip = view.isFlipped ? 1 : -1;
    NSBezierPath *arrow = [NSBezierPath bezierPath];
    [arrow moveToPoint:NSMakePoint(x - 3.5, y - 1.5 * flip)];
    [arrow lineToPoint:NSMakePoint(x + 3.5, y - 1.5 * flip)];
    [arrow lineToPoint:NSMakePoint(x, y + 2.5 * flip)];
    [arrow closePath];
    [[NSColor disabledControlTextColor] setFill];
    [arrow fill];
}

- (void)editWithFrame:(NSRect)frame inView:(NSView *)view editor:(NSText *)editor delegate:(id)delegate event:(NSEvent *)event {
    [super editWithFrame:[self _textFrameOf:frame] inView:view editor:editor delegate:delegate event:event];
}

- (void)selectWithFrame:(NSRect)frame inView:(NSView *)view editor:(NSText *)editor delegate:(id)delegate
                  start:(NSInteger)start length:(NSInteger)length {
    [super selectWithFrame:[self _textFrameOf:frame] inView:view editor:editor delegate:delegate start:start length:length];
}

@end
