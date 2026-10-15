/*---------------------------------------------------------------------------------------------
 *  UDHoverViewController.h
 *
 *  What a hover shows (a language server's hover text), in a popover over
 *  the text. Laid out in UDHoverView.xib.
 *--------------------------------------------------------------------------------------------*/

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface UDHoverViewController : NSViewController

/// Loads UDHoverView.xib from UDCodeKit's bundle.
- (instancetype)init;

@property (nonatomic, weak, nullable) IBOutlet NSTextView *textView;

/// Shows @a text in a popover pointing at @a characterIndex of @a textView.
- (void)showText:(NSString *)text atCharacterIndex:(NSUInteger)characterIndex ofTextView:(NSTextView *)textView;

/// Whether the popover is showing.
@property (nonatomic, readonly, getter=isShown) BOOL shown;

/// Closes the popover, when it is showing: a tooltip that lasts while
/// something is being typed (a function's parameters until its ')').
- (void)close;

@end

NS_ASSUME_NONNULL_END
