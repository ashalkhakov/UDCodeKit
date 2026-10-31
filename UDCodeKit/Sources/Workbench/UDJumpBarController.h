/*---------------------------------------------------------------------------------------------
 *  UDJumpBarController.h
 *
 *  An editor's jump bar (UDJumpBarView), as VS Code's breadcrumbs work: the
 *  file's path from the project's folder (each folder a segment), then the
 *  symbols holding the caret (the session's: the language server's or the
 *  outline query's), kept as the caret moves and the text changes (the
 *  symbols asked again once the typing rests). A path segment's menu lists
 *  its folder's files and folders (each folder a submenu), to open one; a
 *  symbol segment's lists the file's symbols, to go to one.
 *--------------------------------------------------------------------------------------------*/

#import <AppKit/AppKit.h>
#import <UDCodeKit/UDJumpBarView.h>

NS_ASSUME_NONNULL_BEGIN

@class UDJumpBarController, UDCodeEditorViewController, UDEditorSession;

@protocol UDJumpBarControllerDelegate <NSObject>
/// A file chosen in a path segment's menu.
- (void)jumpBarController:(UDJumpBarController *)controller openURL:(NSURL *)url;
@end

@interface UDJumpBarController : NSObject <UDJumpBarViewDelegate, NSMenuDelegate>

/// The jump bar of @a editor (its jumpBar) for @a session's document;
/// @a rootURL is the project's folder (nil: the path is the file's name).
- (instancetype)initWithEditor:(UDCodeEditorViewController *)editor session:(UDEditorSession *)session
                       rootURL:(nullable NSURL *)rootURL;

@property (nonatomic, weak, nullable) id<UDJumpBarControllerDelegate> delegate;
/// Names left out of the folders' menus (the project navigator's).
@property (nonatomic, copy) NSSet<NSString *> *hiddenNames;

/// The symbols, the last the session gave; the path at the caret.
@property (nonatomic, readonly, copy) NSArray<UDDocumentSymbol *> *symbols;
@property (nonatomic, readonly, copy) NSArray<UDDocumentSymbol *> *symbolPath;

/// The symbols asked for again now (else: once the typing rests).
- (void)refreshSymbols;

/// Goes to @a symbol in the editor: the caret at its name, shown.
- (void)revealSymbol:(UDDocumentSymbol *)symbol;

@end

NS_ASSUME_NONNULL_END
