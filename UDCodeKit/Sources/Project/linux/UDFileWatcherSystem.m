/*---------------------------------------------------------------------------------------------
 *  UDFileWatcherSystem.m (Linux: inotify)
 *--------------------------------------------------------------------------------------------*/

#import "../UDFileWatcherSystem.h"
#include <sys/inotify.h>
#include <unistd.h>
#include <limits.h>

@implementation UDFileWatcherSystem {
    __weak UDFileWatcher *_watcher;
    int _inotify;
    NSFileHandle *_reading;
    NSMutableDictionary<NSNumber *, NSString *> *_folders;   // inotify's watch, its folder
}

- (instancetype)initWithWatcher:(UDFileWatcher *)watcher {
    if (!(self = [super init])) return nil;
    _watcher = watcher;
    _inotify = inotify_init1(IN_NONBLOCK | IN_CLOEXEC);
    if (_inotify < 0) return nil;
    _folders = [NSMutableDictionary dictionary];
    [self _watchFolder:watcher.folderURL.path.stringByStandardizingPath];
    _reading = [[NSFileHandle alloc] initWithFileDescriptor:_inotify closeOnDealloc:NO];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_didRead:)
                                                 name:NSFileHandleReadCompletionNotification object:_reading];
    [_reading readInBackgroundAndNotify];
    return self;
}

- (void)dealloc {
    [self stop];
}

/// inotify watches a folder at a time: each one of the tree, and each made later.
- (void)_watchFolder:(NSString *)folder {
    UDFileWatcher *watcher = _watcher;
    if ([watcher _isIgnored:folder] && ![folder isEqualToString:watcher.folderURL.path]) return;
    int watch = inotify_add_watch(_inotify, folder.fileSystemRepresentation,
                                  IN_CREATE | IN_DELETE | IN_MODIFY | IN_CLOSE_WRITE | IN_MOVED_FROM | IN_MOVED_TO |
                                  IN_DELETE_SELF | IN_MOVE_SELF | IN_ONLYDIR);
    if (watch < 0) return;
    _folders[@(watch)] = folder;
    NSSet *ignored = [watcher _ignoredNames];
    for (NSString *name in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:folder error:NULL]) {
        if ([ignored containsObject:name]) continue;
        NSString *path = [folder stringByAppendingPathComponent:name];
        BOOL directory = NO;
        if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&directory] && directory) {
            [self _watchFolder:path];
        }
    }
}

- (void)_didRead:(NSNotification *)note {
    UDFileWatcher *watcher = _watcher;
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
            [watcher _saw:folder];
            continue;
        }
        NSString *path = event->len ? [folder stringByAppendingPathComponent:[NSString stringWithUTF8String:event->name]] : folder;
        [watcher _saw:path];
        [watcher _saw:folder];
        // a folder made (or moved in): watched too
        if ((event->mask & IN_ISDIR) && (event->mask & (IN_CREATE | IN_MOVED_TO))) [self _watchFolder:path];
    }
    if (_inotify >= 0) [_reading readInBackgroundAndNotify];
}

- (void)stop {
    if (_inotify < 0) return;
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSFileHandleReadCompletionNotification object:_reading];
    _reading = nil;
    close(_inotify);
    _inotify = -1;
}

@end
