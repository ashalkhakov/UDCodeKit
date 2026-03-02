/*---------------------------------------------------------------------------------------------
 *  UDTextModelTextStorage.h — NSTextStorage backed by UDTextModel.
 *
 *  Edits flow through UDTextModel (enabling undo/redo and interval-tree
 *  decoration tracking).  Search-match highlights are applied as
 *  NSBackgroundColorAttributeName attributes derived from the model's "find" owner
 *  decorations.  Tree-sitter syntax highlights are stored as decorations under the
 *  "highlight" owner and rendered as foreground-color attributes.
 *--------------------------------------------------------------------------------------------*/

#import <AppKit/AppKit.h>
#import <UDPieceTable/UDPieceTable.h>
#import "TreeSitterTheme.h"

NS_ASSUME_NONNULL_BEGIN

/// Owner string used when registering search-match decorations via deltaDecorations.
extern NSString * const UDFindDecorationOwner;

/// Owner string used when registering tree-sitter syntax-highlight decorations.
extern NSString * const UDHighlightDecorationOwner;

/// C function pointer type that returns a TSLanguage — matches the signature of all
/// generated tree-sitter language functions (e.g. tree_sitter_json).
typedef const void *(*LanguageFunc)(void);

@interface UDTextModelTextStorage : NSTextStorage

/// The underlying text model.  Use this to run searches, manipulate decorations, etc.
@property (nonatomic, readonly, strong) UDTextModel *textModel;

/// The theme used to map Tree-sitter capture names to text attributes.
/// Assign at any time; the next parse will use it.
@property (nonatomic, strong, nullable) TreeSitterTheme *theme;

/// Creates a new text storage initialised with the given text.
- (instancetype)initWithText:(NSString *)initialText;

/// Set the Tree-sitter language function and highlights query (highlights.scm content).
/// Passing NULL for languageFunc disables syntax highlighting.
- (void)setLanguageFunc:(nullable LanguageFunc)languageFunc
    withHighlightsQuery:(NSString *)queryText;

/// Recomputes all "find" and "highlight" decoration attributes from the model and
/// schedules a layout pass.  Call this after a batch of deltaDecorations changes.
- (void)applyDecorationHighlights;

@end

NS_ASSUME_NONNULL_END
