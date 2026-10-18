/*---------------------------------------------------------------------------------------------
 *  UDTextPromptController.m
 *--------------------------------------------------------------------------------------------*/

#import "UDTextPromptController.h"

@interface UDTextPromptController ()
@property (nonatomic, weak) IBOutlet NSTextField *messageLabel;
@property (nonatomic, weak) IBOutlet NSTextField *textField;
@property (nonatomic, readwrite) NSModalResponse returnCode;
@end

@implementation UDTextPromptController {
    __weak id _target;
    SEL _action;
}

/// The XIB is the framework's, not the app's: compiled on macOS, as it is on GNUstep.
- (instancetype)init {
    NSBundle *bundle = [NSBundle bundleForClass:[UDTextPromptController class]];
    NSString *path = [bundle pathForResource:@"UDTextPrompt" ofType:@"nib"] ?: [bundle pathForResource:@"UDTextPrompt" ofType:@"xib"];
    return [super initWithWindowNibPath:path owner:self];
}

- (void)beginSheetForWindow:(NSWindow *)window message:(NSString *)message text:(NSString *)text target:(id)target action:(SEL)action {
    _target = target;
    _action = action;
    _returnCode = NSModalResponseCancel;
    (void)self.window;
    _messageLabel.stringValue = message ?: @"";
    _textField.stringValue = text ?: @"";
    [self.window makeFirstResponder:_textField];
    [_textField selectText:nil];
    [NSApp beginSheet:self.window modalForWindow:window modalDelegate:self
       didEndSelector:@selector(_sheetDidEnd:returnCode:contextInfo:) contextInfo:NULL];
}

- (NSString *)text {
    return _textField.stringValue ?: @"";
}

- (void)_sheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo {
    [sheet orderOut:self];
    id target = _target;
    if (target && _action) [NSApp sendAction:_action to:target from:self];
}

/// Ended: GNUstep's modal loop notices only with the next event, so one comes.
- (void)_end:(NSModalResponse)code {
    _returnCode = code;
    [NSApp endSheet:self.window returnCode:code];
    NSEvent *wake = [NSEvent otherEventWithType:NSEventTypeApplicationDefined location:NSZeroPoint modifierFlags:0
                                      timestamp:0 windowNumber:0 context:nil subtype:0 data1:0 data2:0];
    [NSApp postEvent:wake atStart:NO];
}

- (IBAction)ok:(id)sender {
    [self _end:NSModalResponseOK];
}

- (IBAction)cancel:(id)sender {
    [self _end:NSModalResponseCancel];
}

@end
