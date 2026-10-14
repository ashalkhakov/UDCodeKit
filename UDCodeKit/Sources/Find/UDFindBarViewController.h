/*---------------------------------------------------------------------------------------------
 *  UDFindBarViewController.h
 *
 *  The Xcode-like find and replace bar over an editor's text view, a view of
 *  a UDFindModel. Laid out in UDFindBar.xib: Find/Replace, the search field
 *  with "N of M", previous and next, match case, whole word and regex, Done;
 *  in Replace mode a second row with the replacement, Replace and All.
 *--------------------------------------------------------------------------------------------*/

#import <Cocoa/Cocoa.h>
#import "UDFindModel.h"

NS_ASSUME_NONNULL_BEGIN

@class UDFindBarViewController;

@protocol UDFindBarDelegate <NSObject>
/// The bar wants this height: one row to find, two to replace.
- (void)findBar:(UDFindBarViewController *)findBar wantsHeight:(CGFloat)height;
/// Done (or Escape): the bar should go away.
- (void)findBarDidClose:(UDFindBarViewController *)findBar;
@end

/// The bar's heights, finding and replacing.
extern const CGFloat UDFindBarFindHeight;
extern const CGFloat UDFindBarReplaceHeight;

@interface UDFindBarViewController : NSViewController <NSSearchFieldDelegate, NSTextFieldDelegate>

/// Loads UDFindBar.xib from UDCodeKit's bundle.
- (instancetype)initWithFindModel:(UDFindModel *)findModel textView:(NSTextView *)textView NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithNibName:(nullable NSNibName)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;

@property (nonatomic, strong, readonly) UDFindModel *findModel;
@property (nonatomic, weak, readonly) NSTextView *textView;
@property (nonatomic, weak, nullable) id<UDFindBarDelegate> delegate;

/// Whether the replace row shows.
@property (nonatomic, getter=isReplacing) BOOL replacing;

@property (nonatomic, weak) IBOutlet NSSegmentedControl *modeControl;
@property (nonatomic, weak) IBOutlet NSSearchField      *findField;
@property (nonatomic, weak) IBOutlet NSTextField        *statusLabel;
@property (nonatomic, weak) IBOutlet NSSegmentedControl *navigationControl;
@property (nonatomic, weak) IBOutlet NSButton           *matchCaseButton;
@property (nonatomic, weak) IBOutlet NSButton           *wholeWordButton;
@property (nonatomic, weak) IBOutlet NSButton           *regexButton;
@property (nonatomic, weak) IBOutlet NSButton           *doneButton;
@property (nonatomic, weak) IBOutlet NSView             *replaceRow;
@property (nonatomic, weak) IBOutlet NSTextField        *replaceField;
@property (nonatomic, weak) IBOutlet NSButton           *replaceButton;
@property (nonatomic, weak) IBOutlet NSButton           *replaceAllButton;

/// Puts the cursor in the search field (with @a searchString, when given)
/// and searches.
- (void)focusWithSearchString:(nullable NSString *)searchString;

- (IBAction)findFieldChanged:(nullable id)sender;
- (IBAction)navigate:(nullable id)sender;
- (IBAction)findNext:(nullable id)sender;
- (IBAction)findPrevious:(nullable id)sender;
- (IBAction)optionsChanged:(nullable id)sender;
- (IBAction)modeChanged:(nullable id)sender;
- (IBAction)replace:(nullable id)sender;
- (IBAction)replaceAll:(nullable id)sender;
- (IBAction)done:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
