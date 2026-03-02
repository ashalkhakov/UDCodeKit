/*---------------------------------------------------------------------------------------------
 *  UDFoldingController.h
 *
 *  Computes foldable regions from the current tree-sitter parse tree and manages
 *  UDFoldDecorationOwner decorations on UDTextModel to produce a collapsed
 *  visual appearance via UDTextModelTextStorage.
 *
 *  Call -update whenever the document or its parse tree changes.
 *  Wire the UDLineNumberGutterView via -lineNumberGutterView to keep fold
 *  indicators in sync automatically.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "UDTextModelTextStorage.h"
#import "UDTreeSitterHighlighter.h"
#import "UDLineNumberGutterView.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDFoldingController : NSObject

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

/// Optional reference to the line-number gutter; updated automatically when
/// fold state or foldable regions change.
@property (nonatomic, weak, nullable) UDLineNumberGutterView *lineNumberGutterView;

/// 1-based line numbers of all currently foldable regions (read-only, updated by -update).
@property (nonatomic, readonly, copy) NSSet<NSNumber *> *foldableLineNumbers;

/// 1-based line numbers of all currently folded regions (read-only).
@property (nonatomic, readonly, copy) NSSet<NSNumber *> *foldedLineNumbers;

/// Re-compute foldable regions from the current parse tree.
/// Call after each document or tree-sitter update.
- (void)update;

/// Toggle the fold state for the region whose opening delimiter is on @c lineNumber.
/// Does nothing if @c lineNumber is not in foldableLineNumbers.
- (void)toggleFoldAtLine:(NSInteger)lineNumber;

@end

NS_ASSUME_NONNULL_END
