/*---------------------------------------------------------------------------------------------
 *  UDOpenQuicklyController.h
 *
 *  Open Quickly (⇧⌘O), as Xcode's: a sheet with a field, and as it is typed
 *  the project's files whose names match (the letters in order; ripgrep's
 *  list when it is there, so .gitignore's files are left out) and the
 *  language server's symbols (workspace/symbol). Return opens the chosen
 *  one: the delegate is asked to show it. Laid out in UDOpenQuickly.xib.
 *--------------------------------------------------------------------------------------------*/

#import <Cocoa/Cocoa.h>

@class LSPClient, UDOpenQuicklyController, UDSearchResult;

NS_ASSUME_NONNULL_BEGIN

@protocol UDOpenQuicklyDelegate <NSObject>
/// A file (line 0: no place in it) or a symbol's place chosen.
- (void)openQuickly:(UDOpenQuicklyController *)controller showResult:(UDSearchResult *)result;
@end

@interface UDOpenQuicklyController : NSWindowController <NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate>

- (instancetype)init;

@property (nonatomic, weak, nullable) id<UDOpenQuicklyDelegate> delegate;
/// The folder whose files are listed.
@property (nonatomic, copy, nullable) NSURL *folderURL;
/// The server asked for symbols; nil: files only.
@property (nonatomic, strong, nullable) LSPClient *client;

- (void)beginSheetForWindow:(NSWindow *)window;

/// What is typed; setting it searches, as typing does.
@property (nonatomic, copy) NSString *query;
/// The matches, files then symbols: each a result's line 0 for a file.
@property (nonatomic, readonly, copy) NSArray<UDSearchResult *> *results;
/// The files of the folder, relative to it.
@property (nonatomic, readonly, copy) NSArray<NSString *> *files;

@property (nonatomic, weak, readonly) IBOutlet NSSearchField *searchField;
@property (nonatomic, weak, readonly) IBOutlet NSTableView *tableView;

/// The selected match, opened.
- (IBAction)open:(nullable id)sender;
- (IBAction)cancel:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
