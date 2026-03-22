#import "UDLSPCoordinator.h"
#import "UDTextModel+LSPTextBuffer.h"

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

    NSArray<UDTextModelEdit *> *edits = note.userInfo[@"edits"];  // already set by _modelDidChange:
    if (!edits.count) return;

    // Sort edits end-to-start so each LSP change's range is unaffected
    // by the ones that follow it in the array.
    NSArray<UDTextModelEdit *> *sorted = [edits sortedArrayUsingComparator:
        ^NSComparisonResult(UDTextModelEdit *a, UDTextModelEdit *b) {
            NSInteger aOff = [textModel getOffsetAt:a.range.startLineNumber
                                             column:a.range.startColumn];
            NSInteger bOff = [textModel getOffsetAt:b.range.startLineNumber
                                             column:b.range.startColumn];
            return bOff < aOff ? NSOrderedAscending : NSOrderedDescending;
        }];

    for (UDTextModelEdit *edit in sorted) {
        LSPPosition *startPos = [LSPPosition positionWithLine:edit.range.startLineNumber - 1 character:edit.range.startColumn - 1];
        LSPPosition *endPos = [LSPPosition positionWithLine:edit.range.endLineNumber - 1 character:edit.range.endColumn - 1];
        LSPRange *lspRange = [LSPRange range:startPos end:endPos];

        [_client document:_documentURL
        changeTextInRange:lspRange
        replacementString:edit.text];
    }
}

// ---------------------------------------------------------------------------
#pragma mark - Document lifecycle
// ---------------------------------------------------------------------------

- (void)documentDidOpenWithContent:(UDTextModel *)content {
    if (!_client) return;
    [_client addObserver:self];

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
                                      content:content];
    }];
}

- (void)textWillChangeInRange:(NSRange)range
            replacementString:(NSString *)replacement {
    /*
     // TODO: remove
    if (!_clientInitialized) return;
    [_client document:_documentURL
    changeTextInRange:range
    replacementString:replacement ?: @""];
    NSLog(@"range: %@, replacement: %@", NSStringFromRange(range), replacement);
     */
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

- (void)completionAtIndex:(NSUInteger)characterIndex
        completionHandler:(void (^)(NSArray<LSPCompletionItem *> *, NSError *))handler {
    [_client documentCompletion:_documentURL
                         inText:[_textStorage.textModel getValue]
            forCharacterAtIndex:characterIndex
              completionHandler:^(NSArray<LSPCompletionItem *> *list, BOOL isIncomplete, NSError *err) {
        handler(list, err);
    }];
}

- (void)hoverAtIndex:(NSUInteger)characterIndex
   completionHandler:(void (^)(NSDictionary *, NSError *))handler {
    [_client documentHoverWithContentsOfURL:_documentURL
                                     inText:[_textStorage.textModel getValue]
                        forCharacterAtIndex:characterIndex
                          completionHandler:handler];
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
