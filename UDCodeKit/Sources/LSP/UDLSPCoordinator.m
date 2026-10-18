#import "UDLSPCoordinator.h"
#import "UDTextModel+LSPTextBuffer.h"
#import "UDOccurrencesHighlighter.h"

@interface UDLSPCoordinator ()
@property (nonatomic, weak)   UDTextModelTextStorage     *textStorage;
@property (nonatomic, strong) LSPClient                  *client;
@property (nonatomic, copy)   NSURL                      *documentURL;
@property (nonatomic, strong) UDLSPDiagnosticHighlighter *diagnosticHighlighter;
@property (nonatomic, assign) BOOL                        clientInitialized;
@property (nonatomic, weak)   UDTextModel                *openContent;   // for didOpen, once initialized
@property (nonatomic, strong) UDOccurrencesHighlighter   *occurrences;
@property (nonatomic, copy)   NSArray<NSDictionary *>    *diagnostics;
@end

@implementation UDLSPCoordinator {
    NSUInteger _occurrencesIndex;
    NSInteger _occurrencesRequest;
}

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
    _diagnostics            = @[];
    _occurrences = [[UDOccurrencesHighlighter alloc] initWithTextStorage:textStorage highlighter:textStorage.highlighter];
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(_textModelDidChange:)
               name:UDTextModelDidChangeNotification
             object:_textStorage.textModel];
    return self;
}

- (void)dealloc {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
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
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [_occurrences showRanges:@[] writes:[NSIndexSet indexSet]];
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

- (NSInteger)definitionAtIndex:(NSUInteger)characterIndex target:(id)target action:(SEL)action {
    if (!_clientInitialized) return 0;
    return [_client documentDefinition:_documentURL atPosition:[self _positionAtIndex:characterIndex]
                                target:target action:action];
}

- (NSURL *)documentURL {
    return _documentURL;
}

- (BOOL)isReady {
    return _clientInitialized;
}

- (LSPClient *)client {
    return _client;
}

- (NSInteger)request:(NSString *)method atIndex:(NSUInteger)characterIndex extra:(NSDictionary *)extra
              target:(id)target action:(SEL)action {
    if (!_clientInitialized) return 0;
    LSPPosition *position = [self _positionAtIndex:characterIndex];
    NSMutableDictionary *params = [@{ @"textDocument": @{ @"uri": _documentURL.absoluteString },
                                      @"position": @{ @"line": @(position.line), @"character": @(position.character) } } mutableCopy];
    [params addEntriesFromDictionary:extra ?: @{}];
    return [_client sendRequest:method params:params target:target action:action];
}

- (NSInteger)request:(NSString *)method extra:(NSDictionary *)extra target:(id)target action:(SEL)action {
    if (!_clientInitialized) return 0;
    NSMutableDictionary *params = [@{ @"textDocument": @{ @"uri": _documentURL.absoluteString } } mutableCopy];
    [params addEntriesFromDictionary:extra ?: @{}];
    return [_client sendRequest:method params:params target:target action:action];
}

- (NSRange)characterRangeOfLSPRange:(NSDictionary *)range {
    if (![range isKindOfClass:[NSDictionary class]]) return NSMakeRange(NSNotFound, 0);
    UDTextModel *model = _textStorage.textModel;
    NSDictionary *start = range[@"start"], *end = range[@"end"];
    NSInteger from = [model getOffsetAt:[start[@"line"] integerValue] + 1 column:[start[@"character"] integerValue] + 1];
    NSInteger to = [model getOffsetAt:[end[@"line"] integerValue] + 1 column:[end[@"character"] integerValue] + 1];
    if (from < 0 || to < from) return NSMakeRange(NSNotFound, 0);
    return NSMakeRange((NSUInteger)from, (NSUInteger)(to - from));
}

- (NSArray<NSDictionary *> *)diagnosticsInCharacterRange:(NSRange)range {
    NSMutableArray<NSDictionary *> *found = [NSMutableArray array];
    for (NSDictionary *diagnostic in _diagnostics) {
        NSRange at = [self characterRangeOfLSPRange:diagnostic[@"range"]];
        if (at.location == NSNotFound) continue;
        // touching counts: a caret at a diagnostic's end is on it
        if (at.location <= NSMaxRange(range) && range.location <= NSMaxRange(at)) [found addObject:diagnostic];
    }
    return found;
}

// ---------------------------------------------------------------------------
#pragma mark - Occurrences of the symbol at the caret
// ---------------------------------------------------------------------------

- (void)highlightOccurrencesAtIndex:(NSUInteger)characterIndex {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(_requestOccurrences:) object:nil];
    _occurrencesIndex = characterIndex;
    _occurrencesRequest = 0;
    // shown ones stay while the caret is still in one of them, else go at once
    BOOL inShown = NO;
    for (NSValue *value in _occurrences.ranges) {
        NSRange range = value.rangeValue;
        if (characterIndex >= range.location && characterIndex <= NSMaxRange(range)) inShown = YES;
    }
    if (!inShown) [_occurrences showRanges:@[] writes:[NSIndexSet indexSet]];
    if (!_clientInitialized || !_client.documentHighlightProvider) return;
    [self performSelector:@selector(_requestOccurrences:) withObject:nil afterDelay:0.25
                  inModes:@[ NSDefaultRunLoopMode, NSModalPanelRunLoopMode ]];
}

- (void)_requestOccurrences:(id)unused {
    _occurrencesRequest = [self request:@"textDocument/documentHighlight" atIndex:_occurrencesIndex extra:nil
                                 target:self action:@selector(_didFindOccurrences:)];
}

- (void)_didFindOccurrences:(LSPResponse *)response {
    if (response.requestID != _occurrencesRequest) return;      // the caret has moved on
    NSMutableArray<NSValue *> *ranges = [NSMutableArray array];
    NSMutableIndexSet *writes = [NSMutableIndexSet indexSet];
    for (NSDictionary *highlight in [response.result isKindOfClass:[NSArray class]] ? response.result : @[]) {
        if (![highlight isKindOfClass:[NSDictionary class]]) continue;
        NSRange range = [self characterRangeOfLSPRange:highlight[@"range"]];
        if (range.location == NSNotFound) continue;
        if ([highlight[@"kind"] integerValue] == LSPDocumentHighlightKindWrite) [writes addIndex:ranges.count];
        [ranges addObject:[NSValue valueWithRange:range]];
    }
    // one occurrence is only where the caret is: nothing to point out
    if (ranges.count < 2) [ranges removeAllObjects];
    [_occurrences showRanges:ranges writes:writes];
}

- (NSArray<NSValue *> *)occurrenceRanges {
    return _occurrences.ranges;
}

// ---------------------------------------------------------------------------
#pragma mark - A server's edit (a command's)
// ---------------------------------------------------------------------------

- (BOOL)languageServer:(LSPClient *)client applyEdit:(NSDictionary *)edit {
    id<UDWorkspaceEditDocuments> documents = _editDocuments;
    if (!documents) return NO;
    NSError *error = nil;
    return [UDWorkspaceEdit applyEdit:edit documents:documents error:&error].count > 0;
}

- (NSDictionary *)LSPRangeOfCharacterRange:(NSRange)range {
    LSPPosition *start = [self _positionAtIndex:range.location];
    LSPPosition *end = [self _positionAtIndex:NSMaxRange(range)];
    return @{ @"start": @{ @"line": @(start.line), @"character": @(start.character) },
              @"end": @{ @"line": @(end.line), @"character": @(end.character) } };
}

// ---------------------------------------------------------------------------
#pragma mark - LSPClientObserver
// ---------------------------------------------------------------------------

- (void)languageServer:(LSPClient *)client
              document:(NSURL *)url
           diagnostics:(NSArray<LSPDiagnostic *> *)diagnostics {
    if (url && _documentURL && ![url.path isEqualToString:_documentURL.path]) return;
    NSMutableArray<NSDictionary *> *raw = [NSMutableArray array];
    for (LSPDiagnostic *diagnostic in diagnostics) {
        if (diagnostic.dictionary) [raw addObject:diagnostic.dictionary];
    }
    _diagnostics = raw;
    // Hand off — the highlighter owns all decoration + store logic.
    [_diagnosticHighlighter applyDiagnostics:diagnostics ?: @[]];
}

- (void)languageServer:(LSPClient *)client
            logMessage:(NSString *)message
                  type:(LSPMessageType)type {
    // NSLog(@"[LSP log] %@", message);
}

@end
