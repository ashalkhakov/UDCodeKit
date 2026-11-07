/*---------------------------------------------------------------------------------------------
 *  UDExtensionsWindowController.h
 *
 *  UDCode > Extensions… (⇧⌘X, VS Code's): every extension, built in and
 *  installed (UDInstalledExtensions), whether it is loaded or why not, and
 *  whether its feed has an update (UDExtensionUpdates); a package (.udcx)
 *  installed, one uninstalled, disabled or enabled again, updated.
 *  What changes applies when UDCode starts again, as it says. Laid out in
 *  UDExtensions.xib.
 *--------------------------------------------------------------------------------------------*/

#import <Cocoa/Cocoa.h>
#import "UDInstalledExtensions.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDExtensionsWindowController : NSWindowController <NSTableViewDataSource, NSTableViewDelegate>

- (instancetype)init;

@property (nonatomic, weak, readonly) IBOutlet NSTableView *table;
@property (nonatomic, weak, readonly) IBOutlet NSTextField *detailsField;
@property (nonatomic, weak, readonly) IBOutlet NSButton *uninstallButton;
@property (nonatomic, weak, readonly) IBOutlet NSButton *disableButton;
@property (nonatomic, weak, readonly) IBOutlet NSButton *updateButton;
@property (nonatomic, weak, readonly) IBOutlet NSButton *automaticButton;

/// What the table shows: those found when UDCode started (the registry's),
/// then those installed since.
@property (nonatomic, readonly, copy) NSArray<UDExtensionInfo *> *rows;
/// A row's state, as its State column says it.
- (NSString *)stateOfRow:(NSInteger)row;
/// The rows read again.
- (void)reload;

/// A package chosen with an open panel, installed.
- (IBAction)installPackage:(nullable id)sender;
/// The selected one uninstalled (one built in can't be).
- (IBAction)uninstall:(nullable id)sender;
/// The selected one disabled, or enabled again.
- (IBAction)toggleDisabled:(nullable id)sender;
/// The selected one's update installed.
- (IBAction)updateSelected:(nullable id)sender;
/// The installed extensions' feeds read now.
- (IBAction)checkForUpdates:(nullable id)sender;
/// Updates installed without asking, or not (the checkbox).
- (IBAction)toggleAutomaticUpdates:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
