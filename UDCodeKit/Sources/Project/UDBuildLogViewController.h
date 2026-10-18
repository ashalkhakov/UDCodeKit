/*---------------------------------------------------------------------------------------------
 *  UDBuildLogViewController.h
 *
 *  A build's log, as Xcode's report navigator shows it: what the build said,
 *  as it says it, its errors red and its warnings orange, and under it how it
 *  went ("Build Succeeded", "Build Failed: 2 errors, 1 warning"). Laid out in
 *  UDBuildLog.xib; it follows the runner it is given.
 *--------------------------------------------------------------------------------------------*/

#import <Cocoa/Cocoa.h>
#import "UDBuildRunner.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDBuildLogViewController : NSViewController <UDBuildRunnerDelegate>

- (instancetype)init;

/// The build shown; the controller is its delegate, and passes what it is
/// told on to @a forward (the host's, say).
@property (nonatomic, strong, nullable) UDBuildRunner *runner;
@property (nonatomic, weak, nullable) id<UDBuildRunnerDelegate> forward;

@property (nonatomic, weak, readonly) IBOutlet NSTextView *logView;
@property (nonatomic, weak, readonly) IBOutlet NSTextField *statusLabel;

/// What the status says for @a runner: its command running, or how it went.
+ (NSString *)statusOfRunner:(nullable UDBuildRunner *)runner;

@end

NS_ASSUME_NONNULL_END
