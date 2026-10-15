//
//  LSPClient.h
//  LSPKit
//
//  Created by Christopher Atlan on 12.01.19.
//  Copyright © 2019 Letter Opener GmbH. All rights reserved.
//

#import <Foundation/Foundation.h>

#import <LSPKit/LSPCommon.h>

NS_ASSUME_NONNULL_BEGIN

@class LSPClient;

/**
 * What a request to the server came back with, handed to the action the
 * request named: the request's identifier, the result (its type depends on
 * the request — see each request method), and the error, if any.
 */
@interface LSPResponse : NSObject
@property (readonly) NSInteger requestID;
@property (readonly, nullable) id result;
/** Completion: whether the list is incomplete (typing on should ask again). */
@property (readonly) BOOL isIncomplete;
@property (readonly, nullable) NSError *error;
@end

@protocol LSPTextBuffer <NSObject>
- (NSString *)text;
@end

@protocol LSPClientObserver <NSObject>

@optional
- (void)languageServer:(LSPClient *)client logMessage:(NSString *)message type:(LSPMessageType)type;
- (void)languageServer:(LSPClient *)client showMessage:(NSString *)message type:(LSPMessageType)type;
- (void)languageServer:(LSPClient *)client showMessageRequest:(NSString *)message actions:(NSArray<NSString *> *)actions;
- (void)languageServer:(LSPClient *)client telemetryEvent:(id)event;
- (void)languageServer:(LSPClient *)client document:(NSURL *)url diagnostics:(NSArray<LSPDiagnostic *> *)diagnostics;
/** The server ended without being asked to and was started again: open
    documents must be opened again (after initializing). */
- (void)languageServerDidRestart:(LSPClient *)client;

@end

/**
 * Defines how the host (editor) should sync document changes to the language server.
 */
typedef NS_ENUM(NSUInteger, LSPTextDocumentSyncKind) {
    /**
     * Documents should not be synced at all.
     */
    LSPTextDocumentSyncKindNone = 0,
    /**
     * Documents are synced by always sending the full content
     * of the document.
     */
    LSPTextDocumentSyncKindFull = 1,
    /**
     * Documents are synced by sending the full content on open.
     * After that only incremental updates to the document are
     * send.
     */
    LSPTextDocumentSyncKindIncremental = 2,
};

typedef struct _LSPTextDocumentSyncOptions {
    /**
     * Open and close notifications are sent to the server.
     */
    BOOL openClose;
    /**
     * Change notifications are sent to the server. See TextDocumentSyncKind.None, TextDocumentSyncKind.Full
     * and TextDocumentSyncKind.Incremental. If omitted it defaults to TextDocumentSyncKind.None.
     */
    LSPTextDocumentSyncKind change;
    /**
     * Will save notifications are sent to the server.
     */
    BOOL willSave;
    /**
     * Will save wait until requests are sent to the server.
     */
    BOOL willSaveWaitUntil;
    /**
     * The client is supposed to include the content on save.
     */
    BOOL saveOptionIncludeText;
    
} LSPTextDocumentSyncOptions;

@interface LSPClient : NSObject

/**
 * Defines how text documents are synced. Is either a detailed structure defining each notification or
 * for backwards compatibility the TextDocumentSyncKind number. If omitted it defaults to `TextDocumentSyncKind.None`.
 */
@property (readonly) LSPTextDocumentSyncOptions textDocumentSync;
/**
 * The server provides hover support.
 */
@property (readonly, getter=hasHoverProvider) BOOL hoverProvider;
/**
 * The server provides completion support.
 */
@property (readonly, getter=hasCompletionProvider) BOOL completionProvider;
/**
 * The server provides support to resolve additional
 * information for a completion item.
 */
@property (readonly, getter=hasCompletionResolveProvider) BOOL completionResolveProvider;
/**
 * The characters that trigger completion automatically.
 */
@property (readonly, nullable) NSArray<NSString *> *completionTriggerCharacters;
/**
 * The server provides signature help support.
 */
@property (readonly, getter=hasSignatureHelpProvider) BOOL signatureHelpProvider;
/**
 * The characters that trigger signature help
 * automatically.
 */
@property (readonly, nullable) NSArray<NSString *> *signatureHelpProviderTriggerCharacters;
/**
 * The server provides goto definition support.
 */
@property (readonly, getter=hasDefinitionProvider) BOOL definitionProvider;
/**
 * The server provides Goto Type Definition support.
 *
 * Since 3.6.0
 */
@property (readonly) BOOL typeDefinitionProvider;
/**
 * The server provides Goto Implementation support.
 *
 * Since 3.6.0
 */
@property (readonly) BOOL implementationProvider;
/**
 * The server provides find references support.
 */
@property (readonly, getter=hasReferencesProvider) BOOL referencesProvider;
/**
 * The server provides document highlight support.
 */
@property (readonly, getter=hasDocumentHighlightProvider) BOOL documentHighlightProvider;
/**
 * The server provides document symbol support.
 */
@property (readonly, getter=hasDocumentSymbolProvider) BOOL documentSymbolProvider;
/**
 * The server provides workspace symbol support.
 */
@property (readonly) BOOL workspaceSymbolProvider;
/**
 * The server provides code actions. The `CodeActionOptions` return type is only
 * valid if the client signals code action literal support via the property
 * `textDocument.codeAction.codeActionLiteralSupport`.
 */
@property (readonly) BOOL codeActionProvider;
/**
 * The server provides code lens.
 */
@property (readonly, getter=hasCodeLensProvider) BOOL codeLensProvider;
/**
 * Code lens has a resolve provider as well.
 */
@property (readonly, getter=hasCodeLensResolveProvider) BOOL codeLensResolveProvider;
/**
 * The server provides document formatting.
 */
@property (readonly) BOOL documentFormattingProvider;
/**
 * The server provides document range formatting.
 */
@property (readonly, getter=hasDocumentRangeFormattingProvider) BOOL documentRangeFormattingProvider;
/**
 * The server provides document formatting on typing.
 */
@property (readonly, getter=hasDocumentOnTypeFormattingProvider) BOOL documentOnTypeFormattingProvider;
@property (readonly, nullable) NSString *documentOnTypeFormattingFirstTriggerCharacter;
@property (readonly, nullable) NSArray<NSString *> *documentOnTypeFormattingMoreTriggerCharacter;
/**
 * The server provides rename support. RenameOptions may only be
 * specified if the client states that it supports
 * `prepareSupport` in its initial `initialize` request.
 */
@property (readonly, getter=hasRenameProvider) BOOL renameProvider;
/**
 * Renames should be checked and tested before being executed.
 */
@property (readonly, getter=hasRenamePrepareProvider) BOOL renamePrepareProvider;
/**
 * The server provides document link support.
 */
@property (readonly, getter=hasDocumentLinkProvider) BOOL documentLinkProvider;
/**
 * Document links have a resolve provider as well.
 */
@property (readonly) BOOL documentLinkProviderResolveProvider;

/**
 * The server provides color provider support.
 *
 * Since 3.6.0
 */
@property (readonly, getter=hasColorProvider) BOOL colorProvider;
/**
 * The server provides color provider support.
 *
 * Since 3.6.0
 */
@property (readonly) BOOL colorProviderDynamicRegistration;
/**
 * The server provides folding provider support.
 *
 * Since 3.10.0
 */
@property (readonly, getter=hasFoldingRangeProvider) BOOL foldingRangeProvider;
/**
 * The server provides execute command support.
 */
@property (readonly) BOOL executeCommandProvider;
/**
 * The commands to be executed on the server
 */
@property (readonly, nullable) NSArray<NSString *> *executeCommandCommands;
/**
 * Workspace specific server capabilities
 */
@property (readonly) BOOL workspace;

#pragma mark Servers

+ (nullable instancetype)sharedBashServer;
+ (nullable instancetype)sharedHTMLServer;

- (instancetype)initWithPath:(NSString *)path arguments:(NSArray<NSString *> *)arguments currentDirectoryPath:(nullable NSString *)currentDirectoryPath languageID:(NSString *)languageID;

@property (readonly, nullable) NSString *languageID;

#pragma mark Observers

- (void)addObserver:(id<LSPClientObserver>)observer;
- (void)removeObserver:(id<LSPClientObserver>)observer;

#pragma mark General

/**
 * Sends "initialize" (once; later calls wait for the same reply) and sends
 * @a action to @a target with an LSPResponse when it is answered — at once
 * when it already was. The target is not retained.
 */
- (void)initializeWithTarget:(nullable id)target action:(nullable SEL)action;

- (void)shutdownWithTarget:(nullable id)target action:(nullable SEL)action;
- (void)terminate;

#pragma mark Text Synchronization

/**
 * Sent to the server to signal newly opened text documents. The document's
 * truth is now managed by the client and the server must not try to
 * read the document's truth using the document's Uri.
 * Open in this sense means it is managed by the client. It doesn't necessarily
 * mean that its content is presented in an editor.
 */
- (void)documentDidOpen:(NSURL *)url content:(id<LSPTextBuffer>)textBuffer;
/**
 * Queues a notification, with coalescing turned on and a posting style
 * of NSPostWhenIdle.
 * When the user stops typing, the single notification in the queue (due to coalescing)
 * is posted when the run loop enters its wait state and the language server
 * "textDocument/didChange" notifcation is send.
 */
- (void)document:(NSURL *)url changeTextInRange:(LSPRange *)range replacementString:(nullable NSString *)replacementString;
/**
 * You don't need to send documentDidChange unless your run loop never enters its wait state.
 */
- (void)documentDidChange:(NSURL *)url;
/**
 * The document will save notification is sent from the client
 * to the server before the document is actually saved.
 */
- (void)documentWillSave:(NSURL *)url;
/**
 * The document save notification is sent from the client
 * to the server when the document was saved in the client.
 */
- (void)documentDidSave:(NSURL *)url;
/**
 * The document close notification is sent from the client to the server
 * when the document got closed in the client. The document's truth now
 * exists where the document's Uri points to (e.g. if the document's Uri
 * is a file Uri the truth now exists on disk). As with the open notification
 * the close notification is about managing the document's content.
 */
- (void)documentDidClose:(NSURL *)url;

#pragma mark Language Features

/*
 * Each request returns its identifier and sends @a action to @a target with
 * an LSPResponse when the server answers (on the main thread; the target is
 * not retained). The response's result is:
 *   completion   NSArray<LSPCompletionItem *> (and isIncomplete)
 *   symbols      the server's NSArray
 *   highlights   NSArray<LSPDocumentHighlight *>
 *   hover        the server's NSDictionary
 */
- (NSInteger)documentCompletion:(NSURL *)url atPosition:(LSPPosition *)position target:(nullable id)target action:(nullable SEL)action;
- (NSInteger)documentCompletion:(NSURL *)url inText:(NSString *)string forCharacterAtIndex:(NSUInteger)characterIndex target:(nullable id)target action:(nullable SEL)action;
- (NSInteger)documentSymbol:(NSURL *)url target:(nullable id)target action:(nullable SEL)action;
- (NSInteger)documentHighlight:(NSURL *)url inText:(NSString *)string forCharacterAtIndex:(NSUInteger)characterIndex target:(nullable id)target action:(nullable SEL)action;
- (NSInteger)documentHover:(NSURL *)url atPosition:(LSPPosition *)position target:(nullable id)target action:(nullable SEL)action;
/// textDocument/definition; @a action gets an LSPResponse whose result is
/// the server's reply as JSON: a Location, an array of them, or nil.
- (NSInteger)documentDefinition:(NSURL *)url atPosition:(LSPPosition *)position target:(nullable id)target action:(nullable SEL)action;

/// Any request the methods above do not cover; @a action gets an
/// LSPResponse whose result is the reply's, as JSON. Returns the request's
/// identifier (0 when the server is not ready).
- (NSInteger)sendRequest:(NSString *)method params:(nullable NSDictionary *)params target:(nullable id)target action:(nullable SEL)action;
/// Any notification (workspace/didChangeWatchedFiles, ...).
- (void)sendNotification:(NSString *)method params:(nullable NSDictionary *)params;
- (NSInteger)documentHover:(NSURL *)url inText:(NSString *)string forCharacterAtIndex:(NSUInteger)characterIndex target:(nullable id)target action:(nullable SEL)action;

@end

NS_ASSUME_NONNULL_END
