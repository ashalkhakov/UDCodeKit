/*---------------------------------------------------------------------------------------------
 *  UDDebugNavigatorViewController.h
 *
 *  Xcode's debug navigator: the session's threads, each with its call stack
 *  when stopped,
 *
 *    ▼ Thread 1  main   (breakpoint)
 *        0  level1   script.script:12
 *        1  main     script.script:7
 *    ▶ Thread 2  worker
 *
 *  Choosing a frame selects it in the session, which has its file shown
 *  (the session's delegate) and its variables loaded. A stopped thread's
 *  frames load when it is expanded.
 *
 *  Laid out in UDDebugNavigator.xib. A host puts its view in its navigator
 *  and gives it the session.
 *--------------------------------------------------------------------------------------------*/

#import <Cocoa/Cocoa.h>
#import "UDDebugSession.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDDebugNavigatorViewController : NSViewController <NSOutlineViewDataSource, NSOutlineViewDelegate>

- (instancetype)init;

@property (nonatomic, strong, nullable) UDDebugSession *session;

/// Threads (UDDebugThread) and, under them, frames (UDDebugStackFrame).
@property (nonatomic, weak, readonly) IBOutlet NSOutlineView *outlineView;

@end

NS_ASSUME_NONNULL_END
