/*---------------------------------------------------------------------------------------------
 *  UDCompletionListController.h
 *
 *  The list of completions at the word being typed, in a panel below it
 *  (UDEditorPopup), laid out in UDCompletionList.xib. The text view keeps
 *  the keyboard and hands the list the keys that are its (-handleKeyEvent:);
 *  accepting an item, by Return, Tab or a double-click, sends the action to
 *  the target.
 *--------------------------------------------------------------------------------------------*/

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface UDCompletionListController : NSWindowController <NSTableViewDataSource, NSTableViewDelegate>

/// Loads UDCompletionList.xib from UDCodeKit's bundle.
- (instancetype)init;

@property (nonatomic, weak, nullable) IBOutlet NSTableView *tableView;

/// Shows @a items below @a range of @a textView, the first selected.
- (void)showItems:(NSArray<NSString *> *)items atRange:(NSRange)range ofTextView:(NSTextView *)textView;

/// The items shown, and which is selected (NSNotFound: none).
@property (nonatomic, copy, readonly) NSArray<NSString *> *items;
@property (nonatomic, readonly) NSUInteger selectedIndex;
@property (nonatomic, readonly, nullable) NSString *selectedItem;

@property (nonatomic, readonly, getter=isShown) BOOL shown;
- (void)close;

/// Up, Down, Page Up and Page Down move the selection; Return and Tab
/// accept it; Escape closes the list. YES when @a event was the list's.
- (BOOL)handleKeyEvent:(NSEvent *)event;

/// What accepting an item sends (with this controller): -accept…:(id)sender.
@property (nonatomic, weak, nullable) id target;
@property (nonatomic, nullable) SEL action;

/// The table's double-click.
- (IBAction)acceptSelection:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
