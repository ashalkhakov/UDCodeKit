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

    // End to start, so each change's range is unaffected by the ones sent
    // after it. The ranges are in the text as it was before these edits, so
    // they are compared as they are (the model has moved on).
    NSArray<UDTextModelEdit *> *sorted = [edits sortedArrayUsingComparator:
        ^NSComparisonResult(UDTextModelEdit *a, UDTextModelEdit *b) {
            UDRange ra = a.range, rb = b.range;
            if (ra.startLineNumber != rb.startLineNumber) {
                return ra.startLineNumber > rb.startLineNumber ? NSOrderedAscending : NSOrderedDescending;
            }
            if (ra.startColumn != rb.startColumn) {
                return ra.startColumn > rb.startColumn ? NSOrderedAscending : NSOrderedDescending;
            }
            return NSOrderedSame;
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

- (void)completionAtIndex:(NSUInteger)characterIndex
        completionHandler:(void (^)(NSArray<LSPCompletionItem *> *, NSError *))handler {
    [_client documentCompletion:_documentURL
                     atPosition:[self _positionAtIndex:characterIndex]
              completionHandler:^(NSArray<LSPCompletionItem *> *list, BOOL isIncomplete, NSError *err) {
        handler(list, err);
    }];
}

- (void)hoverAtIndex:(NSUInteger)characterIndex
   completionHandler:(void (^)(NSDictionary *, NSError *))handler {
    [_client documentHover:_documentURL
                atPosition:[self _positionAtIndex:characterIndex]
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
    // NSLog(@"[LSP log] %@", message);
}

@end
