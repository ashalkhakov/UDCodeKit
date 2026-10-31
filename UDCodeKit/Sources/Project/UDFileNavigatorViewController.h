/*---------------------------------------------------------------------------------------------
 *  UDFileNavigatorViewController.h
 *
 *  A folder's files as Xcode's project navigator and VS Code's Explorer show
 *  them: an outline, folders first, each listed when it is first opened
 *  (never the whole tree), hidden files and version control's folders left
 *  out. A click on a file asks the delegate to open it.
 *
 *  -reload lists what was listed again (after a build, or when the window
 *  comes back), keeping what was open and selected. Laid out in
 *  UDFileNavigator.xib.
 *--------------------------------------------------------------------------------------------*/

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@class UDFileNavigatorViewController;

@protocol UDFileNavigatorDelegate <NSObject>
/// A file was chosen (a click, or Return).
- (void)fileNavigator:(UDFileNavigatorViewController *)navigator openFileAtURL:(NSURL *)url;
@optional
/// The context menu of the file or folder at @a url (VS Code's Explorer's:
/// Select for Compare, ...); none when there are none.
- (NSArray<NSMenuItem *> *)fileNavigator:(UDFileNavigatorViewController *)navigator menuItemsForURL:(NSURL *)url;
@end

@interface UDFileNavigatorViewController : NSViewController <NSOutlineViewDataSource, NSOutlineViewDelegate>

- (instancetype)init;

@property (nonatomic, weak, nullable) id<UDFileNavigatorDelegate> delegate;
/// The folder shown; nil shows nothing.
@property (nonatomic, copy, nullable) NSURL *folderURL;

/// Files and folders by name, left out: ".git", ".udcode", ".DS_Store" and
/// any name starting with a dot, unless set otherwise.
@property (nonatomic, copy) NSSet<NSString *> *hiddenNames;

@property (nonatomic, weak, readonly) IBOutlet NSOutlineView *outlineView;

/// Lists again what was listed, what was expanded kept expanded.
- (void)reload;
/// Shows @a url (its folders expanded) and selects it.
- (void)revealURL:(NSURL *)url;
/// The URL @a row shows.
- (nullable NSURL *)URLOfRow:(NSInteger)row;

- (IBAction)openSelectedFile:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
