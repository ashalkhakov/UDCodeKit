//
//  UDIncrementalHighlighterBase.h
//  TestApp
//
//  Created by artyom on 3/8/26.
//
#import "UDDecorationHighlighter.h"
#import "TSTreeVisitor.h"
#import <tree_sitter/api.h>

@class UDModelDeltaDecoration;

NS_ASSUME_NONNULL_BEGIN

/// Subclass of UDDecorationHighlighter for highlighters that collect
/// decorations by walking a tree-sitter parse tree for ERROR/MISSING nodes.
///
/// ## Incremental algorithm
///
/// After every edit tree-sitter provides `ts_tree_get_changed_ranges`, a
/// structural diff of the old vs new parse trees (stored in
/// `UDTreeSitterHighlighter.lastChangedCharRanges`).  This diff is used to
/// drive both removal of stale decorations and discovery of new ones:
///
///   1. **Stale removal** – remove existing decorations whose *start offset*
///      falls within any changed range.  We check start position (not range
///      overlap) because a decoration marks the *start* of the error node that
///      produced it.  If a decoration starts outside every changed range its
///      error node is guaranteed identical in both trees, so the decoration
///      remains valid.
///
///   2. **New discovery** – DFS from the deepest named node covering each
///      changed byte range (efficient: only revisits affected subtrees).
///      Post-filter the candidates to only those whose start offset falls
///      within a changed range, and deduplicate (two changed ranges can
///      resolve to the same large ERROR-node subtree).
///
/// When `alwaysFullScan` is YES the incremental paths are bypassed and a
/// complete tree walk is performed on every update.  Use this for subclasses
/// that maintain external state (e.g. a diagnostic store) that cannot rely on
/// interval-tree position tracking.
///
/// Subclasses MUST override:
///   -decorationOwner
///   -willVisitNode:depth:
///
/// Subclasses MAY override:
///   -defaultMaxDecorations
///   -didFinishUpdate
@interface UDIncrementalHighlighterBase : UDDecorationHighlighter <TSNodeVisitor>

@property (nonatomic, assign) NSUInteger maxDecorations;

/// When YES, bypass the incremental path and always do a full tree walk.
/// Defaults to NO.  Set to YES in subclasses that cannot tolerate partial
/// updates (e.g. UDParseErrorCollector, whose diagnostic items store static
/// line/column positions that are not tracked by the interval tree).
@property (nonatomic, assign) BOOL alwaysFullScan;

// State valid only during a traversal run.
@property (nonatomic, strong, readonly) NSMutableArray<UDModelDeltaDecoration *> *pendingDecorations;
@property (nonatomic, assign) NSUInteger remainingBudget;
@property (nonatomic, assign, readonly) NSUInteger currentDocLen;

- (BOOL)willVisitNode:(TSNode)node depth:(NSUInteger)depth;
- (NSUInteger)defaultMaxDecorations;
- (void)didFinishUpdate;

@end

NS_ASSUME_NONNULL_END
