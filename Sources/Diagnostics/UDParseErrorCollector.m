//
//  UDParseErrorCollector.m
//  TestApp
//
//  Created by artyom on 3/8/26.
//

#import "UDParseErrorCollector.h"
#import "UDDiagnosticItem.h"
#import <tree_sitter/api.h>

// Private owner string — never visible to the model as a real decoration owner.
// We pass it to satisfy UDIncrementalHighlighterBase but never actually commit
// any decorations under it.
static NSString * const kParseErrorCollectorOwner = @"__parseErrorCollector__";

@implementation UDParseErrorCollector {
    UDDiagnosticStore *_store;

    // Accumulated during one traversal run; flushed to the store in
    // -didFinishUpdate.
    NSMutableArray<UDDiagnosticItem *> *_pendingErrors;
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
    // Diagnostic items store static line/column positions that are not tracked
    // by the interval tree — they become stale when the document is edited.
    // A full tree walk on every update ensures the store always reflects the
    // current parse tree exactly.
    self.alwaysFullScan = YES;
    return self;
}

// ---------------------------------------------------------------------------
#pragma mark - UDIncrementalHighlighterBase overrides
// ---------------------------------------------------------------------------

- (NSString *)decorationOwner {
    // We never actually commit decorations, but the base class requires an
    // owner string.  Use a private sentinel that won't collide with real owners.
    return kParseErrorCollectorOwner;
}

- (NSUInteger)defaultMaxDecorations {
    // Re-purpose the budget as the max error count.
    return _store.maxItemsPerSource;
}

- (BOOL)willVisitNode:(TSNode)node depth:(NSUInteger)depth {
    BOOL isError   = ts_node_is_error(node);
    BOOL isMissing = ts_node_is_missing(node);

    if (!isError && !isMissing) return YES; // not an error node — descend

    // Build the diagnostic item.
    TSPoint pt = ts_node_start_point(node);
    NSInteger line   = (NSInteger)pt.row + 1;   // 1-based
    NSInteger column = (NSInteger)pt.column;

    NSString *message;
    if (isMissing) {
        const char *t = ts_node_type(node);
        NSString *type = t ? [NSString stringWithUTF8String:t] : @"token";
        message = [NSString stringWithFormat:@"Missing %@", type];
    } else {
        message = @"Unexpected token";
    }

    UDDiagnosticItem *item =
        [[UDDiagnosticItem alloc] initWithLine:line
                                        column:column
                                       message:message
                                      severity:UDDiagnosticSeverityError
                                        source:UDDiagnosticSourceParser];
    [_pendingErrors addObject:item];
    self.remainingBudget--;

    // For ERROR nodes, still descend — there may be nested MISSING children.
    // For MISSING nodes, there are no meaningful children.
    return isError;
}

- (void)visitorWillBeginTraversal:(id)visitor {
    _pendingErrors = [NSMutableArray array];
}

- (void)didFinishUpdate {
    // With alwaysFullScan = YES the walk always covers the full tree, so
    // _pendingErrors contains every current parse error.  Replacing the whole
    // parser partition in one shot is correct and cheap.
    [_store setDiagnostics:_pendingErrors
                 forSource:UDDiagnosticSourceParser];
    _pendingErrors = nil;

    // Do NOT call commitDecorations: — we have nothing to decorate.
}

@end
