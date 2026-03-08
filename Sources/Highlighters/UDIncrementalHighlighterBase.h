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
/// decorations by walking a tree-sitter tree (incrementally or fully).
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

// State valid only during a traversal run.
@property (nonatomic, strong, readonly) NSMutableArray<UDModelDeltaDecoration *> *pendingDecorations;
@property (nonatomic, assign) NSUInteger remainingBudget;
@property (nonatomic, assign, readonly) NSUInteger currentDocLen;

- (BOOL)willVisitNode:(TSNode)node depth:(NSUInteger)depth;
- (NSUInteger)defaultMaxDecorations;
- (void)didFinishUpdate;

@end

NS_ASSUME_NONNULL_END
