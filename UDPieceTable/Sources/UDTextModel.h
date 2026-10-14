/*---------------------------------------------------------------------------------------------
 *  Portions Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See LICENSE.txt for license information.
 *
 *  Objective-C port of VS Code's textModel.ts (minimal subset)
 *  Original source: https://github.com/microsoft/vscode/blob/main/src/vs/editor/common/model/textModel.ts
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import <UDPieceTable/UDTypes.h>
#import <UDPieceTable/UDTextModelSearch.h>
#import <UDPieceTable/UDIntervalTree.h>

NS_ASSUME_NONNULL_BEGIN

// MARK: - UDTextModelEdit

/// A single edit operation: replace [range] with [text].
/// Mirrors VS Code's IIdentifiedSingleEditOperation (range + text).
@interface UDTextModelEdit : NSObject
@property (nonatomic) UDRange range;
@property (nonatomic, copy) NSString *text;
- (instancetype)initWithRange:(UDRange)range text:(NSString *)text;
@end

// MARK: - UDDecorationOptions

/// Metadata attached to a text decoration (syntax highlights, error messages, etc.).
@interface UDDecorationOptions : NSObject
/// An optional CSS-like class name for visual styling.
@property (nonatomic, copy, nullable) NSString *className;
/// Arbitrary user-supplied metadata (e.g., hover message, diagnostic info).
@property (nonatomic, strong, nullable) id userInfo;
- (instancetype)initWithClassName:(nullable NSString *)className
                         userInfo:(nullable id)userInfo;
@end

// MARK: - UDModelDeltaDecoration

/// A decoration to add: range + options, mirroring VS Code's IModelDeltaDecoration.
@interface UDModelDeltaDecoration : NSObject
@property (nonatomic) UDRange range;
@property (nonatomic, strong) UDDecorationOptions *options;
/// Controls how the decoration's range grows when text is inserted at its boundaries.
/// Defaults to UDTrackedRangeNeverGrowsWhenTypingAtEdges.
@property (nonatomic) UDTrackedRangeStickiness stickiness;
- (instancetype)initWithRange:(UDRange)range options:(UDDecorationOptions *)options;
@end

// MARK: - UDTextModelContentChange

/// One change an edit call made, as VS Code's IModelContentChange: the range
/// it replaced, as offsets and as positions, and the text that replaced it.
/// A call's changes run from the end of the document to the start, so each
/// one's offsets and positions hold in the document as the ones before it
/// left it, and the first in document order is the last.
@interface UDTextModelContentChange : NSObject
@property (nonatomic, readonly) UDRange range;
@property (nonatomic, readonly) NSInteger rangeOffset;
@property (nonatomic, readonly) NSInteger rangeLength;
@property (nonatomic, readonly, copy) NSString *text;
- (instancetype)initWithRange:(UDRange)range
                  rangeOffset:(NSInteger)rangeOffset
                  rangeLength:(NSInteger)rangeLength
                         text:(NSString *)text NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
/// Where the inserted text ends: the position after it.
- (UDPosition)endPositionOfText;
@end

// MARK: - UDTextModel

/// Posted after each successful -applyEdits: call (including undo/redo).
/// The userInfo dictionary contains @"edits": NSArray<UDTextModelEdit *>, the
/// edits as given (their ranges refer to the text before the call), and
/// UDTextModelChangesKey: NSArray<UDTextModelContentChange *>.
extern NSNotificationName const UDTextModelDidChangeNotification;
extern NSString * const UDTextModelChangesKey;

/// Posted after -deltaDecorations:newDecorations:owner: whenever any decoration
/// is added or removed.  The userInfo contains:
///   @"range": NSValue wrapping an NSRange of the union of all changed decoration
///             character offsets (0-based).  Only present when dirtyRange.length > 0.
extern NSNotificationName const UDTextModelDecorationsDidChangeNotification;

/// A minimal port of VS Code's TextModel backed by UDPieceTree.
///
/// Supports:
///  - Simple editing operations (insert / delete / replace) via -applyEdits:
///  - Undo/redo via NSUndoManager (pass in your own or use the built-in one)
///  - Text decorations with range-tracking (syntax highlights, error markers, …)
///    backed by UDIntervalTree with full TrackedRangeStickiness support
///  - Text search via the existing UDTextModelSearch infrastructure
@interface UDTextModel : NSObject

/// The undo manager used for undo/redo. Assign before any edits to share an
/// undo manager with the rest of the application (e.g., the document's NSUndoManager).
@property (nonatomic, strong) NSUndoManager *undoManager;

/// Names the text's current state, as VS Code's alternativeVersionId: every
/// edit gives a new number, and undoing it brings back the number from
/// before (redoing, the one after). Recorded at a save, it tells whether the
/// text now differs from what was saved, however it got here.
@property (nonatomic, readonly) NSInteger alternativeVersionId;

- (instancetype)initWithText:(NSString *)text;

// MARK: Buffer API

/// Returns the full text content of the model.
- (NSString *)getValue;
/// Returns the total number of characters.
- (NSInteger)getLength;
/// Returns the UTF-16 code unit at the given 0-based character offset.
- (unichar)getCharacterAtOffset:(NSUInteger)offset;
/// Returns the text of the piece that contains @c offset, beginning at @c offset
/// and extending to the end of that piece.  This is the efficient way to read a
/// bulk run of characters without per-character tree traversals.
- (NSString *)getNearestChunkAtOffset:(NSUInteger)offset;
/// Fills @c buffer with the UTF-16 code units for @c aRange without creating
/// any intermediate NSString objects.  Prefer this over getNearestChunkAtOffset:
/// for bulk reads where the caller already has a destination buffer.
- (void)fillCharacters:(unichar *)buffer range:(NSRange)aRange;
/// Returns the number of lines (always >= 1).
- (NSInteger)getLineCount;
- (NSInteger)getLineLength:(NSInteger)lineNumber;
- (NSInteger)getLineMaxColumn:(NSInteger)lineNumber;
/// Returns the content of the given 1-based line, without the line-ending.
- (NSString *)getLineContent:(NSInteger)lineNumber;
/// Returns the (1-based line, 1-based column) position at a character offset.
- (UDPosition)getPositionAt:(NSInteger)offset;
/// Returns the character offset for a 1-based line/column.
- (NSInteger)getOffsetAt:(NSInteger)lineNumber column:(NSInteger)column;

/// The nearest position in the text, as VS Code's validatePosition: a line
/// before the first is the start, after the last the end; a column is put
/// within its line.
- (UDPosition)validatePosition:(UDPosition)position;

/// The range with both ends validated, start first. Edits and decorations
/// are validated before use.
- (UDRange)validateRange:(UDRange)range;
/// Returns the text within the given (1-based) range.
- (NSString *)getValueInRange:(UDRange)range;

// MARK: EOL

/// Returns the line-ending sequence used by this model (@"\n", @"\r\n", or @"\r").
/// The EOL is auto-detected from the first line ending in the initial text;
/// if none is found the default is @"\n".
- (NSString *)getEOL;

/// Sets the EOL sequence and re-normalises all existing line endings.
/// Accepted values: @"\n", @"\r\n", @"\r".
- (void)setEOL:(NSString *)eol;

// MARK: Editing

/// Applies a batch of edit operations atomically.
///
/// Each edit's range refers to the document state *before* this call.
/// Edits are applied end-to-start so earlier ranges are not invalidated.
/// The inverse edits are registered with undoManager as a single undo action.
- (void)applyEdits:(NSArray<UDTextModelEdit *> *)edits;

// MARK: Decorations

/// VS Code-style deltaDecorations scoped to an owner.
///
/// @param owner        An arbitrary string identifying the caller (e.g. @"syntax",
///                     @"linter").  Pass nil to use a shared, anonymous owner.
///                     An owner can only remove decorations it created: IDs that
///                     belong to a different owner are silently ignored.
/// @param oldDecorations   IDs previously returned by this method for the same owner.
/// @param newDecorations   Decorations to add.
/// @return The IDs of the newly created decorations.
///
/// Decoration ranges are automatically updated as subsequent edits are applied,
/// respecting the stickiness of each decoration.
- (NSArray<NSString *> *)deltaDecorations:(nullable NSArray<NSString *> *)oldDecorations
                           newDecorations:(NSArray<UDModelDeltaDecoration *> *)newDecorations
                                    owner:(nullable NSString *)owner;

/// Convenience wrapper – equivalent to passing @c nil as the owner.
- (NSArray<NSString *> *)deltaDecorations:(nullable NSArray<NSString *> *)oldDecorations
                           newDecorations:(NSArray<UDModelDeltaDecoration *> *)newDecorations;

/// Returns the IDs of all decorations that belong to the given owner.
/// Pass nil to get decorations belonging to the anonymous owner.
- (NSArray<NSString *> *)decorationsForOwner:(nullable NSString *)owner;

/// The decoration nodes of @a owner, sorted by start: O(k log k) for the
/// owner's k decorations, whatever else the model holds.
- (NSArray<UDIntervalNode *> *)decorationNodesForOwner:(nullable NSString *)owner;

/// Returns the IDs of all decorations whose ranges intersect the given range.
- (NSArray<NSString *> *)decorationsInRange:(UDRange)range;

/// Returns all decoration interval nodes whose offset range intersects [start, end).
/// Unlike -decorationsInRange:, this method works directly with 0-based character
/// offsets, avoiding the line/column conversion overhead.
- (NSArray<UDIntervalNode *> *)decorationNodesInOffsetRange:(NSInteger)start end:(NSInteger)end;

/// Returns the current (possibly edit-adjusted) range of a decoration.
/// Returns an all-zero range (0,0,0,0) if the ID is unknown (valid ranges
/// always use 1-based line/column, so 0 is an unambiguous sentinel).
- (UDRange)rangeForDecoration:(NSString *)decorationID;

/// Returns the options for a decoration, or nil if the ID is unknown.
- (nullable UDDecorationOptions *)optionsForDecoration:(NSString *)decorationID;

// MARK: Search

/// Finds all matches for searchString across the full document.
- (NSArray<UDFindMatch *> *)findMatches:(NSString *)searchString
                                isRegex:(BOOL)isRegex
                              matchCase:(BOOL)matchCase
                         wordSeparators:(nullable NSString *)wordSeparators
                       limitResultCount:(NSInteger)limitResultCount;

/// Finds the matches in @a searchRange, as VS Code's findMatches with a
/// search range: line by line (a match never spans lines), at most
/// @a limitResultCount of them (NSIntegerMax for all). With
/// @a captureMatches each match carries the text of the whole match and of
/// each regex group.
- (NSArray<UDFindMatch *> *)findMatches:(NSString *)searchString
                            searchRange:(UDRange)searchRange
                                isRegex:(BOOL)isRegex
                              matchCase:(BOOL)matchCase
                         wordSeparators:(nullable NSString *)wordSeparators
                         captureMatches:(BOOL)captureMatches
                       limitResultCount:(NSInteger)limitResultCount;

/// Finds the next match at or after @c startPosition, wrapping around to the
/// beginning of the document if needed.  Returns nil if the document contains
/// no match at all.
- (nullable UDFindMatch *)findNextMatch:(NSString *)searchString
                                isRegex:(BOOL)isRegex
                              matchCase:(BOOL)matchCase
                         wordSeparators:(nullable NSString *)wordSeparators
                                   from:(UDPosition)startPosition;

/// Finds the previous match strictly before @c startPosition, wrapping around
/// to the end of the document if needed.  Returns nil if the document contains
/// no match at all.
- (nullable UDFindMatch *)findPreviousMatch:(NSString *)searchString
                                    isRegex:(BOOL)isRegex
                                  matchCase:(BOOL)matchCase
                             wordSeparators:(nullable NSString *)wordSeparators
                                       from:(UDPosition)startPosition;

@end

NS_ASSUME_NONNULL_END
