/*---------------------------------------------------------------------------------------------
 *  UDBuildLogViewController.m
 *--------------------------------------------------------------------------------------------*/

#import "UDBuildLogViewController.h"

@interface UDBuildLogViewController ()
@property (nonatomic, weak) IBOutlet NSTextView *logView;
@property (nonatomic, weak) IBOutlet NSTextField *statusLabel;
@end

@implementation UDBuildLogViewController {
    NSMutableString *_pendingLine;
}

- (instancetype)init {
    return [super initWithNibName:@"UDBuildLog" bundle:[NSBundle bundleForClass:[UDBuildLogViewController class]]];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _logView.font = [NSFont userFixedPitchFontOfSize:11.0];
    _statusLabel.stringValue = [UDBuildLogViewController statusOfRunner:_runner];
}

- (void)setRunner:(UDBuildRunner *)runner {
    if (_runner.delegate == self) _runner.delegate = nil;
    _runner = runner;
    runner.delegate = self;
    (void)self.view;
    [_logView.textStorage setAttributedString:[[NSAttributedString alloc] initWithString:@""]];
    _pendingLine = [NSMutableString string];
    if (runner.output.length) [self _append:runner.output];
    _statusLabel.stringValue = [UDBuildLogViewController statusOfRunner:runner];
}

+ (NSString *)statusOfRunner:(UDBuildRunner *)runner {
    if (!runner.command) return @"";
    if (runner.running) return [NSString stringWithFormat:@"Running %@…", runner.command];
    NSMutableArray<NSString *> *counts = [NSMutableArray array];
    if (runner.errorCount) [counts addObject:[NSString stringWithFormat:@"%lu error%@", (unsigned long)runner.errorCount,
                                              runner.errorCount == 1 ? @"" : @"s"]];
    if (runner.warningCount) [counts addObject:[NSString stringWithFormat:@"%lu warning%@", (unsigned long)runner.warningCount,
                                                runner.warningCount == 1 ? @"" : @"s"]];
    NSString *verdict = runner.succeeded ? @"Succeeded" : @"Failed";
    return counts.count ? [NSString stringWithFormat:@"%@: %@", verdict, [counts componentsJoinedByString:@", "]] : verdict;
}

/// Errors red, warnings orange, the rest as text: a line at a time.
- (void)_append:(NSString *)text {
    [_pendingLine appendString:text];
    NSRange end = [_pendingLine rangeOfString:@"\n" options:NSBackwardsSearch];
    if (end.location == NSNotFound) return;
    NSString *lines = [_pendingLine substringToIndex:NSMaxRange(end)];
    [_pendingLine deleteCharactersInRange:NSMakeRange(0, NSMaxRange(end))];
    NSFont *font = [NSFont userFixedPitchFontOfSize:11.0];
    NSMutableAttributedString *styled = [[NSMutableAttributedString alloc] init];
    for (NSString *line in [lines componentsSeparatedByString:@"\n"]) {
        if (!line.length) continue;
        NSColor *color = [NSColor textColor];
        if ([line rangeOfString:@": error: "].location != NSNotFound || [line rangeOfString:@": fatal error: "].location != NSNotFound) {
            color = [NSColor systemRedColor];
        } else if ([line rangeOfString:@": warning: "].location != NSNotFound) {
            color = [NSColor systemOrangeColor];
        }
        [styled appendAttributedString:[[NSAttributedString alloc] initWithString:[line stringByAppendingString:@"\n"]
                                                                       attributes:@{ NSFontAttributeName: font,
                                                                                     NSForegroundColorAttributeName: color }]];
    }
    [_logView.textStorage appendAttributedString:styled];
    [_logView scrollRangeToVisible:NSMakeRange(_logView.textStorage.length, 0)];
}

// ---------------------------------------------------------------------------
// MARK: - UDBuildRunnerDelegate
// ---------------------------------------------------------------------------

- (void)buildRunner:(UDBuildRunner *)runner didOutput:(NSString *)text {
    if (_logView.textStorage.length == 0 && _pendingLine.length == 0) {
        _statusLabel.stringValue = [UDBuildLogViewController statusOfRunner:runner];
    }
    [self _append:text];
    if ([_forward respondsToSelector:@selector(buildRunner:didOutput:)]) [_forward buildRunner:runner didOutput:text];
}

- (void)buildRunnerDidFinish:(UDBuildRunner *)runner {
    if (_pendingLine.length) [self _append:@"\n"];
    _statusLabel.stringValue = [UDBuildLogViewController statusOfRunner:runner];
    if ([_forward respondsToSelector:@selector(buildRunnerDidFinish:)]) [_forward buildRunnerDidFinish:runner];
}

@end
