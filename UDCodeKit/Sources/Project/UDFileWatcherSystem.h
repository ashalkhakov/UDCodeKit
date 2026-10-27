/*---------------------------------------------------------------------------------------------
 *  UDFileWatcherSystem.h
 *
 *  UDFileWatcher's system half: the system's own watching of the tree under
 *  the watcher's folder (FSEvents on macOS, inotify on Linux,
 *  ReadDirectoryChangesW on Windows), each changed path told to the watcher
 *  (-_saw:) on the main thread. One implementation for each system, in a
 *  folder of its own (apple/, linux/, windows/).
 *--------------------------------------------------------------------------------------------*/

#import "UDFileWatcher.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDFileWatcher (System)
/// Whether @a path is in a folder not watched below (".git/objects/…").
- (BOOL)_isIgnored:(NSString *)path;
/// Names of the folders not watched below.
- (NSSet<NSString *> *)_ignoredNames;
/// A change at @a path (a file, or a folder whose list changed); on the main thread.
- (void)_saw:(NSString *)path;
@end

@interface UDFileWatcherSystem : NSObject
/// Watching @a watcher's folder; nil when the system's watching did not start.
- (nullable instancetype)initWithWatcher:(UDFileWatcher *)watcher;
- (instancetype)init NS_UNAVAILABLE;
- (void)stop;
@end

NS_ASSUME_NONNULL_END
