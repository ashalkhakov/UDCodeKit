/*---------------------------------------------------------------------------------------------
 *  UDSearchResultsViewController.h
 *
 *  The Find navigator, as Xcode's: a search field over what is found, by
 *  file, each match's line with its text. It shows a search of the folder's
 *  files (Find in Workspace: the existing tools, ripgrep when it is there,
 *  else grep) and a language server's references (Find References); a click
 *  on a match asks the delegate to show it. Laid out in UDSearchResults.xib.
 *--------------------------------------------------------------------------------------------*/

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

/// One match: where, and its line's text.
@interface UDSearchResult : NSObject
- (instancetype)initWithURL:(NSURL *)url line:(NSInteger)line column:(NSInteger)column length:(NSInteger)length
                   lineText:(nullable NSString *)lineText;
@property (nonatomic, readonly, copy) NSURL *url;
/// 1-based.
@property (nonatomic, readonly) NSInteger line;
/// 0-based, in UTF-16 characters.
@property (nonatomic, readonly) NSInteger column;
@property (nonatomic, readonly) NSInteger length;
@property (nonatomic, readonly, copy, nullable) NSString *lineText;
@end

@class UDSearchResultsViewController;

@protocol UDSearchResultsDelegate <NSObject>
/// A match chosen: its file, at its place.
- (void)searchResults:(UDSearchResultsViewController *)controller showResult:(UDSearchResult *)result;
@end

@interface UDSearchResultsViewController : NSViewController <NSOutlineViewDataSource, NSOutlineViewDelegate>

- (instancetype)init;

@property (nonatomic, weak, nullable) id<UDSearchResultsDelegate> delegate;
/// The folder Find in Workspace searches; nil: none.
@property (nonatomic, copy, nullable) NSURL *folderURL;

@property (nonatomic, weak, readonly) IBOutlet NSSearchField *searchField;
@property (nonatomic, weak, readonly) IBOutlet NSOutlineView *outlineView;
@property (nonatomic, weak, readonly) IBOutlet NSTextField *statusLabel;

/// What is shown, under a title ("3 references to x"), files in the order found.
- (void)showResults:(NSArray<UDSearchResult *> *)results title:(NSString *)title;
@property (nonatomic, readonly, copy) NSArray<UDSearchResult *> *results;

/// The search field's text searched for in the folder's files (literally,
/// case-insensitively), the results shown as they come.
- (IBAction)search:(nullable id)sender;
- (void)searchFor:(NSString *)text;
@property (nonatomic, readonly, getter=isSearching) BOOL searching;

- (IBAction)showSelectedResult:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
