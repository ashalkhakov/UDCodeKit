/*---------------------------------------------------------------------------------------------
 *  UDMissingNodeHighlighter.h
 *
 *  Detects tree-sitter MISSING nodes in the current parse tree and registers
 *  UDMissingNodeDecorationOwner decorations at their adjacent character positions
 *  so that UDTextModelTextStorage can render them as a distinctive "pill" indicator.
 *
 *  MISSING nodes are zero-width virtual tokens inserted by the tree-sitter
 *  parser for error recovery.  For example, if a JSON value is expected but
 *  absent, tree-sitter emits a MISSING node at that location.  The pill
 *  background (orange, rendered by UDTextModelTextStorage layer 4) highlights
 *  the character immediately after the missing position, signalling to the user
 *  that the parser expected something that was not provided.
 *
 *  Call -update after every document / parse-tree change.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "UDTextModelTextStorage.h"
#import "UDTreeSitterHighlighter.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDMissingNodeHighlighter : NSObject

- (instancetype)initWithTextStorage:(UDTextModelTextStorage *)textStorage
                         highlighter:(UDTreeSitterHighlighter *)highlighter;

/// Re-scan the current parse tree for MISSING nodes and update decorations.
/// Safe to call on every document change.
- (void)update;

@end

NS_ASSUME_NONNULL_END
