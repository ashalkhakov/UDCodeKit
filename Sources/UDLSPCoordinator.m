/*---------------------------------------------------------------------------------------------
 *  UDLSPCoordinator.m
 *--------------------------------------------------------------------------------------------*/

#import "UDLSPCoordinator.h"
#import <UDPieceTable/UDPieceTable.h>

// Decoration owner constant used for LSP diagnostic highlights.
// Defined here (not in UDTextModelTextStorage) so the text-storage layer
// remains unaware of LSP.
NSString * const UDLSPDiagnosticDecorationOwner = @"lsp.diagnostic";

@interface UDLSPCoordinator ()
@property (nonatomic, weak)   UDTextModelTextStorage          *textStorage;
@property (nonatomic, strong) LSPClient                       *client;
@property (nonatomic, copy)   NSURL                           *documentURL;
@property (nonatomic, copy)   NSArray<NSString *>             *decorationIDs;
@property (nonatomic, copy)   NSArray<LSPDiagnostic *>        *diagnostics;
@end

@implementation UDLSPCoordinator

// ---------------------------------------------------------------------------
// MARK: - Init
// ---------------------------------------------------------------------------

- (instancetype)initWithTextStorage:(UDTextModelTextStorage *)textStorage
                              client:(LSPClient *)client
                         documentURL:(NSURL *)url {
    self = [super init];
    if (!self) return nil;
    _textStorage   = textStorage;
    _client        = client;
    _documentURL   = [url copy];
    _decorationIDs = @[];
    _diagnostics   = @[];
    return self;
}

// ---------------------------------------------------------------------------
// MARK: - Document lifecycle
// ---------------------------------------------------------------------------

- (void)openDocument:(NSString *)content {
    __weak typeof(self) weakSelf = self;
    [_client initialWithCompletionHandler:^(NSError *error) {
        __strong typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        if (error) {
            NSLog(@"[UDLSPCoordinator] LSP initialize failed: %@", error);
            return;
        }
        [strongSelf->_client documentDidOpen:strongSelf->_documentURL
                                      content:content];
    }];
    [_client addObserver:self];
}

- (void)textWillChangeInRange:(NSRange)range
              replacementString:(NSString *)replacement {
    if (!replacement) replacement = @"";
    [_client document:_documentURL
    changeTextInRange:range
    replacementString:replacement];
}

- (void)documentWillSave {
    [_client documentWillSave:_documentURL];
}

- (void)documentDidSave {
    [_client documentDidSave:_documentURL];
}

- (void)closeDocument {
    [_client documentDidClose:_documentURL];
    [_client removeObserver:self];
}

// ---------------------------------------------------------------------------
// MARK: - LSPClientObserver
// ---------------------------------------------------------------------------

- (void)languageServer:(LSPClient *)client
              document:(NSURL *)url
           diagnostics:(NSArray<LSPDiagnostic *> *)diagnostics {
    // Only handle diagnostics for our document.
    if (![url.path isEqualToString:_documentURL.path]) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        [self _applyDiagnostics:diagnostics];
    });
}

- (void)languageServer:(LSPClient *)client
            logMessage:(NSString *)message
                  type:(LSPMessageType)type {
    NSLog(@"[LSP] log: %@", message);
}

// ---------------------------------------------------------------------------
// MARK: - Decoration application
// ---------------------------------------------------------------------------

- (void)_applyDiagnostics:(NSArray<LSPDiagnostic *> *)diagnostics {
    _diagnostics = diagnostics ?: @[];

    UDTextModelTextStorage *ts = _textStorage;
    if (!ts) return;

    UDTextModel *model      = ts.textModel;
    NSString    *docText    = [model getValue];
    NSUInteger   docLen     = (NSUInteger)[model getLength];

    // Build new decoration set – one decoration per diagnostic covering its
    // full character range.
    NSMutableArray<UDModelDeltaDecoration *> *newDecors =
        [NSMutableArray arrayWithCapacity:diagnostics.count];

    for (LSPDiagnostic *diag in diagnostics) {
        if (!diag.range) continue;
        NSRange charRange = [diag.range convertToRangeInText:docText];

        // Clamp to document bounds and ensure non-empty (at least 1 char).
        NSUInteger loc = MIN(charRange.location, docLen > 0 ? docLen - 1 : 0);
        NSUInteger end = MIN(NSMaxRange(charRange), docLen);
        if (end <= loc) end = MIN(loc + 1, docLen);
        if (docLen == 0) continue;

        NSUInteger severity = (NSUInteger)diag.severity;
        // Store severity in className for UDTextModelTextStorage to use.
        NSString *className = (severity == LSPDiagnosticSeverityError) ?
            @"lsp.error" : @"lsp.warning";

        UDDecorationOptions *opts =
            [[UDDecorationOptions alloc] initWithClassName:className
                                                  userInfo:nil];
        UDModelDeltaDecoration *d =
            [[UDModelDeltaDecoration alloc]
                initWithRange:PTRangeFromNSRange(PTRangeMake(0,0,0,0), loc, end - loc, docText)
                      options:opts];
        d.stickiness = UDTrackedRangeNeverGrowsWhenTypingAtEdges;
        [newDecors addObject:d];
    }

    _decorationIDs =
        [model deltaDecorations:_decorationIDs
                 newDecorations:newDecors
                          owner:UDLSPDiagnosticDecorationOwner];

    [ts applyDecorationHighlights];

    // Notify delegate so the text view can refresh inline labels.
    id<UDLSPCoordinatorDelegate> delegate = _delegate;
    if ([delegate respondsToSelector:@selector(lspCoordinator:didUpdateDiagnostics:forDocument:)]) {
        [delegate lspCoordinator:self
            didUpdateDiagnostics:_diagnostics
                     forDocument:_documentURL];
    }
}

@end

// ---------------------------------------------------------------------------
// MARK: - PTRangeFromNSRange helper
// ---------------------------------------------------------------------------

/// Convert an NSRange (character-offset based) into a UDRange (line/column).
static UDRange PTRangeFromNSRange(UDRange unused, NSUInteger loc, NSUInteger len,
                                  NSString *text) {
    (void)unused;
    NSUInteger docLen = text.length;
    if (docLen == 0) return PTRangeMake(0, 0, 0, 0);
    NSUInteger safeLoc = MIN(loc, docLen);
    NSUInteger safeEnd = MIN(loc + len, docLen);

    // Count lines / columns for start.
    NSUInteger line   = 0, col = 0, idx = 0;
    while (idx < safeLoc) {
        unichar c = [text characterAtIndex:idx++];
        if (c == '\n') { line++; col = 0; } else { col++; }
    }
    NSUInteger startLine = line, startCol = col;

    // Continue for end.
    while (idx < safeEnd) {
        unichar c = [text characterAtIndex:idx++];
        if (c == '\n') { line++; col = 0; } else { col++; }
    }
    return PTRangeMake((NSInteger)startLine, (NSInteger)startCol,
                       (NSInteger)line,      (NSInteger)col);
}
