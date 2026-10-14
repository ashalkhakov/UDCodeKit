#import "UDLSPCoordinator.h"
#import "UDTextModel+LSPTextBuffer.h"

@interface UDLSPCoordinator ()
@property (nonatomic, weak)   UDTextModelTextStorage     *textStorage;
@property (nonatomic, strong) LSPClient                  *client;
@property (nonatomic, copy)   NSURL                      *documentURL;
@property (nonatomic, strong) UDLSPDiagnosticHighlighter *diagnosticHighlighter;
@property (nonatomic, assign) BOOL                        clientInitialized;
@property (nonatomic, weak)   UDTextModel                *openContent;   // for didOpen, once initialized
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
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(_textModelDidChange:)
               name:UDTextModelDidChangeNotification
             object:_textStorage.textModel];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)_textModelDidChange:(NSNotification *)note {
    if (!_clientInitialized) return;

    UDTextModel *textModel = note.object;
    if (![textModel isKindOfClass:[UDTextModel class]]) return;

    // The changes as the model made them: end to start, each range in the
    // text as the ones before it left it — the order LSP applies them in.
    NSArray<UDTextModelContentChange *> *changes = note.userInfo[UDTextModelChangesKey];
    for (UDTextModelContentChange *change in changes) {
        UDRange r = change.range;
        LSPPosition *startPos = [LSPPosition positionWithLine:r.startLineNumber - 1 character:r.startColumn - 1];
        LSPPosition *endPos = [LSPPosition positionWithLine:r.endLineNumber - 1 character:r.endColumn - 1];
        [_client document:_documentURL
        changeTextInRange:[LSPRange range:startPos end:endPos]
        replacementString:change.text];
    }
}

// ---------------------------------------------------------------------------
#pragma mark - Document lifecycle
// ---------------------------------------------------------------------------

- (void)documentDidOpenWithContent:(UDTextModel *)content {
    if (!_client) return;
    [_client addObserver:self];

    _openContent = content;
    [_client initializeWithTarget:self action:@selector(_clientDidInitialize:)];
}

- (void)_clientDidInitialize:(LSPResponse *)response {
    if (response.error) {
        NSLog(@"[UDLSPCoordinator] LSP initialize failed: %@", response.error);
        return;
    }
    _clientInitialized = YES;
    [_client documentDidOpen:_documentURL content:_openContent];
}

/// The server ended and was started again: open the document again.
- (void)languageServerDidRestart:(LSPClient *)client {
    _clientInitialized = NO;
    [_client initializeWithTarget:self action:@selector(_clientDidInitialize:)];
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

/// The LSP position (0-based line, UTF-16 column) of a character index:
/// O(log n) in the model, instead of scanning the whole text.
- (LSPPosition *)_positionAtIndex:(NSUInteger)characterIndex {
    UDPosition p = [_textStorage.textModel getPositionAt:(NSInteger)characterIndex];
    return [LSPPosition positionWithLine:p.line - 1 character:p.column - 1];
}

- (NSInteger)completionAtIndex:(NSUInteger)characterIndex target:(id)target action:(SEL)action {
    if (!_clientInitialized) return 0;
    return [_client documentCompletion:_documentURL atPosition:[self _positionAtIndex:characterIndex]
                                target:target action:action];
}

- (NSInteger)hoverAtIndex:(NSUInteger)characterIndex target:(id)target action:(SEL)action {
    if (!_clientInitialized) return 0;
    return [_client documentHover:_documentURL atPosition:[self _positionAtIndex:characterIndex]
                           target:target action:action];
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
    // NSLog(@"[LSP log] %@", message);
}

@end
