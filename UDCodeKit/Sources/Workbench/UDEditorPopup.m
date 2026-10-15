/*---------------------------------------------------------------------------------------------
 *  UDEditorPopup.m
 *--------------------------------------------------------------------------------------------*/

#import "UDEditorPopup.h"

/// The characters' rect on the screen.
static NSRect UDScreenRectOfCharacters(NSTextView *textView, NSRange characterRange) {
    NSLayoutManager *lm = textView.layoutManager;
    NSUInteger length = textView.string.length;
    if (characterRange.location >= length && length > 0) characterRange = NSMakeRange(length - 1, 1);
    if (characterRange.length == 0) characterRange.length = 1;
    if (NSMaxRange(characterRange) > length) characterRange.length = length - MIN(characterRange.location, length);
    NSRange glyphs = [lm glyphRangeForCharacterRange:characterRange actualCharacterRange:NULL];
    NSRect rect = [lm boundingRectForGlyphRange:glyphs inTextContainer:textView.textContainer];
    rect = NSOffsetRect(rect, textView.textContainerOrigin.x, textView.textContainerOrigin.y);
    rect = [textView convertRect:rect toView:nil];
    return [textView.window convertRectToScreen:rect];
}

void UDShowEditorPopup(NSWindow *popup, NSTextView *textView, NSRange characterRange) {
    NSWindow *window = textView.window;
    if (window == nil) return;
    NSRect anchor = UDScreenRectOfCharacters(textView, characterRange);
    NSRect visible = (window.screen ?: [NSScreen mainScreen]).visibleFrame;
    NSRect frame = popup.frame;

    // Below the line; above it when the screen ends first.
    frame.origin.x = NSMinX(anchor);
    frame.origin.y = NSMinY(anchor) - NSHeight(frame);
    if (NSMinY(frame) < NSMinY(visible)) frame.origin.y = NSMaxY(anchor);
    frame.origin.x = MAX(NSMinX(visible), MIN(NSMinX(frame), NSMaxX(visible) - NSWidth(frame)));
    [popup setFrame:frame display:YES];

    if (popup.parentWindow != window) {
        [popup.parentWindow removeChildWindow:popup];
        [window addChildWindow:popup ordered:NSWindowAbove];
    }
    [popup orderFront:nil];
}

void UDHideEditorPopup(NSWindow *popup) {
    [popup.parentWindow removeChildWindow:popup];
    [popup orderOut:nil];
}
