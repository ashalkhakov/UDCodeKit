/*---------------------------------------------------------------------------------------------
 *  UDFileWatcherSystem.m (Windows: ReadDirectoryChangesW)
 *
 *  The whole tree at once (bWatchSubtree), read on a thread of its own and
 *  told to the watcher on the main thread: each changed path, and its folder
 *  (whose list changed when a file was made, deleted or renamed).
 *--------------------------------------------------------------------------------------------*/

#import "../UDFileWatcherSystem.h"
#include <windows.h>

@implementation UDFileWatcherSystem {
    __weak UDFileWatcher *_watcher;
    NSString *_root;
    HANDLE _folder;
    volatile BOOL _stopped;
}

- (instancetype)initWithWatcher:(UDFileWatcher *)watcher {
    if (!(self = [super init])) return nil;
    _watcher = watcher;
    _root = watcher.folderURL.path;
    NSUInteger length = _root.length;
    unichar *path = calloc(length + 1, sizeof(unichar));
    [_root getCharacters:path range:NSMakeRange(0, length)];
    _folder = CreateFileW((LPCWSTR)path, FILE_LIST_DIRECTORY, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                          NULL, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, NULL);
    free(path);
    if (_folder == INVALID_HANDLE_VALUE) return nil;
    [NSThread detachNewThreadSelector:@selector(_watch:) toTarget:self withObject:nil];
    return self;
}

- (void)dealloc {
    [self stop];
}

/// On a thread of its own, until stopped: the changes, as they come.
- (void)_watch:(id)unused {
    HANDLE folder = _folder;
    DWORD buffer[16384];   /* DWORD-aligned, as the notifications are */
    while (!_stopped) {
        DWORD got = 0;
        BOOL read = ReadDirectoryChangesW(folder, buffer, sizeof buffer, TRUE,
                                          FILE_NOTIFY_CHANGE_FILE_NAME | FILE_NOTIFY_CHANGE_DIR_NAME |
                                          FILE_NOTIFY_CHANGE_SIZE | FILE_NOTIFY_CHANGE_LAST_WRITE,
                                          &got, NULL, NULL);
        if (!read) break;
        @autoreleasepool {
            NSMutableArray *paths = [NSMutableArray array];
            if (got == 0) {
                /* more changed than fit: the whole tree, as a folder whose list changed */
                [paths addObject:_root];
            } else {
                const char *at = (const char *)buffer;
                for (;;) {
                    const FILE_NOTIFY_INFORMATION *note = (const FILE_NOTIFY_INFORMATION *)at;
                    NSString *name = [NSString stringWithCharacters:(const unichar *)note->FileName
                                                             length:note->FileNameLength / sizeof(WCHAR)];
                    NSString *path = [_root stringByAppendingPathComponent:
                                         [name stringByReplacingOccurrencesOfString:@"\\" withString:@"/"]];
                    [paths addObject:path];
                    if (note->Action != FILE_ACTION_MODIFIED) [paths addObject:[path stringByDeletingLastPathComponent]];
                    if (!note->NextEntryOffset) break;
                    at += note->NextEntryOffset;
                }
            }
            [self performSelectorOnMainThread:@selector(_tell:) withObject:paths waitUntilDone:NO];
        }
    }
    CloseHandle(folder);
}

- (void)_tell:(NSArray<NSString *> *)paths {
    if (_stopped) return;
    UDFileWatcher *watcher = _watcher;
    for (NSString *path in paths) [watcher _saw:path];
}

/// The read waiting on the watching thread cancelled; the thread closes the
/// folder as it ends.
- (void)stop {
    if (_stopped) return;
    _stopped = YES;
    CancelIoEx(_folder, NULL);
}

@end
