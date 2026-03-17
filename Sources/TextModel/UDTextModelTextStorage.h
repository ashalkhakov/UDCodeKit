/*---------------------------------------------------------------------------------------------
 *  UDTextModelTextStorage.h — NSTextStorage backed by UDTextModel.
 *
 *  Edits flow through UDTextModel (enabling undo/redo and interval-tree
 *  decoration tracking).  Attributes are computed on-the-fly from decorations:
 *  - "highlight" owner  → syntax-highlight foreground colours (via tree-sitter)
 *  - "find" owner       → search-match yellow background
 *--------------------------------------------------------------------------------------------*/

#import <AppKit/AppKit.h>
#import <UDPieceTable/UDPieceTable.h>
#import "UDTreeSitterHighlighter.h"

@class UDCursorsController;

@class TreeSitterTheme;

NS_ASSUME_NONNULL_BEGIN

/// Owner string for search-match decorations registered via deltaDecorations.
extern NSString * const UDFindDecorationOwner;

/// Owner string for fold (collapsed) decorations registered via deltaDecorations.
extern NSString * const UDFoldDecorationOwner;

/// Owner string for bracket-match decorations registered via deltaDecorations.
extern NSString * const UDBracketMatchDecorationOwner;

/// Owner string for MISSING-node "pill" decorations registered via deltaDecorations.
extern NSString * const UDMissingNodeDecorationOwner;

/// Owner string for LSP-sourced diagnostic decorations (layer 5, above all local layers).
/// Errors use className "lsp.error"; warnings use className "lsp.warning".
extern NSString * const UDLSPDiagnosticDecorationOwner;

/// Owner string for Tree-sitter parse-error decorations (layer 6, above LSP).
/// ERROR nodes use className "ts.error"; MISSING nodes use className "ts.missing".
extern NSString * const UDParseErrorDecorationOwner;

/// Owner string for RNG/Schematron schema-validation decorations (layer 4, below LSP).
/// Errors use className "rng.error"; warnings use className "rng.warning".
extern NSString * const UDRNGDiagnosticDecorationOwner;

@interface UDTextModelTextStorage : NSTextStorage

/// The underlying text model.  Use for searches, decorations, undo/redo.
@property (nonatomic, readonly, strong) UDTextModel             *textModel;

/// Multi-cursor controller. Created lazily in -initWithTextModel:.
/// Wire this to UDDiagnosticTextView so input routes through it.
@property (nonatomic, readonly, strong) UDCursorsController     *cursorsController;

/// The tree-sitter highlighter.  Use to access the current parse tree
/// for folding and bracket-match features.
@property (nonatomic, readonly, strong) UDTreeSitterHighlighter *highlighter;

/// Theme used to map Tree-sitter capture names to text attributes.
@property (nonatomic, strong, nullable) TreeSitterTheme *theme;

/// Creates a new text storage initialised with the given text.
- (instancetype)initWithText:(NSString *)initialText;

/// Creates a text storage that wraps an existing UDTextModel.
///
/// Use this when the text model is owned by a UDCodeDocument: the same
/// UDTextModel is shared between the model layer (UDCodeDocument) and the
/// AppKit text-system bridge (UDTextModelTextStorage), so edits made through
/// either layer are immediately visible in both.
- (instancetype)initWithTextModel:(UDTextModel *)textModel;

/// Configure tree-sitter syntax highlighting.
/// Delegates to the internal UDTreeSitterHighlighter.
- (void)setLanguageFunc:(nullable LanguageFunc)languageFunc
    withHighlightsQuery:(NSString *)queryText;

/// Rebuild attribute runs from decorations and notify layout managers.
/// Call after any batch of deltaDecorations changes.
- (void)applyDecorationHighlights;

/// Signal to layout managers that attributes changed in a specific range.
/// More efficient than -applyDecorationHighlights when the dirty range is known.
- (void)applyDecorationHighlightsInRange:(NSRange)range;

@end

NS_ASSUME_NONNULL_END
