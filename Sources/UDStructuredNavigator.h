/*---------------------------------------------------------------------------------------------
 *  UDStructuredNavigator.h
 *
 *  Provides tree-structured navigation through the current tree-sitter parse tree.
 *  Each navigation step moves the NSTextView selection to cover the corresponding
 *  AST node's character range, mirroring the "modeless structured navigation"
 *  concept described in the ATStead project.
 *
 *  Key bindings (wired from AppDelegate via a local NSEvent monitor):
 *    Option-Up    → move to parent node
 *    Option-Down  → move to first named child
 *    Option-Left  → move to previous named sibling
 *    Option-Right → move to next named sibling
 *
 *  The "current node" is always derived from the NSTextView's current selection:
 *  the deepest named node that fully contains the selection is used as the
 *  starting point for each navigation step.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "UDTreeSitterHighlighter.h"
#import <UDPieceTable/UDPieceTable.h>

NS_ASSUME_NONNULL_BEGIN

@interface UDStructuredNavigator : NSObject

- (instancetype)initWithTextView:(NSTextView *)textView
                      highlighter:(UDTreeSitterHighlighter *)highlighter
                        textModel:(UDTextModel *)textModel;

/// Move to the parent of the currently selected node.
- (void)moveToParent;

/// Move to the first *named* child of the currently selected node.
- (void)moveToFirstChild;

/// Move to the previous *named* sibling of the currently selected node.
- (void)moveToPrevSibling;

/// Move to the next *named* sibling of the currently selected node.
- (void)moveToNextSibling;

@end

NS_ASSUME_NONNULL_END
