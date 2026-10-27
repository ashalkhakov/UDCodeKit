/*---------------------------------------------------------------------------------------------
 *  UDFileWatcher.m
 *
 *  What is the same on every system: what is ignored, and the changes held
 *  until they stop. The watching itself is UDFileWatcherSystem's.
 *--------------------------------------------------------------------------------------------*/

#import "UDFileWatcher.h"
#import "UDFileWatcherSystem.h"

/// The run loop modes a change is told in: an app's while a sheet or a drag is
/// up too (AppKit's names, whose values these are; this is Foundation).
static NSArray<NSString *> *UDWatcherModes(void) {
    return @[ NSDefaultRunLoopMode, @"NSModalPanelRunLoopMode", @"NSEventTrackingRunLoopMode" ];
}

@implementation UDFileWatcher {
    NSSet<NSString *> *_ignored;
    NSMutableSet<NSString *> *_pending;
    UDFileWatcherSystem *_system;
}

- (instancetype)initWithFolderURL:(NSURL *)folderURL ignoredNames:(NSSet<NSString *> *)ignoredNames {
    if (!(self = [super init])) return nil;
    _folderURL = [folderURL copy];
    _ignored = [ignoredNames copy] ?: [NSSet setWithObjects:@".git", @".svn", @".hg", nil];
    _pending = [NSMutableSet set];
    _latency = 0.2;
    _system = [[UDFileWatcherSystem alloc] initWithWatcher:self];
    _watching = _system != nil;
    return self;
}

- (void)dealloc {
    [self stop];
}

- (NSSet<NSString *> *)_ignoredNames {
    return _ignored;
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

- (void)stop {
    if (!_system) return;
    [_system stop];
    _system = nil;
    _watching = NO;
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
}

@end
