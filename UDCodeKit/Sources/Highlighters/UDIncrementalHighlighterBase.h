//
//  UDIncrementalHighlighterBase.h
//  TestApp
//
//  Created by artyom on 3/8/26.
//
#import "UDDecorationHighlighter.h"
#import <tree_sitter/api.h>

@class UDModelDeltaDecoration;

NS_ASSUME_NONNULL_BEGIN

/// Subclass of UDDecorationHighlighter for highlighters that collect
/// decorations by walking a tree-sitter parse tree for ERROR/MISSING nodes.
///
/// ## Incremental algorithm
///
/// After an incremental parse, `UDTreeSitterHighlighter.lastChangedCharRanges`
/// holds where the tree changed (ts_tree_get_changed_ranges) and where the
/// edits put text. A decoration marks the start of an error node; outside
/// those ranges the nodes, and so the decorations, are the same.
///
///   1. **Stale removal** – a decoration goes if it starts in a changed range,
///      or was squashed to nothing in one (an empty range is where the edits
///      only deleted).
///   2. **New discovery** – walk each changed range: only children that
///      overlap it, and only subtrees that hold an error (ts_node_has_error),
///      so a walk costs the paths to the errors, not the tree. A candidate
///      is added unless a kept decoration already starts where it does (two
///      ranges can reach one node).
///
/// When `alwaysFullScan` is YES the incremental paths are bypassed and the
/// whole tree is walked on every update (still only the subtrees holding an
/// error).
///
/// Subclasses MUST override:
///   -decorationOwner
///   -willVisitNode:depth:
///
/// Subclasses MAY override:
///   -defaultMaxDecorations
///   -didFinishUpdate
@interface UDIncrementalHighlighterBase : UDDecorationHighlighter

@property (nonatomic, assign) NSUInteger maxDecorations;

/// When YES, bypass the incremental path and always walk the whole tree.
/// Defaults to NO.
@property (nonatomic, assign) BOOL alwaysFullScan;

// State valid only during a traversal run.
@property (nonatomic, strong, readonly) NSMutableArray<UDModelDeltaDecoration *> *pendingDecorations;
@property (nonatomic, assign) NSUInteger remainingBudget;
@property (nonatomic, assign, readonly) NSUInteger currentDocLen;

/// Called for each node the walk reaches that holds an error (itself or
/// below); return whether to walk its children.
- (BOOL)willVisitNode:(TSNode)node depth:(NSUInteger)depth;
- (NSUInteger)defaultMaxDecorations;

- (void)didFinishUpdate;

@end

NS_ASSUME_NONNULL_END
