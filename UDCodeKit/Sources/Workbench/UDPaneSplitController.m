/*---------------------------------------------------------------------------------------------
 *  UDPaneSplitController.m
 *--------------------------------------------------------------------------------------------*/

#import "UDPaneSplitController.h"

NSNotificationName const UDPaneSplitControllerDidChangeVisibilityNotification = @"UDPaneSplitControllerDidChangeVisibilityNotification";

@implementation UDPaneSplitController {
    NSMutableArray<NSNumber *> *_thicknesses;   // of every pane; the flexible one's is unused
    NSMutableIndexSet *_hidden;
    BOOL _laying;                               // inside our own layout: no saving
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    _flexiblePaneIndex = 1;
    _hidden = [NSMutableIndexSet indexSet];
    _thicknesses = [NSMutableArray array];
    return self;
}

- (void)setSplitView:(NSSplitView *)splitView {
    _splitView = splitView;
    splitView.delegate = self;
}

- (void)awakeFromNib {
    [super awakeFromNib];
    _splitView.delegate = self;
}

- (NSInteger)_paneCount {
    return (NSInteger)_splitView.subviews.count;
}

- (CGFloat)_minimumOfPane:(NSInteger)i {
    if (i < (NSInteger)_minimumThicknesses.count) return _minimumThicknesses[(NSUInteger)i].doubleValue;
    return i == _flexiblePaneIndex ? 320.0 : 160.0;
}

- (CGFloat)_defaultOfPane:(NSInteger)i {
    if (i < (NSInteger)_defaultThicknesses.count) return _defaultThicknesses[(NSUInteger)i].doubleValue;
    return 240.0;
}

- (CGFloat)thicknessOfPane:(NSInteger)index {
    if (index < 0 || index >= (NSInteger)_thicknesses.count) return [self _defaultOfPane:index];
    return _thicknesses[(NSUInteger)index].doubleValue;
}

- (CGFloat)_lengthOf:(NSView *)view {
    return _splitView.isVertical ? NSWidth(view.frame) : NSHeight(view.frame);
}

// ---------------------------------------------------------------------------
// MARK: - Saving
// ---------------------------------------------------------------------------

- (NSString *)_defaultsKey {
    return _autosaveName.length ? [@"UDPaneSplit " stringByAppendingString:_autosaveName] : nil;
}

- (void)_save {
    NSString *key = [self _defaultsKey];
    if (!key || _laying) return;
    NSMutableArray *hidden = [NSMutableArray array];
    for (NSUInteger i = _hidden.firstIndex; i != NSNotFound; i = [_hidden indexGreaterThanIndex:i]) {
        [hidden addObject:@(i)];
    }
    [[NSUserDefaults standardUserDefaults] setObject:@{ @"thicknesses": [_thicknesses copy], @"hidden": hidden }
                                              forKey:key];
}

- (void)restoreLayout {
    NSInteger count = [self _paneCount];
    [_thicknesses removeAllObjects];
    for (NSInteger i = 0; i < count; i++) [_thicknesses addObject:@([self _defaultOfPane:i])];
    [_hidden removeAllIndexes];

    NSString *key = [self _defaultsKey];
    NSDictionary *saved = key ? [[NSUserDefaults standardUserDefaults] dictionaryForKey:key] : nil;
    NSArray *thicknesses = [saved[@"thicknesses"] isKindOfClass:[NSArray class]] ? saved[@"thicknesses"] : nil;
    if (thicknesses.count == (NSUInteger)count) {
        for (NSInteger i = 0; i < count; i++) {
            if ([thicknesses[(NSUInteger)i] isKindOfClass:[NSNumber class]]) {
                _thicknesses[(NSUInteger)i] = @(MAX([thicknesses[(NSUInteger)i] doubleValue], [self _minimumOfPane:i]));
            }
        }
    }
    for (id i in [saved[@"hidden"] isKindOfClass:[NSArray class]] ? saved[@"hidden"] : @[]) {
        if ([i isKindOfClass:[NSNumber class]] && [i integerValue] < count && [i integerValue] != _flexiblePaneIndex) {
            [_hidden addIndex:[i unsignedIntegerValue]];
        }
    }
    [self _layout];
}

// ---------------------------------------------------------------------------
// MARK: - Showing and hiding
// ---------------------------------------------------------------------------

- (BOOL)isPaneVisible:(NSInteger)index {
    return ![_hidden containsIndex:(NSUInteger)index];
}

- (void)setPane:(NSInteger)index visible:(BOOL)visible {
    if (index < 0 || index >= [self _paneCount] || index == _flexiblePaneIndex) return;
    if ([self isPaneVisible:index] == visible) return;
    if (visible) [_hidden removeIndex:(NSUInteger)index];
    else [_hidden addIndex:(NSUInteger)index];
    [self _layout];
    [self _save];
    [[NSNotificationCenter defaultCenter] postNotificationName:UDPaneSplitControllerDidChangeVisibilityNotification object:self];
}

- (IBAction)togglePane:(id)sender {
    NSInteger index = [sender tag];
    [self setPane:index visible:![self isPaneVisible:index]];
}

// ---------------------------------------------------------------------------
// MARK: - Layout
// ---------------------------------------------------------------------------

/// Every pane where it goes: hidden ones take no room; the others their
/// thickness, the flexible one the rest; when the rest is below its
/// minimum, the others give way (down to their minimums, then below).
- (void)_layout {
    NSSplitView *split = _splitView;
    NSArray<NSView *> *panes = split.subviews;
    NSInteger count = (NSInteger)panes.count;
    if (count == 0) return;
    while ((NSInteger)_thicknesses.count < count) [_thicknesses addObject:@([self _defaultOfPane:(NSInteger)_thicknesses.count])];

    BOOL vertical = split.isVertical;
    CGFloat total = vertical ? NSWidth(split.bounds) : NSHeight(split.bounds);
    CGFloat across = vertical ? NSHeight(split.bounds) : NSWidth(split.bounds);
    CGFloat divider = split.dividerThickness;

    NSMutableArray<NSNumber *> *sizes = [NSMutableArray arrayWithCapacity:(NSUInteger)count];
    NSInteger visible = 0;
    CGFloat fixed = 0, fixedSlack = 0;
    for (NSInteger i = 0; i < count; i++) {
        BOOL shown = [self isPaneVisible:i];
        CGFloat size = 0;
        if (shown) {
            visible++;
            if (i != _flexiblePaneIndex) {
                size = MAX([self thicknessOfPane:i], [self _minimumOfPane:i]);
                fixed += size;
                fixedSlack += size - [self _minimumOfPane:i];
            }
        }
        [sizes addObject:@(size)];
    }
    CGFloat available = total - divider * MAX(visible - 1, 0);
    CGFloat rest = available - fixed;
    CGFloat flexibleMin = [self _minimumOfPane:_flexiblePaneIndex];
    if (rest < flexibleMin && fixed > 0) {
        // The side panes give way: first their slack above their minimums,
        // then evenly below.
        CGFloat need = flexibleMin - rest;
        CGFloat fromSlack = MIN(need, fixedSlack);
        CGFloat beyond = need - fromSlack;
        for (NSInteger i = 0; i < count; i++) {
            if (i == _flexiblePaneIndex || ![self isPaneVisible:i]) continue;
            CGFloat size = sizes[(NSUInteger)i].doubleValue;
            CGFloat slack = size - [self _minimumOfPane:i];
            size -= fixedSlack > 0 ? fromSlack * slack / fixedSlack : 0;
            size -= beyond * size / MAX(fixed - fromSlack, 1);
            sizes[(NSUInteger)i] = @(MAX(size, 0));
        }
        fixed = 0;
        for (NSInteger i = 0; i < count; i++) if (i != _flexiblePaneIndex) fixed += sizes[(NSUInteger)i].doubleValue;
        rest = available - fixed;
    }
    sizes[(NSUInteger)_flexiblePaneIndex] = @(MAX(rest, 0));

    _laying = YES;
    CGFloat position = 0;
    for (NSInteger i = 0; i < count; i++) {
        NSView *pane = panes[(NSUInteger)i];
        BOOL shown = [self isPaneVisible:i];
        pane.hidden = !shown;
        CGFloat size = shown ? floor(sizes[(NSUInteger)i].doubleValue) : 0;
        NSRect frame = vertical ? NSMakeRect(position, 0, size, across) : NSMakeRect(0, position, across, size);
        pane.frame = frame;
        if (shown) position += size + divider;
    }
    // Whatever rounding left over goes to the flexible pane, and what
    // follows it moves along.
    CGFloat leftover = total - (position - (visible > 0 ? divider : 0));
    if (fabs(leftover) >= 1 && [self isPaneVisible:_flexiblePaneIndex]) {
        BOOL after = NO;
        for (NSInteger i = 0; i < count; i++) {
            NSView *pane = panes[(NSUInteger)i];
            NSRect frame = pane.frame;
            if (i == _flexiblePaneIndex) {
                if (vertical) frame.size.width += leftover; else frame.size.height += leftover;
                after = YES;
            } else if (after) {
                if (vertical) frame.origin.x += leftover; else frame.origin.y += leftover;
            }
            pane.frame = frame;
        }
    }
    [split setNeedsDisplay:YES];
    _laying = NO;
}

// ---------------------------------------------------------------------------
// MARK: - NSSplitViewDelegate
// ---------------------------------------------------------------------------

- (void)splitView:(NSSplitView *)splitView resizeSubviewsWithOldSize:(NSSize)oldSize {
    [self _layout];
}

- (BOOL)splitView:(NSSplitView *)splitView shouldAdjustSizeOfSubview:(NSView *)view {
    return [splitView.subviews indexOfObject:view] == (NSUInteger)_flexiblePaneIndex;
}

- (BOOL)splitView:(NSSplitView *)splitView canCollapseSubview:(NSView *)subview {
    return NO;
}

/// A hidden pane's divider hides with it.
- (BOOL)splitView:(NSSplitView *)splitView shouldHideDividerAtIndex:(NSInteger)dividerIndex {
    return ![self isPaneVisible:dividerIndex] || ![self isPaneVisible:dividerIndex + 1];
}

/// The visible panes on either side of a divider.
- (void)_panesAroundDivider:(NSInteger)divider before:(NSInteger *)before after:(NSInteger *)after {
    NSInteger b = divider, a = divider + 1, count = [self _paneCount];
    while (b > 0 && ![self isPaneVisible:b]) b--;
    while (a < count - 1 && ![self isPaneVisible:a]) a++;
    *before = b;
    *after = a;
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposed ofSubviewAt:(NSInteger)divider {
    NSInteger before, after;
    [self _panesAroundDivider:divider before:&before after:&after];
    NSView *pane = splitView.subviews[(NSUInteger)before];
    CGFloat start = splitView.isVertical ? NSMinX(pane.frame) : NSMinY(pane.frame);
    return MAX(proposed, start + [self _minimumOfPane:before]);
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMaxCoordinate:(CGFloat)proposed ofSubviewAt:(NSInteger)divider {
    NSInteger before, after;
    [self _panesAroundDivider:divider before:&before after:&after];
    NSView *pane = splitView.subviews[(NSUInteger)after];
    CGFloat end = splitView.isVertical ? NSMaxX(pane.frame) : NSMaxY(pane.frame);
    return MIN(proposed, end - [self _minimumOfPane:after] - splitView.dividerThickness);
}

/// A divider dragged: the side panes keep their new sizes.
- (void)splitViewDidResizeSubviews:(NSNotification *)note {
    if (_laying) return;
    NSArray<NSView *> *panes = _splitView.subviews;
    for (NSInteger i = 0; i < (NSInteger)panes.count && i < (NSInteger)_thicknesses.count; i++) {
        if (i == _flexiblePaneIndex || ![self isPaneVisible:i]) continue;
        CGFloat length = [self _lengthOf:panes[(NSUInteger)i]];
        if (length > 0) _thicknesses[(NSUInteger)i] = @(length);
    }
    [self _save];
}

@end
