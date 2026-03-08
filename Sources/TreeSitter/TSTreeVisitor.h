//
//  UDTreeSitterVisitor.h
//  TestApp
//
//  Created by artyom on 3/8/26.
//

#import <Foundation/Foundation.h>
#import <tree_sitter/api.h>

NS_ASSUME_NONNULL_BEGIN

/// Implement this protocol to receive callbacks as the tree is walked.
/// Return YES from -visitor:willVisitNode: to recurse into children,
/// or NO to skip them.
@protocol TSNodeVisitor <NSObject>

/// Called before a node's children are visited.
/// Return YES to descend into children, NO to skip them.
- (BOOL)visitor:(id)visitor willVisitNode:(TSNode)node depth:(NSUInteger)depth;

@optional
/// Called after a node's children have been visited.
- (void)visitor:(id)visitor didVisitNode:(TSNode)node depth:(NSUInteger)depth;

/// Called once before the walker begins any traversal for the current
/// -visitTree: / -visitChangedRanges:inTree: call.
- (void)visitorWillBeginTraversal:(id)visitor;

/// Called once after the walker has finished all traversal for the current
/// -visitTree: / -visitChangedRanges:inTree: call.
- (void)visitorDidFinishTraversal:(id)visitor;

@end


/// Walks a tree-sitter TSNode tree depth-first, notifying a delegate
/// conforming to TSNodeVisitor for each node.
///
/// Two entry points are provided:
///   -visitTree:              – full scan from a root node.
///   -visitChangedRanges:inTree: – incremental scan; narrows each byte range
///                             to its deepest named covering node before walking.
@interface TSTreeVisitor : NSObject

/// The visitor delegate that receives node callbacks.
@property (nonatomic, weak, nullable) id<TSNodeVisitor> delegate;

- (instancetype)initWithDelegate:(id<TSNodeVisitor>)delegate NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// Full depth-first walk starting at rootNode.
- (void)visitTree:(TSNode)rootNode;

/// Incremental walk: for each NSRange in changedByteRanges, narrows to the
/// deepest named node that covers that byte range inside tree, then walks it.
/// Ranges with no covering node are skipped silently.
- (void)visitChangedByteRanges:(NSArray<NSValue *> *)changedByteRanges
                        inTree:(const TSTree *)tree;

@end

NS_ASSUME_NONNULL_END
