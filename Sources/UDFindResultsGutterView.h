/*---------------------------------------------------------------------------------------------
 *  UDFindResultsGutterView.h
 *
 *  A narrow vertical strip drawn to the right of the NSScrollView.
 *  Each search-match is represented as a small coloured tick mark at its
 *  proportional position in the document — similar to the Xcode warning/error
 *  gutter shown on the right side of the editor.
 *--------------------------------------------------------------------------------------------*/

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface UDFindResultsGutterView : NSView

/// Each element is an NSNumber (0.0 … 1.0) giving the fractional vertical
/// position of a search match (0.0 = top of document, 1.0 = bottom).
@property (nonatomic, copy) NSArray<NSNumber *> *matchFractions;

/// Index of the match currently scrolled into view.
/// The corresponding tick is drawn in a distinct (orange) colour.
/// Pass -1 for "no current match".
@property (nonatomic) NSInteger currentMatchIndex;

/// Each element is an NSNumber (0.0 … 1.0) giving the fractional vertical
/// position of a parse error (0.0 = top of document, 1.0 = bottom).
/// Error ticks are drawn in red, behind the find-match ticks.
@property (nonatomic, copy) NSArray<NSNumber *> *errorFractions;

@end

NS_ASSUME_NONNULL_END
