/*---------------------------------------------------------------------------------------------
 *  UDFoldingController.h
 *
 *  Finds foldable regions in the tree-sitter parse tree and folds them with
 *  UDFoldDecorationOwner decorations on the UDTextModel, which
 *  UDTextModelTextStorage draws collapsed.
 *
 *  Nothing is computed for the whole document: the gutter asks which of the
 *  lines it draws are foldable or folded, and the answer walks only the parse
 *  tree over those lines. Folds are their decorations, so they move with
 *  edits; -update drops the ones an edit took the region of.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "UDTextModelTextStorage.h"
#import "UDTreeSitterHighlighter.h"
#import "UDLineNumberGutterView.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDFoldingController : NSObject <UDLineNumberGutterFoldingSource>

/// Designated initialiser.
/// @param foldableNodeTypes  Node type names (as returned by ts_node_type) whose
///        multi-line instances become foldable.  Pass nil to use the built-in
///        defaults: @["object", "array"].
- (instancetype)initWithTextView:(NSTextView *)textView
                     textStorage:(UDTextModelTextStorage *)textStorage
                     highlighter:(UDTreeSitterHighlighter *)highlighter
               foldableNodeTypes:(nullable NSArray<NSString *> *)foldableNodeTypes;

/// Convenience initialiser using the built-in default foldable node types.
- (instancetype)initWithTextView:(NSTextView *)textView
                     textStorage:(UDTextModelTextStorage *)textStorage
                     highlighter:(UDTreeSitterHighlighter *)highlighter;

/// The line-number gutter that shows the fold indicators: the controller
/// becomes its folding source and asks it to redraw when folds change.
@property (nonatomic, weak, nullable) UDLineNumberGutterView *lineNumberGutterView;

/// The lines, 1-based, among @a lines (location = first line, length =
/// count) on which a foldable region opens. Costs the parse tree over them.
- (NSIndexSet *)foldableLinesInRange:(NSRange)lines;

/// The lines among @a lines whose region is folded.
- (NSIndexSet *)foldedLinesInRange:(NSRange)lines;

/// After the document or its parse tree changed: drops the folds whose
/// region an edit took. Costs the folds the change touched.
- (void)update;

/// Folds or unfolds the region that opens on @a lineNumber (the innermost,
/// when several do). Does nothing when none does.
- (void)toggleFoldAtLine:(NSInteger)lineNumber;

@end

NS_ASSUME_NONNULL_END
