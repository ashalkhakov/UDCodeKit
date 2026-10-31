/*---------------------------------------------------------------------------------------------
 *  UDAskpass.m
 *--------------------------------------------------------------------------------------------*/

#import <Cocoa/Cocoa.h>
#import "UDAskpass.h"

static NSString * const UDAskpassVariable = @"UDCODE_ASKPASS";

NSDictionary<NSString *, NSString *> *UDAskpassEnvironment(NSString *executable) {
    return @{
        @"GIT_ASKPASS": executable,
        @"SSH_ASKPASS": executable,
        // ssh asks the program even with a terminal, and without DISPLAY
        @"SSH_ASKPASS_REQUIRE": @"force",
        UDAskpassVariable: @"1",
    };
}

BOOL UDAskpassRequested(void) {
    return [[[NSProcessInfo processInfo] environment][UDAskpassVariable] isEqualToString:@"1"];
}

/// ssh's "(yes/no/[fingerprint])?": a question, not a secret.
static BOOL UDIsYesNoQuestion(NSString *prompt) {
    return [prompt rangeOfString:@"(yes/no" options:NSCaseInsensitiveSearch].location != NSNotFound;
}

static BOOL UDIsSecret(NSString *prompt) {
    return [prompt rangeOfString:@"password" options:NSCaseInsensitiveSearch].location != NSNotFound ||
           [prompt rangeOfString:@"passphrase" options:NSCaseInsensitiveSearch].location != NSNotFound ||
           [prompt rangeOfString:@"PIN" options:0].location != NSNotFound;
}

static void UDPrint(NSString *answer) {
    NSData *data = [[answer stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
    [[NSFileHandle fileHandleWithStandardOutput] writeData:data];
}

int UDAskpassMain(NSString *prompt) {
    @autoreleasepool {
        [NSApplication sharedApplication];
#ifdef __APPLE__
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
#endif
        [NSApp activateIgnoringOtherApps:YES];
        NSString *trimmed = [prompt stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"git asks";
        alert.informativeText = trimmed;
        if (UDIsYesNoQuestion(trimmed)) {
            [alert addButtonWithTitle:@"Yes"];
            [alert addButtonWithTitle:@"No"];
            BOOL yes = [alert runModal] == NSAlertFirstButtonReturn;
            UDPrint(yes ? @"yes" : @"no");
            return 0;
        }
        [alert addButtonWithTitle:@"OK"];
        [alert addButtonWithTitle:@"Cancel"];
        NSTextField *field = UDIsSecret(trimmed) ? [[NSSecureTextField alloc] initWithFrame:NSMakeRect(0, 0, 300, 22)]
                                                 : [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 300, 22)];
        alert.accessoryView = field;
        [alert.window setInitialFirstResponder:field];
        if ([alert runModal] != NSAlertFirstButtonReturn) return 1;
        UDPrint(field.stringValue);
        return 0;
    }
}
