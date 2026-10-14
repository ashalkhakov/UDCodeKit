/*---------------------------------------------------------------------------------------------
 *  AppDelegate.m — Application-level delegate.
 *
 *  Per-document setup (text storage, editor accessories, LSP coordinator) lives
 *  in UDDocument.  AppDelegate is now application-level only.
 *--------------------------------------------------------------------------------------------*/

#import "AppDelegate.h"
#import "UDUpdater.h"
#import <UDCodeKit/UDCodeKit.h>

/// Check for Updates… in MainMenu.xib's application menu.
static const NSInteger UDCheckForUpdatesTag = 7100;

@interface AppDelegate ()
@property (nonatomic, strong) UDUpdater *updater;
@end

@implementation AppDelegate

- (void)applicationWillFinishLaunching:(NSNotification *)notification {
    // Updates, set up before the app finishes launching (as Sparkle asks),
    // and not started under XCTest, which reaches no network. Where there is
    // no updater, no menu item.
    BOOL testing = [[NSProcessInfo processInfo] environment][@"XCTestConfigurationFilePath"] != nil;
    self.updater = [[UDUpdater alloc] initStarting:!testing];
    if (!self.updater.available) {
        NSMenu *appMenu = [[[NSApp mainMenu] itemAtIndex:0] submenu];
        NSMenuItem *check = [appMenu itemWithTag:UDCheckForUpdatesTag];
        if (check != nil) [appMenu removeItem:check];
    }
}

- (IBAction)checkForUpdates:(id)sender {
    [self.updater checkForUpdates:sender];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    if ([item action] == @selector(checkForUpdates:)) {
        return self.updater.canCheckForUpdates;
    }
    return YES;
}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    return YES;
}

- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender {
    // Open one untitled document on launch if no other document is opened.
    return YES;
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    // Notify all loaded grammar extensions that the app is terminating.
    // Extension instances may linger in memory after this call (non-deterministic
    // teardown — see UDExtension.h for details).
    [[UDLanguageModeRegistry sharedRegistry] unloadAllExtensions];
}

@end
