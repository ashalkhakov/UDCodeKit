/*---------------------------------------------------------------------------------------------
 *  Portions Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See LICENSE.txt for license information.
 *
 *  Objective-C port of VS Code's textModel.ts (minimal subset)
 *  Original source: https://github.com/microsoft/vscode/blob/main/src/vs/editor/common/model/textModel.ts
 *--------------------------------------------------------------------------------------------*/

#import "UDTextModel.h"
#import "UDPieceTree.h"
#import "UDStringBuffer.h"

// MARK: - Internal decoration (private to this file)

@interface UDDecoration : NSObject
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic) NSInteger startOffset;
@property (nonatomic) NSInteger endOffset;
@property (nonatomic, strong) UDDecorationOptions *options;
@property (nonatomic, copy, nullable) NSString *owner;
- (instancetype)initWithIdentifier:(NSString *)identifier
                       startOffset:(NSInteger)startOffset
                         endOffset:(NSInteger)endOffset
                           options:(UDDecorationOptions *)options
                             owner:(nullable NSString *)owner;
@end

@implementation UDDecoration
- (instancetype)initWithIdentifier:(NSString *)identifier
                       startOffset:(NSInteger)startOffset
                         endOffset:(NSInteger)endOffset
                           options:(UDDecorationOptions *)options
                             owner:(nullable NSString *)owner {
    self = [super init];
    if (self) {
        _identifier   = [identifier copy];
        _startOffset  = startOffset;
        _endOffset    = endOffset;
        _options      = options;
        _owner        = [owner copy];
    }
    return self;
}
@end

// MARK: - UDTextModelEdit

@implementation UDTextModelEdit
- (instancetype)initWithRange:(UDRange)range text:(NSString *)text {
    self = [super init];
    if (self) {
        _range = range;
        _text  = [text copy];
    }
    return self;
}
@end

// MARK: - UDDecorationOptions

@implementation UDDecorationOptions
- (instancetype)initWithClassName:(nullable NSString *)className
                         userInfo:(nullable id)userInfo {
    self = [super init];
    if (self) {
        _className = [className copy];
        _userInfo  = userInfo;
    }
    return self;
}
@end

// MARK: - UDModelDeltaDecoration

@implementation UDModelDeltaDecoration
- (instancetype)initWithRange:(UDRange)range options:(UDDecorationOptions *)options {
    self = [super init];
    if (self) {
        _range   = range;
        _options = options;
    }
    return self;
}
@end

// MARK: - Notification name

NSNotificationName const UDTextModelDidChangeNotification = @"UDTextModelDidChangeNotification";

// MARK: - Helpers

/// Build a UDPieceTree from an arbitrary text string.
static UDPieceTree *CreatePieceTreeFromText(NSString *text) {
    NSMutableArray<NSNumber *> *lineStarts = [NSMutableArray arrayWithObject:@0];
    NSInteger len = (NSInteger)text.length;
    for (NSInteger i = 0; i < len; i++) {
        unichar c = [text characterAtIndex:(NSUInteger)i];
        if (c == '\r') {
            if (i + 1 < len && [text characterAtIndex:(NSUInteger)(i + 1)] == '\n') {
                [lineStarts addObject:@(i + 2)];
                i++;
            } else {
                [lineStarts addObject:@(i + 1)];
            }
        } else if (c == '\n') {
            [lineStarts addObject:@(i + 1)];
        }
    }
    UDStringBuffer *buf = [[UDStringBuffer alloc] initWithBuffer:text lineStarts:lineStarts];
    NSArray<UDStringBuffer *> *chunks = (text.length > 0) ? @[buf] : @[];
    return [[UDPieceTree alloc] initWithChunks:chunks eol:@"\n" eolNormalized:YES];
}

/// Map a single offset through an edit (delete deleteLen chars at editStart,
/// then insert insertedLen chars at editStart).
///
/// Strategy:
///  - Offsets at or before editStart are unchanged.
///  - Offsets inside the deleted region move to (editStart + insertedLen).
///  - Offsets after the deleted region shift by (insertedLen - deleteLen).
static NSInteger AdjustOffset(NSInteger offset,
                               NSInteger editStart,
                               NSInteger deleteLen,
                               NSInteger insertedLen) {
    if (offset < editStart) {
        return offset;
    } else if (offset < editStart + deleteLen) {
        return editStart + insertedLen;
    } else {
        return offset - deleteLen + insertedLen;
    }
}

// MARK: - UDTextModel private interface

@interface UDTextModel ()
@property (nonatomic, strong) UDPieceTree *pieceTree;
@property (nonatomic, strong) NSMutableDictionary<NSString *, UDDecoration *> *decorations;
@end

// MARK: - UDTextModel implementation

@implementation UDTextModel

- (instancetype)initWithText:(NSString *)text {
    self = [super init];
    if (self) {
        _pieceTree   = CreatePieceTreeFromText(text);
        _undoManager = [[NSUndoManager alloc] init];
        _decorations = [NSMutableDictionary dictionary];
    }
    return self;
}

// MARK: Buffer API

- (NSString *)getValue {
    return [self.pieceTree getLinesRawContent];
}

- (NSInteger)getLength {
    return [self.pieceTree getLength];
}

- (NSInteger)getLineCount {
    return [self.pieceTree getLineCount];
}

- (NSString *)getLineContent:(NSInteger)lineNumber {
    return [self.pieceTree getLineContent:lineNumber];
}

- (UDPosition)getPositionAt:(NSInteger)offset {
    return [self.pieceTree getPositionAt:offset];
}

- (NSInteger)getOffsetAt:(NSInteger)lineNumber column:(NSInteger)column {
    return [self.pieceTree getOffsetAtLine:lineNumber column:column];
}

- (NSString *)getValueInRange:(UDRange)range {
    return [self.pieceTree getValueInRange_startLine:range.startLineNumber
                                        startColumn:range.startColumn
                                            endLine:range.endLineNumber
                                          endColumn:range.endColumn];
}

// MARK: - Internal editing

/// Adjust all tracked decoration offsets to account for a single edit.
- (void)_adjustDecorationsForEditAtOffset:(NSInteger)editStart
                                deleteLen:(NSInteger)deleteLen
                              insertedLen:(NSInteger)insertedLen {
    for (UDDecoration *d in self.decorations.allValues) {
        d.startOffset = AdjustOffset(d.startOffset, editStart, deleteLen, insertedLen);
        d.endOffset   = AdjustOffset(d.endOffset,   editStart, deleteLen, insertedLen);
    }
}

/// Core editing implementation shared by -applyEdits: and the undo/redo handler.
///
/// Sorts edits end-to-start, applies each to the piece tree, adjusts decoration
/// ranges, and registers a single undo action.  Undo-edit positions are tracked
/// as raw character offsets so that each subsequent forward edit (applied to the
/// left of prior ones) can shift them correctly before the final conversion to
/// line/column.
- (void)_applyEditsCore:(NSArray<UDTextModelEdit *> *)edits {
    // Sort edits end-to-start so each edit's range indexes into the unmodified document.
    NSArray<UDTextModelEdit *> *sorted =
        [edits sortedArrayUsingComparator:^NSComparisonResult(UDTextModelEdit *a,
                                                              UDTextModelEdit *b) {
            if (a.range.endLineNumber != b.range.endLineNumber) {
                return (a.range.endLineNumber > b.range.endLineNumber)
                       ? NSOrderedAscending : NSOrderedDescending;
            }
            if (a.range.endColumn != b.range.endColumn) {
                return (a.range.endColumn > b.range.endColumn)
                       ? NSOrderedAscending : NSOrderedDescending;
            }
            return NSOrderedSame;
        }];

    // Track each undo edit as a raw (startOffset, endOffset) pair in the
    // evolving document.  After every forward edit we shift all previously
    // recorded offsets so they remain valid in the current document state.
    NSMutableArray<NSNumber *> *undoStartOffsets =
        [NSMutableArray arrayWithCapacity:sorted.count];
    NSMutableArray<NSNumber *> *undoEndOffsets =
        [NSMutableArray arrayWithCapacity:sorted.count];
    NSMutableArray<NSString *> *undoTexts =
        [NSMutableArray arrayWithCapacity:sorted.count];

    for (UDTextModelEdit *edit in sorted) {
        NSInteger startOffset =
            [self.pieceTree getOffsetAtLine:edit.range.startLineNumber
                                     column:edit.range.startColumn];
        NSInteger endOffset =
            [self.pieceTree getOffsetAtLine:edit.range.endLineNumber
                                     column:edit.range.endColumn];
        NSInteger deleteLen   = endOffset - startOffset;
        NSInteger insertedLen = (NSInteger)edit.text.length;

        // Capture the text that will be overwritten (needed for undo).
        NSString *originalText = [self getValueInRange:edit.range];

        // Apply the edit to the underlying piece tree.
        if (deleteLen > 0) {
            [self.pieceTree deleteAtOffset:startOffset count:deleteLen];
        }
        if (insertedLen > 0) {
            [self.pieceTree insertAtOffset:startOffset
                                     value:edit.text
                             eolNormalized:NO];
        }

        // Adjust previously recorded undo offsets for this edit.
        // This edit is always to the LEFT of the previously recorded edits
        // (because we process end-to-start), so their offsets shift by
        // (insertedLen - deleteLen).
        NSUInteger prevCount = undoStartOffsets.count;
        for (NSUInteger k = 0; k < prevCount; k++) {
            undoStartOffsets[k] = @(AdjustOffset(undoStartOffsets[k].integerValue,
                                                  startOffset, deleteLen, insertedLen));
            undoEndOffsets[k]   = @(AdjustOffset(undoEndOffsets[k].integerValue,
                                                  startOffset, deleteLen, insertedLen));
        }

        // Record the undo for this edit in the current document state.
        [undoStartOffsets addObject:@(startOffset)];
        [undoEndOffsets   addObject:@(startOffset + insertedLen)];
        [undoTexts        addObject:originalText];

        // Track decoration offsets through this edit.
        [self _adjustDecorationsForEditAtOffset:startOffset
                                      deleteLen:deleteLen
                                    insertedLen:insertedLen];
    }

    // All undo offsets are now expressed in the FINAL document state.
    // Convert them to line/column ranges for the undo action.
    NSMutableArray<UDTextModelEdit *> *undoEdits =
        [NSMutableArray arrayWithCapacity:undoTexts.count];
    for (NSUInteger k = 0; k < undoTexts.count; k++) {
        NSInteger s = undoStartOffsets[k].integerValue;
        NSInteger e = undoEndOffsets[k].integerValue;
        UDPosition startPos = [self.pieceTree getPositionAt:s];
        UDPosition endPos   = (e > s) ? [self.pieceTree getPositionAt:e] : startPos;
        UDRange range = PTRangeMake(startPos.line, startPos.column,
                                    endPos.line,   endPos.column);
        [undoEdits addObject:[[UDTextModelEdit alloc] initWithRange:range
                                                               text:undoTexts[k]]];
    }

    // Register a single undo action that reapplies the inverse edits.
    NSArray<UDTextModelEdit *> *undoArray = [undoEdits copy];
    [self.undoManager registerUndoWithTarget:self
                                     handler:^(UDTextModel *target) {
        [target _applyEditsCore:undoArray];
        [[NSNotificationCenter defaultCenter]
            postNotificationName:UDTextModelDidChangeNotification
                          object:target
                        userInfo:@{@"edits": undoArray}];
    }];
}

- (void)applyEdits:(NSArray<UDTextModelEdit *> *)edits {
    [self _applyEditsCore:edits];
    [[NSNotificationCenter defaultCenter]
        postNotificationName:UDTextModelDidChangeNotification
                      object:self
                    userInfo:@{@"edits": edits}];
}

// MARK: - Decorations

- (NSArray<NSString *> *)deltaDecorations:(nullable NSArray<NSString *> *)oldDecorations
                           newDecorations:(NSArray<UDModelDeltaDecoration *> *)newDecorations
                                    owner:(nullable NSString *)owner {
    // Remove old decorations that belong to this owner (ignore foreign IDs).
    for (NSString *oldID in oldDecorations) {
        UDDecoration *existing = self.decorations[oldID];
        if (!existing) { continue; }
        // Treat nil owner as the anonymous owner: only remove if owners match.
        BOOL sameOwner = (owner == nil && existing.owner == nil)
                      || [owner isEqualToString:existing.owner];
        if (sameOwner) {
            [self.decorations removeObjectForKey:oldID];
        }
    }

    // Add new decorations tagged with this owner.
    NSMutableArray<NSString *> *newIDs =
        [NSMutableArray arrayWithCapacity:newDecorations.count];
    for (UDModelDeltaDecoration *delta in newDecorations) {
        NSString *identifier = [[NSUUID UUID] UUIDString];
        NSInteger startOffset = [self getOffsetAt:delta.range.startLineNumber
                                           column:delta.range.startColumn];
        NSInteger endOffset   = [self getOffsetAt:delta.range.endLineNumber
                                           column:delta.range.endColumn];
        UDDecoration *decor =
            [[UDDecoration alloc] initWithIdentifier:identifier
                                         startOffset:startOffset
                                           endOffset:endOffset
                                             options:delta.options
                                               owner:owner];
        self.decorations[identifier] = decor;
        [newIDs addObject:identifier];
    }
    return [newIDs copy];
}

- (NSArray<NSString *> *)deltaDecorations:(nullable NSArray<NSString *> *)oldDecorations
                           newDecorations:(NSArray<UDModelDeltaDecoration *> *)newDecorations {
    return [self deltaDecorations:oldDecorations
                   newDecorations:newDecorations
                            owner:nil];
}

- (NSArray<NSString *> *)decorationsForOwner:(nullable NSString *)owner {
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    for (UDDecoration *d in self.decorations.allValues) {
        BOOL sameOwner = (owner == nil && d.owner == nil)
                      || [owner isEqualToString:d.owner];
        if (sameOwner) {
            [result addObject:d.identifier];
        }
    }
    return [result copy];
}

- (UDRange)rangeForDecoration:(NSString *)decorationID {
    UDDecoration *decor = self.decorations[decorationID];
    // Return an all-zero sentinel (all fields 0) for an unknown ID.
    // Valid ranges always use 1-based line/column, so 0 is unambiguous.
    if (!decor) { return PTRangeMake(0, 0, 0, 0); }
    UDPosition startPos = [self.pieceTree getPositionAt:decor.startOffset];
    UDPosition endPos   = [self.pieceTree getPositionAt:decor.endOffset];
    return PTRangeMake(startPos.line, startPos.column, endPos.line, endPos.column);
}

- (nullable UDDecorationOptions *)optionsForDecoration:(NSString *)decorationID {
    return self.decorations[decorationID].options;
}

// MARK: - Search

- (NSArray<UDFindMatch *> *)findMatches:(NSString *)searchString
                                isRegex:(BOOL)isRegex
                              matchCase:(BOOL)matchCase
                         wordSeparators:(nullable NSString *)wordSeparators
                       limitResultCount:(NSInteger)limitResultCount {
    UDSearchParams *params =
        [[UDSearchParams alloc] initWithSearchString:searchString
                                             isRegex:isRegex
                                           matchCase:matchCase
                                      wordSeparators:wordSeparators];
    UDSearchData *data = [params parseSearchRequest];
    if (!data) {
        NSLog(@"UDTextModel: -findMatches: invalid or empty search string '%@'", searchString);
        return @[];
    }

    NSInteger lineCount  = [self.pieceTree getLineCount];
    NSInteger lastLineLen = [self.pieceTree getLineLength:lineCount];
    UDRange fullRange = PTRangeMake(1, 1, lineCount, lastLineLen + 1);

    return [self.pieceTree findMatchesLineByLine:fullRange
                                     searchData:data
                                 captureMatches:NO
                               limitResultCount:limitResultCount];
}

@end
