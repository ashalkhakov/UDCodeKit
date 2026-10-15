/*---------------------------------------------------------------------------------------------
 *  UDCodeEditorLayoutManager.m
 *--------------------------------------------------------------------------------------------*/

#import "UDCodeEditorLayoutManager.h"
#import "UDPlaceholderHighlighter.h"

@implementation UDCodeEditorLayoutManager

- (instancetype)init {
    self = [super init];
    if (!self) return nil;

    // ── 1. Non-contiguous layout ─────────────────────────────────────────────
    // Allows the manager to lay out only the requested area instead of
    // everything from character 0 up to that area.  Critical for large
    // documents where the visible area is near the end: without this,
    // -glyphRangeForBoundingRect:inTextContainer: forces O(N) work; with it
    // the work is O(visible_area).
    //
    // Guarded with -respondsToSelector: for GNUstep compatibility.
    if ([self respondsToSelector:@selector(setAllowsNonContiguousLayout:)]) {
        self.allowsNonContiguousLayout = YES;
    }

    // ── 2. Background layout ─────────────────────────────────────────────────
    // Lays out off-screen text asynchronously between run-loop cycles,
    // keeping the UI responsive during large pastes.
    //
    // Guarded with -respondsToSelector: for GNUstep compatibility.
    if ([self respondsToSelector:@selector(setBackgroundLayoutEnabled:)]) {
        self.backgroundLayoutEnabled = YES;
    }

    return self;
}

// ── Placeholders: a rounded pill behind each one's text ─────────────────────
- (void)drawBackgroundForGlyphRange:(NSRange)glyphsToShow atPoint:(NSPoint)origin {
    [super drawBackgroundForGlyphRange:glyphsToShow atPoint:origin];
    NSTextStorage *storage = self.textStorage;
    NSTextContainer *container = self.textContainers.firstObject;
    if (storage == nil || container == nil) return;
    NSRange characters = [self characterRangeForGlyphRange:glyphsToShow actualGlyphRange:NULL];
    NSUInteger index = characters.location, end = NSMaxRange(characters);
    while (index < end) {
        NSRange run;
        id pill = [storage attribute:UDPlaceholderAttributeName atIndex:index longestEffectiveRange:&run
                             inRange:NSMakeRange(index, end - index)];
        if (pill != nil) {
            NSRange glyphs = [self glyphRangeForCharacterRange:run actualCharacterRange:NULL];
            NSRect rect = [self boundingRectForGlyphRange:glyphs inTextContainer:container];
            rect = NSInsetRect(NSOffsetRect(rect, origin.x, origin.y), -3, 1);
            NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:4 yRadius:4];
            [[NSColor colorWithCalibratedRed:0.55 green:0.68 blue:0.90 alpha:0.30] setFill];
            [path fill];
            [[NSColor colorWithCalibratedRed:0.40 green:0.55 blue:0.85 alpha:0.60] setStroke];
            [path stroke];
        }
        index = NSMaxRange(run);
    }
}

@end
