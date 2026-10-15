/*---------------------------------------------------------------------------------------------
 *  UDEditorPopup.h
 *
 *  A window floating at a range of a text view's text, as a hover or a
 *  completion list does: placed below its line, or above it when the
 *  screen has no room below, and kept on the screen; a child of the text
 *  view's window, so it moves with it. A borderless window, which never
 *  becomes key: the keyboard stays with the text view.
 *
 *  (UDCodeKit's own, not NSPopover: GNUstep's places a popover by the
 *  positioning rect as if it were in window coordinates, and makes it key.)
 *--------------------------------------------------------------------------------------------*/

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// Shows @a popup at @a characterRange of @a textView.
void UDShowEditorPopup(NSWindow *popup, NSTextView *textView, NSRange characterRange);

/// Puts @a popup away.
void UDHideEditorPopup(NSWindow *popup);

NS_ASSUME_NONNULL_END
