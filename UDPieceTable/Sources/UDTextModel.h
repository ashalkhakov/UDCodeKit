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
- (instancetype)initWithRange:(UDRange)range options:(UDDecorationOptions *)options;
@end

// MARK: - UDTextModel

/// Posted after each successful -applyEdits: call (including undo/redo).
/// The userInfo dictionary contains @"edits": NSArray<UDTextModelEdit *>.
extern NSNotificationName const UDTextModelDidChangeNotification;

/// A minimal port of VS Code's TextModel backed by UDPieceTree.
///
/// Supports:
///  - Simple editing operations (insert / delete / replace) via -applyEdits:
///  - Undo/redo via NSUndoManager (pass in your own or use the built-in one)
///  - Text decorations with range-tracking (syntax highlights, error markers, …)
///  - Text search via the existing UDTextModelSearch infrastructure
@interface UDTextModel : NSObject

/// The undo manager used for undo/redo. Assign before any edits to share an
/// undo manager with the rest of the application (e.g., the document's NSUndoManager).
@property (nonatomic, strong) NSUndoManager *undoManager;

- (instancetype)initWithText:(NSString *)text;

// MARK: Buffer API

/// Returns the full text content of the model.
- (NSString *)getValue;
/// Returns the total number of characters.
- (NSInteger)getLength;
/// Returns the number of lines (always >= 1).
- (NSInteger)getLineCount;
/// Returns the content of the given 1-based line, without the line-ending.
- (NSString *)getLineContent:(NSInteger)lineNumber;
/// Returns the (1-based line, 1-based column) position at a character offset.
- (UDPosition)getPositionAt:(NSInteger)offset;
/// Returns the character offset for a 1-based line/column.
- (NSInteger)getOffsetAt:(NSInteger)lineNumber column:(NSInteger)column;
/// Returns the text within the given (1-based) range.
- (NSString *)getValueInRange:(UDRange)range;

// MARK: Editing

/// Applies a batch of edit operations atomically.
///
/// Each edit's range refers to the document state *before* this call.
/// Edits are applied end-to-start so earlier ranges are not invalidated.
/// The inverse edits are registered with undoManager as a single undo action.
- (void)applyEdits:(NSArray<UDTextModelEdit *> *)edits;

// MARK: Decorations

/// VS Code-style deltaDecorations: removes decorations with the given IDs and
/// adds the new decorations.  Returns the IDs of the newly created decorations.
///
/// Decoration ranges are automatically updated as subsequent edits are applied.
- (NSArray<NSString *> *)deltaDecorations:(nullable NSArray<NSString *> *)oldDecorations
                           newDecorations:(NSArray<UDModelDeltaDecoration *> *)newDecorations;

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

@end

NS_ASSUME_NONNULL_END
