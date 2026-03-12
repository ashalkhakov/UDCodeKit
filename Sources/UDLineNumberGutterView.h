/*---------------------------------------------------------------------------------------------
 *  UDLineNumberGutterView.h
 *
 *  A narrow strip displayed to the LEFT of the NSScrollView.
 *  Draws 1-based line numbers aligned with each visible line fragment produced
 *  by the text view's NSLayoutManager.
 *  Also renders ▼ / ▶ fold-indicator triangles for lines that contain a
 *  foldable region; click events on those triangles are forwarded via the
 *  delegate protocol.
 *--------------------------------------------------------------------------------------------*/

#import <AppKit/AppKit.h>
#import <UDPieceTable/UDPieceTable.h>
@class UDTextModel;

NS_ASSUME_NONNULL_BEGIN

@class UDLineNumberGutterView;

@protocol UDLineNumberGutterViewDelegate <NSObject>
@optional
/// Called when the user clicks the fold-indicator triangle for @c lineNumber (1-based).
- (void)lineNumberGutterView:(UDLineNumberGutterView *)view
  didClickFoldIndicatorAtLine:(NSInteger)lineNumber;
@end

/// Preferred width of the line-number gutter view.
extern const CGFloat UDLineNumberGutterWidth;

@interface UDLineNumberGutterView : NSView

- (instancetype)initWithScrollView:(NSScrollView *)scrollView
                          textView:(NSTextView *)textView
                         textModel:(UDTextModel *)textModel;

@property (nonatomic, weak, nullable) id<UDLineNumberGutterViewDelegate> delegate;

/// 1-based line numbers whose first character begins a foldable region.
/// Setting this property triggers a redraw.
@property (nonatomic, copy) NSSet<NSNumber *> *foldableLines;

/// Subset of foldableLines that are currently folded (interior collapsed).
/// Setting this property triggers a redraw.
@property (nonatomic, copy) NSSet<NSNumber *> *foldedLines;

@end

NS_ASSUME_NONNULL_END
