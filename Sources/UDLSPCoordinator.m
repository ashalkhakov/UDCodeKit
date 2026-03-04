/*---------------------------------------------------------------------------------------------
 *  UDLSPCoordinator.m
 *--------------------------------------------------------------------------------------------*/

#import "UDLSPCoordinator.h"
#import <UDPieceTable/UDPieceTable.h>

// ---------------------------------------------------------------------------
// MARK: - Helpers (forward declarations before @implementation)
// ---------------------------------------------------------------------------

/// Convert an absolute character offset to a 1-based UDPosition using the model.
static inline UDPosition UDPositionAtOffset(UDTextModel *model, NSUInteger offset) {
    NSInteger safeOffset = (NSInteger)MIN(offset, (NSUInteger)MAX(0LL, [model getLength]));
    return [model getPositionAt:safeOffset];
}

/// Build a UDRange (1-based) from two character offsets.
static inline UDRange UDRangeMakeFromOffsets(UDTextModel *model,
                                              NSUInteger startOffset,
                                              NSUInteger endOffset) {
    UDPosition s = UDPositionAtOffset(model, startOffset);
    UDPosition e = UDPositionAtOffset(model, endOffset);
    return PTRangeMake(s.line, s.column, e.line, e.column);
}

// ---------------------------------------------------------------------------
// MARK: - Private interface
// ---------------------------------------------------------------------------

@interface UDLSPCoordinator ()
@property (nonatomic, weak)   UDTextModelTextStorage   *textStorage;
@property (nonatomic, strong) LSPClient                *client;
@property (nonatomic, copy)   NSURL                    *documentURL;
@property (nonatomic, copy)   NSArray<NSString *>      *decorationIDs;
@property (nonatomic, copy)   NSArray<LSPDiagnostic *> *diagnostics;
@property (nonatomic)         BOOL                      clientInitialized;
@end

// ---------------------------------------------------------------------------

@implementation UDLSPCoordinator

// ---------------------------------------------------------------------------
// MARK: - Init
// ---------------------------------------------------------------------------

- (instancetype)initWithTextStorage:(UDTextModelTextStorage *)textStorage
                              client:(LSPClient *)client
                         documentURL:(NSURL *)url {
    self = [super init];
    if (!self) return nil;
    _textStorage       = textStorage;
    _client            = client;
    _documentURL       = [url copy];
    _decorationIDs     = @[];
    _diagnostics       = @[];
    _clientInitialized = NO;
    return self;
}

// ---------------------------------------------------------------------------
// MARK: - Document lifecycle
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
    if (!replacement) replacement = @"";
    [_client document:_documentURL
    changeTextInRange:range
    replacementString:replacement];
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

    // Clear any LSP decorations.
    UDTextModelTextStorage *ts = _textStorage;
    if (ts) {
        UDTextModel *model = ts.textModel;
        _decorationIDs =
            [model deltaDecorations:_decorationIDs
                     newDecorations:@[]
                              owner:UDLSPDiagnosticDecorationOwner];
    }
}

// ---------------------------------------------------------------------------
// MARK: - LSPClientObserver
// ---------------------------------------------------------------------------

- (void)languageServer:(LSPClient *)client
              document:(NSURL *)url
           diagnostics:(NSArray<LSPDiagnostic *> *)diagnostics {
    // Only handle diagnostics for our document.
    if (url && _documentURL && ![url.path isEqualToString:_documentURL.path]) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        [self _applyDiagnostics:diagnostics ?: @[]];
    });
}

- (void)languageServer:(LSPClient *)client
            logMessage:(NSString *)message
                  type:(LSPMessageType)type {
    NSLog(@"[LSP log] %@", message);
}

// ---------------------------------------------------------------------------
// MARK: - Decoration application
// ---------------------------------------------------------------------------

- (void)_applyDiagnostics:(NSArray<LSPDiagnostic *> *)diagnostics {
    _diagnostics = diagnostics;

    UDTextModelTextStorage *ts = _textStorage;
    if (!ts) return;

    UDTextModel *model   = ts.textModel;
    NSString    *docText = [model getValue];
    NSUInteger   docLen  = (NSUInteger)MAX(0LL, [model getLength]);

    NSMutableArray<UDModelDeltaDecoration *> *newDecors =
        [NSMutableArray arrayWithCapacity:diagnostics.count];

    for (LSPDiagnostic *diag in diagnostics) {
        if (!diag.range) continue;

        // Convert LSP character range to absolute character offsets.
        NSRange charRange = [diag.range convertToRangeInText:docText];

        // Clamp and ensure at least 1 character wide so the decoration is visible.
        NSUInteger loc = MIN(charRange.location, docLen > 0 ? docLen - 1 : 0);
        NSUInteger end = MIN(NSMaxRange(charRange), docLen);
        if (end <= loc) end = MIN(loc + 1, docLen);
        if (docLen == 0) continue;

        // Convert to 1-based UDRange for UDTextModel.
        UDRange udRange = UDRangeMakeFromOffsets(model, loc, end);

        // Store the severity in className so UDTextModelTextStorage can pick a colour.
        NSString *className = (diag.severity == LSPDiagnosticSeverityWarning) ?
            @"lsp.warning" : @"lsp.error";

        // Store the full diagnostic message for inline label display.
        UDDecorationOptions *opts =
            [[UDDecorationOptions alloc] initWithClassName:className
                                                  userInfo:diag.message ?: @""];
        UDModelDeltaDecoration *d =
            [[UDModelDeltaDecoration alloc] initWithRange:udRange options:opts];
        d.stickiness = UDTrackedRangeNeverGrowsWhenTypingAtEdges;
        [newDecors addObject:d];
    }

    _decorationIDs =
        [model deltaDecorations:_decorationIDs
                 newDecorations:newDecors
                          owner:UDLSPDiagnosticDecorationOwner];

    [ts applyDecorationHighlights];

    // Notify the delegate (e.g. UDDiagnosticTextView) that diagnostics changed.
    id<UDLSPCoordinatorDelegate> delegate = _delegate;
    if ([delegate respondsToSelector:
            @selector(lspCoordinator:didUpdateDiagnostics:forDocument:)]) {
        [delegate lspCoordinator:self
            didUpdateDiagnostics:_diagnostics
                     forDocument:_documentURL];
    }
}

@end
