/*---------------------------------------------------------------------------------------------
 *  UDLineNumberGutterView.h
 *
 *  A narrow strip displayed to the LEFT of the NSScrollView.
 *  Draws 1-based line numbers aligned with each visible line fragment produced
 *  by the text view's NSLayoutManager.
 *  Also renders ▼ / ▶ fold-indicator triangles for lines that contain a
 *  foldable region; click events on those triangles are forwarded via the
 *  delegate protocol.
 *  And, as Xcode's, the breakpoints, blue tags over the line numbers (pale
 *  when disabled, outlined when the debugger could not bind them; marked
 *  "=" when conditional and with a diamond when a logpoint, as VS Code
 *  marks them), and the debugger's instruction pointer, a green one; a
 *  click on a line number, or a breakpoint dragged off the gutter, goes to
 *  the delegate, which also gives the context menu of a line.
 *--------------------------------------------------------------------------------------------*/

#import <AppKit/AppKit.h>
#import <UDPieceTable/UDPieceTable.h>

/* UDCodeKit's own: exported where it is built for Windows (its GNUmakefile),
   imported everywhere else, as FOUNDATION_EXPORT. */
#ifndef UDCODEKIT_EXPORT
#define UDCODEKIT_EXPORT FOUNDATION_EXPORT
#endif

NS_ASSUME_NONNULL_BEGIN

@class UDLineNumberGutterView;

@protocol UDLineNumberGutterViewDelegate <NSObject>
@optional
/// Called when the user clicks the fold-indicator triangle for @c lineNumber (1-based).
- (void)lineNumberGutterView:(UDLineNumberGutterView *)view
  didClickFoldIndicatorAtLine:(NSInteger)lineNumber;
/// A click on line @a lineNumber's number (its breakpoint, when it has one).
- (void)lineNumberGutterView:(UDLineNumberGutterView *)view didClickLine:(NSInteger)lineNumber;
/// Line @a lineNumber's breakpoint was dragged off the gutter and let go.
- (void)lineNumberGutterView:(UDLineNumberGutterView *)view didDragBreakpointOffLine:(NSInteger)lineNumber;
/// The context menu of line @a lineNumber (a right click, or a control
/// click), nil for none.
- (nullable NSMenu *)lineNumberGutterView:(UDLineNumberGutterView *)view menuForLine:(NSInteger)lineNumber;
@end

/// How a line's breakpoint is drawn: one of the first three, and what it
/// does marked with one of the last two.
typedef NS_ENUM(NSInteger, UDGutterBreakpoint) {
    UDGutterBreakpointEnabled = 1,
    UDGutterBreakpointDisabled,
    /// Enabled, and the debugger could not bind it.
    UDGutterBreakpointUnverified,
    UDGutterBreakpointStateMask = 0x0F,
    /// With a condition or a hit count: marked "=".
    UDGutterBreakpointConditional = 0x10,
    /// A logpoint: marked with a diamond.
    UDGutterBreakpointLogpoint = 0x20,
};

/// What the gutter asks about breakpoints, for the lines it draws.
@protocol UDLineNumberGutterBreakpointSource <NSObject>
/// The lines (1-based) among @a lines with a breakpoint: line → UDGutterBreakpoint.
- (NSDictionary<NSNumber *, NSNumber *> *)breakpointsInLines:(NSRange)lines;
/// The line the debugger stands at in this text, 0 when it is not in it.
- (NSInteger)instructionPointerLine;
@end

/// What the gutter asks about folding, for the lines it draws.
@protocol UDLineNumberGutterFoldingSource <NSObject>
/// The lines (1-based) among @a lines on which a foldable region opens.
- (NSIndexSet *)foldableLinesInRange:(NSRange)lines;
/// The lines among @a lines whose region is folded.
- (NSIndexSet *)foldedLinesInRange:(NSRange)lines;
@end

/// Preferred width of the line-number gutter view.
UDCODEKIT_EXPORT const CGFloat UDLineNumberGutterWidth;

@interface UDLineNumberGutterView : NSView

- (instancetype)initWithScrollView:(NSScrollView *)scrollView
                          textView:(NSTextView *)textView
                         textModel:(UDTextModel *)textModel;

/// Shows the lines of @a textView, in @a scrollView, of @a textModel — for
/// a gutter loaded from a XIB (or to move it to another text view).
- (void)attachToScrollView:(NSScrollView *)scrollView
                  textView:(NSTextView *)textView
                 textModel:(UDTextModel *)textModel;

@property (nonatomic, weak, nullable) IBOutlet id<UDLineNumberGutterViewDelegate> delegate;

/// Which of the drawn lines show a fold indicator, and which of those are
/// folded. Asked for the visible lines only, on each draw.
@property (nonatomic, weak, nullable) id<UDLineNumberGutterFoldingSource> foldingSource;

/// The breakpoints and the instruction pointer to draw. Asked for the
/// visible lines only, on each draw.
@property (nonatomic, weak, nullable) id<UDLineNumberGutterBreakpointSource> breakpointSource;

/// The line at @a point (in the gutter's coordinates), 0 when none is there.
- (NSInteger)lineAtPoint:(NSPoint)point;

@end

NS_ASSUME_NONNULL_END
