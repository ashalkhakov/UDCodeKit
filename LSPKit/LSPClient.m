//  LSPClient.m
//  LSPKit
//
//  Created by Christopher Atlan on 12.01.19.
//  Copyright © 2019 Letter Opener GmbH. All rights reserved.
//
//  Portable since: the server's process and its messages' Content-Length
//  framing are LSPTransport's (no CFHTTPMessage), which delivers everything
//  on the main run loop. Replies go to a target and an action.
//

#import "LSPClient.h"

#import "LSPCommon.h"
#import "LSPTransport.h"

#include <sys/wait.h>

NSNotificationName const LSPDocumentDidChangeNotification = @"LSPDocumentDidChange";
NSString * const LSPDocumentUserInfoKey = @"Document";

// ---------------------------------------------------------------------------
// MARK: - Responses and pending requests
// ---------------------------------------------------------------------------

@interface LSPResponse ()
@property (readwrite) NSInteger requestID;
@property (readwrite, nullable) id result;
@property (readwrite) BOOL isIncomplete;
@property (readwrite, nullable) NSError *error;
@end

@implementation LSPResponse
@end

/// What a request's reply is turned into before the action gets it.
typedef NS_ENUM(NSInteger, LSPReplyKind) {
    LSPReplyRaw,
    LSPReplyInitialize,
    LSPReplyCompletion,
    LSPReplyHighlights,
    LSPReplyHover,
};

/// A request waiting for its reply: who to tell, and how to read the reply.
@interface LSPPendingRequest : NSObject
@property (weak) id target;
@property SEL action;
@property LSPReplyKind kind;
@property (copy) NSString *text;     // highlights: the text the ranges are in
@end

@implementation LSPPendingRequest
@end

// ---------------------------------------------------------------------------
// MARK: - The pipeline: the server's process and its messages
// ---------------------------------------------------------------------------

@class LSPPipeline;

@protocol LSPPipelineDelegate <NSObject>
- (void)pipeline:(LSPPipeline *)pipeline didReceiveMessage:(NSDictionary *)message;
/// The server's process ended (or never started).
- (void)pipelineDidClose:(LSPPipeline *)pipeline;
@end

/// JSON-RPC over the server's process, its messages framed by LSPTransport.
@interface LSPPipeline : NSObject <LSPTransportDelegate> {
    NSUInteger _messageID;
}
@property (readonly) LSPTransport *transport;
@property (weak) id<LSPPipelineDelegate> delegate;
@property NSMutableString *log;
@end

@implementation LSPPipeline

- (instancetype)initWithTransport:(LSPTransport *)transport {
    self = [super init];
    if (self) {
        _transport = transport;
        _transport.delegate = self;
    }
    return self;
}

- (void)close {
    [_transport close];
}

- (void)transport:(LSPTransport *)transport didReceiveMessage:(NSDictionary *)message {
    if (_log) {
        [self logMessage:message type:[message objectForKey:@"id"] ? @"recv-request" : @"recv-notification"];
    }
    [_delegate pipeline:self didReceiveMessage:message];
}

- (void)transportDidClose:(LSPTransport *)transport {
    [_delegate pipelineDidClose:self];
}

/// Sends a request; returns its identifier.
- (NSInteger)sendRequest:(NSString *)method params:(nullable NSDictionary *)params {
    _messageID++;
    NSNumber *messageID = [NSNumber numberWithUnsignedInteger:_messageID];
    NSDictionary *request = [NSDictionary dictionaryWithObjectsAndKeys:
                             @"2.0", @"jsonrpc",
                             messageID, @"id",
                             method, @"method",
                             params ?: [NSNull null], @"params",
                             nil];
    [_transport sendMessage:request];
    if (_log) {
        [self logMessage:request type:@"send-request"];
    }
    return (NSInteger)_messageID;
}

- (void)sendNotification:(NSString *)method params:(nullable NSDictionary *)params {
    NSDictionary *request = [NSDictionary dictionaryWithObjectsAndKeys:
                             @"2.0", @"jsonrpc",
                             method, @"method",
                             params ?: [NSNull null], @"params",
                             nil];
    [_transport sendMessage:request];
    if (_log) {
        [self logMessage:request type:@"send-notification"];
    }
}

/** See LspItem at https://github.com/Microsoft/language-server-protocol-inspector  */
- (void)logMessage:(NSDictionary *)message type:(NSString *)type {
    NSDictionary *logItem = [NSDictionary dictionaryWithObjectsAndKeys:
                             type, @"type",
                             message, @"message",
                             [NSNumber numberWithInteger:(NSInteger)[[NSDate date] timeIntervalSince1970]], @"timestamp",
                             nil];
    NSData *logData = [NSJSONSerialization dataWithJSONObject:logItem options:0 error:NULL];
    NSString *logString = [[NSString alloc] initWithData:logData encoding:NSUTF8StringEncoding];
    if (logString) {
        [_log appendString:logString];
        [_log appendString:@"\r\n"];
    }
}

@end

// ---------------------------------------------------------------------------
// MARK: - Documents
// ---------------------------------------------------------------------------

@interface LSPDocument : NSObject
@property NSURL *uri;
@property id<LSPTextBuffer> textBuffer;
@property NSString *languageID;
@property NSUInteger version;
@property NSMutableArray *contentChanges;
@end

@implementation LSPDocument

- (instancetype)initWithURL:(NSURL *)URL content:(id<LSPTextBuffer>)textBuffer languageID:(NSString *)languageID {
    self = [super init];
    if (self) {
        _uri = [URL copy];
        _textBuffer = textBuffer;
        _languageID = [languageID copy];
        _version = 1;
        _contentChanges = [NSMutableArray array];
    }
    return self;
}

- (NSDictionary *)textDocumentIdentifier {
    return [NSDictionary dictionaryWithObjectsAndKeys:[_uri absoluteString], @"uri", nil];
}

- (NSDictionary *)versionedTextDocumentIdentifier {
    // increase version only on "textDocument/didChange" notification
    // and not with every -changeTextInRange:replacementString:.
    _version++;
    return [NSDictionary dictionaryWithObjectsAndKeys:
            [_uri absoluteString], @"uri",
            [NSNumber numberWithUnsignedInteger:_version], @"version",
            nil];
}

- (NSDictionary *)textDocumentItem {
    return [NSDictionary dictionaryWithObjectsAndKeys:
            [_uri absoluteString], @"uri",
            _languageID, @"languageId",
            [NSNumber numberWithUnsignedInteger:_version], @"version",
            [_textBuffer text], @"text",
            nil];
}

- (void)changeTextInRange:(LSPRange *)range replacementString:(NSString *)replacementString {
    NSDictionary *changeEvent = [NSDictionary dictionaryWithObjectsAndKeys:
                                 [range params], @"range",
                                 replacementString ?: @"", @"text",
                                 nil];
    [_contentChanges addObject:changeEvent];
}

- (NSDictionary *)syncTextDocumentParams:(LSPTextDocumentSyncKind)kind {
    NSDictionary *textDocument = [self versionedTextDocumentIdentifier];
    NSArray *contentChanges = nil;
    if (kind == LSPTextDocumentSyncKindIncremental) {
        contentChanges = _contentChanges;
    } else if (kind == LSPTextDocumentSyncKindFull) {
        NSDictionary *changeEvent = [NSDictionary dictionaryWithObjectsAndKeys:[_textBuffer text], @"text", nil];
        contentChanges = [NSArray arrayWithObject:changeEvent];
    }
    return [NSDictionary dictionaryWithObjectsAndKeys:
            textDocument, @"textDocument",
            contentChanges, @"contentChanges",
            nil];
}

- (void)clearContentChanges {
    [_contentChanges removeAllObjects];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@ uri = %@ version = %lu>", NSStringFromClass([self class]), _uri, (unsigned long)_version];
}

@end

// ---------------------------------------------------------------------------
// MARK: - The client
// ---------------------------------------------------------------------------

@interface LSPClient () <LSPPipelineDelegate> {
    BOOL _initialized;
    BOOL _initializing;
    NSMutableArray<LSPPendingRequest *> *_initializeWaiters;
    BOOL _shouldTerminate;
    NSMutableArray<id<LSPClientObserver>> *_observers;
    NSMutableDictionary<NSURL *, LSPDocument *> *_documents;
    NSNotificationQueue *_documentChangesQueue;
    NSMutableDictionary<NSNumber *, LSPPendingRequest *> *_pending;
    NSString *_path;
    NSArray<NSString *> *_arguments;
    NSString *_currentDirectoryPath;
}
@property LSPPipeline *pipeline;
@end

@implementation LSPClient

/** Used for Coalescing Notifications, where we want to post a notification if a given event occurs at least once, but we want to post no more than one notification even if the event occurs multiple times. */
+ (NSNotificationCenter *)defaultNotificationCenter {
    static NSNotificationCenter *notificationCenter = nil;
    @synchronized (self) {
        if (notificationCenter == nil) {
            notificationCenter = [[NSNotificationCenter alloc] init];
        }
    }
    return notificationCenter;
}

+ (NSString *)languageServersPath {
    NSString *contentsPath = @"Contents/Library/Language Servers";
    NSString *path = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:contentsPath];
    if ([[NSFileManager defaultManager] fileExistsAtPath:path] == NO) {
        // In case of unit test Agents.
        NSArray *components = [[[NSBundle bundleForClass:[self class]] bundlePath] pathComponents];
        if ([components count]) {
            components = [components subarrayWithRange:NSMakeRange(0, [components count] - 1)];
            path = [NSString pathWithComponents:components];
        }
    }
    return path;
}

+ (instancetype)_sharedServerInBundle:(NSString *)name arguments:(NSArray *)arguments languageID:(NSString *)languageID {
    NSString *bundlePath = [[[self class] languageServersPath] stringByAppendingPathComponent:name];
    NSBundle *bundle = [NSBundle bundleWithPath:bundlePath];
    if (bundle == nil) {
        NSLog(@"Could not find bundle %@", bundlePath);
        return nil;
    }
    return [[[self class] alloc] initWithPath:[bundle executablePath] arguments:arguments currentDirectoryPath:nil languageID:languageID];
}

+ (instancetype)sharedBashServer {
    static LSPClient *sharedServer = nil;
    @synchronized (self) {
        if (sharedServer == nil) {
            sharedServer = [self _sharedServerInBundle:@"bash-language-server.bundle"
                                             arguments:[NSArray arrayWithObject:@"start"] languageID:@"shellscript"];
        }
    }
    return sharedServer;
}

+ (instancetype)sharedHTMLServer {
    static LSPClient *sharedServer = nil;
    @synchronized (self) {
        if (sharedServer == nil) {
            sharedServer = [self _sharedServerInBundle:@"vscode-html-languageserver.bundle"
                                             arguments:[NSArray arrayWithObject:@"--stdio"] languageID:@"html"];
        }
    }
    return sharedServer;
}

- (instancetype)initWithPath:(NSString *)path arguments:(NSArray<NSString *> *)arguments currentDirectoryPath:(NSString *)currentDirectoryPath languageID:(NSString *)languageID {
    self = [super init];
    if (self) {
        _observers = [NSMutableArray array];
        _documents = [NSMutableDictionary dictionary];
        _pending = [NSMutableDictionary dictionary];
        _documentChangesQueue = [[NSNotificationQueue alloc] initWithNotificationCenter:[[self class] defaultNotificationCenter]];
        [[[self class] defaultNotificationCenter] addObserver:self selector:@selector(_documentDidChange:) name:LSPDocumentDidChangeNotification object:self];
        _languageID = languageID;
        _path = [path copy];
        _arguments = [arguments copy];
        _currentDirectoryPath = [currentDirectoryPath copy];
        [self _launch];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[[self class] defaultNotificationCenter] removeObserver:self];
}

- (void)_launch {
    LSPTransport *transport = [[LSPTransport alloc] initWithLaunchPath:_path arguments:_arguments
                                                  currentDirectoryPath:_currentDirectoryPath];
    if (transport.launchError) {
        NSLog(@"LSPKit: %@", [transport.launchError localizedDescription]);
        _shouldTerminate = YES;       // not again and again
    }
    _pipeline = [[LSPPipeline alloc] initWithTransport:transport];
    _pipeline.delegate = self;
}

#pragma mark Termination

- (void)terminate {
    if ([_pipeline.transport.task isRunning]) {
        _shouldTerminate = YES;
        // Nothing more is sent: the documents' closing, say, before the
        // task's end is noticed on the run loop.
        _initialized = NO;
        [_pipeline.transport terminate];
    }
}

- (void)pipelineDidClose:(LSPPipeline *)pipeline {
    _initialized = NO;
    _initializing = NO;
    _initializeWaiters = nil;
    [_pending removeAllObjects];
    [_documents removeAllObjects];
    if (_shouldTerminate) return;
    // Ended without being asked: start it again, and say so.
    [self _launch];
    for (id<LSPClientObserver> observer in [_observers copy]) {
        if ([observer respondsToSelector:@selector(languageServerDidRestart:)]) {
            [observer languageServerDidRestart:self];
        }
    }
}

#pragma mark Observers

- (void)addObserver:(id<LSPClientObserver>)observer {
    [_observers addObject:observer];
}

- (void)removeObserver:(id<LSPClientObserver>)observer {
    [_observers removeObject:observer];
}

#pragma mark Messages from the server

- (void)pipeline:(LSPPipeline *)pipeline didReceiveMessage:(NSDictionary *)message {
    NSNumber *messageID = [message objectForKey:@"id"];
    if (messageID == nil) {
        [self handleNotificationMessage:message];
    } else if ([message objectForKey:@"method"]) {
        [self handleRequestMessage:message];
    } else {
        [self _handleReply:message toRequest:messageID];
    }
}

- (NSError *)_errorForMessage:(NSDictionary *)json {
    NSDictionary *jsonError = [json objectForKey:@"error"];
    if (![jsonError isKindOfClass:[NSDictionary class]]) return nil;
    NSString *message = [jsonError objectForKey:@"message"];
    NSDictionary *info = message ? [NSDictionary dictionaryWithObject:message forKey:NSLocalizedDescriptionKey] : nil;
    return [NSError errorWithDomain:LSPResponseError code:[[jsonError objectForKey:@"code"] integerValue] userInfo:info];
}

- (void)_handleReply:(NSDictionary *)message toRequest:(NSNumber *)messageID {
    LSPPendingRequest *request = [_pending objectForKey:messageID];
    if (request == nil) return;
    [_pending removeObjectForKey:messageID];

    LSPResponse *response = [[LSPResponse alloc] init];
    response.requestID = [messageID integerValue];
    response.error = [self _errorForMessage:message];
    id result = [message objectForKey:@"result"];
    if (result == [NSNull null]) result = nil;

    switch (request.kind) {
        case LSPReplyInitialize:
            [self _initializeResponseWithObject:result error:response.error];
            return;
        case LSPReplyCompletion: {
            NSArray *items = nil;
            if ([result isKindOfClass:[NSDictionary class]]) {
                response.isIncomplete = [[result objectForKey:@"isIncomplete"] boolValue];
                items = [result objectForKey:@"items"];
            } else if ([result isKindOfClass:[NSArray class]]) {
                items = result;
            }
            NSMutableArray *completionList = [NSMutableArray arrayWithCapacity:[items count]];
            for (NSDictionary *item in items) {
                LSPCompletionItem *completionItem = [[LSPCompletionItem alloc] initWithDictionary:item];
                if (completionItem) [completionList addObject:completionItem];
            }
            response.result = [completionList copy];
            break;
        }
        case LSPReplyHighlights:
            response.result = [result isKindOfClass:[NSArray class]]
                ? [[self class] documentHighlightFromArray:result inText:request.text] : nil;
            break;
        case LSPReplyHover:
            response.result = [result isKindOfClass:[NSDictionary class]] ? result : nil;
            break;
        case LSPReplyRaw:
            response.result = result;
            break;
    }
    [self _send:request response:response];
}

- (void)_send:(LSPPendingRequest *)request response:(LSPResponse *)response {
    id target = request.target;
    if (target && request.action && [target respondsToSelector:request.action]) {
        // One object argument: performSelector, as NSAlert's did-end selector.
        IMP imp = [target methodForSelector:request.action];
        ((void (*)(id, SEL, LSPResponse *))imp)(target, request.action, response);
    }
}

- (NSInteger)_request:(NSString *)method params:(NSDictionary *)params kind:(LSPReplyKind)kind
               target:(id)target action:(SEL)action text:(NSString *)text {
    LSPPendingRequest *request = [[LSPPendingRequest alloc] init];
    request.target = target;
    request.action = action;
    request.kind = kind;
    request.text = text;
    NSInteger requestID = [_pipeline sendRequest:method params:params];
    [_pending setObject:request forKey:[NSNumber numberWithInteger:requestID]];
    return requestID;
}

- (void)handleRequestMessage:(NSDictionary *)requestMessage {
    NSString *method = [requestMessage objectForKey:@"method"];
    if ([method isEqual:@"window/showMessageRequest"]) {
        NSLog(@"window/showMessageRequest %@", requestMessage);
    }
}

- (void)handleNotificationMessage:(NSDictionary *)notificaton {
    NSString *method = [notificaton objectForKey:@"method"];
    NSDictionary *params = [notificaton objectForKey:@"params"];
    LSPMessageType messageType = 0;
    NSString *message = nil;
    NSURL *url = nil;
    NSArray *diagnostics = nil;
    if ([params isKindOfClass:[NSDictionary class]]) {
        // method: window
        messageType = [[params objectForKey:@"type"] integerValue];
        message = [params objectForKey:@"message"];
        // method: publishDiagnostics
        NSString *uri = [params objectForKey:@"uri"];
        url = uri ? [NSURL URLWithString:uri] : nil;
        diagnostics = [LSPDiagnostic diagnosticsFromArray:[params objectForKey:@"diagnostics"]];
    }
    for (id<LSPClientObserver> observer in [_observers copy]) {
        if ([method isEqual:@"window/logMessage"]) {
            if ([observer respondsToSelector:@selector(languageServer:logMessage:type:)]) {
                [observer languageServer:self logMessage:message type:messageType];
            }
        } else if ([method isEqual:@"window/showMessage"]) {
            if ([observer respondsToSelector:@selector(languageServer:showMessage:type:)]) {
                [observer languageServer:self showMessage:message type:messageType];
            }
        } else if ([method isEqual:@"telemetry/event"]) {
            if ([observer respondsToSelector:@selector(languageServer:telemetryEvent:)]) {
                [observer languageServer:self telemetryEvent:params];
            }
        } else if ([method isEqual:@"textDocument/publishDiagnostics"]) {
            if ([observer respondsToSelector:@selector(languageServer:document:diagnostics:)]) {
                [observer languageServer:self document:url diagnostics:diagnostics];
            }
        }
    }
}

#pragma mark General

- (void)initializeWithTarget:(id)target action:(SEL)action {
    LSPPendingRequest *waiter = [[LSPPendingRequest alloc] init];
    waiter.target = target;
    waiter.action = action;
    if (_initialized) {
        [self _send:waiter response:[[LSPResponse alloc] init]];
        return;
    }
    if (_initializeWaiters == nil) _initializeWaiters = [NSMutableArray array];
    [_initializeWaiters addObject:waiter];
    if (_initializing) return;        // one initialize request answers them all
    _initializing = YES;

    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    NSNumber *pid = [NSNumber numberWithInt:[[NSProcessInfo processInfo] processIdentifier]];
    NSDictionary *capabilities = [NSDictionary dictionaryWithObjectsAndKeys:
                                  [NSNull null], @"workspace",
                                  [NSNull null], @"textDocument",
                                  [NSNull null], @"experimental",
                                  nil];
    [params setObject:pid forKey:@"processId"];
    NSURL *root = [self rootURL];
    if (root) {
        [params setObject:[root path] forKey:@"rootPath"];
        [params setObject:[root absoluteString] forKey:@"rootUri"];
        [params setObject:[NSArray arrayWithObject:[NSDictionary dictionaryWithObjectsAndKeys:
                                                    [root absoluteString], @"uri",
                                                    [root lastPathComponent], @"name", nil]]
                   forKey:@"workspaceFolders"];
    } else {
        [params setObject:[NSNull null] forKey:@"rootPath"];
        [params setObject:[NSNull null] forKey:@"rootUri"];
        [params setObject:[NSNull null] forKey:@"workspaceFolders"];
    }
    NSDictionary *options = [self initializationOptions];
    [params setObject:options ? (id)options : (id)[NSNull null] forKey:@"initializationOptions"];
    [params setObject:capabilities forKey:@"capabilities"];
    [params setObject:@"verbose" forKey:@"trace"];
    [self _request:@"initialize" params:params kind:LSPReplyInitialize target:nil action:NULL text:nil];
}

- (void)_initializeResponseWithObject:(id)obj error:(NSError *)error {
    _initializing = NO;
    _initialized = (error == nil);
    NSDictionary *capabilities = [obj isKindOfClass:[NSDictionary class]] ? [obj objectForKey:@"capabilities"] : nil;
    id textDocumentSyncValue = [capabilities objectForKey:@"textDocumentSync"];
    if ([textDocumentSyncValue isKindOfClass:[NSDictionary class]]) {
        NSDictionary *syncOptions = textDocumentSyncValue;
        _textDocumentSync.openClose = [[syncOptions objectForKey:@"openClose"] boolValue];
        _textDocumentSync.change = [[syncOptions objectForKey:@"change"] integerValue];
        _textDocumentSync.willSave = [[syncOptions objectForKey:@"willSave"] boolValue];
        _textDocumentSync.willSaveWaitUntil = [[syncOptions objectForKey:@"willSaveWaitUntil"] boolValue];
        NSDictionary *saveOptions = [syncOptions objectForKey:@"save"];
        if ([saveOptions isKindOfClass:[NSDictionary class]]) {
            _textDocumentSync.saveOptionIncludeText = [[saveOptions objectForKey:@"includeText"] boolValue];
        }
    } else if ([textDocumentSyncValue isKindOfClass:[NSNumber class]]) {
        _textDocumentSync.change = [textDocumentSyncValue integerValue];
        if (_textDocumentSync.change != LSPTextDocumentSyncKindNone) {
            _textDocumentSync.openClose = YES;
        }
    }
    _hoverProvider = [[capabilities objectForKey:@"hoverProvider"] boolValue];
    id completionProvider = [capabilities objectForKey:@"completionProvider"];
    if ([completionProvider isKindOfClass:[NSDictionary class]]) {
        _completionProvider = YES;
        _completionResolveProvider = [[completionProvider objectForKey:@"resolveProvider"] boolValue];
        _completionTriggerCharacters = [completionProvider objectForKey:@"triggerCharacters"];
    }
    NSDictionary *signatureHelpProvider = [capabilities objectForKey:@"signatureHelpProvider"];
    if ([signatureHelpProvider isKindOfClass:[NSDictionary class]]) {
        _signatureHelpProvider = YES;
        _signatureHelpProviderTriggerCharacters = [signatureHelpProvider objectForKey:@"triggerCharacters"];
    }
    _definitionProvider = [[capabilities objectForKey:@"definitionProvider"] boolValue];
    _referencesProvider = [[capabilities objectForKey:@"referencesProvider"] boolValue];
    _documentHighlightProvider = [[capabilities objectForKey:@"documentHighlightProvider"] boolValue];
    _documentSymbolProvider = [[capabilities objectForKey:@"documentSymbolProvider"] boolValue];
    _workspaceSymbolProvider = [[capabilities objectForKey:@"workspaceSymbolProvider"] boolValue];
    NSDictionary *codeLensProvider = [capabilities objectForKey:@"codeLensProvider"];
    if ([codeLensProvider isKindOfClass:[NSDictionary class]]) {
        _codeLensProvider = YES;
        _codeLensResolveProvider = [[codeLensProvider objectForKey:@"resolveProvider"] boolValue];
    }
    _documentFormattingProvider = [[capabilities objectForKey:@"documentFormattingProvider"] boolValue];
    _documentRangeFormattingProvider = [[capabilities objectForKey:@"documentRangeFormattingProvider"] boolValue];
    NSDictionary *documentOnTypeFormattingProvider = [capabilities objectForKey:@"documentOnTypeFormattingProvider"];
    if ([documentOnTypeFormattingProvider isKindOfClass:[NSDictionary class]]) {
        _documentOnTypeFormattingProvider = YES;
        _documentOnTypeFormattingFirstTriggerCharacter = [documentOnTypeFormattingProvider objectForKey:@"firstTriggerCharacter"];
        _documentOnTypeFormattingMoreTriggerCharacter = [documentOnTypeFormattingProvider objectForKey:@"moreTriggerCharacter"];
    }
    id renameProvider = [capabilities objectForKey:@"renameProvider"];
    if ([renameProvider isKindOfClass:[NSDictionary class]]) {
        _renameProvider = YES;
        _renamePrepareProvider = [[renameProvider objectForKey:@"prepareProvider"] boolValue];
    } else if ([renameProvider isKindOfClass:[NSNumber class]]) {
        _renameProvider = [renameProvider boolValue];
    }
    NSDictionary *documentLinkProvider = [capabilities objectForKey:@"documentLinkProvider"];
    if ([documentLinkProvider isKindOfClass:[NSDictionary class]]) {
        _documentLinkProvider = YES;
        _documentLinkProviderResolveProvider = [[documentLinkProvider objectForKey:@"resolveProvider"] boolValue];
    }
    NSDictionary *colorProvider = [capabilities objectForKey:@"colorProvider"];
    if ([colorProvider isKindOfClass:[NSDictionary class]]) {
        _colorProvider = YES;
        _colorProviderDynamicRegistration = [[colorProvider objectForKey:@"dynamicRegistration"] boolValue];
    }
    _foldingRangeProvider = [[capabilities objectForKey:@"foldingRangeProvider"] boolValue];
    NSDictionary *executeCommandProvider = [capabilities objectForKey:@"executeCommandProvider"];
    if ([executeCommandProvider isKindOfClass:[NSDictionary class]]) {
        _executeCommandProvider = YES;
        _executeCommandCommands = [executeCommandProvider objectForKey:@"commands"];
    }

    LSPResponse *response = [[LSPResponse alloc] init];
    response.error = error;
    NSArray *waiters = _initializeWaiters;
    _initializeWaiters = nil;
    for (LSPPendingRequest *waiter in waiters) {
        [self _send:waiter response:response];
    }
}

- (void)shutdownWithTarget:(id)target action:(SEL)action {
    if (_initialized == NO) return;
    [self _request:@"shutdown" params:nil kind:LSPReplyRaw target:target action:action text:nil];
}

- (void)exit {
    // The one notification where we don't check for if (_initialize == NO) return;
    // This will allow the exit of a server without an initialize request.
    _shouldTerminate = YES;
    pid_t pid = [_pipeline.transport.task processIdentifier];
    [_pipeline sendNotification:@"exit" params:nil];
    waitpid(pid, NULL, 0);
}

#pragma mark Text Synchronization

- (void)documentDidOpen:(NSURL *)url content:(id<LSPTextBuffer>)text {
    if (_initialized == NO) return;
    NSAssert(([_documents objectForKey:url] == nil), @"An open notification must not be sent more than once without a corresponding close notification send before. This means open and close notification must be balanced and the max open count for a particular textDocument is one.");

    LSPDocument *document = [[LSPDocument alloc] initWithURL:url content:text languageID:_languageID];
    [_documents setObject:document forKey:url];
    if (_textDocumentSync.openClose == NO) {
        return;
    }
    NSDictionary *documentParams = [document textDocumentItem];
    [_pipeline sendNotification:@"textDocument/didOpen" params:[NSDictionary dictionaryWithObjectsAndKeys:documentParams, @"textDocument", nil]];
}

- (void)document:(NSURL *)url changeTextInRange:(LSPRange *)affectedCharRange replacementString:(NSString *)replacementString {
    if (_initialized == NO) return;
    LSPDocument *document = [_documents objectForKey:url];
    NSAssert((document != nil), @"An open notification must be send before.");

    [document changeTextInRange:affectedCharRange replacementString:replacementString];

    NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:document, LSPDocumentUserInfoKey, nil];
    NSNotification *changeNotification = [NSNotification notificationWithName:LSPDocumentDidChangeNotification object:self userInfo:userInfo];
    // It would be very expensive (and not very useful) to update the document after
    // each character the user types, especially if the user types quickly.
    // We queue a notification, with coalescing turned on and a posting style
    // of NSPostWhenIdle after each character typed.
    // When the user stops typing, the single notification in the queue (due to coalescing)
    // is posted when the run loop enters its wait state and the language server
    // "textDocument/didChange" notifcation is send.
    [_documentChangesQueue enqueueNotification:changeNotification
                                  postingStyle:NSPostWhenIdle
                                  coalesceMask:NSNotificationCoalescingOnName
                                      forModes:nil];
}

- (void)documentDidChange:(NSURL *)url {
    if (_initialized == NO) return;
    LSPDocument *document = [_documents objectForKey:url];
    NSAssert((document != nil), @"An open notification must be send before.");

    NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:document, LSPDocumentUserInfoKey, nil];
    NSNotification *changeNotification = [NSNotification notificationWithName:LSPDocumentDidChangeNotification object:self userInfo:userInfo];
    [_documentChangesQueue enqueueNotification:changeNotification
                                  postingStyle:NSPostNow
                                  coalesceMask:NSNotificationCoalescingOnName
                                      forModes:nil];
}

- (void)_documentDidChange:(NSNotification *)notification {
    if (_initialized == NO) return;

    LSPDocument *document = [[notification userInfo] objectForKey:LSPDocumentUserInfoKey];
    if (_textDocumentSync.change == LSPTextDocumentSyncKindNone) {
        [document clearContentChanges];
        return;
    }
    NSDictionary *documentParams = [document syncTextDocumentParams:_textDocumentSync.change];
    [_pipeline sendNotification:@"textDocument/didChange" params:documentParams];
    [document clearContentChanges];
}

- (void)documentWillSave:(NSURL *)url {
    if (_initialized == NO) return;
    LSPDocument *document = [_documents objectForKey:url];
    NSAssert((document != nil), @"An open notification must be send before.");

    NSDictionary *documentParams = [NSDictionary dictionaryWithObjectsAndKeys:[document textDocumentIdentifier], @"textDocument", nil];
    [_pipeline sendNotification:@"textDocument/willSave" params:documentParams];
}

- (void)documentDidSave:(NSURL *)url {
    if (_initialized == NO) return;
    LSPDocument *document = [_documents objectForKey:url];
    NSAssert((document != nil), @"An open notification must be send before.");

    NSMutableDictionary *documentParams = [NSMutableDictionary dictionaryWithObjectsAndKeys:[document textDocumentIdentifier], @"textDocument", nil];
    if (_textDocumentSync.saveOptionIncludeText) {
        [documentParams setObject:[[document textBuffer] text] forKey:@"text"];
    }
    [_pipeline sendNotification:@"textDocument/didSave" params:documentParams];
}

- (void)documentDidClose:(NSURL *)url {
    if (_initialized == NO) return;
    LSPDocument *document = [_documents objectForKey:url];
    NSAssert((document != nil), @"An open notification must be send before.");

    NSDictionary *documentParams = [NSDictionary dictionaryWithObjectsAndKeys:[document textDocumentIdentifier], @"textDocument", nil];
    [_pipeline sendNotification:@"textDocument/didClose" params:documentParams];
    [_documents removeObjectForKey:url];
}

#pragma mark Language Features

- (NSDictionary *)_paramsForDocument:(NSURL *)url position:(LSPPosition *)position {
    LSPDocument *document = [_documents objectForKey:url];
    NSAssert((document != nil), @"An open notification must be send before.");
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    [params setObject:[document textDocumentIdentifier] forKey:@"textDocument"];
    if (position) [params setObject:[position params] forKey:@"position"];
    return params;
}

- (NSInteger)documentCompletion:(NSURL *)url atPosition:(LSPPosition *)position target:(id)target action:(SEL)action {
    if (_initialized == NO) return 0;
    return [self _request:@"textDocument/completion" params:[self _paramsForDocument:url position:position]
                     kind:LSPReplyCompletion target:target action:action text:nil];
}

- (NSInteger)documentCompletion:(NSURL *)url inText:(NSString *)string forCharacterAtIndex:(NSUInteger)characterIndex target:(id)target action:(SEL)action {
    return [self documentCompletion:url atPosition:[LSPPosition positionForCharacterAtIndex:characterIndex inText:string]
                             target:target action:action];
}

- (NSInteger)documentSymbol:(NSURL *)url target:(id)target action:(SEL)action {
    if (_initialized == NO) return 0;
    return [self _request:@"textDocument/documentSymbol" params:[self _paramsForDocument:url position:nil]
                     kind:LSPReplyRaw target:target action:action text:nil];
}

+ (NSArray<LSPDocumentHighlight *> *)documentHighlightFromArray:(NSArray *)array inText:(NSString *)string {
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:[array count]];
    for (NSDictionary *dict in array) {
        if ([dict isKindOfClass:[NSDictionary class]]) {
            LSPDocumentHighlight *highlight = [[self class] documentHighlightFromDictionary:dict inText:string];
            if (highlight) {
                [result addObject:highlight];
            }
        }
    }
    return [result copy];
}

+ (LSPDocumentHighlight *)documentHighlightFromDictionary:(NSDictionary *)dict inText:(NSString *)string {
    LSPRange *lspRange = [LSPRange rangeFromDictionary:[dict objectForKey:@"range"]];
    NSRange range = [lspRange convertToRangeInText:string];
    LSPDocumentHighlightKind kind = LSPDocumentHighlightKindText;
    if ([dict objectForKey:@"kind"]) {
        kind = [[dict objectForKey:@"kind"] integerValue];
    }
    return [[LSPDocumentHighlight alloc] initWithRange:range kind:kind];
}

- (NSInteger)documentHighlight:(NSURL *)url inText:(NSString *)string forCharacterAtIndex:(NSUInteger)characterIndex target:(id)target action:(SEL)action {
    if (_initialized == NO) return 0;
    LSPPosition *position = [LSPPosition positionForCharacterAtIndex:characterIndex inText:string];
    return [self _request:@"textDocument/documentHighlight" params:[self _paramsForDocument:url position:position]
                     kind:LSPReplyHighlights target:target action:action text:string];
}

- (NSInteger)documentHover:(NSURL *)url atPosition:(LSPPosition *)position target:(id)target action:(SEL)action {
    if (_initialized == NO) return 0;
    return [self _request:@"textDocument/hover" params:[self _paramsForDocument:url position:position]
                     kind:LSPReplyHover target:target action:action text:nil];
}

- (NSInteger)documentDefinition:(NSURL *)url atPosition:(LSPPosition *)position target:(id)target action:(SEL)action {
    if (_initialized == NO) return 0;
    return [self _request:@"textDocument/definition" params:[self _paramsForDocument:url position:position]
                     kind:LSPReplyRaw target:target action:action text:nil];
}

- (NSInteger)sendRequest:(NSString *)method params:(NSDictionary *)params target:(id)target action:(SEL)action {
    if (_initialized == NO) return 0;
    return [self _request:method params:params kind:LSPReplyRaw target:target action:action text:nil];
}

- (void)sendNotification:(NSString *)method params:(NSDictionary *)params {
    if (_initialized == NO) return;
    [_pipeline sendNotification:method params:params];
}

- (NSInteger)documentHover:(NSURL *)url inText:(NSString *)string forCharacterAtIndex:(NSUInteger)characterIndex target:(id)target action:(SEL)action {
    return [self documentHover:url atPosition:[LSPPosition positionForCharacterAtIndex:characterIndex inText:string]
                        target:target action:action];
}

@end
