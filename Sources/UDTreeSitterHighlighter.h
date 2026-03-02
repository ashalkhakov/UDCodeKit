/*---------------------------------------------------------------------------------------------
 *  UDTreeSitterHighlighter.h
 *
 *  Encapsulates all tree-sitter parsing state and maintains a set of
 *  "highlight" owner decorations on a UDTextModel.  UDTextModelTextStorage
 *  owns one instance and delegates incremental parsing to it.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import <UDPieceTable/UDPieceTable.h>
#import "TreeSitterTheme.h"

NS_ASSUME_NONNULL_BEGIN

extern NSString * const UDHighlightDecorationOwner;

/// C function pointer type matching all generated tree-sitter language functions
/// (e.g. tree_sitter_json).
typedef const void *_Nullable(*LanguageFunc)(void);

@interface UDTreeSitterHighlighter : NSObject

/// Theme used to resolve capture-name → NSAttributedString attributes.
/// Set before calling setLanguageFunc:withHighlightsQuery:.
@property (nonatomic, strong, nullable) TreeSitterTheme *theme;

/// YES while a language has been configured and parsing is active.
@property (nonatomic, readonly) BOOL isActive;

/// The IDs of all "highlight" decorations currently registered on the model.
@property (nonatomic, readonly, copy) NSArray<NSString *> *highlightDecorationIDs;

/// The current parse tree (opaque TSTree*).  Valid until the next edit.
/// Import <tree_sitter/api.h> and cast to TSTree* to use.  Do NOT free.
/// Returns NULL when no language is active.
@property (nonatomic, readonly, nullable) const void *currentParseTree;

- (instancetype)initWithTextModel:(UDTextModel *)model;

/// Configure (or replace) the tree-sitter language and highlights query.
/// Pass NULL to disable parsing.
- (void)setLanguageFunc:(nullable LanguageFunc)languageFunc
    withHighlightsQuery:(NSString *)queryText;

/// Call after each NSTextStorage edit to perform an incremental re-parse.
/// @param editedRange  The range reported by NSTextStorage.editedRange.
/// @param delta        The changeInLength value from NSTextStorage.
/// @param s            A snapshot of the full document text at this point.
- (void)performIncrementalParseAfterEdit:(NSRange)editedRange
                           changeInLength:(NSInteger)delta
                            currentString:(NSString *)s;

/// Force a complete re-parse (e.g. after undo/redo).
- (void)reparseFullString:(NSString *)s;

@end

NS_ASSUME_NONNULL_END
