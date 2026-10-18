/*---------------------------------------------------------------------------------------------
 *  UDTextPromptController.h
 *
 *  A sheet asking for one line of text (Rename Symbol's new name, say): a
 *  message, a field with what there is now selected, OK and Cancel. Laid out
 *  in UDTextPrompt.xib. When it ends, its target is sent its action with it.
 *--------------------------------------------------------------------------------------------*/

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface UDTextPromptController : NSWindowController

- (instancetype)init;

- (void)beginSheetForWindow:(NSWindow *)window message:(NSString *)message text:(NSString *)text
                     target:(nullable id)target action:(nullable SEL)action;

/// NSModalResponseOK when it was answered.
@property (nonatomic, readonly) NSModalResponse returnCode;
/// What was typed.
@property (nonatomic, readonly, copy) NSString *text;
/// What the host keeps with it (the place a rename is at, say).
@property (nonatomic, strong, nullable) id context;

@property (nonatomic, weak, readonly) IBOutlet NSTextField *messageLabel;
@property (nonatomic, weak, readonly) IBOutlet NSTextField *textField;

- (IBAction)ok:(nullable id)sender;
- (IBAction)cancel:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
