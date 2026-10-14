/*---------------------------------------------------------------------------------------------
 *  Portions Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See LICENSE.txt for license information.
 *
 *  Decoration tracking after VS Code's intervalTree.ts (its node edit rules;
 *  the tree itself is a treap with lazy offsets)
 *  Original source: https://github.com/microsoft/vscode/blob/main/src/vs/editor/common/model/intervalTree.ts
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import <UDPieceTable/UDTypes.h>

@class UDDecorationOptions;

NS_ASSUME_NONNULL_BEGIN

// MARK: - UDIntervalNode

/// A node in the interval tree. Each node represents one decoration and stores the
/// decoration's current document-offset range together with its metadata.
@interface UDIntervalNode : NSObject

/// Start offset in the document (inclusive, 0-based). Read-only: the tree
/// moves its nodes as the text is edited (O(log D) to read on a node the
/// tree has not just returned, O(1) otherwise).
@property (nonatomic, readonly) NSInteger start;
/// End offset in the document (exclusive, 0-based).
@property (nonatomic, readonly) NSInteger end;

/// Stable decoration identifier.
@property (nonatomic, copy) NSString *identifier;
/// Decoration rendering options.
@property (nonatomic, strong) UDDecorationOptions *options;
/// The owner tag supplied at creation time; nil = anonymous owner.
@property (nonatomic, copy, nullable) NSString *owner;
/// Controls how the range behaves when text is inserted at its boundaries.
@property (nonatomic) UDTrackedRangeStickiness stickiness;

- (instancetype)initWithIdentifier:(NSString *)identifier
                             start:(NSInteger)start
                               end:(NSInteger)end
                           options:(UDDecorationOptions *)options
                             owner:(nullable NSString *)owner
                        stickiness:(UDTrackedRangeStickiness)stickiness;

@end

// MARK: - UDIntervalTree

/// The decorations of a text model, ordered by (start, end), as a treap whose
/// nodes carry pending offsets and their subtree's largest end. With D
/// decorations:
///   insert, remove              O(log D)
///   nodesInRange:end:           O(log D + nodes returned)
///   acceptEdit:…                O(log D + nodes touching the edit · log D);
///                               everything after the edit moves in one step
///   nodeWithIdentifier:         O(1)
///   nodesForOwner:              O(k log k) for the owner's k nodes
///   allNodes                    O(D)
@interface UDIntervalTree : NSObject

/// Number of nodes in the tree.
@property (nonatomic, readonly) NSUInteger count;

/// Insert a new node into the tree.
- (void)insert:(UDIntervalNode *)node;

/// Remove a node that was previously inserted.
- (void)remove:(UDIntervalNode *)node;

/// Return the node with the given decoration identifier, or nil.
- (nullable UDIntervalNode *)nodeWithIdentifier:(NSString *)identifier;

/// Return all nodes, ordered by start (then end).
- (NSArray<UDIntervalNode *> *)allNodes;

/// Return the nodes created with this owner (nil: no owner), ordered by start.
- (NSArray<UDIntervalNode *> *)nodesForOwner:(nullable NSString *)owner;

/// Return all nodes whose [start, end) range intersects [queryStart, queryEnd).
- (NSArray<UDIntervalNode *> *)nodesInRange:(NSInteger)queryStart
                                        end:(NSInteger)queryEnd;

/// Adjust all node ranges to account for a single edit operation.
///
/// @param editStart      First character offset affected by the edit.
/// @param deleteCount    Number of characters deleted starting at editStart.
/// @param insertCount    Number of characters inserted at editStart.
/// @param forceMoveMarkers  When YES the edit pushes nodes at editStart rightward
///                          regardless of their stickiness setting.
- (void)acceptEdit:(NSInteger)editStart
       deleteCount:(NSInteger)deleteCount
       insertCount:(NSInteger)insertCount
  forceMoveMarkers:(BOOL)forceMoveMarkers;

@end

NS_ASSUME_NONNULL_END
