/*---------------------------------------------------------------------------------------------
 *  UDGitSourceControl.h
 *
 *  A git repository as the editor's source control (UDSourceControl, VS
 *  Code's git extension's Repository as an SCM provider): its groups
 *  (Conflicts, Staged, Unstaged with the untracked files), the commit
 *  (all of the changes when nothing is staged: VS Code's smart commit),
 *  the index's text for the change bars, HEAD's for Code Review, its
 *  history and blame, its context menus, its Integrate menu items (Push…,
 *  Pull…, Fetch Changes, Stage, Discard, Stash, Cherry-Pick) and its
 *  Repositories view. Its menus are UDGitMenus.xib's.
 *--------------------------------------------------------------------------------------------*/

#import <AppKit/AppKit.h>
#import <UDCodeKit/UDCodeKit.h>
#import "UDGitRepository.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDGitSourceControl : NSObject <UDSourceControl>

- (instancetype)initWithRepository:(UDGitRepository *)repository;

@property (nonatomic, readonly, strong) UDGitRepository *repository;

@end

NS_ASSUME_NONNULL_END
