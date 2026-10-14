//
//  UDDecorationLayerRegistry.h
//  TestApp
//
//  Created by artyom on 3/8/26.
//


#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <UDPieceTable/UDIntervalTree.h>

NS_ASSUME_NONNULL_BEGIN

/// A block that maps an interval node to its visual NSAttributedString
/// attributes, or returns nil if the node should not affect text appearance.
typedef NSDictionary<NSAttributedStringKey, id> * _Nullable
    (^UDDecorationAttrBlock)(UDIntervalNode *node);

/// Singleton registry: maps decoration owner string → (render layer, attr block).
/// Lower layer indices are applied first; higher layers override them.
/// Register entries from any +load or -init before text storage is used.
@interface UDDecorationLayerRegistry : NSObject

+ (instancetype)shared;

/// Register an owner.  Safe to call from any thread before the run loop starts.
/// Registering the same owner twice replaces the previous entry.
- (void)registerOwner:(NSString *)owner
                layer:(NSInteger)layer
           attrBlock:(UDDecorationAttrBlock)block;

/// Ordered (by ascending layer) entries whose owner is known.
/// Returns nil for unknown owners.
- (nullable NSArray<NSDictionary *> *)entriesForOwner:(NSString *)owner;

/// Compute merged attributes for a set of covering nodes at one character
/// position, applying registered layers in ascending order.
/// baseAttributes is applied first (lowest priority).
- (NSDictionary<NSAttributedStringKey, id> *)
    mergedAttributesForNodes:(NSArray<UDIntervalNode *> *)nodes
             baseAttributes:(NSDictionary<NSAttributedStringKey, id> *)base;

@end

NS_ASSUME_NONNULL_END
