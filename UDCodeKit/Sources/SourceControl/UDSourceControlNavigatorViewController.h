/*---------------------------------------------------------------------------------------------
 *  UDSourceControlNavigatorViewController.h
 *
 *  Xcode's Source Control navigator (⌘2), of a source control (UDSourceControl:
 *  git's, an extension's): Changes (where it is; its groups of changed files
 *  with Xcode's letters and its context menus; a commit message and Commit,
 *  with Commit and Push and Amend) and Repositories (the provider's own
 *  view, when it has one). A file chosen is the delegate's to show.
 *--------------------------------------------------------------------------------------------*/

#import <AppKit/AppKit.h>
#import <UDCodeKit/UDSourceControl.h>

NS_ASSUME_NONNULL_BEGIN

@class UDSourceControlNavigatorViewController;

@protocol UDSourceControlNavigatorDelegate <NSObject>
/// A changed file chosen: its change shown (the file's Code Review, say).
- (void)sourceControlNavigator:(UDSourceControlNavigatorViewController *)navigator openChange:(UDSourceControlResource *)resource;
@optional
- (void)sourceControlNavigator:(UDSourceControlNavigatorViewController *)navigator revealInProjectNavigator:(NSString *)path;
@end

@interface UDSourceControlNavigatorViewController : NSViewController

- (instancetype)init;

@property (nonatomic, weak, nullable) id<UDSourceControlNavigatorDelegate> delegate;
/// The source control shown; nil shows that there is none.
@property (nonatomic, strong, nullable) id<UDSourceControl> sourceControl;

/// Changes (0) or Repositories (1).
@property (nonatomic) NSInteger selectedTab;

@property (nonatomic, readonly) NSOutlineView *changesView;
@property (nonatomic, readonly) NSTextField *messageField;

/// The files selected in Changes.
@property (nonatomic, readonly, copy) NSArray<UDSourceControlResource *> *selectedResources;

/// Integrate > Commit… (⌥⌘C): Changes shown, its message to type.
- (void)focusCommitMessage;

/// Commit, Commit and Push, Amend: the message's.
- (IBAction)commit:(nullable id)sender;
- (IBAction)commitAndPush:(nullable id)sender;
- (IBAction)amend:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
