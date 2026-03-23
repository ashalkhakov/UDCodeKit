#import <Foundation/Foundation.h>
#import <UDPieceTable/UDPieceTable.h>

NS_ASSUME_NONNULL_BEGIN

/// C function pointer type matching all generated tree-sitter language
/// functions (e.g. tree_sitter_json).
typedef const void *_Nullable(*LanguageFunc)(void);

/// Encapsulates all tree-sitter parsing state.  Performs incremental
/// re-parses and exposes the current parse tree and changed ranges so that
/// separate highlighter objects can react to document changes.
///
/// This class no longer owns any decorations; decoration work is delegated
/// to UDSyntaxHighlighter (and siblings like UDMissingNodeHighlighter).
@interface UDTreeSitterHighlighter : NSObject

/// YES while a language has been configured and parsing is active.
@property (nonatomic, readonly) BOOL isActive;

/// The current parse tree (opaque TSTree *).
/// Cast to TSTree * after importing <tree_sitter/api.h>.  Do NOT free.
/// NULL when no language is active.
@property (nonatomic, readonly, nullable) const void *currentParseTree;

/// The active TSQuery * (opaque), or NULL when none is configured.
/// Cast to TSQuery * after importing <tree_sitter/api.h>.  Do NOT free.
@property (nonatomic, readonly, nullable) const void *currentQuery;

/// The active TSQueryCursor * (opaque), or NULL when none is configured.
/// Cast to TSQueryCursor * after importing <tree_sitter/api.h>.  Do NOT free.
@property (nonatomic, readonly, nullable) const void *currentQueryCursor;

/// Character ranges (NSValue-wrapped NSRanges, 0-based character offsets)
/// that changed in the most recent incremental re-parse.
/// Nil after a full re-parse (initial load, undo/redo).
/// Empty array when an incremental re-parse produced no changed ranges.
@property (nonatomic, readonly, copy, nullable) NSArray<NSValue *> *lastChangedCharRanges;

- (instancetype)initWithTextModel:(UDTextModel *)model;

/// Configure (or replace) the tree-sitter language and highlights query.
/// Pass NULL / empty string to disable parsing.
- (void)setLanguageFunc:(nullable LanguageFunc)languageFunc
    withHighlightsQuery:(nullable NSString *)queryText;

/// Call after each NSTextStorage edit to perform an incremental re-parse.
/// Reads the current document text directly from the text model; no string copy needed.
- (void)performIncrementalParseAfterEdit:(NSRange)editedRange
                           changeInLength:(NSInteger)delta;

/// Force a complete re-parse from the text model (e.g. after undo/redo).
/// Reads the current document text directly from the text model; no string copy needed.
- (void)reparseFromModel;

@end

NS_ASSUME_NONNULL_END
