/*---------------------------------------------------------------------------------------------
 *  UDProjectSettingsController.h
 *
 *  A project's settings as a sheet (Debug > Project Settings…), for what can't
 *  be guessed: its build and clean commands, the program it runs, its
 *  arguments and folder, the debugger, the shell its commands run in. The fields show what is in effect on
 *  this system (what the folder says, or what is guessed, placeholders), and
 *  OK writes what differs into this system's section of the folder's
 *  settings ("macos" or "gnustep"), so the other system's stay as they are.
 *  Laid out in UDProjectSettings.xib.
 *--------------------------------------------------------------------------------------------*/

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class UDProject;

@interface UDProjectSettingsController : NSWindowController

- (instancetype)init;

/// The sheet over @a window, for @a project; when it ends, @a action is sent
/// to @a target with this controller (its returnCode says how).
- (void)beginSheetForWindow:(NSWindow *)window project:(UDProject *)project target:(nullable id)target action:(nullable SEL)action;

@property (nonatomic, strong, readonly, nullable) UDProject *project;
/// NSModalResponseOK when it was saved.
@property (nonatomic, readonly) NSModalResponse returnCode;

@property (nonatomic, weak, readonly) IBOutlet NSTextField *buildField;
@property (nonatomic, weak, readonly) IBOutlet NSTextField *cleanField;
@property (nonatomic, weak, readonly) IBOutlet NSTextField *programField;
@property (nonatomic, weak, readonly) IBOutlet NSTextField *argumentsField;
@property (nonatomic, weak, readonly) IBOutlet NSTextField *directoryField;
/// Automatic, lldb, gdb.
@property (nonatomic, weak, readonly) IBOutlet NSPopUpButton *debuggerPopUp;
@property (nonatomic, weak, readonly) IBOutlet NSTextField *shellField;

- (IBAction)ok:(nullable id)sender;
- (IBAction)cancel:(nullable id)sender;
/// The program, chosen with an open panel.
- (IBAction)chooseProgram:(nullable id)sender;
/// The shell, chosen with an open panel.
- (IBAction)chooseShell:(nullable id)sender;

/// What OK writes, from the fields (for the tests): the folder's settings
/// with this system's section set to what differs from the shared ones.
- (NSDictionary *)settingsFromFields;

@end

NS_ASSUME_NONNULL_END
