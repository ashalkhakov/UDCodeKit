/*---------------------------------------------------------------------------------------------
 *  UDBadgeTextFieldCell.m
 *--------------------------------------------------------------------------------------------*/

#import "UDBadgeTextFieldCell.h"

// GNUstep has AppKit's older name
#ifdef __APPLE__
#define UDCompositeSourceOver NSCompositingOperationSourceOver
#else
#define UDCompositeSourceOver NSCompositeSourceOver
#endif

// The badge, its colour and the image are the cell's represented object:
// NSCell copies its own (a table copies its cells), and not a subclass's
// instance variables.
static NSString * const UDBadgeKey = @"badge";
static NSString * const UDBadgeColorKey = @"color";
static NSString * const UDBadgeImageKey = @"image";

@implementation UDBadgeTextFieldCell

- (nullable id)_value:(NSString *)key {
    NSDictionary *values = [self.representedObject isKindOfClass:[NSDictionary class]] ? self.representedObject : nil;
    return values[key];
}

- (void)_setValue:(nullable id)value forKey:(NSString *)key {
    NSDictionary *old = [self.representedObject isKindOfClass:[NSDictionary class]] ? self.representedObject : nil;
    NSMutableDictionary *values = old ? [old mutableCopy] : [NSMutableDictionary dictionary];
    if (value) values[key] = value;
    else [values removeObjectForKey:key];
    self.representedObject = values;
}

- (NSString *)badge { return [self _value:UDBadgeKey]; }
- (void)setBadge:(NSString *)badge { [self _setValue:[badge copy] forKey:UDBadgeKey]; }
- (NSColor *)badgeColor { return [self _value:UDBadgeColorKey]; }
- (void)setBadgeColor:(NSColor *)badgeColor { [self _setValue:badgeColor forKey:UDBadgeColorKey]; }
- (NSImage *)leadingImage { return [self _value:UDBadgeImageKey]; }
- (void)setLeadingImage:(NSImage *)image { [self _setValue:image forKey:UDBadgeImageKey]; }

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
    NSImage *image = self.leadingImage;
    if (image) {
        CGFloat side = MIN(16.0, NSHeight(cellFrame));
        NSRect at = NSMakeRect(NSMinX(cellFrame) + 1.0, NSMidY(cellFrame) - side / 2.0, side, side);
        [image drawInRect:at fromRect:NSZeroRect operation:UDCompositeSourceOver fraction:1.0
           respectFlipped:YES hints:nil];
        cellFrame.origin.x += side + 4.0;
        cellFrame.size.width = MAX(0.0, NSWidth(cellFrame) - side - 4.0);
    }
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
