/*---------------------------------------------------------------------------------------------
 *  UDDebugBarViewController.m
 *--------------------------------------------------------------------------------------------*/

#import "UDDebugBarViewController.h"
#import <objc/runtime.h>

@interface UDDebugBarViewController ()
@property (nonatomic, weak) IBOutlet NSButton *continueButton;
@property (nonatomic, weak) IBOutlet NSButton *stepOverButton;
@property (nonatomic, weak) IBOutlet NSButton *stepIntoButton;
@property (nonatomic, weak) IBOutlet NSButton *stepOutButton;
@property (nonatomic, weak) IBOutlet NSButton *stepBackButton;
@property (nonatomic, weak) IBOutlet NSButton *reverseContinueButton;
@property (nonatomic, weak) IBOutlet NSButton *stopButton;
@property (nonatomic, weak) IBOutlet NSTextField *statusLabel;
@end

@implementation UDDebugBarViewController {
    CGFloat _stopX, _statusX;      // where the XIB has them, the step back buttons showing
}

- (instancetype)init {
    return [super initWithNibName:@"UDDebugBar" bundle:[NSBundle bundleForClass:[UDDebugBarViewController class]]];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _stopX = NSMinX(_stopButton.frame);
    _statusX = NSMinX(_statusLabel.frame);
    [self _update];
}

- (void)setSession:(UDDebugSession *)session {
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    if (_session) [center removeObserver:self name:nil object:_session];
    _session = session;
    if (session) {
        [center addObserver:self selector:@selector(_sessionDidChange:)
                       name:UDDebugSessionDidChangeStateNotification object:session];
        [center addObserver:self selector:@selector(_sessionDidChange:)
                       name:UDDebugSessionDidSelectFrameNotification object:session];
    }
    (void)self.view;
    [self _update];
}

- (void)_sessionDidChange:(NSNotification *)note {
    [self _update];
}

/// The buttons as the session allows, the one that continues or pauses as
/// it is stopped or running, and where it stands.
- (void)_update {
    UDDebugSession *session = _session;
    BOOL running = session.state == UDDebugSessionStateRunning || session.state == UDDebugSessionStateStarting;
    _continueButton.title = running ? @"❚❚" : @"▶";
    _continueButton.toolTip = running ? @"Pause" : @"Continue";
    _continueButton.enabled = session.canContinue || session.canPause;
    _stepOverButton.enabled = session.canStep;
    _stepIntoButton.enabled = session.canStep;
    _stepOutButton.enabled = session.canStep;
    _stopButton.enabled = session.canStop;
    _statusLabel.stringValue = [self _status];
    [self _showStepBack:session.client.supportsStepBack && session.state != UDDebugSessionStateEnded];
}

/// Step back and reverse continue, between step out and stop, or not
/// there at all (stop and the status closing up).
- (void)_showStepBack:(BOOL)shown {
    _stepBackButton.hidden = !shown;
    _reverseContinueButton.hidden = !shown;
    _stepBackButton.enabled = _session.canStepBack;
    _reverseContinueButton.enabled = _session.canStepBack;
    // Stop where step back is.
    CGFloat shift = shown ? 0.0 : _stopX - NSMinX(_stepBackButton.frame);
    NSRect stop = _stopButton.frame, status = _statusLabel.frame;
    stop.origin.x = _stopX - shift;
    CGFloat right = NSMaxX(status);
    status.origin.x = _statusX - shift;
    status.size.width = right - status.origin.x;
    _stopButton.frame = stop;
    _statusLabel.frame = status;
}

- (NSString *)_status {
    UDDebugSession *session = _session;
    if (!session) return @"";
    switch (session.state) {
        case UDDebugSessionStateStarting: return @"Starting…";
        case UDDebugSessionStateRunning:  return @"Running";
        case UDDebugSessionStateEnded:    return @"Finished";
        case UDDebugSessionStateStopped: break;
    }
    UDDebugStackFrame *frame = session.selectedFrame;
    UDDebugThread *thread = session.selectedThread;
    if (!frame) return thread.stopReason ? [NSString stringWithFormat:@"Paused (%@)", thread.stopReason] : @"Paused";
    NSMutableString *status = [NSMutableString stringWithFormat:@"%@ › %@", thread.name, frame.name];
    if (frame.path) [status appendFormat:@" — %@:%ld", frame.path.lastPathComponent, (long)frame.line];
    if (thread.stopReason && thread.stopDescription) [status appendFormat:@" (%@: %@)", thread.stopReason, thread.stopDescription];
    else if (thread.stopReason) [status appendFormat:@" (%@)", thread.stopReason];
    return status;
}

// ---------------------------------------------------------------------------
// MARK: - Actions
// ---------------------------------------------------------------------------

/// With sel_isEqual: on GNUstep's runtime selectors are typed, and one made
/// elsewhere (a menu item's, from its XIB) need not be this file's pointer.
- (BOOL)canPerformAction:(SEL)action {
    UDDebugSession *session = _session;
    if (sel_isEqual(action, @selector(continueOrPause:))) return session.canContinue || session.canPause;
    if (sel_isEqual(action, @selector(stepOver:)) || sel_isEqual(action, @selector(stepInto:)) ||
        sel_isEqual(action, @selector(stepOut:))) return session.canStep;
    if (sel_isEqual(action, @selector(stepBack:)) || sel_isEqual(action, @selector(reverseContinue:))) return session.canStepBack;
    if (sel_isEqual(action, @selector(stop:))) return session.canStop;
    return NO;
}

- (IBAction)continueOrPause:(id)sender {
    if (_session.canPause) [_session pause];
    else [_session continueExecution];
}

- (IBAction)stepOver:(id)sender { [_session stepOver]; }
- (IBAction)stepInto:(id)sender { [_session stepInto]; }
- (IBAction)stepOut:(id)sender  { [_session stepOut]; }
- (IBAction)stepBack:(id)sender { [_session stepBack]; }
- (IBAction)reverseContinue:(id)sender { [_session reverseContinue]; }
- (IBAction)stop:(id)sender     { [_session stop]; }

@end
