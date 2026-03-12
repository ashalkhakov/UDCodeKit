//
//  UDDecorationHighlighter.h
//  TestApp
//
//  Created by artyom on 3/8/26.
//

#import <Foundation/Foundation.h>
#import "UDTextModelTextStorage.h"
#import "UDTreeSitterHighlighter.h"

@class UDModelDeltaDecoration;

NS_ASSUME_NONNULL_BEGIN

/// Lightweight base class for highlighters that manage a set of decorations
/// in a UDTextModel.  Handles the decoration ID list, committing new
/// decorations, clearing on teardown, and calling
/// -applyDecorationHighlights after every commit.
///
/// Subclasses implement -update and call -commitDecorations:
/// (or -clearDecorations) when they are done building their decoration list.
@interface UDDecorationHighlighter : NSObject

/// Called once (from +load) to register this highlighter's owner, layer,
/// and attribute block with UDDecorationLayerRegistry.
/// Subclasses MUST override this if they produce visual decorations.
+ (void)registerDecorationLayer;

@property (nonatomic, weak, readonly) UDTextModelTextStorage  *textStorage;
@property (nonatomic, weak, readonly) UDTreeSitterHighlighter *highlighter;

- (instancetype)initWithTextStorage:(UDTextModelTextStorage *)textStorage
                         highlighter:(UDTreeSitterHighlighter *)highlighter
    NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// Re-evaluate and update decorations. Subclasses must override.
- (void)update;

/// The decoration owner tag. Subclasses must override.
- (NSString *)decorationOwner;

// ---------------------------------------------------------------------------
// Protected helpers — call from subclass -update implementations
// ---------------------------------------------------------------------------

/// Direct access to the current decoration ID list for subclasses that need
/// surgical (partial) replacement rather than a full swap.
- (NSArray<NSString *> *)_currentDecorationIDs;
- (void)_setDecorationIDs:(NSArray<NSString *> *)ids;

/// Replace all current decorations with newDecorations and call
/// -applyDecorationHighlights.  Passing an empty array clears all.
- (void)commitDecorations:(NSArray<UDModelDeltaDecoration *> *)newDecorations;

/// Remove all current decorations and call -applyDecorationHighlights.
- (void)clearDecorations;

@end

NS_ASSUME_NONNULL_END
