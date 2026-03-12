/*---------------------------------------------------------------------------------------------
 *  UDStructuredNavigator.h
 *
 *  Provides tree-structured navigation through the current tree-sitter parse tree,
 *  following the "modeless structure editing" model described by Bernard Sufrin
 *  (Oxford, ATStead project).
 *
 *  HOLE
 *  ----
 *  The "hole" (focus) is always derived from the NSTextView's current cursor position
 *  or selection: the deepest named AST node that fully contains the cursor/selection
 *  is treated as the current node for each navigation step.  No separate navigation
 *  state is maintained — the text cursor IS the hole.
 *
 *  NAVIGATION OPERATIONS (Option + arrow key)
 *  ------------------------------------------
 *    Option-Up    (Up)    Move to the nearest named parent.
 *                         Stays put when already at the root (no parent).
 *
 *    Option-Down  (Down)  Move to the first named child.
 *                         Stays put when the node has no named children (leaf).
 *
 *    Option-Left  (Left)  Move to the previous named sibling.
 *                         Stays put when already the leftmost child (no previous
 *                         named sibling), or when there is no parent.
 *
 *    Option-Right (Right) Move to the next named sibling.
 *                         Stays put when already the rightmost child (no next
 *                         named sibling), or when there is no parent.
 *
 *  IDENTITIES (Sufrin §2)
 *  ----------------------
 *    down, then up  = identity   — when the starting node is not a leaf
 *                                  (going to first child and back always returns
 *                                   to the same parent)
 *
 *    up, then down  = identity   — when the starting node is NOT the root AND
 *                                  IS the leftmost child of its parent
 *                                  (going to parent then down to first child
 *                                   lands back at the same node iff it was
 *                                   already the first child)
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "UDTreeSitterHighlighter.h"
#import <UDPieceTable/UDPieceTable.h>
@class UDTextModel;

NS_ASSUME_NONNULL_BEGIN

@interface UDStructuredNavigator : NSObject

- (instancetype)initWithTextView:(NSTextView *)textView
                      highlighter:(UDTreeSitterHighlighter *)highlighter
                        textModel:(UDTextModel *)textModel;

/// Up: move to the nearest named parent.
/// Stays put when already at the root.
- (void)moveToParent;

/// Down: move to the first named child.
/// Stays put when the node has no named children.
- (void)moveToFirstChild;

/// Left: move to the previous named sibling.
/// Stays put when already the leftmost child.
- (void)moveToPrevSibling;

/// Right: move to the next named sibling.
/// Stays put when already the rightmost child.
- (void)moveToNextSibling;

@end

NS_ASSUME_NONNULL_END
