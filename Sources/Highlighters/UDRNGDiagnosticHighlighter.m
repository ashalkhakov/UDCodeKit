/*---------------------------------------------------------------------------------------------
 *  UDRNGDiagnosticHighlighter.m
 *--------------------------------------------------------------------------------------------*/

#import "UDRNGDiagnosticHighlighter.h"
#import "UDDiagnosticItem.h"
#import "UDDecorationLayerRegistry.h"
#import <UDPieceTable/UDPieceTable.h>

NSString * const UDRNGDiagnosticDecorationOwner = @"rng.diagnostic";

// NOTE: these are also defined in the extension.
// TODO: make it possible for extensions to provide their own highlighting, or just colors for the highlights
// so that we can then use that uniformly
UDDiagnosticSource const UDDiagnosticSourceRNG        = @"rng";
UDDiagnosticSource const UDDiagnosticSourceSchematron = @"schematron";

@implementation UDRNGDiagnosticHighlighter {
    UDDiagnosticStore * __weak _store;
}

// ---------------------------------------------------------------------------
#pragma mark - Decoration layer registration
// ---------------------------------------------------------------------------

+ (void)load { [self registerDecorationLayer]; }

+ (void)registerDecorationLayer {
    [[UDDecorationLayerRegistry shared]
        registerOwner:UDRNGDiagnosticDecorationOwner
                layer:4
           attrBlock:^NSDictionary *(UDIntervalNode *node) {
        static NSColor *errC, *warnC;
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            // Purple tint for RNG/Schematron errors — distinct from LSP (red) and
            // Tree-sitter parse errors (orange).
            errC  = [NSColor colorWithRed:0.60 green:0.10 blue:0.85 alpha:0.20];
            warnC = [NSColor colorWithRed:0.90 green:0.70 blue:0.00 alpha:0.20];
        });
        BOOL isWarning = [node.options.className isEqualToString:@"rng.warning"];
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

    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(_diagnosticsDidChange:)
               name:UDDiagnosticsDidChangeNotification
             object:store];
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

// ---------------------------------------------------------------------------
#pragma mark - UDDecorationHighlighter overrides
// ---------------------------------------------------------------------------

- (NSString *)decorationOwner {
    return UDRNGDiagnosticDecorationOwner;
}

/// The trigger is a notification, not a tree-parse event.  No-op here.
- (void)update {}

// ---------------------------------------------------------------------------
#pragma mark - UDDocumentService
// ---------------------------------------------------------------------------

- (void)closeDocument {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self clearDecorations];
}

// ---------------------------------------------------------------------------
#pragma mark - Notification handler
// ---------------------------------------------------------------------------

- (void)_diagnosticsDidChange:(NSNotification *)note {
    NSAssert([NSThread isMainThread],
             @"UDDiagnosticsDidChangeNotification must arrive on the main thread");

    UDDiagnosticStore *store = _store;
    if (!store || note.object != store) return;

    UDTextModel *model = self.textStorage.textModel;
    if (!model) return;

    NSInteger docLen = [model getLength];
    if (docLen <= 0) {
        [self clearDecorations];
        return;
    }

    NSMutableArray<UDModelDeltaDecoration *> *newDecors = [NSMutableArray array];

    for (UDDiagnosticItem *item in store.allDiagnostics) {
        // Only handle RNG and Schematron items.
        if (![item.source isEqualToString:UDDiagnosticSourceRNG] &&
            ![item.source isEqualToString:UDDiagnosticSourceSchematron]) continue;

        // Map 1-based line / 0-based column to a character offset.
        // UDTextModel.getOffsetAt: uses 1-based line and 1-based column, so
        // add 1 to the 0-based column from UDDiagnosticItem.
        NSInteger startOff = [model getOffsetAt:item.line
                                         column:item.column + 1];
        if (startOff < 0 || startOff >= docLen) continue;

        NSUInteger loc = (NSUInteger)startOff;
        NSUInteger end = MIN(loc + 1, (NSUInteger)docLen);

        UDPosition sp = [model getPositionAt:(NSInteger)loc];
        UDPosition ep = [model getPositionAt:(NSInteger)end];
        UDRange udRange = PTRangeMake(sp.line, sp.column, ep.line, ep.column);

        BOOL isWarning = (item.severity != UDDiagnosticSeverityError);
        NSString *className = isWarning ? @"rng.warning" : @"rng.error";
        UDDecorationOptions *opts =
            [[UDDecorationOptions alloc] initWithClassName:className
                                                  userInfo:item.message];
        UDModelDeltaDecoration *d =
            [[UDModelDeltaDecoration alloc] initWithRange:udRange options:opts];
        d.stickiness = UDTrackedRangeNeverGrowsWhenTypingAtEdges;
        [newDecors addObject:d];
    }

    [self commitDecorations:newDecors];
}

@end
