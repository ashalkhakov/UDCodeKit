/*---------------------------------------------------------------------------------------------
 *  UDFileWatcher.m
 *--------------------------------------------------------------------------------------------*/

#import "UDFileWatcher.h"

#ifdef __APPLE__
#import <CoreServices/CoreServices.h>
#else
#include <sys/inotify.h>
#include <unistd.h>
#include <limits.h>
#endif

/// The run loop modes a change is told in: an app's while a sheet or a drag is
/// up too (AppKit's names, whose values these are; this is Foundation).
static NSArray<NSString *> *UDWatcherModes(void) {
    return @[ NSDefaultRunLoopMode, @"NSModalPanelRunLoopMode", @"NSEventTrackingRunLoopMode" ];
}

@interface UDFileWatcher ()
- (void)_saw:(NSString *)path;
@end

#ifdef __APPLE__
/// FSEvents' callback, on the main queue: each path that changed.
static void UDFileWatcherEvents(ConstFSEventStreamRef stream, void *info, size_t count, void *paths,
                                const FSEventStreamEventFlags flags[], const FSEventStreamEventId ids[]) {
    UDFileWatcher *watcher = (__bridge UDFileWatcher *)info;
    char **list = paths;
    for (size_t i = 0; i < count; i++) [watcher _saw:[NSString stringWithUTF8String:list[i]]];
}
#endif

@implementation UDFileWatcher {
    NSSet<NSString *> *_ignored;
    NSMutableSet<NSString *> *_pending;
#ifdef __APPLE__
    FSEventStreamRef _stream;
#else
    int _inotify;
    NSFileHandle *_reading;
    NSMutableDictionary<NSNumber *, NSString *> *_folders;   // inotify's watch, its folder
#endif
}

- (instancetype)initWithFolderURL:(NSURL *)folderURL ignoredNames:(NSSet<NSString *> *)ignoredNames {
    if (!(self = [super init])) return nil;
    _folderURL = [folderURL copy];
    _ignored = [ignoredNames copy] ?: [NSSet setWithObjects:@".git", @".svn", @".hg", nil];
    _pending = [NSMutableSet set];
    _latency = 0.2;
    [self _start];
    return self;
}

- (void)dealloc {
    [self stop];
}

/// Whether @a path is in a folder not watched below (".git/objects/…").
- (BOOL)_isIgnored:(NSString *)path {
    NSString *root = _folderURL.path;
    if (![path hasPrefix:root]) return YES;
    for (NSString *component in [[path substringFromIndex:root.length] pathComponents]) {
        if ([_ignored containsObject:component]) return YES;
    }
    return NO;
}

/// A change: told once the changes stop.
- (void)_saw:(NSString *)path {
    // (not standardized: on macOS that takes /private off, and the folder has it)
    if ([path hasSuffix:@"/"] && path.length > 1) path = [path substringToIndex:path.length - 1];
    if ([self _isIgnored:path]) return;
    [_pending addObject:path];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(_tell) object:nil];
    [self performSelector:@selector(_tell) withObject:nil afterDelay:_latency
                  inModes:UDWatcherModes()];
}

- (void)_tell {
    if (!_pending.count) return;
    NSSet *paths = [_pending copy];
    [_pending removeAllObjects];
    [_delegate fileWatcher:self didSeeChangesAtPaths:paths];
}

#ifdef __APPLE__

- (void)_start {
    FSEventStreamContext context = { 0, (__bridge void *)self, NULL, NULL, NULL };
    CFArrayRef paths = (__bridge CFArrayRef)@[ _folderURL.path ];
    // each file (not just its folder), with no latency of the stream's own: ours coalesces
    _stream = FSEventStreamCreate(NULL, UDFileWatcherEvents, &context, paths, kFSEventStreamEventIdSinceNow, 0.05,
                                  kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer);
    if (!_stream) return;
    FSEventStreamSetDispatchQueue(_stream, dispatch_get_main_queue());
    _watching = FSEventStreamStart(_stream);
}

- (void)stop {
    if (!_stream) return;
    FSEventStreamStop(_stream);
    FSEventStreamInvalidate(_stream);
    FSEventStreamRelease(_stream);
    _stream = NULL;
    _watching = NO;
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
}

#else

/// inotify watches a folder at a time: each one of the tree, and each made later.
- (void)_watchFolder:(NSString *)folder {
    if ([self _isIgnored:folder] && ![folder isEqualToString:_folderURL.path]) return;
    int watch = inotify_add_watch(_inotify, folder.fileSystemRepresentation,
                                  IN_CREATE | IN_DELETE | IN_MODIFY | IN_CLOSE_WRITE | IN_MOVED_FROM | IN_MOVED_TO |
                                  IN_DELETE_SELF | IN_MOVE_SELF | IN_ONLYDIR);
    if (watch < 0) return;
    _folders[@(watch)] = folder;
    for (NSString *name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:folder error:NULL]) {
        if ([_ignored containsObject:name]) continue;
        NSString *path = [folder stringByAppendingPathComponent:name];
        BOOL directory = NO;
        if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&directory] && directory) {
            [self _watchFolder:path];
        }
    }
}

- (void)_start {
    _inotify = inotify_init1(IN_NONBLOCK | IN_CLOEXEC);
    if (_inotify < 0) return;
    _folders = [NSMutableDictionary dictionary];
    [self _watchFolder:_folderURL.path.stringByStandardizingPath];
    _reading = [[NSFileHandle alloc] initWithFileDescriptor:_inotify closeOnDealloc:NO];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_didRead:)
                                                 name:NSFileHandleReadCompletionNotification object:_reading];
    [_reading readInBackgroundAndNotify];
    _watching = YES;
}

- (void)_didRead:(NSNotification *)note {
    NSData *data = note.userInfo[NSFileHandleNotificationDataItem];
    const char *bytes = data.bytes;
    NSUInteger at = 0;
    while (at + sizeof(struct inotify_event) <= data.length) {
        const struct inotify_event *event = (const struct inotify_event *)(bytes + at);
        at += sizeof(struct inotify_event) + event->len;
        NSString *folder = _folders[@(event->wd)];
        if (!folder) continue;
        if (event->mask & (IN_DELETE_SELF | IN_IGNORED)) {
            [_folders removeObjectForKey:@(event->wd)];
            [self _saw:folder];
            continue;
        }
        NSString *path = event->len ? [folder stringByAppendingPathComponent:[NSString stringWithUTF8String:event->name]] : folder;
        [self _saw:path];
        [self _saw:folder];
        // a folder made (or moved in): watched too
        if ((event->mask & IN_ISDIR) && (event->mask & (IN_CREATE | IN_MOVED_TO))) [self _watchFolder:path];
    }
    if (_watching) [_reading readInBackgroundAndNotify];
}

- (void)stop {
    if (!_watching) return;
    _watching = NO;
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSFileHandleReadCompletionNotification object:_reading];
    _reading = nil;
    close(_inotify);
    _inotify = -1;
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
}

#endif

@end
