/*---------------------------------------------------------------------------------------------
 *  Portions Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See LICENSE.txt for license information.
 *
 *  Cursor-oriented operations.
 *  Original concept: https://github.com/microsoft/vscode/blob/main/src/vs/editor/common/cursor/cursor.ts
 *--------------------------------------------------------------------------------------------*/
#import <Foundation/Foundation.h>
#import <UDPieceTable/UDTypes.h>
#import <UDPieceTable/UDCommand.h>

NS_ASSUME_NONNULL_BEGIN

@class UDTextModel;

/// The main controller for multi-cursor editing.
/// Mirrors VS Code's CursorsController.
///
/// Usage:
///   UDCursorsController *ctrl = [[UDCursorsController alloc] initWithModel:model];
///   ctrl.selections = @[ [NSValue ud_valueWithSelection:UDSelectionFromPosition(1, 1)] ];
///   [ctrl typeText:@"a" source:@"keyboard"];
@interface UDCursorsController : NSObject

/// All current cursor selections. The first element is the primary cursor.
/// Each element is an NSValue wrapping a UDSelection.
@property (nonatomic, copy) NSArray<NSValue *> *selections;

- (instancetype)initWithModel:(UDTextModel *)model;

// MARK: - Editing

/// Type a string (plain, no auto-closing/smart-indent).
- (void)typeText:(NSString *)text source:(nullable NSString *)source;

/// Backspace: delete left of each cursor.
- (void)deleteLeftWithSource:(nullable NSString *)source;

/// Forward-delete: delete right of each cursor.
- (void)deleteRightWithSource:(nullable NSString *)source;

/// Execute a set of pre-built commands (one per cursor), replacing current selections.
- (void)executeCommands:(NSArray<id<UDCommand>> *)commands;

// MARK: - Multi-cursor management

/// Add an additional cursor at position, keeping all existing ones.
- (void)addCursorAtLine:(NSInteger)line column:(NSInteger)column;

/// Remove all secondary cursors; keep only the primary.
- (void)removeSecondaryCursors;

@end

// MARK: - NSValue category for UDSelection

@interface NSValue (UDSelection)
+ (instancetype)ud_valueWithSelection:(UDSelection)sel;
- (UDSelection)ud_selectionValue;
@end

NS_ASSUME_NONNULL_END
