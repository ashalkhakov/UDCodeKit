/*---------------------------------------------------------------------------------------------
 *  UDGitDialogs.m
 *--------------------------------------------------------------------------------------------*/

#import "UDGitDialogs.h"

@implementation UDGitAccessories

+ (instancetype)accessories {
    UDGitAccessories *accessories = [[self alloc] init];
    NSNib *nib = [[NSNib alloc] initWithNibNamed:@"UDGitDialogs" bundle:[NSBundle bundleForClass:self]];
    NSArray *objects = nil;     // held by the outlets
    if (![nib instantiateWithOwner:accessories topLevelObjects:&objects]) {
        NSLog(@"UDGitAccessories: could not load UDGitDialogs.xib");
        return nil;
    }
    return accessories;
}

@end

NSString *UDGitAsk(NSString *title, NSString *detail, NSString *value, NSString *button) {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = title;
    alert.informativeText = detail ?: @"";
    [alert addButtonWithTitle:button];
    [alert addButtonWithTitle:@"Cancel"];
    NSTextField *field = [UDGitAccessories accessories].field;
    field.stringValue = value ?: @"";
    alert.accessoryView = field;
    [alert.window setInitialFirstResponder:field];
    if ([alert runModal] != NSAlertFirstButtonReturn) return nil;
    NSString *answer = [field.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return answer.length ? answer : nil;
}

BOOL UDGitConfirm(NSString *title, NSString *detail, NSString *button) {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = title;
    alert.informativeText = detail ?: @"";
    [alert addButtonWithTitle:button];
    [alert addButtonWithTitle:@"Cancel"];
    return [alert runModal] == NSAlertFirstButtonReturn;
}

NSButton *UDGitCheckBox(NSString *title) {
    NSButton *box = [UDGitAccessories accessories].checkBox;
    box.title = title;
    [box sizeToFit];
    return box;
}
