//
//  UDUpdater.m
//  UDCode
//
//  Sparkle on macOS; on GNUstep the AppImage is updated from outside it
//  (UDUpdater.h).
//

#import "UDUpdater.h"
#ifdef __APPLE__
#import <Sparkle/Sparkle.h>
#endif

@implementation UDUpdater {
#ifdef __APPLE__
    SPUStandardUpdaterController *_controller;
#endif
}

- (instancetype)initStarting:(BOOL)start {
    if (!(self = [super init])) return nil;
#ifdef __APPLE__
    _controller = [[SPUStandardUpdaterController alloc] initWithStartingUpdater:start
                                                                updaterDelegate:nil
                                                             userDriverDelegate:nil];
#endif
    return self;
}

- (BOOL)available {
#ifdef __APPLE__
    return YES;
#else
    return NO;
#endif
}

- (BOOL)canCheckForUpdates {
#ifdef __APPLE__
    return _controller.updater.canCheckForUpdates;
#else
    return NO;
#endif
}

- (IBAction)checkForUpdates:(id)sender {
#ifdef __APPLE__
    [_controller checkForUpdates:sender];
#endif
}

@end
