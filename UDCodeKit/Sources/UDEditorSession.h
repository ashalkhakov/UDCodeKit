/*---------------------------------------------------------------------------------------------
 *  UDEditorSession.h
 *
 *  One open document's editor services: the text storage over its text model,
 *  the parse-error and missing-node highlighters, the collector that feeds
 *  parse errors into the document's diagnostic store, and the language server.
 *
 *  Any number of UDTextEditorViewControllers may show one session: each adds
 *  its own layout manager to the shared text storage.
 *
 *  Lifecycle:
 *    1. -initWithDocument:
 *    2. create the first editor view controller and load its view, so its
 *       layout manager is attached before the first parse;
 *    3. -activateWithTheme:;
 *    4. -startLanguageServer, when the language mode names one;
 *    5. -close.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import <LSPKit/LSPKit.h>
#import "UDCodeDocument.h"
#import "UDTextModelTextStorage.h"
#import "UDLSPCoordinator.h"

@class TreeSitterTheme;

NS_ASSUME_NONNULL_BEGIN

@interface UDEditorSession : NSObject

@property (nonatomic, strong, readonly) UDCodeDocument         *document;
@property (nonatomic, strong, readonly) UDTextModelTextStorage *textStorage;

/// The language server, once -startLanguageServer found one.
@property (nonatomic, strong, readonly, nullable) UDLSPCoordinator *lspCoordinator;

/// The last completion list the language server gave.
@property (nonatomic, strong, nullable) NSArray<LSPCompletionItem *> *completionList;

- (instancetype)initWithDocument:(UDCodeDocument *)document NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// Sets the theme and the document's grammar, runs the first parse and starts
/// the parse diagnostics. Call after the first editor's view has loaded.
- (void)activateWithTheme:(nullable TreeSitterTheme *)theme;

/// Starts the language server the document's language mode names, if it has
/// one and it is installed. Returns whether one started.
- (BOOL)startLanguageServer;

/// Tells the language server the document closed.
- (void)close;

@end

NS_ASSUME_NONNULL_END
