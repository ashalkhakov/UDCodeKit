/*---------------------------------------------------------------------------------------------
 *  UDFileWatcherSystem.m (macOS: FSEvents)
 *--------------------------------------------------------------------------------------------*/

#import "../UDFileWatcherSystem.h"
#import <CoreServices/CoreServices.h>

/// FSEvents' callback, on the main queue: each path that changed.
static void UDFileWatcherEvents(ConstFSEventStreamRef stream, void *info, size_t count, void *paths,
                                const FSEventStreamEventFlags flags[], const FSEventStreamEventId ids[]) {
    UDFileWatcher *watcher = (__bridge UDFileWatcher *)info;
    char **list = paths;
    for (size_t i = 0; i < count; i++) [watcher _saw:[NSString stringWithUTF8String:list[i]]];
}

@implementation UDFileWatcherSystem {
    FSEventStreamRef _stream;
}

- (instancetype)initWithWatcher:(UDFileWatcher *)watcher {
    if (!(self = [super init])) return nil;
    /* the watcher outlives its system half: it stops it as it goes */
    FSEventStreamContext context = { 0, (__bridge void *)watcher, NULL, NULL, NULL };
    CFArrayRef paths = (__bridge CFArrayRef)@[ watcher.folderURL.path ];
    // each file (not just its folder), with no latency of the stream's own: the watcher's coalesces
    _stream = FSEventStreamCreate(NULL, UDFileWatcherEvents, &context, paths, kFSEventStreamEventIdSinceNow, 0.05,
                                  kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer);
    if (!_stream) return nil;
    FSEventStreamSetDispatchQueue(_stream, dispatch_get_main_queue());
    if (!FSEventStreamStart(_stream)) {
        [self stop];
        return nil;
    }
    return self;
}

- (void)stop {
    if (!_stream) return;
    FSEventStreamStop(_stream);
    FSEventStreamInvalidate(_stream);
    FSEventStreamRelease(_stream);
    _stream = NULL;
}

@end
