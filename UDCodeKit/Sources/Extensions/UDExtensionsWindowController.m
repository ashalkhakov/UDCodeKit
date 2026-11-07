/*---------------------------------------------------------------------------------------------
 *  UDExtensionsWindowController.m
 *--------------------------------------------------------------------------------------------*/

#import "UDExtensionsWindowController.h"
#import "UDLanguageModeRegistry.h"
#import "UDExtensionUpdates.h"

@interface UDExtensionsWindowController ()
@property (nonatomic, weak) IBOutlet NSTableView *table;
@property (nonatomic, weak) IBOutlet NSTextField *detailsField;
@property (nonatomic, weak) IBOutlet NSButton *uninstallButton;
@property (nonatomic, weak) IBOutlet NSButton *disableButton;
@property (nonatomic, weak) IBOutlet NSButton *updateButton;
@property (nonatomic, weak) IBOutlet NSButton *automaticButton;
@property (nonatomic, copy) NSArray<UDExtensionInfo *> *rows;
@end

@implementation UDExtensionsWindowController {
    // Found when UDCode started, and the folders of those installed now.
    NSSet<UDExtensionInfo *> *_atStart;
    NSSet<NSString *> *_installedPaths;
    // Each id's version installed now (an update's, since UDCode started).
    NSDictionary<NSString *, UDExtensionInfo *> *_installedByIdentifier;
}

/// The XIB is the framework's, not the app's: compiled on macOS, as it is on GNUstep.
- (instancetype)init {
    NSBundle *bundle = [NSBundle bundleForClass:[UDExtensionsWindowController class]];
    NSString *path = [bundle pathForResource:@"UDExtensions" ofType:@"nib"]
                  ?: [bundle pathForResource:@"UDExtensions" ofType:@"xib"];
    return [super initWithWindowNibPath:path owner:self];
}

- (void)windowDidLoad {
    [super windowDidLoad];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_updatesDidChange:)
                                                 name:UDExtensionUpdatesDidChangeNotification object:nil];
    [self reload];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)_updatesDidChange:(NSNotification *)note {
    [self reload];
}

- (void)showWindow:(id)sender {
    [super showWindow:sender];
    [self reload];
}

- (void)reload {
    NSArray<UDExtensionInfo *> *found = [UDLanguageModeRegistry sharedRegistry].extensionInfos;
    NSArray<UDExtensionInfo *> *installed = [UDInstalledExtensions installed];
    _atStart = [NSSet setWithArray:found];
    _installedPaths = [NSSet setWithArray:[installed valueForKey:@"path"]];
    _installedByIdentifier = [NSDictionary dictionaryWithObjects:installed forKeys:[installed valueForKey:@"identifier"]];
    NSMutableArray *rows = [found mutableCopy];
    NSSet *foundPaths = [NSSet setWithArray:[found valueForKey:@"path"]];
    NSSet *foundIdentifiers = [NSSet setWithArray:[found valueForKey:@"identifier"]];
    // one installed since UDCode started; an update of one running is its row's
    for (UDExtensionInfo *info in installed) {
        if (![foundPaths containsObject:info.path] && ![foundIdentifiers containsObject:info.identifier]) [rows addObject:info];
    }
    NSInteger selected = _table.selectedRow;
    self.rows = rows;
    [_table reloadData];
    if (selected >= 0 && selected < (NSInteger)rows.count) {
        [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)selected] byExtendingSelection:NO];
    }
    _automaticButton.state = [UDExtensionUpdates sharedUpdates].automaticallyUpdates ? NSControlStateValueOn : NSControlStateValueOff;
    [self _selectionChanged];
}

/// Its update, when it is running, its feed has one, and it isn't installed yet.
- (nullable UDExtensionUpdate *)_updateOf:(UDExtensionInfo *)info {
    if (info.location != UDExtensionLocationInstalled || ![_installedPaths containsObject:info.path]) return nil;
    return [[UDExtensionUpdates sharedUpdates] updateForIdentifier:info.identifier];
}

- (nullable UDExtensionInfo *)_selected {
    NSInteger row = _table.selectedRow;
    return row >= 0 && row < (NSInteger)_rows.count ? _rows[row] : nil;
}

- (NSString *)stateOfRow:(NSInteger)row {
    UDExtensionInfo *info = _rows[row];
    BOOL disabled = [UDInstalledExtensions isDisabled:info.identifier];
    if (info.location == UDExtensionLocationInstalled && ![_installedPaths containsObject:info.path]) {
        UDExtensionInfo *now = _installedByIdentifier[info.identifier];
        if (now) return [NSString stringWithFormat:@"Updated to %@: used when UDCode starts again", now.version];
        return @"Uninstalled: removed when UDCode starts again";
    }
    if (![_atStart containsObject:info]) {
        if (info.problem) return [@"Not loadable: " stringByAppendingString:info.problem];
        return disabled ? @"Installed, disabled" : @"Installed: loaded when UDCode starts again";
    }
    UDExtensionUpdate *update = [self _updateOf:info];
    if (update && info.loaded && !disabled) return [NSString stringWithFormat:@"Enabled; %@ is available", update.version];
    if (info.loaded) return disabled ? @"Disabled when UDCode starts again" : @"Enabled";
    if (info.problem) return [@"Not loaded: " stringByAppendingString:info.problem];
    return disabled ? @"Disabled" : @"Enabled when UDCode starts again";
}

// ---------------------------------------------------------------------------
// MARK: - The table
// ---------------------------------------------------------------------------

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    return (NSInteger)_rows.count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    UDExtensionInfo *info = _rows[row];
    NSString *key = column.identifier;
    if ([key isEqualToString:@"name"]) return info.displayName;
    if ([key isEqualToString:@"version"]) return info.version ?: @"";
    if ([key isEqualToString:@"location"]) return info.location == UDExtensionLocationBuiltIn ? @"Built in" : @"Installed";
    return [self stateOfRow:row];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    [self _selectionChanged];
}

/// The selected one's details, and what can be done with it.
- (void)_selectionChanged {
    UDExtensionInfo *info = [self _selected];
    BOOL uninstalled = info && info.location == UDExtensionLocationInstalled && ![_installedPaths containsObject:info.path];
    _uninstallButton.enabled = info && info.location == UDExtensionLocationInstalled && !uninstalled;
    _disableButton.enabled = info && !uninstalled;
    _disableButton.title = info && [UDInstalledExtensions isDisabled:info.identifier] ? @"Enable" : @"Disable";
    _updateButton.enabled = info && [self _updateOf:info] != nil;
    if (!info) {
        _detailsField.stringValue = @"";
        return;
    }
    NSMutableArray *lines = [NSMutableArray array];
    [lines addObject:[NSString stringWithFormat:@"%@ (%@)%@", info.displayName, info.identifier,
                                                info.publisher ? [@", by " stringByAppendingString:info.publisher] : @""]];
    if (info.summary.length) [lines addObject:info.summary];
    if (info.modeNames.count) [lines addObject:[@"Modes: " stringByAppendingString:[info.modeNames componentsJoinedByString:@", "]]];
    NSMutableArray *facts = [NSMutableArray array];
    if (info.license) [facts addObject:[@"Licence: " stringByAppendingString:info.license]];
    if (info.engine) [facts addObject:[@"For UDCode " stringByAppendingString:info.engine]];
    if (info.targetPlatform) [facts addObject:[@"Built for " stringByAppendingString:info.targetPlatform]];
    if (facts.count) [lines addObject:[facts componentsJoinedByString:@" · "]];
    [lines addObject:info.path];
    UDExtensionUpdate *update = [self _updateOf:info];
    if (update) [lines addObject:[NSString stringWithFormat:@"Update: %@ (from %@)", update.version, info.updatesURL.absoluteString]];
    if (info.problem) [lines addObject:info.problem];
    _detailsField.stringValue = [lines componentsJoinedByString:@"\n"];
}

// ---------------------------------------------------------------------------
// MARK: - Actions
// ---------------------------------------------------------------------------

- (void)_showError:(NSError *)error {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = @"The extension couldn't be installed or uninstalled.";
    alert.informativeText = error.localizedDescription ?: @"";
    [alert addButtonWithTitle:@"OK"];
    [alert runModal];
}

- (IBAction)installPackage:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowedFileTypes = @[ @"udcx" ];
    if ([panel runModal] != NSModalResponseOK || !panel.URLs.count) return;
    NSError *error = nil;
    UDExtensionInfo *info = [UDInstalledExtensions installPackageAtPath:[(NSURL *)panel.URLs.firstObject path] error:&error];
    if (!info) [self _showError:error];
    [self reload];
    NSUInteger row = info ? [[_rows valueForKey:@"path"] indexOfObject:info.path] : NSNotFound;
    if (row != NSNotFound) [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
}

- (IBAction)uninstall:(id)sender {
    UDExtensionInfo *info = [self _selected];
    if (!info) return;
    NSInteger row = _table.selectedRow;
    NSError *error = nil;
    if (![UDInstalledExtensions uninstall:info.identifier error:&error]) [self _showError:error];
    [self reload];
    if (row < (NSInteger)_rows.count) [_table selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
}

- (IBAction)updateSelected:(id)sender {
    UDExtensionInfo *info = [self _selected];
    UDExtensionUpdate *update = info ? [self _updateOf:info] : nil;
    if (!update) return;
    _updateButton.enabled = NO;
    [[UDExtensionUpdates sharedUpdates] installUpdate:update completion:^(UDExtensionInfo *installed, NSError *error) {
        if (!installed && error) [self _showError:error];
        [self reload];
    }];
}

- (IBAction)checkForUpdates:(id)sender {
    [[UDExtensionUpdates sharedUpdates] checkNowCompletion:^(NSArray<UDExtensionUpdate *> *updates) {
        [self reload];
    }];
}

- (IBAction)toggleAutomaticUpdates:(id)sender {
    [UDExtensionUpdates sharedUpdates].automaticallyUpdates = _automaticButton.state == NSControlStateValueOn;
}

- (IBAction)toggleDisabled:(id)sender {
    UDExtensionInfo *info = [self _selected];
    if (!info) return;
    [UDInstalledExtensions setDisabled:![UDInstalledExtensions isDisabled:info.identifier] identifier:info.identifier];
    [_table reloadData];
    [self _selectionChanged];
}

@end
