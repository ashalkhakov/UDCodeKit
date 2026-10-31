/*---------------------------------------------------------------------------------------------
 *  UDGitDialogs.h
 *
 *  The git extension's questions, as Xcode asks them: a name or an address
 *  (an alert with a field), a confirmation of what can't be undone.
 *--------------------------------------------------------------------------------------------*/

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// An alert with a field holding @a value: what was typed, nil when cancelled
/// (or nothing was).
FOUNDATION_EXPORT NSString *_Nullable UDGitAsk(NSString *title, NSString *_Nullable detail, NSString *_Nullable value, NSString *button);

/// An alert asking to go on with @a button: whether it was chosen.
FOUNDATION_EXPORT BOOL UDGitConfirm(NSString *title, NSString *_Nullable detail, NSString *button);

/// A check box, an alert's accessory.
FOUNDATION_EXPORT NSButton *UDGitCheckBox(NSString *title, CGFloat width);

NS_ASSUME_NONNULL_END
