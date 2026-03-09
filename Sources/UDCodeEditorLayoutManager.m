/*---------------------------------------------------------------------------------------------
 *  UDCodeEditorLayoutManager.m
 *--------------------------------------------------------------------------------------------*/

#import "UDCodeEditorLayoutManager.h"

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

@end
