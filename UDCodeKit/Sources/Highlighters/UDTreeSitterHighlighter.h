#import <Foundation/Foundation.h>
#import <UDPieceTable/UDPieceTable.h>
#import "UDTreeSitterTypes.h"

NS_ASSUME_NONNULL_BEGIN

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
/// that changed in the most recent incremental re-parse: where the tree
/// changed, and the text the edits since the previous parse put in (an empty
/// range where they only deleted). Nil after a full parse (initial load, a
/// new language). Empty when nothing changed.
@property (nonatomic, readonly, copy, nullable) NSArray<NSValue *> *lastChangedCharRanges;

- (instancetype)initWithTextModel:(UDTextModel *)model;

/// Configure (or replace) the tree-sitter language and highlights query.
/// Pass NULL / empty string to disable parsing.
- (void)setLanguageFunc:(nullable LanguageFunc)languageFunc
    withHighlightsQuery:(nullable NSString *)queryText;

/// Tells the current tree about one edit, right after the model applied it:
/// characters [start, oldEnd) became [start, newEnd); the positions are the
/// model's (1-based) at those offsets — oldEnd's taken before the edit.
/// Several edits may be applied before one -reparseAfterEdits.
- (void)applyEditAtOffset:(NSUInteger)start
                   oldEnd:(NSUInteger)oldEnd
                   newEnd:(NSUInteger)newEnd
            startPosition:(UDPosition)startPosition
           oldEndPosition:(UDPosition)oldEndPosition
           newEndPosition:(UDPosition)newEndPosition;

/// Incrementally re-parses after the edits applied since the last parse.
/// Reads the current document text directly from the text model; no string copy needed.
- (void)reparseAfterEdits;

/// Force a complete re-parse from the text model (e.g. after undo/redo).
/// Reads the current document text directly from the text model; no string copy needed.
- (void)reparseFromModel;

@end

NS_ASSUME_NONNULL_END
