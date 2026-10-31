/*---------------------------------------------------------------------------------------------
 *  UDGit.h
 *
 *  git, as VS Code's git extension has it (extensions/git/src/git.ts): the
 *  git command line, found as VS Code finds it (git.path aside: the shell's
 *  toolchain and PATH, Git for Windows' folders, and on macOS not the
 *  /usr/bin/git that only offers to install the command line tools), and
 *  run without waiting for it: its output comes to a target, on the main
 *  thread, with what went wrong told by its error output (GitErrorCodes).
 *  Its messages in English, whatever the user's language, as they are read.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>

#ifndef UDCODEKIT_EXPORT
#define UDCODEKIT_EXPORT FOUNDATION_EXPORT
#endif

NS_ASSUME_NONNULL_BEGIN

/// What a git command's error output says went wrong: VS Code's GitErrorCodes.
typedef NS_ENUM(NSInteger, UDGitErrorCode) {
    UDGitErrorNone = 0,
    UDGitErrorUnknown,
    UDGitErrorBadConfigFile,
    UDGitErrorAuthenticationFailed,
    UDGitErrorNoUserNameConfigured,
    UDGitErrorNoUserEmailConfigured,
    UDGitErrorNotAGitRepository,
    UDGitErrorNotASafeGitRepository,
    UDGitErrorConflict,
    UDGitErrorStashConflict,
    UDGitErrorUnmergedChanges,
    UDGitErrorPushRejected,
    UDGitErrorRemoteConnectionError,
    UDGitErrorDirtyWorkTree,
    UDGitErrorCantAccessRemote,
    UDGitErrorRepositoryNotFound,
    UDGitErrorRepositoryIsLocked,
    UDGitErrorBranchNotFullyMerged,
    UDGitErrorNoRemoteReference,
    UDGitErrorInvalidBranchName,
    UDGitErrorBranchAlreadyExists,
    UDGitErrorNoLocalChanges,
    UDGitErrorNoStashFound,
    UDGitErrorLocalChangesOverwritten,
    UDGitErrorNoUpstreamBranch,
    UDGitErrorCantLockRef,
    UDGitErrorEmptyCommitMessage,
};

/// A git command run: what it printed, how it ended.
@interface UDGitResult : NSObject
@property (nonatomic, readonly, copy) NSArray<NSString *> *arguments;
@property (nonatomic, readonly) int terminationStatus;
@property (nonatomic, readonly, copy) NSData *outputData;
/// Its output and error output, as UTF-8.
@property (nonatomic, readonly, copy) NSString *output;
@property (nonatomic, readonly, copy) NSString *errorOutput;
@property (nonatomic, readonly) UDGitErrorCode errorCode;
/// It ended with 0 (and was not cancelled).
@property (nonatomic, readonly) BOOL succeeded;
/// What the caller gave -run:…, handed back.
@property (nonatomic, readonly, strong, nullable) id context;
/// Its error output's message, for an alert: git's last "fatal:" or
/// "error:" line, else the whole of it.
@property (nonatomic, readonly, copy) NSString *message;
@end

/// A git command running, to cancel.
@interface UDGitProcess : NSObject
- (void)cancel;
@end

@interface UDGit : NSObject

/// The git found (nil when there is none): -[UDGit locate] once.
+ (nullable UDGit *)sharedGit;

/// The git at @a path, nil when it does not run (git --version).
- (nullable instancetype)initWithPath:(NSString *)path;
- (instancetype)init NS_UNAVAILABLE;

/// Where git is, as VS Code looks: nil when it is nowhere.
+ (nullable NSString *)locate;

@property (nonatomic, readonly, copy) NSString *path;
/// "2.39.5" of "git version 2.39.5 (Apple Git-154)".
@property (nonatomic, readonly, copy) NSString *version;

/// The environment its commands get, beside the app's and the credential
/// prompts' (UDSourceControlCredentialEnvironment).
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *environment;

/// `git <arguments>` in @a folder, @a input on its standard input; the
/// result sent to @a target's @a action (one UDGitResult argument) on the
/// main thread, as the run loop runs (a modal one too).
- (UDGitProcess *)run:(NSArray<NSString *> *)arguments
             inFolder:(NSString *)folder
                input:(nullable NSData *)input
              context:(nullable id)context
               target:(id)target
               action:(SEL)action;

/// The same, waited for: for what must be known before going on (and tests).
- (UDGitResult *)runAndWait:(NSArray<NSString *> *)arguments inFolder:(NSString *)folder input:(nullable NSData *)input;

/// A path git wrote, as the system's: on Windows an MSYS2 or Cygwin git's
/// (/c/…, /tmp/…) as Windows' (cygpath -m); else @a path.
- (NSString *)nativePathOf:(NSString *)path;

/// What @a errorOutput of `git <command>` says went wrong (getGitErrorCode).
+ (UDGitErrorCode)errorCodeOfOutput:(NSString *)errorOutput command:(nullable NSString *)command;

@end

NS_ASSUME_NONNULL_END
