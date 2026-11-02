/*---------------------------------------------------------------------------------------------
 *  UDBadgeTextFieldCell.m
 *--------------------------------------------------------------------------------------------*/

#import "UDBadgeTextFieldCell.h"

// The badge and its colour are the cell's represented object: NSCell copies
// its own (a table copies its cells), and not a subclass's instance variables.
static NSString * const UDBadgeKey = @"badge";
static NSString * const UDBadgeColorKey = @"color";

@implementation UDBadgeTextFieldCell

- (NSString *)badge {
    NSDictionary *badge = [self.representedObject isKindOfClass:[NSDictionary class]] ? self.representedObject : nil;
    return badge[UDBadgeKey];
}

- (void)setBadge:(NSString *)badge {
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    if (badge) values[UDBadgeKey] = [badge copy];
    if (self.badgeColor) values[UDBadgeColorKey] = self.badgeColor;
    self.representedObject = values;
}

- (NSColor *)badgeColor {
    NSDictionary *badge = [self.representedObject isKindOfClass:[NSDictionary class]] ? self.representedObject : nil;
    return badge[UDBadgeColorKey];
}

- (void)setBadgeColor:(NSColor *)badgeColor {
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    if (self.badge) values[UDBadgeKey] = self.badge;
    if (badgeColor) values[UDBadgeColorKey] = badgeColor;
    self.representedObject = values;
}

- (NSDictionary *)_badgeAttributes {
    return @{ NSFontAttributeName: [NSFont boldSystemFontOfSize:[NSFont smallSystemFontSize]],
              NSForegroundColorAttributeName: self.badgeColor ?: [NSColor disabledControlTextColor] };
}

- (CGFloat)_badgeWidth {
    NSString *badge = self.badge;
    return badge.length ? ceil([badge sizeWithAttributes:[self _badgeAttributes]].width) + 10.0 : 0.0;
}

/// A badge this wide or less is always shown (a source-control letter); a
/// wider one is what the text leaves of the row, cut short, or none.
static const CGFloat UDShortBadgeWidth = 36.0;

/// The badge's width in @a cellFrame: the text first, unless it is short.
- (CGFloat)_badgeWidthIn:(NSRect)cellFrame {
    CGFloat width = [self _badgeWidth];
    if (width <= UDShortBadgeWidth) return width;
    CGFloat text = ceil(self.attributedStringValue.size.width) + 8.0;
    CGFloat left = NSWidth(cellFrame) - text;
    if (left >= width) return width;
    return left >= UDShortBadgeWidth ? left : 0.0;
}

- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
    CGFloat width = [self _badgeWidthIn:cellFrame];
    NSRect text = cellFrame;
    text.size.width = MAX(0.0, NSWidth(cellFrame) - width);
    [super drawInteriorWithFrame:text inView:controlView];
    if (!width) return;
    NSMutableDictionary *attributes = [[self _badgeAttributes] mutableCopy];
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.lineBreakMode = NSLineBreakByTruncatingTail;
    attributes[NSParagraphStyleAttributeName] = style;
    NSString *badge = self.badge;
    NSSize size = [badge sizeWithAttributes:attributes];
    NSRect at = NSMakeRect(NSMaxX(cellFrame) - width + 4.0, NSMidY(cellFrame) - size.height / 2.0, width - 6.0, size.height);
    [badge drawInRect:at withAttributes:attributes];
}

@end
