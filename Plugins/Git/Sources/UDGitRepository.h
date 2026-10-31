/*---------------------------------------------------------------------------------------------
 *  UDGitRepository.h
 *
 *  A git repository, as VS Code's git extension models it (repository.ts):
 *  its files' status in groups (Merge, Staged: the index, Changes: the
 *  working tree, Untracked), HEAD (its branch, upstream, ahead and behind),
 *  its branches, tags, remotes and stashes; read again (-refresh) after its
 *  files or .git change (a moment after: -scheduleRefresh), one read at a
 *  time. What it does (stage, commit, push, ...) is git's command line, each
 *  followed by a refresh, retried while another git holds the repository.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import <UDCodeKit/UDCodeKit.h>
#import "UDGit.h"

NS_ASSUME_NONNULL_BEGIN

/// A file's status in a group: VS Code's Status.
typedef NS_ENUM(NSInteger, UDGitStatus) {
    UDGitStatusIndexModified,
    UDGitStatusIndexAdded,
    UDGitStatusIndexDeleted,
    UDGitStatusIndexRenamed,
    UDGitStatusIndexCopied,
    UDGitStatusModified,
    UDGitStatusDeleted,
    UDGitStatusUntracked,
    UDGitStatusIgnored,
    UDGitStatusIntentToAdd,
    UDGitStatusIntentToRename,
    UDGitStatusTypeChanged,
    UDGitStatusAddedByUs,
    UDGitStatusAddedByThem,
    UDGitStatusDeletedByUs,
    UDGitStatusDeletedByThem,
    UDGitStatusBothAdded,
    UDGitStatusBothDeleted,
    UDGitStatusBothModified,
};

typedef NS_ENUM(NSInteger, UDGitResourceGroup) {
    UDGitResourceGroupMerge,
    UDGitResourceGroupIndex,
    UDGitResourceGroupWorkingTree,
    UDGitResourceGroupUntracked,
};

/// A file of a group.
@interface UDGitResource : NSObject
/// Its path (absolute); a renamed file's new one.
@property (nonatomic, readonly, copy) NSString *path;
/// A renamed or copied file's path before.
@property (nonatomic, readonly, copy, nullable) NSString *originalPath;
/// Its path in the repository ("Sources/a.c").
@property (nonatomic, readonly, copy) NSString *relativePath;
@property (nonatomic, readonly) UDGitStatus status;
@property (nonatomic, readonly) UDGitResourceGroup group;
/// Xcode's letter for it: M, A, D, R, C, T, ? (untracked), I, U (conflict).
@property (nonatomic, readonly, copy) NSString *letter;
/// Its status in words ("Modified", "Added", "Untracked", ...).
@property (nonatomic, readonly, copy) NSString *statusDescription;
@end

typedef NS_ENUM(NSInteger, UDGitRefType) {
    UDGitRefTypeHead,
    UDGitRefTypeRemoteHead,
    UDGitRefTypeTag,
};

/// A branch, a remote's branch or a tag.
@interface UDGitRef : NSObject
@property (nonatomic, readonly) UDGitRefType type;
/// "main", "origin/main", "v1.0".
@property (nonatomic, readonly, copy) NSString *name;
/// "refs/heads/main".
@property (nonatomic, readonly, copy) NSString *fullName;
@property (nonatomic, readonly, copy) NSString *commit;
/// A branch's upstream ("origin/main"), and how far ahead and behind of it.
@property (nonatomic, readonly, copy, nullable) NSString *upstream;
@property (nonatomic, readonly) NSInteger ahead, behind;
@end

@interface UDGitRemote : NSObject
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly, copy) NSString *fetchURL;
@property (nonatomic, readonly, copy, nullable) NSString *pushURL;
@end

@interface UDGitStash : NSObject
/// Its place: 0 is stash@{0}.
@property (nonatomic, readonly) NSInteger index;
@property (nonatomic, readonly, copy) NSString *message;
@property (nonatomic, readonly, strong, nullable) NSDate *date;
@end

/// Posted, the repository the object, when what it knows changed (a refresh).
FOUNDATION_EXPORT NSNotificationName const UDGitRepositoryDidChangeNotification;

/// A repository's operation in progress (merging and the like).
typedef NS_ENUM(NSInteger, UDGitOperationState) {
    UDGitOperationStateNone,
    UDGitOperationStateMerging,
    UDGitOperationStateRebasing,
    UDGitOperationStateCherryPicking,
};

@interface UDGitRepository : NSObject

/// The repository @a folder is in (git rev-parse --show-toplevel), nil when
/// none is, or git is not there.
+ (nullable instancetype)repositoryOfFolder:(NSString *)folder git:(nullable UDGit *)git;

- (instancetype)initWithRoot:(NSString *)root gitDirectory:(NSString *)gitDirectory git:(UDGit *)git NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, readonly, strong) UDGit *git;
/// Its working tree's folder, and its .git.
@property (nonatomic, readonly, copy) NSString *root;
@property (nonatomic, readonly, copy) NSString *gitDirectory;

// MARK: What it knows (after a refresh)

@property (nonatomic, readonly, copy) NSArray<UDGitResource *> *mergeChanges;
@property (nonatomic, readonly, copy) NSArray<UDGitResource *> *indexChanges;
@property (nonatomic, readonly, copy) NSArray<UDGitResource *> *workingTreeChanges;
@property (nonatomic, readonly, copy) NSArray<UDGitResource *> *untrackedChanges;

/// HEAD's branch's name; nil when detached (headCommit then).
@property (nonatomic, readonly, copy, nullable) NSString *branch;
@property (nonatomic, readonly, copy, nullable) NSString *headCommit;
@property (nonatomic, readonly, copy, nullable) NSString *upstream;
@property (nonatomic, readonly) NSInteger ahead, behind;
@property (nonatomic, readonly) UDGitOperationState operationState;

@property (nonatomic, readonly, copy) NSArray<UDGitRef *> *refs;
@property (nonatomic, readonly, copy) NSArray<UDGitRemote *> *remotes;
@property (nonatomic, readonly, copy) NSArray<UDGitStash *> *stashes;

/// Whether it has been read once.
@property (nonatomic, readonly, getter=isLoaded) BOOL loaded;

/// What its file at @a path is: its most telling resource (a conflict, else
/// the working tree's, else the index's), nil when it is unchanged.
- (nullable UDGitResource *)resourceAtPath:(NSString *)path;
/// Whether files under the folder @a path changed (deletions aside).
- (BOOL)folderContainsChanges:(NSString *)path;
/// Whether @a path is the repository's (under its root).
- (BOOL)containsPath:(NSString *)path;

// MARK: Reading

/// Read again now (one at a time: one more after the one under way).
- (void)refresh;
/// ... a moment from now: after its files changed.
- (void)scheduleRefresh;
/// A file in .git or the working tree changed (the window's watcher's):
/// scheduled, unless it is git's own lock.
- (void)filesDidChangeAtPaths:(NSSet<NSString *> *)paths;

/// The text of @a path at @a ref ("HEAD"; "" for the index; a commit) to
/// @a target's @a action (a UDGitResult: its outputData).
- (void)contentsOfPath:(NSString *)path atRef:(NSString *)ref target:(id)target action:(SEL)action;
/// The same, waited for; nil when it is not there (a new file).
- (nullable NSString *)contentsOfPath:(NSString *)path atRef:(NSString *)ref;

/// The commits, newest first: @a count of them from @a ref (nil: HEAD),
/// those of @a path only when it is given.
- (void)logFromRef:(nullable NSString *)ref path:(nullable NSString *)path count:(NSInteger)count
            target:(id)target action:(SEL)action;
/// A UDGitResult of -logFromRef:…: its commits.
+ (NSArray<UDSourceControlCommit *> *)commitsOfLog:(UDGitResult *)result;

/// Who last changed each line of @a path (its saved text, at HEAD).
- (void)blameOfPath:(NSString *)path target:(id)target action:(SEL)action;
+ (NSArray<UDSourceControlBlameRange *> *)rangesOfBlame:(UDGitResult *)result;

/// The files a commit changed (name-status), each "M\tpath".
- (void)filesOfCommit:(NSString *)commit target:(id)target action:(SEL)action;

// MARK: Doing (each refreshes after; the result, a UDGitResult, to target's action)

- (void)stagePaths:(NSArray<NSString *> *)paths target:(nullable id)target action:(nullable SEL)action;
- (void)unstagePaths:(NSArray<NSString *> *)paths target:(nullable id)target action:(nullable SEL)action;
- (void)stageAllWithTarget:(nullable id)target action:(nullable SEL)action;
- (void)unstageAllWithTarget:(nullable id)target action:(nullable SEL)action;
/// The working tree's changes to @a paths gone (an untracked file: to the trash).
- (void)discardChangesToPaths:(NSArray<NSString *> *)paths target:(nullable id)target action:(nullable SEL)action;
/// The whole of @a path's index text replaced by @a text (a change staged:
/// VS Code's stageSelectedRanges, through hash-object and update-index).
- (void)stageText:(NSString *)text ofPath:(NSString *)path target:(nullable id)target action:(nullable SEL)action;

/// A commit of what is staged (@a all: of every change, staged first), with
/// @a message; @a amend: in place of HEAD.
- (void)commitWithMessage:(NSString *)message all:(BOOL)all amend:(BOOL)amend
                   target:(nullable id)target action:(nullable SEL)action;

- (void)fetchWithTarget:(nullable id)target action:(nullable SEL)action;
/// Pulls HEAD's branch from its upstream; @a rebase: its commits on top.
- (void)pullRebasing:(BOOL)rebase target:(nullable id)target action:(nullable SEL)action;
/// Pushes HEAD's branch to its upstream, or (none yet) to @a remote, made
/// its upstream; @a tags: and its tags.
- (void)pushToRemote:(nullable NSString *)remote tags:(BOOL)tags target:(nullable id)target action:(nullable SEL)action;

- (void)checkout:(NSString *)ref target:(nullable id)target action:(nullable SEL)action;
/// A branch @a name at @a ref (nil: HEAD), switched to when @a checkout.
- (void)createBranch:(NSString *)name fromRef:(nullable NSString *)ref checkout:(BOOL)checkout
              target:(nullable id)target action:(nullable SEL)action;
- (void)deleteBranch:(NSString *)name force:(BOOL)force target:(nullable id)target action:(nullable SEL)action;
- (void)renameBranch:(NSString *)name to:(NSString *)newName target:(nullable id)target action:(nullable SEL)action;
- (void)merge:(NSString *)ref target:(nullable id)target action:(nullable SEL)action;
- (void)abortMergeWithTarget:(nullable id)target action:(nullable SEL)action;
- (void)createTag:(NSString *)name message:(nullable NSString *)message atRef:(nullable NSString *)ref
           target:(nullable id)target action:(nullable SEL)action;
- (void)deleteTag:(NSString *)name target:(nullable id)target action:(nullable SEL)action;
- (void)addRemote:(NSString *)name url:(NSString *)url target:(nullable id)target action:(nullable SEL)action;
- (void)removeRemote:(NSString *)name target:(nullable id)target action:(nullable SEL)action;
- (void)cherryPick:(NSString *)commit target:(nullable id)target action:(nullable SEL)action;

/// Stashes the changes (@a includeUntracked: the untracked files too).
- (void)stashWithMessage:(nullable NSString *)message includeUntracked:(BOOL)includeUntracked
                  target:(nullable id)target action:(nullable SEL)action;
- (void)applyStash:(NSInteger)index pop:(BOOL)pop target:(nullable id)target action:(nullable SEL)action;
- (void)dropStash:(NSInteger)index target:(nullable id)target action:(nullable SEL)action;

/// `git <arguments>` in the repository, a refresh after: what the above do.
- (void)runOperation:(NSArray<NSString *> *)arguments input:(nullable NSData *)input
              target:(nullable id)target action:(nullable SEL)action;

/// A new repository in @a folder (git init), nil when it fails.
+ (nullable instancetype)initializeRepositoryInFolder:(NSString *)folder git:(UDGit *)git error:(NSString *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END
