/*---------------------------------------------------------------------------------------------
 *  AppDelegate.m — Application-level delegate.
 *
 *  Per-document setup (text storage, editor accessories, LSP coordinator) lives
 *  in UDDocument.  AppDelegate is now application-level only.
 *--------------------------------------------------------------------------------------------*/

#import "AppDelegate.h"
#import "UDAskpass.h"
#import "UDUpdater.h"
#import "UDDocument.h"
#import <UDCodeKit/UDCodeKit.h>

/// Check for Updates… in MainMenu.xib's application menu.
static const NSInteger UDCheckForUpdatesTag = 7100;

@interface AppDelegate ()
@property (nonatomic, strong) UDUpdater *updater;
@property (nonatomic, strong, nullable) UDPreferencesController *preferences;
@end

@implementation AppDelegate

- (void)applicationWillFinishLaunching:(NSNotification *)notification {
    // git's credential prompts: asked by UDCode itself (VS Code's askpass)
    NSString *executable = [[NSBundle mainBundle] executablePath];
    if (executable) UDSourceControlSetCredentialEnvironment(UDAskpassEnvironment(executable));

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

- (IBAction)showPreferences:(id)sender {
    if (!self.preferences) self.preferences = [[UDPreferencesController alloc] init];
    [self.preferences showWindow:sender];
}

/// File > Open Folder…: the folder as a project, in a window of its own (the
/// one it has, when it is open already).
- (IBAction)openFolder:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = NO;
    panel.canChooseDirectories = YES;
    panel.allowsMultipleSelection = NO;
    if ([panel runModal] != NSModalResponseOK || panel.URLs.count == 0) return;
    [self openFolderAtURL:panel.URLs.firstObject];
}

- (nullable UDWorkspace *)openFolderAtURL:(NSURL *)url {
    NSDocumentController *documents = [NSDocumentController sharedDocumentController];
    UDProject *project = [[UDProject alloc] initWithFolderURL:url];
    NSString *path = project.folderURL.path;
    for (NSDocument *document in documents.documents) {
        if ([document isKindOfClass:[UDWorkspace class]] &&
            [((UDWorkspace *)document).project.folderURL.path isEqualToString:path]) {
            [document showWindows];
            return (UDWorkspace *)document;
        }
    }
    // no type: a project is a folder, not a file of any of the app's types
    UDWorkspace *workspace = [[UDWorkspace alloc] init];
    workspace.project = project;
    [documents addDocument:workspace];
    [workspace makeWindowControllers];
    [workspace showWindows];
    return workspace;
}

/// Debug > Launch Configuration and Run Task: the key project window's
/// launch.json configurations and tasks.json tasks, as they are when the menu opens.
- (void)menuNeedsUpdate:(NSMenu *)menu {
    BOOL configurations = [menu.title isEqualToString:@"Launch Configuration"];
    if (!configurations && ![menu.title isEqualToString:@"Run Task"]) return;
    // GNUstep updates a menu as its items change, which asks again: once is enough
    static BOOL updating = NO;
    if (updating) return;
    updating = YES;
    [menu removeAllItems];
    // the key window's project, else the main window's, else the frontmost one's
    UDTasks *tasks = nil;
    NSMutableArray<NSWindow *> *windows = [NSMutableArray array];
    if ([NSApp keyWindow]) [windows addObject:[NSApp keyWindow]];
    if ([NSApp mainWindow]) [windows addObject:[NSApp mainWindow]];
    [windows addObjectsFromArray:[NSApp orderedWindows]];
    for (NSWindow *window in windows) {
        id controller = window.windowController;
        tasks = [controller respondsToSelector:@selector(tasks)] ? [controller tasks] : nil;
        if (tasks) break;
    }
    NSArray *names = configurations ? [tasks.configurations valueForKey:@"name"] : [tasks.tasks valueForKey:@"label"];
    for (NSString *name in names) {
        NSMenuItem *item = [menu addItemWithTitle:name
                                           action:configurations ? @selector(selectLaunchConfiguration:) : @selector(runTask:)
                                    keyEquivalent:@""];
        item.representedObject = name;
    }
    if (!names.count) {
        // no action: disabled
        [menu addItemWithTitle:configurations ? @"No launch.json" : @"No tasks.json" action:NULL keyEquivalent:@""];
    }
    updating = NO;
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
