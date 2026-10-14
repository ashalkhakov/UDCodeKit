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

NS_ASSUME_NONNULL_BEGIN

@class UDLineNumberGutterView;

@protocol UDLineNumberGutterViewDelegate <NSObject>
@optional
/// Called when the user clicks the fold-indicator triangle for @c lineNumber (1-based).
- (void)lineNumberGutterView:(UDLineNumberGutterView *)view
  didClickFoldIndicatorAtLine:(NSInteger)lineNumber;
@end

/// What the gutter asks about folding, for the lines it draws.
@protocol UDLineNumberGutterFoldingSource <NSObject>
/// The lines (1-based) among @a lines on which a foldable region opens.
- (NSIndexSet *)foldableLinesInRange:(NSRange)lines;
/// The lines among @a lines whose region is folded.
- (NSIndexSet *)foldedLinesInRange:(NSRange)lines;
@end

/// Preferred width of the line-number gutter view.
extern const CGFloat UDLineNumberGutterWidth;

@interface UDLineNumberGutterView : NSView

- (instancetype)initWithScrollView:(NSScrollView *)scrollView
                          textView:(NSTextView *)textView
                         textModel:(UDTextModel *)textModel;

@property (nonatomic, weak, nullable) id<UDLineNumberGutterViewDelegate> delegate;

/// Which of the drawn lines show a fold indicator, and which of those are
/// folded. Asked for the visible lines only, on each draw.
@property (nonatomic, weak, nullable) id<UDLineNumberGutterFoldingSource> foldingSource;

@end

NS_ASSUME_NONNULL_END
