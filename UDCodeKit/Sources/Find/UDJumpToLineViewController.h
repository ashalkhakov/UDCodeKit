/*---------------------------------------------------------------------------------------------
 *  UDJumpToLineViewController.h
 *
 *  Jump to Line (⌘L, as Xcode has it): a strip over the editor, laid out in
 *  UDJumpToLine.xib, with a field for the line. Return goes there, Escape
 *  puts it away; the delegate does the going.
 *--------------------------------------------------------------------------------------------*/

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class UDJumpToLineViewController;

@protocol UDJumpToLineDelegate <NSObject>
- (void)jumpToLine:(UDJumpToLineViewController *)controller didChooseLine:(NSInteger)line;
- (void)jumpToLineDidCancel:(UDJumpToLineViewController *)controller;
@end

extern const CGFloat UDJumpToLineHeight;

@interface UDJumpToLineViewController : NSViewController <NSTextFieldDelegate>

/// Loads UDJumpToLine.xib from UDCodeKit's bundle.
- (instancetype)init;

@property (nonatomic, weak, nullable) IBOutlet NSTextField *lineField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *rangeLabel;
@property (nonatomic, weak, nullable) id<UDJumpToLineDelegate> delegate;

/// An empty field, the keyboard in it; @a lineCount says which lines there are.
- (void)focusWithLineCount:(NSInteger)lineCount;

/// The field's Return.
- (IBAction)jump:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
