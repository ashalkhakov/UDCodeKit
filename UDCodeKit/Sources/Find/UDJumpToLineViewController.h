/*---------------------------------------------------------------------------------------------
 *  UDJumpToLineViewController.h
 *
 *  Jump to Line (⌘L, as Xcode has it): a box floating over the top of the
 *  editor, with a field for the line, laid out in UDJumpToLine.xib. Return
 *  goes there; Escape, or the keyboard going elsewhere, puts it away; the
 *  delegate does the going.
 *
 *  The box is a borderless panel, a child of the editor's window, that may
 *  become key (a borderless window may not, on macOS and GNUstep alike,
 *  unless it says so): its field takes the keyboard as any window's does,
 *  and the editor's window gets it back when the box goes. Not NSPopover,
 *  which points at its anchor and, on GNUstep, cannot take the keyboard.
 *--------------------------------------------------------------------------------------------*/

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class UDJumpToLineViewController;

@protocol UDJumpToLineDelegate <NSObject>
- (void)jumpToLine:(UDJumpToLineViewController *)controller didChooseLine:(NSInteger)line;
- (void)jumpToLineDidCancel:(UDJumpToLineViewController *)controller;
@end

/// The box's window: borderless, and yet it becomes key.
@interface UDJumpToLinePanel : NSPanel
@end

@interface UDJumpToLineViewController : NSViewController <NSTextFieldDelegate>

/// Loads UDJumpToLine.xib from UDCodeKit's bundle.
- (instancetype)init;

@property (nonatomic, strong, nullable) IBOutlet UDJumpToLinePanel *panel;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *lineField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *rangeLabel;
@property (nonatomic, weak, nullable) id<UDJumpToLineDelegate> delegate;

/// The box over the top of @a view (centred, a little below its top
/// edge), an empty field, the keyboard in it; @a lineCount says which
/// lines there are.
- (void)showOverView:(NSView *)view lineCount:(NSInteger)lineCount;
/// The box put away, the keyboard back with the window it floated over.
- (void)close;
/// Whether the box is up.
@property (nonatomic, readonly, getter=isShown) BOOL shown;

/// The field's Return.
- (IBAction)jump:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
