/*---------------------------------------------------------------------------------------------
 *  AppDelegate.m — Application-level delegate.
 *
 *  Per-document setup (text storage, editor accessories, LSP coordinator) lives
 *  in UDDocument.  AppDelegate is now application-level only.
 *--------------------------------------------------------------------------------------------*/

#import "AppDelegate.h"

@implementation AppDelegate

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    return YES;
}

- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender {
    // Open one untitled document on launch if no other document is opened.
    return YES;
}

@end
