//
//  UDLSPDiagnosticHighlighter.m
//  TestApp
//
//  Created by artyom on 3/8/26.
//


#import "UDLSPDiagnosticHighlighter.h"
#import "UDDiagnosticItem.h"
#import <UDPieceTable/UDPieceTable.h>
#import "UDDecorationLayerRegistry.h"

NSString * const UDLSPDiagnosticDecorationOwner = @"lsp.diagnostic";

@implementation UDLSPDiagnosticHighlighter {
    UDDiagnosticStore *_store;
}

+ (void)load { [self registerDecorationLayer]; }

+ (void)registerDecorationLayer {
    [[UDDecorationLayerRegistry shared]
        registerOwner:UDLSPDiagnosticDecorationOwner
                layer:5
           attrBlock:^NSDictionary *(UDIntervalNode *node) {
        static NSColor *errC, *warnC;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            errC  = [NSColor colorWithRed:0.95 green:0.20 blue:0.20 alpha:0.18];
            warnC = [NSColor colorWithRed:0.95 green:0.75 blue:0.10 alpha:0.22];
        });
        BOOL isWarning = [node.options.className isEqualToString:@"lsp.warning"];
        return @{ NSBackgroundColorAttributeName: isWarning ? warnC : errC };
    }];
}

// ---------------------------------------------------------------------------
#pragma mark - Init
// ---------------------------------------------------------------------------

- (instancetype)initWithTextStorage:(UDTextModelTextStorage *)textStorage
                         highlighter:(UDTreeSitterHighlighter *)highlighter
                               store:(UDDiagnosticStore *)store {
    self = [super initWithTextStorage:textStorage highlighter:highlighter];
    if (!self) return nil;
    _store = store;
    return self;
}

// ---------------------------------------------------------------------------
#pragma mark - UDDecorationHighlighter overrides
// ---------------------------------------------------------------------------

- (NSString *)decorationOwner {
    return UDLSPDiagnosticDecorationOwner;
}

/// -update is intentionally unused for LSP: the trigger is -applyDiagnostics:,
/// not a parse event. Override to no-op so accidental calls are harmless.
- (void)update {}

// ---------------------------------------------------------------------------
#pragma mark - Public API
// ---------------------------------------------------------------------------

- (void)applyDiagnostics:(NSArray<LSPDiagnostic *> *)diagnostics {
    // Ensure we always land on the main queue — callers need not worry.
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self applyDiagnostics:diagnostics];
        });
        return;
    }

    UDTextModel *model  = self.textStorage.textModel;
    NSUInteger   docLen = (NSUInteger)MAX(0LL, [model getLength]);

    NSMutableArray<UDModelDeltaDecoration *> *newDecors =
        [NSMutableArray arrayWithCapacity:diagnostics.count];
    NSMutableArray<UDDiagnosticItem *> *newItems =
        [NSMutableArray arrayWithCapacity:diagnostics.count];

    for (LSPDiagnostic *diag in diagnostics) {
        if (!diag.range) continue;

        // LSP uses 0-based line/character; UDTextModel uses 1-based line/column.
        NSInteger startOff =
            [model getOffsetAt:(NSInteger)diag.range.start.line + 1
                        column:(NSInteger)diag.range.start.character + 1];
        NSInteger endOff =
            [model getOffsetAt:(NSInteger)diag.range.end.line + 1
                        column:(NSInteger)diag.range.end.character + 1];

        NSUInteger loc = (NSUInteger)MAX(0LL, startOff);
        NSUInteger end = (NSUInteger)MAX(0LL, endOff);
        if (docLen > 0) {
            loc = MIN(loc, docLen - 1);
            end = MIN(end, docLen);
        }
        if (end <= loc) end = MIN(loc + 1, docLen);
        if (docLen == 0) continue;

        // --- Decoration --------------------------------------------------
        UDPosition sp = [model getPositionAt:(NSInteger)loc];
        UDPosition ep = [model getPositionAt:(NSInteger)end];
        UDRange udRange = PTRangeMake(sp.line, sp.column, ep.line, ep.column);

        BOOL isWarning = (diag.severity == LSPDiagnosticSeverityWarning);
        NSString *className = isWarning ? @"lsp.warning" : @"lsp.error";
        UDDecorationOptions *opts =
            [[UDDecorationOptions alloc] initWithClassName:className
                                                  userInfo:diag.message ?: @""];
        UDModelDeltaDecoration *d =
            [[UDModelDeltaDecoration alloc] initWithRange:udRange options:opts];
        d.stickiness = UDTrackedRangeNeverGrowsWhenTypingAtEdges;
        [newDecors addObject:d];

        // --- Diagnostic item --------------------------------------------
        UDDiagnosticSeverity severity = isWarning ? UDDiagnosticSeverityWarning
                                                   : UDDiagnosticSeverityError;
        UDDiagnosticItem *item =
            [[UDDiagnosticItem alloc] initWithLine:(NSInteger)diag.range.start.line + 1
                                            column:(NSInteger)diag.range.start.character
                                           message:diag.message ?: @""
                                          severity:severity
                                            source:UDDiagnosticSourceLSP];
        [newItems addObject:item];
    }

    // Commit decorations (base class handles ID tracking + applyHighlights).
    [self commitDecorations:newDecors];

    // Publish to the shared store — replaces the entire LSP partition.
    [_store setDiagnostics:newItems forSource:UDDiagnosticSourceLSP];
}

@end
