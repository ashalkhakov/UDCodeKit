/*---------------------------------------------------------------------------------------------
 *  UDHoverViewController.m
 *--------------------------------------------------------------------------------------------*/

#import "UDHoverViewController.h"

@implementation UDHoverViewController {
    NSPopover *_popover;
}

- (instancetype)init {
    return [super initWithNibName:@"UDHoverView" bundle:[NSBundle bundleForClass:[UDHoverViewController class]]];
}

- (void)showText:(NSString *)text atCharacterIndex:(NSUInteger)characterIndex ofTextView:(NSTextView *)textView {
    (void)self.view;
    _textView.string = text;
    if (!_popover) {
        _popover = [[NSPopover alloc] init];
        _popover.behavior = NSPopoverBehaviorSemitransient;
        _popover.contentViewController = self;
    }
    NSLayoutManager *lm = textView.layoutManager;
    NSRange glyphs = [lm glyphRangeForCharacterRange:NSMakeRange(characterIndex, 1) actualCharacterRange:NULL];
    NSRect rect = [lm boundingRectForGlyphRange:glyphs inTextContainer:textView.textContainer];
    rect = NSOffsetRect(rect, textView.textContainerOrigin.x, textView.textContainerOrigin.y);
    [_popover showRelativeToRect:rect ofView:textView preferredEdge:NSRectEdgeMaxY];
}

@end
