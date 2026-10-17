/*---------------------------------------------------------------------------------------------
 *  UDJumpToLineViewController.h
 *
 *  Jump to Line (⌘L, as Xcode has it): a box over the top of the editor,
 *  with a field for the line, laid out in UDJumpToLine.xib. Return goes
 *  there; Escape, or the field losing the keyboard (a click in the text),
 *  puts it away; the delegate does the going.
 *
 *  The box is a view laid over the editor's scroll view (its sibling, above
 *  it; not in the scrolled text), so its field takes the keyboard in the
 *  editor's own window. On GNUstep that needs gnustep-patches'
 *  view-overlapping-siblings: without it, the text redrawing under the box
 *  painted over it. Not NSPopover, which points at its anchor and, on
 *  GNUstep, cannot take the keyboard.
 *--------------------------------------------------------------------------------------------*/

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class UDJumpToLineViewController;

@protocol UDJumpToLineDelegate <NSObject>
- (void)jumpToLine:(UDJumpToLineViewController *)controller didChooseLine:(NSInteger)line;
- (void)jumpToLineDidCancel:(UDJumpToLineViewController *)controller;
@end

@interface UDJumpToLineViewController : NSViewController <NSTextFieldDelegate>

/// Loads UDJumpToLine.xib from UDCodeKit's bundle.
- (instancetype)init;

@property (nonatomic, weak, nullable) IBOutlet NSTextField *lineField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *rangeLabel;
@property (nonatomic, weak, nullable) id<UDJumpToLineDelegate> delegate;

/// The box over the top of @a view (centred, a little below its top
/// edge), laid on @a view's superview above it; an empty field, the
/// keyboard in it; @a lineCount says which lines there are.
- (void)showOverView:(NSView *)view lineCount:(NSInteger)lineCount;
/// The box put away.
- (void)close;
/// Whether the box is up.
@property (nonatomic, readonly, getter=isShown) BOOL shown;

/// The field's Return.
- (IBAction)jump:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
