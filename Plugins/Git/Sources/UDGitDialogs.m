/*---------------------------------------------------------------------------------------------
 *  UDGitDialogs.m
 *--------------------------------------------------------------------------------------------*/

#import "UDGitDialogs.h"

NSString *UDGitAsk(NSString *title, NSString *detail, NSString *value, NSString *button) {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = title;
    alert.informativeText = detail ?: @"";
    [alert addButtonWithTitle:button];
    [alert addButtonWithTitle:@"Cancel"];
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 300, 22)];
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

NSButton *UDGitCheckBox(NSString *title, CGFloat width) {
    NSButton *box = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, width, 20)];
    [box setButtonType:NSSwitchButton];
    box.title = title;
    return box;
}
