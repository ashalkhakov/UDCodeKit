/*---------------------------------------------------------------------------------------------
 *  UDGitDialogs.h
 *
 *  The git extension's questions, as Xcode asks them: a name or an address
 *  (an alert with a field), a confirmation of what can't be undone, an
 *  option (an alert with a check box). The alerts' accessory views are
 *  UDGitDialogs.xib's.
 *--------------------------------------------------------------------------------------------*/

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/// A fresh set of the alerts' accessory views, from UDGitDialogs.xib.
@interface UDGitAccessories : NSObject

+ (nullable instancetype)accessories;

/// A name, an address, a description.
@property (nonatomic, strong) IBOutlet NSTextField *field;
/// An option, titled by the question.
@property (nonatomic, strong) IBOutlet NSButton *checkBox;
/// Push…'s: the remote (its button) and Include tags.
@property (nonatomic, strong) IBOutlet NSView *pushView;
@property (nonatomic, strong) IBOutlet NSPopUpButton *remotesButton;
@property (nonatomic, strong) IBOutlet NSButton *tagsCheckBox;

@end

/// An alert with a field holding @a value: what was typed, nil when cancelled
/// (or nothing was).
FOUNDATION_EXPORT NSString *_Nullable UDGitAsk(NSString *title, NSString *_Nullable detail, NSString *_Nullable value, NSString *button);

/// An alert asking to go on with @a button: whether it was chosen.
FOUNDATION_EXPORT BOOL UDGitConfirm(NSString *title, NSString *_Nullable detail, NSString *button);

/// A check box titled @a title, an alert's accessory.
FOUNDATION_EXPORT NSButton *UDGitCheckBox(NSString *title);

NS_ASSUME_NONNULL_END
