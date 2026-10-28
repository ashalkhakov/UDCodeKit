//
//  UDUpdater.m (GNUstep)
//  UDCode
//
//  The stack's GSUpdater (UDUpdater.h).
//

#import "../UDUpdater.h"
#import <GSUpdater/GSUpdater.h>

@implementation UDUpdater {
    GSUpdater *_updater;
}

- (instancetype)initStarting:(BOOL)start {
    if (!(self = [super init])) return nil;
    _updater = [[GSUpdater alloc] initStarting:start];
    return self;
}

- (BOOL)available {
    return [_updater available];
}

- (BOOL)canCheckForUpdates {
    return [_updater canCheckForUpdates];
}

- (IBAction)checkForUpdates:(id)sender {
    [_updater checkForUpdates:sender];
}

@end
