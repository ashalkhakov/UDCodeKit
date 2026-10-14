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


// MARK: - Undo offsets
//
// One applyEdits call records, for each edit, where its replacement text ends
// up in the final document. Every later edit moves those positions by the
// same order-preserving rule — before the edit: unchanged; inside what it
// deleted: to the end of its inserted text; after it: shifted by the length
// change — so they live in a treap ordered by value, where the rule is one
// lazy "assign" on a contiguous run and one lazy "add" on a suffix: O(log E)
// per edit instead of a pass over all E positions.

typedef struct {
    NSInteger value;
    NSInteger tagAdd;            // pending for the children: add…
    NSInteger tagAssign;         // …after setting every value to this, if hasAssign
    BOOL      hasAssign;
    uint32_t  priority;
    NSInteger left, right;       // indices, -1 for none
} UDOffsetNode;

typedef struct {
    UDOffsetNode *nodes;
    NSInteger count, capacity, root;
    uint32_t random;
} UDOffsetSet;

static void UDOffsetApply(UDOffsetSet *set, NSInteger i, BOOL hasAssign, NSInteger assign, NSInteger add) {
    if (i < 0) return;
    UDOffsetNode *n = &set->nodes[i];
    if (hasAssign) {
        n->value = assign;
        n->hasAssign = YES;
        n->tagAssign = assign;
        n->tagAdd = 0;
    }
    n->value += add;
    if (n->hasAssign) n->tagAssign += add; else n->tagAdd += add;
}

static void UDOffsetPush(UDOffsetSet *set, NSInteger i) {
    UDOffsetNode *n = &set->nodes[i];
    if (!n->hasAssign && n->tagAdd == 0) return;
    // With hasAssign the children are set to tagAssign (which already
    // includes any later adds); otherwise they get tagAdd.
    UDOffsetApply(set, n->left, n->hasAssign, n->tagAssign, n->hasAssign ? 0 : n->tagAdd);
    UDOffsetApply(set, n->right, n->hasAssign, n->tagAssign, n->hasAssign ? 0 : n->tagAdd);
    n->hasAssign = NO;
    n->tagAdd = 0;
}

/// Splits into values < limit and values >= limit.
static void UDOffsetSplit(UDOffsetSet *set, NSInteger t, NSInteger limit, NSInteger *outLeft, NSInteger *outRight) {
    if (t < 0) { *outLeft = -1; *outRight = -1; return; }
    UDOffsetPush(set, t);
    if (set->nodes[t].value < limit) {
        UDOffsetSplit(set, set->nodes[t].right, limit, &set->nodes[t].right, outRight);
        *outLeft = t;
    } else {
        UDOffsetSplit(set, set->nodes[t].left, limit, outLeft, &set->nodes[t].left);
        *outRight = t;
    }
}

static NSInteger UDOffsetMerge(UDOffsetSet *set, NSInteger a, NSInteger b) {
    if (a < 0) return b;
    if (b < 0) return a;
    if (set->nodes[a].priority > set->nodes[b].priority) {
        UDOffsetPush(set, a);
        set->nodes[a].right = UDOffsetMerge(set, set->nodes[a].right, b);
        return a;
    }
    UDOffsetPush(set, b);
    set->nodes[b].left = UDOffsetMerge(set, a, set->nodes[b].left);
    return b;
}

/// Adds a position; returns its index (the order of addition).
static NSInteger UDOffsetAdd(UDOffsetSet *set, NSInteger value) {
    if (set->count == set->capacity) {
        set->capacity = set->capacity ? set->capacity * 2 : 16;
        set->nodes = realloc(set->nodes, (size_t)set->capacity * sizeof(UDOffsetNode));
    }
    NSInteger i = set->count++;
    set->random ^= set->random << 13; set->random ^= set->random >> 17; set->random ^= set->random << 5;
    set->nodes[i] = (UDOffsetNode){ value, 0, 0, NO, set->random, -1, -1 };
    NSInteger left, right;
    UDOffsetSplit(set, set->root, value, &left, &right);
    set->root = UDOffsetMerge(set, UDOffsetMerge(set, left, i), right);
    return i;
}

/// Moves every position through the replacement of [start, start + deleted)
/// with `inserted` characters.
static void UDOffsetAcceptEdit(UDOffsetSet *set, NSInteger start, NSInteger deleted, NSInteger inserted) {
    NSInteger before, rest, inside, after;
    UDOffsetSplit(set, set->root, start, &before, &rest);
    UDOffsetSplit(set, rest, start + deleted, &inside, &after);
    UDOffsetApply(set, inside, YES, start + inserted, 0);
    UDOffsetApply(set, after, NO, 0, inserted - deleted);
    set->root = UDOffsetMerge(set, UDOffsetMerge(set, before, inside), after);
}

/// Pushes every pending change down, so each node's value is final.
static void UDOffsetSettle(UDOffsetSet *set, NSInteger t) {
    while (t >= 0) {
        UDOffsetPush(set, t);
        UDOffsetSettle(set, set->nodes[t].left);
        t = set->nodes[t].right;
    }
}

// MARK: - UDTextModel implementation

@implementation UDTextModel {
    NSUInteger _lastDecorationID;   // decoration ids are "1", "2", … per model
}

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

- (NSInteger)getLineLength:(NSInteger)lineNumber {
    if (lineNumber < 1 || lineNumber > [self getLineCount]) {
        //throw new BugIndicatingError('Illegal value for lineNumber');
        return 0;
    }

    return [self.pieceTree getLineLength:lineNumber];
}

- (NSInteger)getLineMaxColumn:(NSInteger)lineNumber {
    if (lineNumber < 1 || lineNumber > [self getLineCount]) {
        //throw new BugIndicatingError('Illegal value for lineNumber');
        return 0;
    }
    return [self.pieceTree getLineLength:lineNumber] + 1;
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
            // Same end: the later start first, so an insertion at the end of
            // a replaced range goes after the replacement.
            if (a.range.startLineNumber != b.range.startLineNumber) {
                return (a.range.startLineNumber > b.range.startLineNumber)
                       ? NSOrderedAscending : NSOrderedDescending;
            }
            if (a.range.startColumn != b.range.startColumn) {
                return (a.range.startColumn > b.range.startColumn)
                       ? NSOrderedAscending : NSOrderedDescending;
            }
            return NSOrderedSame;
        }];

    // As in VS Code, edits in one call must not overlap (touching is fine):
    // their ranges all refer to the document before the call.
    for (NSUInteger i = 1; i < sorted.count; i++) {
        UDRange later = sorted[i - 1].range, earlier = sorted[i].range;
        BOOL overlaps = earlier.endLineNumber > later.startLineNumber ||
                        (earlier.endLineNumber == later.startLineNumber && earlier.endColumn > later.startColumn);
        if (overlaps) {
            [NSException raise:NSInvalidArgumentException format:@"Overlapping ranges are not allowed!"];
        }
    }

    // Where each edit's replacement ends up: start and end positions, moved
    // by every later edit (see UDOffsetSet).
    UDOffsetSet undoOffsets = { NULL, 0, 0, -1, 0x9E3779B9u };
    NSMutableArray<NSNumber *> *undoStartIndices =
        [NSMutableArray arrayWithCapacity:sorted.count];
    NSMutableArray<NSNumber *> *undoEndIndices =
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

        // Move the undo positions recorded so far (they are in the evolving document).
        UDOffsetAcceptEdit(&undoOffsets, startOffset, deleteLen, insertedLen);

        [undoStartIndices addObject:@(UDOffsetAdd(&undoOffsets, startOffset))];
        [undoEndIndices   addObject:@(UDOffsetAdd(&undoOffsets, startOffset + insertedLen))];
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
    UDOffsetSettle(&undoOffsets, undoOffsets.root);
    for (NSUInteger k = 0; k < undoTexts.count; k++) {
        NSInteger s = undoOffsets.nodes[undoStartIndices[k].integerValue].value;
        NSInteger e = undoOffsets.nodes[undoEndIndices[k].integerValue].value;
        UDPosition startPos = [self.pieceTree getPositionAt:s];
        UDPosition endPos   = (e > s) ? [self.pieceTree getPositionAt:e] : startPos;
        UDRange range = PTRangeMake(startPos.line, startPos.column,
                                    endPos.line,   endPos.column);
        [undoEdits addObject:[[UDTextModelEdit alloc] initWithRange:range
                                                               text:undoTexts[k]]];
    }

    free(undoOffsets.nodes);

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
        // Digits only: Apple's NSString hash clusters keys like "d1"…"d80000"
        // so badly that removing them from a dictionary goes linear.
        NSString *identifier = [NSString stringWithFormat:@"%lu", (unsigned long)++_lastDecorationID];
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
    NSArray<UDIntervalNode *> *nodes = [self.decorationTree nodesForOwner:owner];
    NSMutableArray<NSString *> *result = [NSMutableArray arrayWithCapacity:nodes.count];
    for (UDIntervalNode *n in nodes) {
        [result addObject:n.identifier];
    }
    return result;
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
