/*---------------------------------------------------------------------------------------------
 *  UDHistoryViewController.h
 *
 *  A branch's or tag's history, as Xcode shows it when one is selected in
 *  the Repositories navigator, of a source control's (its history and its
 *  commits' files, UDSourceControl's): its commits (message, author, date,
 *  commit), newest first; the one selected, its details and the files it
 *  changed, each to open as it was before and after it (the delegate's).
 *  Its view is UDHistory.xib.
 *--------------------------------------------------------------------------------------------*/

#import <AppKit/AppKit.h>
#import <UDCodeKit/UDSourceControl.h>

NS_ASSUME_NONNULL_BEGIN

@class UDHistoryViewController;

@protocol UDHistoryDelegate <NSObject>
/// A file a commit changed, chosen: its change shown.
- (void)history:(UDHistoryViewController *)history openFile:(UDSourceControlCommitFile *)file
       ofCommit:(UDSourceControlCommit *)commit;
@end

@interface UDHistoryViewController : NSViewController

- (instancetype)initWithSourceControl:(id<UDSourceControl>)sourceControl ref:(NSString *)ref;

@property (nonatomic, readonly, strong) id<UDSourceControl> sourceControl;
@property (nonatomic, readonly, copy) NSString *ref;
@property (nonatomic, weak, nullable) id<UDHistoryDelegate> delegate;

/// Its commits (once read) and the one selected's files.
@property (nonatomic, readonly, copy) NSArray<UDSourceControlCommit *> *commits;
@property (nonatomic, readonly, copy) NSArray<UDSourceControlCommitFile *> *selectedCommitFiles;
@property (nonatomic, weak, readonly) IBOutlet NSTableView *commitsTable;
@property (nonatomic, weak, readonly) IBOutlet NSTableView *filesTable;

/// Its commits read again.
- (void)reload;

@end

NS_ASSUME_NONNULL_END
