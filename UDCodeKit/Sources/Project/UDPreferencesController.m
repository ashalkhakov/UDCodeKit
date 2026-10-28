/*---------------------------------------------------------------------------------------------
 *  UDPreferencesController.m
 *--------------------------------------------------------------------------------------------*/

#import "UDPreferencesController.h"
#import "UDProject.h"
#import <UDCodeKit/UDShell.h>

@interface UDPreferencesController ()
@property (nonatomic, weak) IBOutlet NSTextField *shellField;
@end

@implementation UDPreferencesController

/// The XIB is the framework's, not the app's: compiled on macOS, as it is on GNUstep.
- (instancetype)init {
    NSBundle *bundle = [NSBundle bundleForClass:[UDPreferencesController class]];
    NSString *path = [bundle pathForResource:@"UDPreferences" ofType:@"nib"]
                  ?: [bundle pathForResource:@"UDPreferences" ofType:@"xib"];
    return [super initWithWindowNibPath:path owner:self];
}

/// What the user chose, else (a placeholder) the shell found.
- (void)windowDidLoad {
    [super windowDidLoad];
    _shellField.stringValue = [[NSUserDefaults standardUserDefaults] stringForKey:UDShellDefaultsKey] ?: @"";
    [_shellField.cell setPlaceholderString:UDLoginShellArguments(nil).firstObject ?: @""];
}

- (IBAction)shellChanged:(id)sender {
    NSString *shell = [_shellField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (shell.length) [[NSUserDefaults standardUserDefaults] setObject:shell forKey:UDShellDefaultsKey];
    else [[NSUserDefaults standardUserDefaults] removeObjectForKey:UDShellDefaultsKey];
}

- (IBAction)chooseShell:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    if ([panel runModal] != NSModalResponseOK || !panel.URLs.count) return;
    _shellField.stringValue = [(NSURL *)panel.URLs.firstObject path];
    [self shellChanged:sender];
}

@end
