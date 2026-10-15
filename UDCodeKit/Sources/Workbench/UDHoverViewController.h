/*---------------------------------------------------------------------------------------------
 *  UDHoverViewController.h
 *
 *  What a hover shows (a language server's hover text), in a panel at the
 *  text (UDEditorPopup). Laid out in UDHoverView.xib.
 *--------------------------------------------------------------------------------------------*/

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface UDHoverViewController : NSViewController

/// Loads UDHoverView.xib from UDCodeKit's bundle.
- (instancetype)init;

@property (nonatomic, weak, nullable) IBOutlet NSTextView *textView;
/// The borderless panel the hover shows in.
@property (nonatomic, strong, nullable) IBOutlet NSWindow *panel;

/// Shows @a text below @a characterIndex of @a textView (above, when the
/// screen has no room below).
- (void)showText:(NSString *)text atCharacterIndex:(NSUInteger)characterIndex ofTextView:(NSTextView *)textView;

/// Whether the hover is showing.
@property (nonatomic, readonly, getter=isShown) BOOL shown;

/// Closes the hover, when it is showing: a tooltip that lasts while
/// something is being typed (a function's parameters until its ')').
- (void)close;

@end

NS_ASSUME_NONNULL_END
