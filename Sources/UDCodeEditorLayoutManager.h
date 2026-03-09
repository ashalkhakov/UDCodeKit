/*---------------------------------------------------------------------------------------------
 *  UDCodeEditorLayoutManager.h
 *
 *  A lean NSLayoutManager subclass tuned for code-editing text views.
 *
 *  Optimisations over the stock NSLayoutManager:
 *
 *  1. allowsNonContiguousLayout = YES
 *     Stock NSLayoutManager lays out text sequentially from character 0.
 *     When the visible area is near the END of a large document (e.g. after
 *     pasting 165 KB at the end of a 165 KB file), every call to
 *     -glyphRangeForBoundingRect:inTextContainer: forces O(N) work — it must
 *     lay out the ENTIRE document to reach the requested position.
 *
 *     With non-contiguous layout the manager lays out only the requested
 *     window, reducing glyphRangeForBoundingRect: from O(fullDoc) to
 *     O(visibleArea) — typically a 100–1000× speedup for large files.
 *
 *  2. backgroundLayoutEnabled = YES
 *     Off-screen text is laid out asynchronously between events, keeping the
 *     UI responsive during large pastes and initial document load.
 *
 *  GNUstep compatibility: both properties are accessed via -respondsToSelector:
 *  guards so that the class compiles and runs correctly on GNUstep builds where
 *  one or both properties may not yet be implemented.
 *--------------------------------------------------------------------------------------------*/

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface UDCodeEditorLayoutManager : NSLayoutManager
@end

NS_ASSUME_NONNULL_END
