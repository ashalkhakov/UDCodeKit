/*---------------------------------------------------------------------------------------------
 *  UDSourceControl.h
 *
 *  Source control, as the editor knows it: VS Code's SCM API (vscode.scm),
 *  which an extension provides for a folder (git's: Plugins/Git). Its
 *  changes in groups of resources (a file, its badge letter, what it is);
 *  a commit of them, with a message; the text a file is compared with (its
 *  change bars' and its Code Review's); and what it may also have: a
 *  history, who changed each line (blame), its own context menus and
 *  Integrate menu items, its own Repositories view. The editor draws all
 *  of it the way Xcode does (the Source Control navigator, the project
 *  navigator's badges, change bars, Code Review, Authors, a history).
 *--------------------------------------------------------------------------------------------*/

#import <AppKit/AppKit.h>

#ifndef UDCODEKIT_EXPORT
#define UDCODEKIT_EXPORT FOUNDATION_EXPORT
#endif

NS_ASSUME_NONNULL_BEGIN

@protocol UDSourceControl, UDSourceControlHost;

/// A changed file: VS Code's SourceControlResourceState.
@interface UDSourceControlResource : NSObject
- (instancetype)initWithPath:(NSString *)path originalPath:(nullable NSString *)originalPath
                      letter:(NSString *)letter statusDescription:(NSString *)statusDescription
                     deleted:(BOOL)deleted object:(nullable id)object;
/// Its path (absolute); a renamed file's new one, and its path before.
@property (nonatomic, readonly, copy) NSString *path;
@property (nonatomic, readonly, copy, nullable) NSString *originalPath;
/// Xcode's letter for it (M, A, D, R, ?, C...) and what it is ("Modified").
@property (nonatomic, readonly, copy) NSString *letter;
@property (nonatomic, readonly, copy) NSString *statusDescription;
/// Deleted: drawn struck out (VS Code's strikeThrough), shown as it was.
@property (nonatomic, readonly, getter=isDeleted) BOOL deleted;
/// The provider's own (its status, its group).
@property (nonatomic, readonly, strong, nullable) id object;
@end

/// A group of changes: VS Code's SourceControlResourceGroup.
@interface UDSourceControlResourceGroup : NSObject
- (instancetype)initWithIdentifier:(NSString *)identifier label:(NSString *)label
                         resources:(NSArray<UDSourceControlResource *> *)resources;
@property (nonatomic, readonly, copy) NSString *identifier;
/// "Staged", "Unstaged", "Conflicts".
@property (nonatomic, readonly, copy) NSString *label;
@property (nonatomic, readonly, copy) NSArray<UDSourceControlResource *> *resources;
/// Not shown when it has no resources (VS Code's hideWhenEmpty).
@property (nonatomic) BOOL hidesWhenEmpty;
@end

/// A commit, as a history lists it.
@interface UDSourceControlCommit : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, readonly, copy) NSString *shortIdentifier;
@property (nonatomic, copy) NSString *authorName;
@property (nonatomic, copy) NSString *authorEmail;
@property (nonatomic, strong) NSDate *authorDate;
@property (nonatomic, copy) NSArray<NSString *> *parents;
/// Its message's first line, and the whole.
@property (nonatomic, copy) NSString *subject;
@property (nonatomic, copy) NSString *message;
/// The branches and tags at it ("HEAD -> main", "origin/main", "tag: v1").
@property (nonatomic, copy) NSArray<NSString *> *refNames;
/// Its changes not committed yet (blame's lines being edited).
@property (nonatomic, getter=isUncommitted) BOOL uncommitted;
@end

/// A range of lines one commit last changed: blame's (Xcode's Authors).
@interface UDSourceControlBlameRange : NSObject
/// Lines [startLine, startLine + lineCount), 1-based.
@property (nonatomic) NSInteger startLine, lineCount;
@property (nonatomic, strong) UDSourceControlCommit *commit;
@end

/// A file a commit changed.
@interface UDSourceControlCommitFile : NSObject
/// The provider's letter (M, A, D, R...), the file's path in the
/// repository, a rename's path before.
@property (nonatomic, copy) NSString *letter;
@property (nonatomic, copy) NSString *path;
@property (nonatomic, copy, nullable) NSString *originalPath;
@end

/// What an operation of a provider's came to: told to a target's action.
@interface UDSourceControlResult : NSObject
- (instancetype)initSucceeded:(BOOL)succeeded message:(nullable NSString *)message
                        value:(nullable id)value context:(nullable id)context;
@property (nonatomic, readonly) BOOL succeeded;
/// What went wrong, as said in an alert.
@property (nonatomic, readonly, copy, nullable) NSString *message;
/// What it read: a text, commits, blame ranges, commit files.
@property (nonatomic, readonly, strong, nullable) id value;
/// What the caller gave, handed back (a path, say).
@property (nonatomic, readonly, strong, nullable) id context;
@end

/// Posted, the provider the object, when what it knows changed.
UDCODEKIT_EXPORT NSNotificationName const UDSourceControlDidChangeNotification;

/// What a commit is.
typedef NS_OPTIONS(NSUInteger, UDSourceControlCommitOptions) {
    UDSourceControlCommitAmend = 1 << 0,
    UDSourceControlCommitPush = 1 << 1,
};

/// A folder's source control: what an extension provides (VS Code's SourceControl).
@protocol UDSourceControl <NSObject>

/// Who shows it: told what went wrong, asked what is selected.
@property (nonatomic, weak, nullable) id<UDSourceControlHost> host;

/// Its name ("Git"), its folder, and where it is ("main ↑1").
@property (nonatomic, readonly, copy) NSString *label;
@property (nonatomic, readonly, copy) NSString *rootPath;
@property (nonatomic, readonly, copy) NSString *statusText;
/// Read once at least.
@property (nonatomic, readonly, getter=isLoaded) BOOL loaded;

@property (nonatomic, readonly, copy) NSArray<UDSourceControlResourceGroup *> *resourceGroups;
/// The file's most telling change (nil: unchanged); whether files under a
/// folder changed; whether a path is its own.
- (nullable UDSourceControlResource *)resourceAtPath:(NSString *)path;
- (BOOL)folderContainsChanges:(NSString *)path;
- (BOOL)containsPath:(NSString *)path;

/// Read again: now, or after files changed (the window's watcher's).
- (void)refresh;
- (void)filesDidChangeAtPaths:(NSSet<NSString *> *)paths;

/// A commit of its changes with @a message (VS Code's input box and its
/// accept command): to @a target's @a action (a UDSourceControlResult).
- (void)commitWithMessage:(NSString *)message options:(UDSourceControlCommitOptions)options
                   target:(nullable id)target action:(nullable SEL)action;

/// The text @a path's change bars are against (VS Code's quick diff: the
/// index's), its value; nil for none (an untracked file).
- (void)originalTextOfPath:(NSString *)path target:(id)target action:(SEL)action;
/// The text @a path's Code Review is against (Xcode's: the last commit's);
/// nil: the saved file's.
- (nullable NSString *)codeReviewTextOfPath:(NSString *)path;
/// Stage Change: @a text, the original's with a change in it, as the original.
- (void)stageText:(NSString *)text ofPath:(NSString *)path target:(nullable id)target action:(nullable SEL)action;

/// The changes' context menus, its own (Stage, Discard Changes…).
- (NSArray<NSMenuItem *> *)menuItemsForResources:(NSArray<UDSourceControlResource *> *)resources;
- (NSArray<NSMenuItem *> *)menuItemsForGroup:(UDSourceControlResourceGroup *)group;
/// Its items of the Integrate menu (Push…, Pull…, Fetch Changes...).
- (NSArray<NSMenuItem *> *)integrateMenuItems;

@optional
/// The commits of @a ref (nil: the current), newest first: its value.
- (void)historyOfRef:(nullable NSString *)ref count:(NSInteger)count target:(id)target action:(SEL)action;
/// The files @a commit changed (UDSourceControlCommitFile): its value.
- (void)filesOfCommit:(NSString *)commit target:(id)target action:(SEL)action;
/// @a path's text at @a commit (nil: not there then).
- (nullable NSString *)textOfPath:(NSString *)path atCommit:(NSString *)commit;
/// Who last changed each line of @a path (UDSourceControlBlameRange): its value.
- (void)blameOfPath:(NSString *)path target:(id)target action:(SEL)action;
/// Its Repositories tab (git's: branches, tags, remotes, stashes).
- (nullable NSViewController *)repositoriesViewController;

@end

/// Who shows a provider: the window.
@protocol UDSourceControlHost <NSObject>
/// The window its sheets go on.
@property (nonatomic, readonly, nullable) NSWindow *window;
/// An operation that failed (nil: an extension's, of no source control): what
/// went wrong, told.
- (void)sourceControl:(nullable id<UDSourceControl>)sourceControl didFail:(UDSourceControlResult *)result;
/// The files the Integrate menu's "Selected Files" are.
- (NSArray<NSString *> *)selectedPathsForSourceControl:(id<UDSourceControl>)sourceControl;
/// A ref's history, shown (a branch selected in Repositories).
- (void)sourceControl:(id<UDSourceControl>)sourceControl showHistoryOfRef:(NSString *)ref title:(NSString *)title;
/// A folder (a clone) opened as a project.
- (void)sourceControl:(nullable id<UDSourceControl>)sourceControl openFolder:(NSURL *)folder;
/// The project's source control asked of the extensions again (a
/// repository made for it, say).
- (void)reloadSourceControl;
@end

/// The environment a provider's commands get so that credentials are asked
/// by the app (its askpass), set by the app at launch.
UDCODEKIT_EXPORT NSDictionary<NSString *, NSString *> *UDSourceControlCredentialEnvironment(void);
UDCODEKIT_EXPORT void UDSourceControlSetCredentialEnvironment(NSDictionary<NSString *, NSString *> *environment);

NS_ASSUME_NONNULL_END
