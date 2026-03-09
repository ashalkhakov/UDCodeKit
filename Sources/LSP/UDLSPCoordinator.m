#import "UDLSPCoordinator.h"

@interface UDLSPCoordinator ()
@property (nonatomic, weak)   UDTextModelTextStorage     *textStorage;
@property (nonatomic, strong) LSPClient                  *client;
@property (nonatomic, copy)   NSURL                      *documentURL;
@property (nonatomic, strong) UDLSPDiagnosticHighlighter *diagnosticHighlighter;
@property (nonatomic, assign) BOOL                        clientInitialized;
@end

@implementation UDLSPCoordinator

// ---------------------------------------------------------------------------
#pragma mark - Init
// ---------------------------------------------------------------------------

- (instancetype)initWithTextStorage:(UDTextModelTextStorage *)textStorage
                              client:(LSPClient *)client
                         documentURL:(NSURL *)url
                   diagnosticHighlighter:(UDLSPDiagnosticHighlighter *)diagnosticHighlighter {
    self = [super init];
    if (!self) return nil;
    _textStorage            = textStorage;
    _client                 = client;
    _documentURL            = [url copy];
    _diagnosticHighlighter  = diagnosticHighlighter;
    _clientInitialized      = NO;
    return self;
}

// ---------------------------------------------------------------------------
#pragma mark - Document lifecycle
// ---------------------------------------------------------------------------

- (void)openDocument:(NSString *)content {
    if (!_client) return;
    [_client addObserver:self];

    NSString *snapshot = [content copy];
    __weak typeof(self) weakSelf = self;
    [_client initialWithCompletionHandler:^(NSError *error) {
        __strong typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (error) {
            NSLog(@"[UDLSPCoordinator] LSP initialize failed: %@", error);
            return;
        }
        strongSelf->_clientInitialized = YES;
        [strongSelf->_client documentDidOpen:strongSelf->_documentURL
                                      content:snapshot];
    }];
}

- (void)textWillChangeInRange:(NSRange)range
            replacementString:(NSString *)replacement {
    if (!_clientInitialized) return;
    [_client document:_documentURL
    changeTextInRange:range
    replacementString:replacement ?: @""];
}

- (void)documentWillSave {
    if (!_clientInitialized) return;
    [_client documentWillSave:_documentURL];
}

- (void)documentDidSave {
    if (!_clientInitialized) return;
    [_client documentDidSave:_documentURL];
}

- (void)closeDocument {
    if (_clientInitialized) {
        [_client documentDidClose:_documentURL];
    }
    [_client removeObserver:self];
    _clientInitialized = NO;

    // Clear LSP diagnostics and decorations on close.
    [_diagnosticHighlighter applyDiagnostics:@[]];
}

// ---------------------------------------------------------------------------
#pragma mark - LSPClientObserver
// ---------------------------------------------------------------------------

- (void)languageServer:(LSPClient *)client
              document:(NSURL *)url
           diagnostics:(NSArray<LSPDiagnostic *> *)diagnostics {
    if (url && _documentURL && ![url.path isEqualToString:_documentURL.path]) return;
    // Hand off — the highlighter owns all decoration + store logic.
    [_diagnosticHighlighter applyDiagnostics:diagnostics ?: @[]];
}

- (void)languageServer:(LSPClient *)client
            logMessage:(NSString *)message
                  type:(LSPMessageType)type {
    NSLog(@"[LSP log] %@", message);
}

@end
