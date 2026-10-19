/*---------------------------------------------------------------------------------------------
 *  UDFileWatcher.h
 *
 *  A folder's files, watched for changes made by anything (a build, git, another
 *  editor), as VS Code's file watcher does: the system's own mechanism, FSEvents
 *  on macOS, inotify on Linux, over the whole tree. What changed is told to the
 *  delegate on the main thread, a moment after the changes stop (a build
 *  changes hundreds of files: they come as one call), as the paths of the
 *  folders whose files changed and the files themselves.
 *
 *  Folders whose names are in ignoredNames (".git", build products) are not
 *  watched below (inotify watches a folder at a time: a node_modules would cost
 *  thousands).
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class UDFileWatcher;

@protocol UDFileWatcherDelegate <NSObject>
/// Files under the folder changed: @a paths are the changed files and folders
/// (absolute, under the folder as it was given), each folder whose list
/// changed among them.
- (void)fileWatcher:(UDFileWatcher *)watcher didSeeChangesAtPaths:(NSSet<NSString *> *)paths;
@end

@interface UDFileWatcher : NSObject

/// Watches the tree under @a folderURL; starts at once.
- (instancetype)initWithFolderURL:(NSURL *)folderURL ignoredNames:(nullable NSSet<NSString *> *)ignoredNames;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, readonly, copy) NSURL *folderURL;
@property (nonatomic, weak, nullable) id<UDFileWatcherDelegate> delegate;
/// How long changes must stop before the delegate is told (0.2 s).
@property (nonatomic) NSTimeInterval latency;
/// Whether the system's watching started (NO: the delegate is never told).
@property (nonatomic, readonly, getter=isWatching) BOOL watching;

- (void)stop;

@end

NS_ASSUME_NONNULL_END
