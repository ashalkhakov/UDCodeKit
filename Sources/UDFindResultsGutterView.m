/*---------------------------------------------------------------------------------------------
 *  UDFindResultsGutterView.m
 *--------------------------------------------------------------------------------------------*/

#import "UDFindResultsGutterView.h"

@implementation UDFindResultsGutterView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _matchFractions    = @[];
        _errorFractions    = @[];
        _currentMatchIndex = -1;
    }
    return self;
}

// ---------------------------------------------------------------------------
// MARK: - Drawing
// ---------------------------------------------------------------------------

- (void)drawRect:(NSRect)dirtyRect {
    // Background
    [[NSColor windowBackgroundColor] setFill];
    NSRectFill(self.bounds);

    // 1-px left border
    [[NSColor separatorColor] setFill];
    NSRectFill(NSMakeRect(0.0, 0.0, 1.0, NSHeight(self.bounds)));

    CGFloat totalH = NSHeight(self.bounds);
    CGFloat tickW  = NSWidth(self.bounds) - 4.0;
    CGFloat tickH  = 3.0;

    // Draw error ticks first (red), so find-match ticks appear on top.
    if (_errorFractions.count > 0) {
        [[NSColor systemRedColor] setFill];
        for (NSNumber *frac in _errorFractions) {
            CGFloat y = (1.0 - frac.doubleValue) * (totalH - tickH);
            NSRectFill(NSMakeRect(2.0, y, tickW, tickH));
        }
    }

    // Draw find-match ticks (orange for current, yellow for the rest).
    for (NSUInteger i = 0; i < _matchFractions.count; i++) {
        CGFloat frac = [_matchFractions[i] doubleValue]; // 0 = top, 1 = bottom
        // Map frac → y origin (AppKit y-axis grows upward):
        CGFloat y = (1.0 - frac) * (totalH - tickH);

        NSColor *color = ((NSInteger)i == _currentMatchIndex)
            ? [NSColor systemOrangeColor]
            : [NSColor systemYellowColor];
        [color setFill];
        NSRectFill(NSMakeRect(2.0, y, tickW, tickH));
    }
}

// ---------------------------------------------------------------------------
// MARK: - Property setters (trigger redraw)
// ---------------------------------------------------------------------------

- (void)setMatchFractions:(NSArray<NSNumber *> *)matchFractions {
    _matchFractions = [matchFractions copy];
    [self setNeedsDisplay:YES];
}

- (void)setCurrentMatchIndex:(NSInteger)currentMatchIndex {
    _currentMatchIndex = currentMatchIndex;
    [self setNeedsDisplay:YES];
}

- (void)setErrorFractions:(NSArray<NSNumber *> *)errorFractions {
    _errorFractions = [errorFractions copy];
    [self setNeedsDisplay:YES];
}

@end
