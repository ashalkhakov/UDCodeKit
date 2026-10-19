/*---------------------------------------------------------------------------------------------
 *  UDIssuePopupController.h
 *
 *  An issue and its fixes, as Xcode shows a Fix-it: the issue's message, and
 *  below it each fix the language server has (its code actions), with a Fix
 *  button, in a panel at the issue (UDEditorPopup). A click on a fix, or
 *  Return in the text (the host passes it on), applies it; Escape, or the
 *  caret moving away, puts the panel away. Laid out in UDIssuePopup.xib.
 *--------------------------------------------------------------------------------------------*/

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class UDIssuePopupController;

@protocol UDIssuePopupDelegate <NSObject>
/// Fix @a index chosen (the panel is away already).
- (void)issuePopup:(UDIssuePopupController *)popup didChooseFixAtIndex:(NSUInteger)index;
@end

@interface UDIssuePopupController : NSViewController <NSTableViewDataSource, NSTableViewDelegate>

/// Loads UDIssuePopup.xib from UDCodeKit's bundle.
- (instancetype)init;

@property (nonatomic, weak, nullable) id<UDIssuePopupDelegate> delegate;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *messageLabel;
@property (nonatomic, weak, nullable) IBOutlet NSTableView *tableView;
@property (nonatomic, strong, nullable) IBOutlet NSWindow *panel;

/// @a message over @a fixes' titles, below @a characterIndex of @a textView;
/// the first fix selected.
- (void)showMessage:(NSString *)message fixes:(NSArray<NSString *> *)fixes
   atCharacterIndex:(NSUInteger)characterIndex ofTextView:(NSTextView *)textView;
@property (nonatomic, readonly, getter=isShown) BOOL shown;
@property (nonatomic, readonly, copy) NSArray<NSString *> *fixes;
/// The fix Return applies.
@property (nonatomic) NSUInteger selectedIndex;

/// The selected fix applied (Return).
- (void)chooseSelectedFix;
/// A row clicked: its fix applied.
- (IBAction)chooseFix:(nullable id)sender;
- (void)close;

@end

NS_ASSUME_NONNULL_END
