/*---------------------------------------------------------------------------------------------
 *  UDProjectSettingsController.m
 *--------------------------------------------------------------------------------------------*/

#import "UDProjectSettingsController.h"
#import "UDDebugger.h"
#import "UDProject.h"
#import <UDCodeKit/UDShell.h>


@interface UDProjectSettingsController ()
@property (nonatomic, weak) IBOutlet NSTextField *buildField;
@property (nonatomic, weak) IBOutlet NSTextField *cleanField;
@property (nonatomic, weak) IBOutlet NSTextField *programField;
@property (nonatomic, weak) IBOutlet NSTextField *argumentsField;
@property (nonatomic, weak) IBOutlet NSTextField *directoryField;
@property (nonatomic, weak) IBOutlet NSPopUpButton *debuggerPopUp;
@property (nonatomic, weak) IBOutlet NSTextField *shellField;
@property (nonatomic, strong, readwrite, nullable) UDProject *project;
@property (nonatomic, readwrite) NSModalResponse returnCode;
@end

@implementation UDProjectSettingsController {
    __weak id _target;
    SEL _action;
}

/// The XIB is the framework's, not the app's: compiled on macOS, as it is on GNUstep.
- (instancetype)init {
    NSBundle *bundle = [NSBundle bundleForClass:[UDProjectSettingsController class]];
    NSString *path = [bundle pathForResource:@"UDProjectSettings" ofType:@"nib"]
                  ?: [bundle pathForResource:@"UDProjectSettings" ofType:@"xib"];
    return [super initWithWindowNibPath:path owner:self];
}

- (void)beginSheetForWindow:(NSWindow *)window project:(UDProject *)project target:(id)target action:(SEL)action {
    _project = project;
    _target = target;
    _action = action;
    _returnCode = NSModalResponseCancel;
    (void)self.window;
    [self _fillFields];
    [NSApp beginSheet:self.window modalForWindow:window modalDelegate:self
       didEndSelector:@selector(_sheetDidEnd:returnCode:contextInfo:) contextInfo:NULL];
}

- (void)_sheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo {
    [sheet orderOut:self];
    id target = _target;
    if (target && _action) [NSApp sendAction:_action to:target from:self];
}

/// What this system's section says, else what the folder says for both,
/// else (a placeholder) what is guessed.
- (void)_fillFields {
    NSDictionary *settings = _project.settings;
    NSDictionary *mine = [settings[UDProjectPlatformKey] isKindOfClass:[NSDictionary class]] ? settings[UDProjectPlatformKey] : @{};
    NSDictionary *inferred = _project.inferredSettings;
    NSDictionary *run = [self _run:mine] ?: [self _run:settings] ?: @{};
    NSDictionary *inferredRun = [self _run:inferred] ?: @{};
    [self _field:_buildField value:mine[@"build"] ?: settings[@"build"] guess:inferred[@"build"]];
    [self _field:_cleanField value:mine[@"clean"] ?: settings[@"clean"] guess:inferred[@"clean"]];
    [self _field:_programField value:run[@"program"] ?: [self _run:settings][@"program"] guess:inferredRun[@"program"] ?: _project.inferredProgram];
    id arguments = run[@"arguments"];
    if ([arguments isKindOfClass:[NSArray class]]) arguments = [arguments componentsJoinedByString:@" "];
    [self _field:_argumentsField value:arguments guess:nil];
    [self _field:_directoryField value:run[@"directory"] guess:@"The project's folder"];
    [self _field:_shellField value:mine[@"shell"] ?: settings[@"shell"]
           guess:[UDProject userShell] ?: UDLoginShellArguments(nil).firstObject];
    // Automatic (the XIB's), then the debuggers the extensions know, by name
    while (_debuggerPopUp.numberOfItems > 1) [_debuggerPopUp removeItemAtIndex:1];
    for (Class each in [UDDebugger classes]) {
        [_debuggerPopUp addItemWithTitle:[each displayName]];
        _debuggerPopUp.lastItem.representedObject = [each name];
    }
    id debugger = mine[@"debugger"] ?: settings[@"debugger"];
    NSInteger index = [debugger isKindOfClass:[NSString class]] ? [_debuggerPopUp indexOfItemWithRepresentedObject:debugger] : -1;
    [_debuggerPopUp selectItemAtIndex:index > 0 ? index : 0];
}

- (nullable NSDictionary *)_run:(NSDictionary *)settings {
    return [settings[@"run"] isKindOfClass:[NSDictionary class]] ? settings[@"run"] : nil;
}

- (void)_field:(NSTextField *)field value:(id)value guess:(nullable NSString *)guess {
    field.stringValue = [value isKindOfClass:[NSString class]] ? value : @"";
    [field.cell setPlaceholderString:guess ?: @""];
}

- (NSDictionary *)settingsFromFields {
    NSMutableDictionary *settings = [_project.settings mutableCopy] ?: [NSMutableDictionary dictionary];
    NSMutableDictionary *mine = [NSMutableDictionary dictionary];
    NSMutableDictionary *run = [NSMutableDictionary dictionary];
    NSArray *pairs = @[ @[ _buildField, @"build" ], @[ _cleanField, @"clean" ], @[ _shellField, @"shell" ] ];
    for (NSArray *pair in pairs) {
        NSString *value = [((NSTextField *)pair[0]).stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (value.length) mine[pair[1]] = value;
    }
    NSArray *runPairs = @[ @[ _programField, @"program" ], @[ _argumentsField, @"arguments" ], @[ _directoryField, @"directory" ] ];
    for (NSArray *pair in runPairs) {
        NSString *value = [((NSTextField *)pair[0]).stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (value.length) run[pair[1]] = value;
    }
    if (run.count) mine[@"run"] = run;
    NSString *debugger = _debuggerPopUp.selectedItem.representedObject;
    if ([debugger isKindOfClass:[NSString class]]) mine[@"debugger"] = debugger;
    if (mine.count) settings[UDProjectPlatformKey] = mine;
    else [settings removeObjectForKey:UDProjectPlatformKey];
    return settings;
}

/// The sheet ended: GNUstep's modal loop notices only with the next event, so one comes.
- (void)_endSheet:(NSModalResponse)code {
    [NSApp endSheet:self.window returnCode:code];
    NSEvent *wake = [NSEvent otherEventWithType:NSEventTypeApplicationDefined location:NSZeroPoint modifierFlags:0
                                      timestamp:0 windowNumber:0 context:nil subtype:0 data1:0 data2:0];
    [NSApp postEvent:wake atStart:NO];
}

- (IBAction)ok:(id)sender {
    NSError *error = nil;
    if (![_project setSettings:[self settingsFromFields] error:&error]) {
        [NSApp presentError:error];
        return;
    }
    _returnCode = NSModalResponseOK;
    [self _endSheet:NSModalResponseOK];
}

- (IBAction)cancel:(id)sender {
    _returnCode = NSModalResponseCancel;
    [self _endSheet:NSModalResponseCancel];
}

- (IBAction)chooseProgram:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.directoryURL = _project.folderURL;
    if ([panel runModal] != NSModalResponseOK || !panel.URLs.count) return;
    NSString *path = [(NSURL *)panel.URLs.firstObject path];
    NSString *folder = [_project.folderURL.path stringByAppendingString:@"/"];
    // in the project: relative, so it goes with it
    _programField.stringValue = [path hasPrefix:folder] ? [path substringFromIndex:folder.length] : path;
}

- (IBAction)chooseShell:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    if ([panel runModal] != NSModalResponseOK || !panel.URLs.count) return;
    _shellField.stringValue = [(NSURL *)panel.URLs.firstObject path];
}

@end
