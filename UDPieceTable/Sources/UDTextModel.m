/*---------------------------------------------------------------------------------------------
 *  Portions Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See LICENSE.txt for license information.
 *
 *  Objective-C port of VS Code's textModel.ts (minimal subset)
 *  Original source: https://github.com/microsoft/vscode/blob/main/src/vs/editor/common/model/textModel.ts
 *--------------------------------------------------------------------------------------------*/

#import "UDTextModel.h"
#import "UDIntervalTree.h"
#import "UDPieceTree.h"
#import "UDStringBuffer.h"

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
        _range      = range;
        _options    = options;
        _stickiness = UDTrackedRangeNeverGrowsWhenTypingAtEdges;
    }
    return self;
}
@end

// MARK: - Notification names

NSNotificationName const UDTextModelDidChangeNotification = @"UDTextModelDidChangeNotification";
NSNotificationName const UDTextModelDecorationsDidChangeNotification = @"UDTextModelDecorationsDidChangeNotification";

// MARK: - Helpers

/// Auto-detect the EOL sequence from the first line ending found in text.
/// Falls back to @"\n" if none is found.
static NSString *DetectEOL(NSString *text) {
    NSInteger len = (NSInteger)text.length;
    for (NSInteger i = 0; i < len; i++) {
        unichar c = [text characterAtIndex:(NSUInteger)i];
        if (c == '\r') {
            if (i + 1 < len && [text characterAtIndex:(NSUInteger)(i + 1)] == '\n') {
                return @"\r\n";
            }
            return @"\r";
        } else if (c == '\n') {
            return @"\n";
        }
    }
    return @"\n";
}

/// Build a UDPieceTree from an arbitrary text string, auto-detecting the EOL.
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
    NSString *eol = DetectEOL(text);
    UDStringBuffer *buf = [[UDStringBuffer alloc] initWithBuffer:text lineStarts:lineStarts];
    NSArray<UDStringBuffer *> *chunks = (text.length > 0) ? @[buf] : @[];
    return [[UDPieceTree alloc] initWithChunks:chunks eol:eol eolNormalized:YES];
}

/// Build a UDSearchData (or nil on invalid input) from search parameters.
static UDSearchData * _Nullable BuildSearchData(NSString *searchString,
                                                BOOL isRegex,
                                                BOOL matchCase,
                                                NSString * _Nullable wordSeparators) {
    UDSearchParams *params =
        [[UDSearchParams alloc] initWithSearchString:searchString
                                             isRegex:isRegex
                                           matchCase:matchCase
                                      wordSeparators:wordSeparators];
    return [params parseSearchRequest];
}

// MARK: - UDTextModel private interface

@interface UDTextModel ()
@property (nonatomic, strong) UDPieceTree    *pieceTree;
@property (nonatomic, strong) UDIntervalTree *decorationTree;
@end

// MARK: - UDTextModel implementation

@implementation UDTextModel

- (instancetype)initWithText:(NSString *)text {
    self = [super init];
    if (self) {
        _pieceTree      = CreatePieceTreeFromText(text);
        _undoManager    = [[NSUndoManager alloc] init];
        _decorationTree = [[UDIntervalTree alloc] init];
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

- (unichar)getCharacterAtOffset:(NSUInteger)offset {
    return (unichar)[self.pieceTree getCharCode:(NSInteger)offset];
}

- (NSString *)getNearestChunkAtOffset:(NSUInteger)offset {
    return [self.pieceTree getNearestChunk:(NSInteger)offset];
}

- (void)fillCharacters:(unichar *)buffer range:(NSRange)aRange {
    [self.pieceTree fillCharacters:buffer range:aRange];
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

// MARK: - EOL

- (NSString *)getEOL {
    return [self.pieceTree getEOL];
}

- (void)setEOL:(NSString *)eol {
    [self.pieceTree setEOL:eol];
}

// MARK: - Internal editing

/// Core editing implementation shared by -applyEdits: and the undo/redo handler.
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

        NSString *originalText = [self getValueInRange:edit.range];

        if (deleteLen > 0) {
            [self.pieceTree deleteAtOffset:startOffset count:deleteLen];
        }
        if (insertedLen > 0) {
            [self.pieceTree insertAtOffset:startOffset
                                     value:edit.text
                             eolNormalized:NO];
        }

        // Shift previously accumulated undo offsets (they are in the evolving document).
        NSUInteger prevCount = undoStartOffsets.count;
        for (NSUInteger k = 0; k < prevCount; k++) {
            NSInteger s = undoStartOffsets[k].integerValue;
            NSInteger e = undoEndOffsets[k].integerValue;
            NSInteger newS = s, newE = e;
            if (s >= startOffset + deleteLen) {
                newS = s - deleteLen + insertedLen;
            } else if (s >= startOffset) {
                newS = startOffset + insertedLen;
            }
            if (e >= startOffset + deleteLen) {
                newE = e - deleteLen + insertedLen;
            } else if (e >= startOffset) {
                newE = startOffset + insertedLen;
            }
            undoStartOffsets[k] = @(newS);
            undoEndOffsets[k]   = @(newE);
        }

        [undoStartOffsets addObject:@(startOffset)];
        [undoEndOffsets   addObject:@(startOffset + insertedLen)];
        [undoTexts        addObject:originalText];

        // Adjust all decoration ranges through this edit via the interval tree.
        [self.decorationTree acceptEdit:startOffset
                            deleteCount:deleteLen
                            insertCount:insertedLen
                       forceMoveMarkers:NO];
    }

    // Build undo edits from the final-state offsets.
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
    // Track the union of all affected character offset ranges for the notification.
    NSInteger dirtyStart = NSIntegerMax;
    NSInteger dirtyEnd   = NSIntegerMin;

    // Remove old decorations that belong to this owner; collect their ranges.
    for (NSString *oldID in oldDecorations) {
        UDIntervalNode *existing = [self.decorationTree nodeWithIdentifier:oldID];
        if (!existing) { continue; }
        BOOL sameOwner = (owner == nil && existing.owner == nil)
                      || [owner isEqualToString:existing.owner];
        if (sameOwner) {
            dirtyStart = MIN(dirtyStart, existing.start);
            dirtyEnd   = MAX(dirtyEnd,   existing.end);
            [self.decorationTree remove:existing];
        }
    }

    // Add new decorations; collect their ranges.
    NSMutableArray<NSString *> *newIDs =
        [NSMutableArray arrayWithCapacity:newDecorations.count];
    for (UDModelDeltaDecoration *delta in newDecorations) {
        NSString *identifier = [[NSUUID UUID] UUIDString];
        NSInteger startOffset = [self getOffsetAt:delta.range.startLineNumber
                                           column:delta.range.startColumn];
        NSInteger endOffset   = [self getOffsetAt:delta.range.endLineNumber
                                           column:delta.range.endColumn];
        dirtyStart = MIN(dirtyStart, startOffset);
        dirtyEnd   = MAX(dirtyEnd,   endOffset);
        UDIntervalNode *node =
            [[UDIntervalNode alloc] initWithIdentifier:identifier
                                                 start:startOffset
                                                   end:endOffset
                                               options:delta.options
                                                 owner:owner
                                            stickiness:delta.stickiness];
        [self.decorationTree insert:node];
        [newIDs addObject:identifier];
    }

    // Post notification for the union of changed decoration ranges.
    if (dirtyStart < dirtyEnd) {
        NSRange dirty = NSMakeRange((NSUInteger)MAX(0LL, dirtyStart),
                                    (NSUInteger)(dirtyEnd - MAX(0LL, dirtyStart)));
        [[NSNotificationCenter defaultCenter]
            postNotificationName:UDTextModelDecorationsDidChangeNotification
                          object:self
                        userInfo:@{@"range": [NSValue valueWithRange:dirty]}];
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
    for (UDIntervalNode *n in [self.decorationTree allNodes]) {
        BOOL sameOwner = (owner == nil && n.owner == nil)
                      || [owner isEqualToString:n.owner];
        if (sameOwner) {
            [result addObject:n.identifier];
        }
    }
    return [result copy];
}

- (NSArray<NSString *> *)decorationsInRange:(UDRange)range {
    NSInteger startOffset = [self getOffsetAt:range.startLineNumber column:range.startColumn];
    NSInteger endOffset   = [self getOffsetAt:range.endLineNumber   column:range.endColumn];
    NSArray<UDIntervalNode *> *nodes =
        [self.decorationTree nodesInRange:startOffset end:endOffset];
    NSMutableArray<NSString *> *ids = [NSMutableArray arrayWithCapacity:nodes.count];
    for (UDIntervalNode *n in nodes) {
        [ids addObject:n.identifier];
    }
    return [ids copy];
}

- (UDRange)rangeForDecoration:(NSString *)decorationID {
    UDIntervalNode *node = [self.decorationTree nodeWithIdentifier:decorationID];
    if (!node) { return PTRangeMake(0, 0, 0, 0); }
    UDPosition startPos = [self.pieceTree getPositionAt:node.start];
    UDPosition endPos   = [self.pieceTree getPositionAt:node.end];
    return PTRangeMake(startPos.line, startPos.column, endPos.line, endPos.column);
}

- (nullable UDDecorationOptions *)optionsForDecoration:(NSString *)decorationID {
    return [self.decorationTree nodeWithIdentifier:decorationID].options;
}

- (NSArray<UDIntervalNode *> *)decorationNodesInOffsetRange:(NSInteger)start end:(NSInteger)end {
    return [self.decorationTree nodesInRange:start end:end];
}

// MARK: - Search

- (NSArray<UDFindMatch *> *)findMatches:(NSString *)searchString
                                isRegex:(BOOL)isRegex
                              matchCase:(BOOL)matchCase
                         wordSeparators:(nullable NSString *)wordSeparators
                       limitResultCount:(NSInteger)limitResultCount {
    UDSearchData *data = BuildSearchData(searchString, isRegex, matchCase, wordSeparators);
    if (!data) {
        NSLog(@"UDTextModel: -findMatches: invalid or empty search string '%@'", searchString);
        return @[];
    }

    NSInteger lineCount   = [self.pieceTree getLineCount];
    NSInteger lastLineLen = [self.pieceTree getLineLength:lineCount];
    UDRange fullRange = PTRangeMake(1, 1, lineCount, lastLineLen + 1);

    return [self.pieceTree findMatchesLineByLine:fullRange
                                     searchData:data
                                 captureMatches:NO
                               limitResultCount:limitResultCount];
}

- (nullable UDFindMatch *)findNextMatch:(NSString *)searchString
                                isRegex:(BOOL)isRegex
                              matchCase:(BOOL)matchCase
                         wordSeparators:(nullable NSString *)wordSeparators
                                   from:(UDPosition)startPosition {
    UDSearchData *data = BuildSearchData(searchString, isRegex, matchCase, wordSeparators);
    if (!data) { return nil; }

    NSInteger lineCount   = [self.pieceTree getLineCount];
    NSInteger lastLineLen = [self.pieceTree getLineLength:lineCount];

    // Search from startPosition to end of document.
    UDRange forwardRange = PTRangeMake(startPosition.line, startPosition.column,
                                      lineCount, lastLineLen + 1);
    NSArray<UDFindMatch *> *forward =
        [self.pieceTree findMatchesLineByLine:forwardRange
                                   searchData:data
                               captureMatches:NO
                             limitResultCount:1];
    if (forward.count > 0) { return forward[0]; }

    // Wrap around: search from beginning to startPosition.
    UDRange wrapRange = PTRangeMake(1, 1,
                                    startPosition.line, startPosition.column);
    NSArray<UDFindMatch *> *wrap =
        [self.pieceTree findMatchesLineByLine:wrapRange
                                   searchData:data
                               captureMatches:NO
                             limitResultCount:1];
    return wrap.firstObject;
}

- (nullable UDFindMatch *)findPreviousMatch:(NSString *)searchString
                                    isRegex:(BOOL)isRegex
                                  matchCase:(BOOL)matchCase
                             wordSeparators:(nullable NSString *)wordSeparators
                                       from:(UDPosition)startPosition {
    UDSearchData *data = BuildSearchData(searchString, isRegex, matchCase, wordSeparators);
    if (!data) { return nil; }

    NSInteger lineCount   = [self.pieceTree getLineCount];
    NSInteger lastLineLen = [self.pieceTree getLineLength:lineCount];

    // Search from start of document to startPosition; return the last match.
    UDRange beforeRange = PTRangeMake(1, 1,
                                      startPosition.line, startPosition.column);
    NSArray<UDFindMatch *> *before =
        [self.pieceTree findMatchesLineByLine:beforeRange
                                   searchData:data
                               captureMatches:NO
                             limitResultCount:1000000];
    if (before.count > 0) { return before.lastObject; }

    // Wrap around: search from startPosition to end of document; return the last match.
    UDRange afterRange = PTRangeMake(startPosition.line, startPosition.column,
                                     lineCount, lastLineLen + 1);
    NSArray<UDFindMatch *> *after =
        [self.pieceTree findMatchesLineByLine:afterRange
                                   searchData:data
                               captureMatches:NO
                             limitResultCount:1000000];
    return after.lastObject;
}

@end
