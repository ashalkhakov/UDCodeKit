/*---------------------------------------------------------------------------------------------
 *  UDDebugBarViewController.h
 *
 *  Xcode's debug bar, over the debug area while a session runs: continue or
 *  pause (one button, as the session is stopped or running), step over,
 *  step into, step out, step back and reverse continue (only when the
 *  adapter supportsStepBack, as VS Code shows them), stop, and where the
 *  session stands ("Running", "main › level1 — file.script:12
 *  (breakpoint)", "… (exception: Error: boom)").
 *
 *  Laid out in UDDebugBar.xib. A host puts its view where it goes (above
 *  UDDebugAreaViewController's) and gives it the session; its menu items
 *  can send the same actions here.
 *--------------------------------------------------------------------------------------------*/

#import <Cocoa/Cocoa.h>
#import "UDDebugSession.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDDebugBarViewController : NSViewController

- (instancetype)init;

/// The session the buttons act on and the bar shows; nil: every button off.
@property (nonatomic, strong, nullable) UDDebugSession *session;

@property (nonatomic, weak, readonly) IBOutlet NSButton *continueButton;
@property (nonatomic, weak, readonly) IBOutlet NSButton *stepOverButton;
@property (nonatomic, weak, readonly) IBOutlet NSButton *stepIntoButton;
@property (nonatomic, weak, readonly) IBOutlet NSButton *stepOutButton;
/// Hidden unless the session's adapter supports stepping back.
@property (nonatomic, weak, readonly) IBOutlet NSButton *stepBackButton;
@property (nonatomic, weak, readonly) IBOutlet NSButton *reverseContinueButton;
@property (nonatomic, weak, readonly) IBOutlet NSButton *stopButton;
@property (nonatomic, weak, readonly) IBOutlet NSTextField *statusLabel;

/// Continue when stopped, pause when running.
- (IBAction)continueOrPause:(nullable id)sender;
- (IBAction)stepOver:(nullable id)sender;
- (IBAction)stepInto:(nullable id)sender;
- (IBAction)stepOut:(nullable id)sender;
- (IBAction)stepBack:(nullable id)sender;
- (IBAction)reverseContinue:(nullable id)sender;
- (IBAction)stop:(nullable id)sender;

/// Whether @a action (one of the above) may be sent now; menu items
/// validate with it.
- (BOOL)canPerformAction:(SEL)action;

@end

NS_ASSUME_NONNULL_END
