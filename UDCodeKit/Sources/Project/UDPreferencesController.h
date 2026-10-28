/*---------------------------------------------------------------------------------------------
 *  UDPreferencesController.h
 *
 *  UDCode > Preferences…: what the user chooses for every project. The
 *  shell builds and terminals run in (UDShellDefaultsKey), when the one found
 *  is not it: MSYS2 somewhere else on Windows, another MSYS2 environment, a
 *  shell other than $SHELL. Empty, the field shows the one found; a
 *  project's settings may name another ("shell"). Kept as it is typed.
 *  Laid out in UDPreferences.xib.
 *--------------------------------------------------------------------------------------------*/

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface UDPreferencesController : NSWindowController

- (instancetype)init;

@property (nonatomic, weak, readonly) IBOutlet NSTextField *shellField;

/// The shell field's: kept in the user defaults (empty: removed).
- (IBAction)shellChanged:(nullable id)sender;
/// The shell, chosen with an open panel.
- (IBAction)chooseShell:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
