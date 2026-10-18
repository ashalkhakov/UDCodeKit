/*---------------------------------------------------------------------------------------------
 *  UDHoverViewController.m
 *--------------------------------------------------------------------------------------------*/

#import "UDHoverViewController.h"
#import "UDEditorPopup.h"

/// The widest and tallest a hover grows to fit its text.
static const CGFloat UDHoverMaxWidth = 480, UDHoverMaxHeight = 240;

@implementation UDHoverViewController

- (instancetype)init {
    return [super initWithNibName:@"UDHoverView" bundle:[NSBundle bundleForClass:[UDHoverViewController class]]];
}

- (void)showText:(NSString *)text atCharacterIndex:(NSUInteger)characterIndex ofTextView:(NSTextView *)textView {
    (void)self.view;
    _textView.string = text;

    // As big as the text, up to a limit.
    NSLayoutManager *lm = _textView.layoutManager;
    NSTextContainer *tc = _textView.textContainer;
    tc.widthTracksTextView = NO;
    tc.containerSize = NSMakeSize(UDHoverMaxWidth - 12, 1.0e7);
    [lm ensureLayoutForTextContainer:tc];
    NSSize used = [lm usedRectForTextContainer:tc].size;
    NSSize size = NSMakeSize(MIN(MAX(used.width + 14, 80), UDHoverMaxWidth),
                             MIN(used.height + 2 * _textView.textContainerInset.height + 6, UDHoverMaxHeight));
    [_panel setContentSize:size];
    tc.widthTracksTextView = YES;

    UDShowEditorPopup(_panel, textView, NSMakeRange(characterIndex, 1));
}

- (BOOL)isShown {
    return _panel.isVisible;
}

/// Away, and no longer its window's child (a child outliving its window
/// is ordered front again, on GNUstep, with its parent gone).
- (void)close {
    if (_panel.isVisible || _panel.parentWindow) UDHideEditorPopup(_panel);
}

@end
