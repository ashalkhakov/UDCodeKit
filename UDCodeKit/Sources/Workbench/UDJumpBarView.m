/*---------------------------------------------------------------------------------------------
 *  UDJumpBarView.m
 *--------------------------------------------------------------------------------------------*/

#import "UDJumpBarView.h"

// GNUstep has AppKit's older name
#ifdef __APPLE__
#define UDCompositeSourceOver NSCompositingOperationSourceOver
#else
#define UDCompositeSourceOver NSCompositeSourceOver
#endif

static const CGFloat UDJumpBarIconSize = 16.0;
static const CGFloat UDJumpBarPadding = 6.0;      // at the ends, and around a chevron
static const CGFloat UDJumpBarGap = 4.0;          // an icon to its title

@implementation UDJumpBarItem

+ (instancetype)itemWithTitle:(NSString *)title image:(NSImage *)image representedObject:(id)object {
    UDJumpBarItem *item = [[self alloc] init];
    item->_title = [title copy];
    item->_image = image;
    item->_representedObject = object;
    return item;
}

+ (instancetype)itemWithTitle:(NSString *)title symbolKind:(UDSymbolKind)kind representedObject:(id)object {
    UDJumpBarItem *item = [self itemWithTitle:title image:nil representedObject:object];
    item->_symbolKind = kind;
    return item;
}

@end

@implementation UDJumpBarView {
    NSArray<NSValue *> *_rects;      // each segment's, as last laid out
    NSArray<NSNumber *> *_titled;    // whether each shows its title
    NSInteger _pressed;              // the segment whose menu is up; -1: none
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) [self _setUp];
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) [self _setUp];
    return self;
}

- (void)_setUp {
    _items = @[];
    _rects = @[];
    _titled = @[];
    _pressed = -1;
}

- (BOOL)isFlipped {
    return YES;
}

- (void)setItems:(NSArray<UDJumpBarItem *> *)items {
    _items = [items copy];
    [self _layout];
    [self setNeedsDisplay:YES];
}

- (void)setFrameSize:(NSSize)size {
    [super setFrameSize:size];
    [self _layout];
}

// ---------------------------------------------------------------------------
// MARK: - Layout: titles dropped from the folders first where it is narrow
// ---------------------------------------------------------------------------

static NSDictionary *UDTitleAttributes(BOOL last) {
    NSFont *font = [NSFont systemFontOfSize:[NSFont smallSystemFontSize]];
    return @{ NSFontAttributeName: font,
              NSForegroundColorAttributeName: last ? [NSColor controlTextColor] : [NSColor secondaryLabelColor] };
}

- (CGFloat)_widthOfItem:(UDJumpBarItem *)item titled:(BOOL)titled {
    BOOL icon = item.image || item.symbolKind;
    CGFloat width = icon ? UDJumpBarIconSize : 0;
    if (titled) width += (icon ? UDJumpBarGap : 0) + ceil([item.title sizeWithAttributes:UDTitleAttributes(NO)].width);
    return width;
}

static CGFloat UDChevronWidth(void) {
    return ceil([@"›" sizeWithAttributes:UDTitleAttributes(NO)].width) + 2 * UDJumpBarPadding;
}

- (void)_layout {
    NSUInteger count = _items.count;
    NSMutableArray<NSNumber *> *titled = [NSMutableArray array];
    for (NSUInteger i = 0; i < count; i++) [titled addObject:@YES];
    CGFloat available = NSWidth(self.bounds) - 2 * UDJumpBarPadding;
    for (NSUInteger dropped = 0;; dropped++) {
        CGFloat width = count ? (count - 1) * UDChevronWidth() : 0;
        for (NSUInteger i = 0; i < count; i++) width += [self _widthOfItem:_items[i] titled:[titled[i] boolValue]];
        if (width <= available || dropped + 1 >= count) break;
        // the outermost titled one, the last kept
        for (NSUInteger i = 0; i + 1 < count; i++) {
            if ([titled[i] boolValue] && (_items[i].image || _items[i].symbolKind)) {
                titled[i] = @NO;
                break;
            }
        }
    }
    NSMutableArray<NSValue *> *rects = [NSMutableArray array];
    CGFloat x = UDJumpBarPadding, height = NSHeight(self.bounds);
    for (NSUInteger i = 0; i < count; i++) {
        CGFloat width = MIN([self _widthOfItem:_items[i] titled:[titled[i] boolValue]], MAX(0, NSWidth(self.bounds) - UDJumpBarPadding - x));
        [rects addObject:[NSValue valueWithRect:NSMakeRect(x, 0, width, height)]];
        x += width + UDChevronWidth();
    }
    _rects = rects;
    _titled = titled;
}

- (NSRect)rectOfItemAtIndex:(NSUInteger)index {
    return index < _rects.count ? [_rects[index] rectValue] : NSZeroRect;
}

// ---------------------------------------------------------------------------
// MARK: - Drawing
// ---------------------------------------------------------------------------

+ (NSImage *)imageOfSymbolKind:(UDSymbolKind)kind size:(CGFloat)size {
    NSString *letter = @"V";
    NSColor *color = [NSColor colorWithCalibratedRed:0.25 green:0.56 blue:0.58 alpha:1];      // values: teal
    NSColor *type = [NSColor colorWithCalibratedRed:0.55 green:0.36 blue:0.75 alpha:1];       // types: purple
    NSColor *code = [NSColor colorWithCalibratedRed:0.20 green:0.47 blue:0.85 alpha:1];       // methods, functions: blue
    NSColor *other = [NSColor colorWithCalibratedRed:0.50 green:0.50 blue:0.52 alpha:1];      // keys, headings: grey
    switch (kind) {
        case UDSymbolKindClass: letter = @"C"; color = type; break;
        case UDSymbolKindStruct: letter = @"S"; color = type; break;
        case UDSymbolKindEnum: letter = @"E"; color = type; break;
        case UDSymbolKindInterface: letter = @"Pr"; color = type; break;
        case UDSymbolKindModule: case UDSymbolKindNamespace: case UDSymbolKindPackage: letter = @"N"; color = type; break;
        case UDSymbolKindTypeParameter: letter = @"T"; color = type; break;
        case UDSymbolKindObject: letter = @"O"; color = type; break;
        case UDSymbolKindMethod: case UDSymbolKindConstructor: letter = @"M"; color = code; break;
        case UDSymbolKindFunction: letter = @"f"; color = code; break;
        case UDSymbolKindOperator: letter = @"Op"; color = code; break;
        case UDSymbolKindEvent: letter = @"Ev"; color = code; break;
        case UDSymbolKindProperty: letter = @"P"; break;
        case UDSymbolKindField: letter = @"F"; break;
        case UDSymbolKindEnumMember: letter = @"E"; break;
        case UDSymbolKindConstant: letter = @"K"; color = [NSColor colorWithCalibratedRed:0.82 green:0.45 blue:0.20 alpha:1]; break;
        case UDSymbolKindArray: letter = @"[]"; break;
        case UDSymbolKindKey: letter = @"K"; color = other; break;
        case UDSymbolKindString: letter = @"#"; color = other; break;
        case UDSymbolKindFile: letter = @"F"; color = other; break;
        default: break;
    }
    NSImage *image = [[NSImage alloc] initWithSize:NSMakeSize(size, size)];
    [image lockFocus];
    NSRect box = NSMakeRect(0, 0, size, size);
    [color setFill];
    [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(box, 0.5, 0.5) xRadius:size / 5 yRadius:size / 5] fill];
    CGFloat fontSize = size * (letter.length > 1 ? 0.5 : 0.68);
    NSDictionary *attributes = @{ NSFontAttributeName: [NSFont boldSystemFontOfSize:fontSize],
                                  NSForegroundColorAttributeName: [NSColor whiteColor] };
    NSSize text = [letter sizeWithAttributes:attributes];
    [letter drawAtPoint:NSMakePoint((size - text.width) / 2, (size - text.height) / 2) withAttributes:attributes];
    [image unlockFocus];
    return image;
}

- (void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = self.bounds;
    [[NSColor controlBackgroundColor] setFill];
    NSRectFill(NSIntersectionRect(dirtyRect, bounds));
    [[NSColor gridColor] setFill];
    NSRectFill(NSMakeRect(0, NSMaxY(bounds) - 1, NSWidth(bounds), 1));

    NSDictionary *chevron = UDTitleAttributes(NO);
    for (NSUInteger i = 0; i < _items.count && i < _rects.count; i++) {
        UDJumpBarItem *item = _items[i];
        NSRect rect = [_rects[i] rectValue];
        if ((NSInteger)i == _pressed) {
            [[NSColor selectedControlColor] setFill];
            [[NSBezierPath bezierPathWithRoundedRect:NSInsetRect(rect, -3, 3) xRadius:4 yRadius:4] fill];
        }
        CGFloat x = NSMinX(rect);
        NSImage *icon = item.symbolKind ? [UDJumpBarView imageOfSymbolKind:item.symbolKind size:UDJumpBarIconSize] : item.image;
        if (icon) {
            NSRect iconRect = NSMakeRect(x, floor((NSHeight(bounds) - UDJumpBarIconSize) / 2), UDJumpBarIconSize, UDJumpBarIconSize);
            [icon drawInRect:iconRect fromRect:NSZeroRect operation:UDCompositeSourceOver fraction:1.0
              respectFlipped:YES hints:nil];
            x += UDJumpBarIconSize + UDJumpBarGap;
        }
        if ([_titled[i] boolValue] && x < NSMaxX(rect)) {
            NSDictionary *attributes = UDTitleAttributes(i + 1 == _items.count);
            NSSize size = [item.title sizeWithAttributes:attributes];
            NSRect titleRect = NSMakeRect(x, floor((NSHeight(bounds) - size.height) / 2), NSMaxX(rect) - x, size.height);
            NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
            style.lineBreakMode = NSLineBreakByTruncatingTail;
            NSMutableDictionary *truncating = [attributes mutableCopy];
            truncating[NSParagraphStyleAttributeName] = style;
            [item.title drawInRect:titleRect withAttributes:truncating];
        }
        if (i + 1 < _items.count) {
            NSSize size = [@"›" sizeWithAttributes:chevron];
            [@"›" drawAtPoint:NSMakePoint(NSMaxX(rect) + UDJumpBarPadding, floor((NSHeight(bounds) - size.height) / 2))
               withAttributes:chevron];
        }
    }
}

// ---------------------------------------------------------------------------
// MARK: - A segment clicked: its menu
// ---------------------------------------------------------------------------

- (void)mouseDown:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    for (NSUInteger i = 0; i < _rects.count; i++) {
        if (NSPointInRect(point, NSInsetRect([_rects[i] rectValue], -UDJumpBarPadding, 0))) {
            [self popUpMenuOfItemAtIndex:i];
            return;
        }
    }
}

- (void)popUpMenuOfItemAtIndex:(NSUInteger)index {
    NSMenu *menu = index < _items.count ? [_delegate jumpBar:self menuForItemAtIndex:index] : nil;
    if (!menu) return;
    NSRect rect = [self rectOfItemAtIndex:index];
    _pressed = (NSInteger)index;
    [self setNeedsDisplay:YES];
    // under the segment, its icon over the items'
    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(NSMinX(rect) - 22, NSMaxY(self.bounds)) inView:self];
    _pressed = -1;
    [self setNeedsDisplay:YES];
}

@end
