/*---------------------------------------------------------------------------------------------
 *  Portions Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See LICENSE.txt for license information.
 *
 *  Objective-C port of VS Code's intervalTree.ts (decoration-tracking subset)
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

/// Start offset in the document (inclusive, 0-based).
@property (nonatomic) NSInteger start;
/// End offset in the document (exclusive, 0-based).
@property (nonatomic) NSInteger end;

/// Stable decoration identifier (UUID string).
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

/// A minimal interval tree for decoration range tracking.
///
/// The tree is backed by a plain sorted NSMutableArray of UDIntervalNode objects.
/// This gives O(n) for inserts, deletes, and edit-adjustment but provides
/// correct range-intersection queries with early-exit based on start-position order
/// — all nodes whose start ≥ queryEnd are skipped without visiting them.
///
/// The key algorithmic value-add over the previous flat-dictionary implementation
/// is the stickiness-aware @c acceptEdit logic (ported from VS Code's
/// @c nodeAcceptEdit function) and the @c nodesInRange: intersection query.
@interface UDIntervalTree : NSObject

/// Insert a new node into the tree.
- (void)insert:(UDIntervalNode *)node;

/// Remove a node that was previously inserted.
- (void)remove:(UDIntervalNode *)node;

/// Return the node with the given decoration identifier, or nil.
- (nullable UDIntervalNode *)nodeWithIdentifier:(NSString *)identifier;

/// Return all nodes in insertion order.
- (NSArray<UDIntervalNode *> *)allNodes;

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
