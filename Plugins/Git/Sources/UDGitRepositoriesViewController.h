/*---------------------------------------------------------------------------------------------
 *  UDGitRepositoriesViewController.h
 *
 *  The Source Control navigator's Repositories, as Xcode's: a repository's
 *  Branches (the current one marked), Tags, Remotes and their branches,
 *  Stashed Changes, each with Xcode's context menu (Switch…, New Branch…,
 *  Merge…, New Tag…, Delete…, Add Existing Remote…, Apply Stashed
 *  Changes…). A branch or tag selected: its history, the host's to show.
 *  Its view and menus are UDGitRepositories.xib's.
 *--------------------------------------------------------------------------------------------*/

#import <AppKit/AppKit.h>
#import <UDCodeKit/UDCodeKit.h>
#import "UDGitRepository.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDGitRepositoriesViewController : NSViewController

/// Of @a repository, for @a sourceControl (whose host is told).
- (instancetype)initWithRepository:(UDGitRepository *)repository sourceControl:(id<UDSourceControl>)sourceControl;

@property (nonatomic, weak, readonly) IBOutlet NSOutlineView *outlineView;

@end

NS_ASSUME_NONNULL_END
