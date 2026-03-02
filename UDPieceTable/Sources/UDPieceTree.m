/*---------------------------------------------------------------------------------------------
 *  Portions Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See LICENSE.txt for license information.
 *
 *  Objective-C port of VS Code's pieceTreeBase.ts
 *  Original source: https://github.com/microsoft/vscode/blob/main/src/vs/editor/common/model/pieceTreeTextBuffer/pieceTreeBase.ts
 *--------------------------------------------------------------------------------------------*/

#import "UDPieceTree+Internal.h"
#import "UDTextModelSearch.h"

static const NSInteger AverageBufferSize = 65535;

UDPieceTreeNode *Leftest(UDPieceTreeNode *node);
UDPieceTreeNode *Rightest(UDPieceTreeNode *node);

// MARK: - Sentinel

static UDPieceTreeNode *_sentinel = nil;

UDPieceTreeNode *Sentinel(void) {
    if (!_sentinel) {
        _sentinel = [[UDPieceTreeNode alloc] initWithPiece:nil color:PTNodeColorBlack];
        _sentinel.parent = _sentinel;
        _sentinel.left   = _sentinel;
        _sentinel.right  = _sentinel;
        _sentinel.color  = PTNodeColorBlack;
    }
    return _sentinel;
}

static void ResetSentinel(void) {
    UDPieceTreeNode *s = Sentinel();
    s.parent = s;
}

// MARK: - Utility: line starts

static NSMutableArray<NSNumber *> *CreateLineStartsFast(NSString *str) {
    NSMutableArray<NSNumber *> *r = [NSMutableArray arrayWithObject:@0];
    NSInteger len = (NSInteger)str.length;
    for (NSInteger i = 0; i < len; i++) {
        unichar c = [str characterAtIndex:(NSUInteger)i];
        if (c == '\r') {
            if (i + 1 < len && [str characterAtIndex:(NSUInteger)(i + 1)] == '\n') {
                [r addObject:@(i + 2)];
                i++; // skip \n
            } else {
                [r addObject:@(i + 1)];
            }
        } else if (c == '\n') {
            [r addObject:@(i + 1)];
        }
    }
    return r;
}

// MARK: - PTPiece

@implementation UDPiece

- (instancetype)initWithBufferIndex:(NSInteger)bufferIndex
                              start:(UDBufferCursor)start
                                end:(UDBufferCursor)end
                        lineFeedCnt:(NSInteger)lineFeedCnt
                             length:(NSInteger)length {
    self = [super init];
    if (self) {
        _bufferIndex = bufferIndex;
        _start = start;
        _end = end;
        _lineFeedCnt = lineFeedCnt;
        _length = length;
    }
    return self;
}

- (id)copyWithZone:(nullable NSZone *)zone {
    return [[UDPiece allocWithZone:zone] initWithBufferIndex:_bufferIndex
                                                       start:_start
                                                         end:_end
                                                 lineFeedCnt:_lineFeedCnt
                                                      length:_length];
}

@end

// MARK: - Tree helpers (free functions)

UDPieceTreeNode *Leftest(UDPieceTreeNode *node) {
    UDPieceTreeNode *s = Sentinel();
    while (node.left != s) { node = node.left; }
    return node;
}

UDPieceTreeNode *Rightest(UDPieceTreeNode *node) {
    UDPieceTreeNode *s = Sentinel();
    while (node.right != s) { node = node.right; }
    return node;
}

static NSInteger CalculateSize(UDPieceTreeNode *node) {
    UDPieceTreeNode *s = Sentinel();
    if (node == s) { return 0; }
    return node.sizeLeft + node.piece.length + CalculateSize(node.right);
}

static NSInteger CalculateLF(UDPieceTreeNode *node) {
    UDPieceTreeNode *s = Sentinel();
    if (node == s) { return 0; }
    return node.lfLeft + node.piece.lineFeedCnt + CalculateLF(node.right);
}

// Forward declarations for tree operations that need PTPieceTreeBase
@class UDPieceTree;
static void LeftRotate(UDPieceTree *tree, UDPieceTreeNode *x);
static void RightRotate(UDPieceTree *tree, UDPieceTreeNode *y);
static void UpdateTreeMetadata(UDPieceTree *tree, UDPieceTreeNode *x, NSInteger delta, NSInteger lfDelta);
static void RecomputeTreeMetadata(UDPieceTree *tree, UDPieceTreeNode *x);
static void FixInsert(UDPieceTree *tree, UDPieceTreeNode *x);
static void RBDelete(UDPieceTree *tree, UDPieceTreeNode *z);

// MARK: - PTPieceTreeBase private interface

@interface UDPieceTree ()

@property (nonatomic, strong) NSMutableArray<UDStringBuffer *> *buffers; // 0 = change buffer
@property (nonatomic) NSInteger lineCnt;
@property (nonatomic) NSInteger length;
@property (nonatomic, strong) NSString *eol;
@property (nonatomic) NSInteger eolLength;
@property (nonatomic) BOOL eolNormalized;
@property (nonatomic) UDBufferCursor lastChangeBufferPos;

// Simple 1-entry search cache
@property (nonatomic, strong, nullable) UDPieceTreeNode *cacheNode;
@property (nonatomic) NSInteger cacheNodeStartOffset;

@end

// MARK: - PTPieceTreeBase implementation

@implementation UDPieceTree

- (instancetype)initWithChunks:(NSArray<UDStringBuffer *> *)chunks
                           eol:(NSString *)eol
                 eolNormalized:(BOOL)eolNormalized {
    self = [super init];
    if (self) {
        [self createWithChunks:chunks eol:eol eolNormalized:eolNormalized];
    }
    return self;
}

- (void)createWithChunks:(NSArray<UDStringBuffer *> *)chunks
                     eol:(NSString *)eol
           eolNormalized:(BOOL)eolNormalized {
    UDStringBuffer *changeBuffer = [[UDStringBuffer alloc] initWithBuffer:@"" lineStarts:@[@0]];
    self.buffers = [NSMutableArray arrayWithObject:changeBuffer];
    self.lastChangeBufferPos = PTBufferCursorMake(0, 0);
    self.root = Sentinel();
    self.lineCnt = 1;
    self.length = 0;
    self.eol = eol;
    self.eolLength = (NSInteger)eol.length;
    self.eolNormalized = eolNormalized;
    self.cacheNode = nil;
    self.cacheNodeStartOffset = 0;

    UDPieceTreeNode *lastNode = nil;
    for (NSInteger i = 0; i < (NSInteger)chunks.count; i++) {
        UDStringBuffer *chunk = chunks[(NSUInteger)i];
        if (chunk.buffer.length == 0) { continue; }
        if (!chunk.lineStarts || chunk.lineStarts.count == 0) {
            chunk.lineStarts = CreateLineStartsFast(chunk.buffer);
        }
        NSInteger ls = (NSInteger)chunk.lineStarts.count;
        NSInteger bufLen = (NSInteger)chunk.buffer.length;
        NSInteger lastLineStart = chunk.lineStarts[(NSUInteger)(ls - 1)].integerValue;
        UDPiece *piece = [[UDPiece alloc] initWithBufferIndex:i + 1
                                                        start:PTBufferCursorMake(0, 0)
                                                          end:PTBufferCursorMake(ls - 1, bufLen - lastLineStart)
                                                  lineFeedCnt:ls - 1
                                                       length:bufLen];
        [self.buffers addObject:chunk];
        lastNode = [self rbInsertRight:lastNode piece:piece];
    }

    [self computeBufferMetadata];
}

// MARK: - EOL

- (NSString *)getEOL { return self.eol; }

- (void)setEOL:(NSString *)newEOL {
    self.eol = newEOL;
    self.eolLength = (NSInteger)newEOL.length;
    [self normalizeEOL:newEOL];
}

- (void)normalizeEOL:(NSString *)eol {
    NSInteger min = AverageBufferSize - AverageBufferSize / 3;
    NSInteger max = min * 2;

    NSMutableString *tempChunk = [NSMutableString string];
    __block NSInteger tempChunkLen = 0;
    NSMutableArray<UDStringBuffer *> *chunks = [NSMutableArray array];

    [self iterateFrom:self.root callback:^BOOL(UDPieceTreeNode *node) {
        if (node == Sentinel()) { return YES; }
        NSString *str = [self getNodeContent:node];
        NSInteger len = (NSInteger)str.length;
        if (tempChunkLen <= min || tempChunkLen + len < max) {
            [tempChunk appendString:str];
            tempChunkLen += len;
            return YES;
        }
        NSString *text = [tempChunk stringByReplacingOccurrencesOfString:@"\r\n" withString:eol];
        text = [text stringByReplacingOccurrencesOfString:@"\r" withString:eol];
        text = [text stringByReplacingOccurrencesOfString:@"\n" withString:eol];
        [chunks addObject:[[UDStringBuffer alloc] initWithBuffer:text lineStarts:CreateLineStartsFast(text)]];
        [tempChunk setString:str];
        tempChunkLen = len;
        return YES;
    }];

    if (tempChunkLen > 0) {
        NSString *text = [tempChunk stringByReplacingOccurrencesOfString:@"\r\n" withString:eol];
        text = [text stringByReplacingOccurrencesOfString:@"\r" withString:eol];
        text = [text stringByReplacingOccurrencesOfString:@"\n" withString:eol];
        [chunks addObject:[[UDStringBuffer alloc] initWithBuffer:text lineStarts:CreateLineStartsFast(text)]];
    }
    [self createWithChunks:chunks eol:eol eolNormalized:YES];
}

// MARK: - Buffer metadata

- (NSInteger)getLength { return self.length; }
- (NSInteger)getLineCount { return self.lineCnt; }

- (void)computeBufferMetadata {
    UDPieceTreeNode *x = self.root;
    UDPieceTreeNode *s = Sentinel();
    NSInteger lfCnt = 1, len = 0;
    while (x != s) {
        lfCnt += x.lfLeft + x.piece.lineFeedCnt;
        len += x.sizeLeft + x.piece.length;
        x = x.right;
    }
    self.lineCnt = lfCnt;
    self.length = len;
    // invalidate cache if beyond length
    if (self.cacheNode && self.cacheNodeStartOffset >= self.length) {
        self.cacheNode = nil;
    }
}

// MARK: - Offset / Position

- (NSInteger)getOffsetAtLine:(NSInteger)lineNumber column:(NSInteger)column {
    NSInteger leftLen = 0;
    UDPieceTreeNode *x = self.root;
    UDPieceTreeNode *s = Sentinel();
    while (x != s) {
        if (x.left != s && x.lfLeft + 1 >= lineNumber) {
            x = x.left;
        } else if (x.lfLeft + x.piece.lineFeedCnt + 1 >= lineNumber) {
            leftLen += x.sizeLeft;
            NSInteger accVal = [self getAccumulatedValue:x index:lineNumber - x.lfLeft - 2];
            return leftLen + accVal + column - 1;
        } else {
            lineNumber -= x.lfLeft + x.piece.lineFeedCnt;
            leftLen += x.sizeLeft + x.piece.length;
            x = x.right;
        }
    }
    return leftLen;
}

- (NSInteger)getLineLength:(NSInteger)lineNumber {
    if (lineNumber == [self getLineCount]) {
        NSInteger startOffset = [self getOffsetAtLine:lineNumber column:1];
        return [self getLength] - startOffset;
    }
    return [self getOffsetAtLine:lineNumber + 1 column:1] - [self getOffsetAtLine:lineNumber column:1] - self.eolLength;
}

// ---------------------------------------------------------------------------
// MARK: - Private helpers (inlined from TS private methods)
// ---------------------------------------------------------------------------

// Equivalent of TS offsetInBuffer(bufferIndex, cursor)
static NSInteger PTOffsetInBuffer(NSArray<NSNumber *> *lineStarts,
                                   NSInteger line, NSInteger column) {
    return lineStarts[(NSUInteger)line].integerValue + column;
}

// Equivalent of TS positionInBuffer(node, remainder) -> {line, column}
// Returns the buffer-relative {line, column} for `remainder` chars into node.
static void PTPositionInBuffer(UDPieceTreeNode *node,
                                NSInteger remainder,
                                NSArray<NSArray<NSNumber *> *> *bufferLineStarts,
                                NSInteger *outLine,
                                NSInteger *outColumn) {
    UDPiece *piece = node.piece;
    NSArray<NSNumber *> *lineStarts = bufferLineStarts[(NSUInteger)piece.bufferIndex];

    NSInteger startOffset = lineStarts[(NSUInteger)piece.start.line].integerValue
                          + piece.start.column;
    NSInteger offset = startOffset + remainder;

    NSInteger low  = piece.start.line;
    NSInteger high = piece.end.line;
    NSInteger mid = 0, midStart = 0, midStop = 0;

    while (low <= high) {
        mid = low + (high - low) / 2;
        midStart = lineStarts[(NSUInteger)mid].integerValue;
        if (mid == high) { break; }
        midStop = lineStarts[(NSUInteger)(mid + 1)].integerValue;
        if (offset < midStart)       { high = mid - 1; }
        else if (offset >= midStop)  { low  = mid + 1; }
        else                         { break; }
    }

    *outLine   = mid;
    *outColumn = offset - midStart;
}

// Equivalent of TS getLineFeedCnt(bufferIndex, start, end)
static NSInteger PTGetLineFeedCnt(NSInteger bufferIndex,
                                   NSInteger startLine,
                                   NSInteger endLine, NSInteger endColumn,
                                   NSArray<NSArray<NSNumber *> *> *bufferLineStarts,
                                   NSArray<NSString *> *buffers) {
    if (endColumn == 0) {
        return endLine - startLine;
    }
    NSArray<NSNumber *> *lineStarts = bufferLineStarts[(NSUInteger)bufferIndex];
    if (endLine == (NSInteger)lineStarts.count - 1) {
        return endLine - startLine;
    }
    NSInteger nextLineStartOffset = lineStarts[(NSUInteger)(endLine + 1)].integerValue;
    NSInteger endOffset           = lineStarts[(NSUInteger)endLine].integerValue + endColumn;
    if (nextLineStartOffset > endOffset + 1) {
        return endLine - startLine;
    }
    // character at endOffset - 1: check for \r
    NSString *buf = buffers[(NSUInteger)bufferIndex];
    NSInteger prevCharOffset = endOffset - 1;
    unichar prevChar = [buf characterAtIndex:(NSUInteger)prevCharOffset];
    if (prevChar == '\r') {
        return endLine - startLine + 1;
    }
    return endLine - startLine;
}

// Equivalent of TS getIndexOf(node, accumulatedValue) -> {index, remainder}
static void PTGetIndexOf(UDPieceTreeNode *node,
                          NSInteger accumulatedValue,
                          NSArray<NSArray<NSNumber *> *> *bufferLineStarts,
                          NSArray<NSString *> *buffers,
                          NSInteger *outIndex,
                          NSInteger *outRemainder) {
    UDPiece *piece = node.piece;

    NSInteger posLine = 0, posColumn = 0;
    PTPositionInBuffer(node, accumulatedValue, bufferLineStarts, &posLine, &posColumn);

    NSInteger lineCnt = posLine - piece.start.line;

    // CRLF check: if accumulatedValue == full piece length, verify lineFeedCnt
    NSArray<NSNumber *> *lineStarts = bufferLineStarts[(NSUInteger)piece.bufferIndex];
    NSInteger pieceEndOffset   = lineStarts[(NSUInteger)piece.end.line].integerValue + piece.end.column;
    NSInteger pieceStartOffset = lineStarts[(NSUInteger)piece.start.line].integerValue + piece.start.column;

    if (pieceEndOffset - pieceStartOffset == accumulatedValue) {
        NSInteger realLineCnt = PTGetLineFeedCnt(piece.bufferIndex,
                                                  piece.start.line,
                                                  posLine, posColumn,
                                                  bufferLineStarts, buffers);
        if (realLineCnt != lineCnt) {
            *outIndex     = realLineCnt;
            *outRemainder = 0;
            return;
        }
    }

    *outIndex     = lineCnt;
    *outRemainder = posColumn;
}

// ---------------------------------------------------------------------------
// MARK: - getPositionAt: (public)
// ---------------------------------------------------------------------------

- (UDPosition)getPositionAt:(NSInteger)offset {
    offset = MAX((NSInteger)0, offset);

    // Build the two arrays needed by the helpers:
    // bufferLineStarts[i] = NSArray<NSNumber*> of line-start offsets for buffer i
    // bufferStrings[i]    = the raw NSString for buffer i
    NSMutableArray<NSArray<NSNumber *> *> *bufferLineStarts = [NSMutableArray array];
    NSMutableArray<NSString *> *bufferStrings = [NSMutableArray array];
    for (UDStringBuffer *buf in self.buffers) {
        [bufferLineStarts addObject:buf.lineStarts];
        [bufferStrings    addObject:buf.buffer];
    }

    UDPieceTreeNode *x = self.root;
    NSInteger lfCnt = 0;
    NSInteger originalOffset = offset;

    while (x != Sentinel()) {
        if (x.sizeLeft != 0 && x.sizeLeft >= offset) {
            x = x.left;
        } else if (x.sizeLeft + x.piece.length >= offset) {
            NSInteger idxOut = 0, remOut = 0;
            PTGetIndexOf(x, offset - x.sizeLeft,
                         bufferLineStarts, bufferStrings,
                         &idxOut, &remOut);

            lfCnt += x.lfLeft + idxOut;

            if (idxOut == 0) {
                NSInteger lineStartOffset = [self getOffsetAtLine:lfCnt + 1 column:1];
                NSInteger col = originalOffset - lineStartOffset;
                return (UDPosition){ lfCnt + 1, col + 1 };
            }
            return (UDPosition){ lfCnt + 1, remOut + 1 };
        } else {
            offset -= x.sizeLeft + x.piece.length;
            lfCnt  += x.lfLeft + x.piece.lineFeedCnt;

            if (x.right == Sentinel()) {
                NSInteger lineStartOffset = [self getOffsetAtLine:lfCnt + 1 column:1];
                NSInteger col = originalOffset - offset - lineStartOffset;
                return (UDPosition){ lfCnt + 1, col + 1 };
            }
            x = x.right;
        }
    }

    return (UDPosition){ 1, 1 };
}
// MARK: - Line content

- (NSString *)getLineContent:(NSInteger)lineNumber {
    if (lineNumber == self.lineCnt) {
        return [self getLineRawContent:lineNumber endOffset:0];
    } else if (self.eolNormalized) {
        return [self getLineRawContent:lineNumber endOffset:self.eolLength];
    } else {
        NSString *raw = [self getLineRawContent:lineNumber endOffset:0];
        // strip trailing EOL
        NSArray *patterns = @[@"\r\n", @"\r", @"\n"];
        for (NSString *pat in patterns) {
            if ([raw hasSuffix:pat]) {
                return [raw substringToIndex:raw.length - pat.length];
            }
        }
        return raw;
    }
}

- (NSString *)getLineRawContent:(NSInteger)lineNumber {
    return [self getLineRawContent:lineNumber endOffset:0];
}

- (NSString *)getLineRawContent:(NSInteger)lineNumber endOffset:(NSInteger)endOffset {
    UDPieceTreeNode *x = self.root;
    UDPieceTreeNode *s = Sentinel();
    NSMutableString *ret = [NSMutableString string];

    // No line-number cache; walk the tree
    NSInteger origLineNumber = lineNumber;
    (void)origLineNumber;
    while (x != s) {
        if (x.left != s && x.lfLeft >= lineNumber - 1) {
            x = x.left;
        } else if (x.lfLeft + x.piece.lineFeedCnt > lineNumber - 1) {
            NSInteger prevAcc = [self getAccumulatedValue:x index:lineNumber - x.lfLeft - 2];
            NSInteger acc     = [self getAccumulatedValue:x index:lineNumber - x.lfLeft - 1];
            NSString *buffer  = self.buffers[(NSUInteger)x.piece.bufferIndex].buffer;
            NSInteger startOff = [self offsetInBuffer:x.piece.bufferIndex cursor:x.piece.start];
            NSRange range = NSMakeRange((NSUInteger)(startOff + prevAcc),
                                        (NSUInteger)(acc - endOffset - prevAcc));
            return [buffer substringWithRange:range];
        } else if (x.lfLeft + x.piece.lineFeedCnt == lineNumber - 1) {
            NSInteger prevAcc = [self getAccumulatedValue:x index:lineNumber - x.lfLeft - 2];
            NSString *buffer  = self.buffers[(NSUInteger)x.piece.bufferIndex].buffer;
            NSInteger startOff = [self offsetInBuffer:x.piece.bufferIndex cursor:x.piece.start];
            NSInteger from = startOff + prevAcc;
            NSInteger to   = startOff + x.piece.length;
            [ret appendString:[buffer substringWithRange:NSMakeRange((NSUInteger)from, (NSUInteger)(to - from))]];
            break;
        } else {
            lineNumber -= x.lfLeft + x.piece.lineFeedCnt;
            x = x.right;
        }
    }

    // Continue in-order to find the end of this line
    x = [x next];
    while (x != s) {
        NSString *buffer = self.buffers[(NSUInteger)x.piece.bufferIndex].buffer;
        if (x.piece.lineFeedCnt > 0) {
            NSInteger acc = [self getAccumulatedValue:x index:0];
            NSInteger startOff = [self offsetInBuffer:x.piece.bufferIndex cursor:x.piece.start];
            NSRange range = NSMakeRange((NSUInteger)startOff, (NSUInteger)(acc - endOffset));
            [ret appendString:[buffer substringWithRange:range]];
            return [ret copy];
        } else {
            NSInteger startOff = [self offsetInBuffer:x.piece.bufferIndex cursor:x.piece.start];
            [ret appendString:[buffer substringWithRange:NSMakeRange((NSUInteger)startOff, (NSUInteger)x.piece.length)]];
        }
        x = [x next];
    }
    return [ret copy];
}

- (NSString *)getLinesRawContent {
    return [self getContentOfSubTree:self.root];
}

// MARK: - Value in range

- (NSString *)getValueInRange_startLine:(NSInteger)startLine startColumn:(NSInteger)startColumn
                                endLine:(NSInteger)endLine endColumn:(NSInteger)endColumn {
    if (startLine == endLine && startColumn == endColumn) { return @""; }
    PTNodePosition startPos = [self nodeAt2Line:startLine column:startColumn];
    PTNodePosition endPos   = [self nodeAt2Line:endLine   column:endColumn];
    return [self getValueInRange2:startPos end:endPos];
}

- (NSString *)getValueInRange2:(PTNodePosition)startPos end:(PTNodePosition)endPos {
    UDPieceTreeNode *s = Sentinel();
    if (startPos.node == endPos.node) {
        NSString *buffer  = self.buffers[(NSUInteger)startPos.node.piece.bufferIndex].buffer;
        NSInteger startOff = [self offsetInBuffer:startPos.node.piece.bufferIndex cursor:startPos.node.piece.start];
        NSInteger from = startOff + startPos.remainder;
        NSInteger to   = startOff + endPos.remainder;
        return [buffer substringWithRange:NSMakeRange((NSUInteger)from, (NSUInteger)(to - from))];
    }
    UDPieceTreeNode *x = startPos.node;
    NSString *buf  = self.buffers[(NSUInteger)x.piece.bufferIndex].buffer;
    NSInteger startOff = [self offsetInBuffer:x.piece.bufferIndex cursor:x.piece.start];
    NSInteger from = startOff + startPos.remainder;
    NSMutableString *ret = [NSMutableString stringWithString:
        [buf substringWithRange:NSMakeRange((NSUInteger)from, (NSUInteger)(startOff + x.piece.length - from))]];

    x = [x next];
    while (x != s) {
        NSString *buffer2 = self.buffers[(NSUInteger)x.piece.bufferIndex].buffer;
        NSInteger so = [self offsetInBuffer:x.piece.bufferIndex cursor:x.piece.start];
        if (x == endPos.node) {
            [ret appendString:[buffer2 substringWithRange:NSMakeRange((NSUInteger)so, (NSUInteger)endPos.remainder)]];
            break;
        } else {
            [ret appendString:[buffer2 substringWithRange:NSMakeRange((NSUInteger)so, (NSUInteger)x.piece.length)]];
        }
        x = [x next];
    }
    return [ret copy];
}

// MARK: - getLinesContent

- (NSArray<NSString *> *)getLinesContent {
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    NSMutableString *currentLine = [NSMutableString string];
    __block BOOL danglingCR = NO;

    [self iterateFrom:self.root callback:^BOOL(UDPieceTreeNode *node) {
        if (node == Sentinel()) { return YES; }

        UDPiece *piece = node.piece;
        NSInteger pieceLength = piece.length;
        if (pieceLength == 0) { return YES; }

        NSString *buffer   = self.buffers[(NSUInteger)piece.bufferIndex].buffer;
        NSArray<NSNumber *> *lineStarts = self.buffers[(NSUInteger)piece.bufferIndex].lineStarts;

        NSInteger pieceStartLine   = piece.start.line;
        NSInteger pieceEndLine     = piece.end.line;
        NSInteger pieceStartOffset = lineStarts[(NSUInteger)pieceStartLine].integerValue + piece.start.column;

        if (danglingCR) {
            if ([buffer characterAtIndex:(NSUInteger)pieceStartOffset] == '\n') {
                // '\n' belongs to the previous '\r', consume it
                pieceStartOffset++;
                pieceLength--;
            }
            [lines addObject:[currentLine copy]];
            [currentLine setString:@""];
            danglingCR = NO;
            if (pieceLength == 0) { return YES; }
        }

        if (pieceStartLine == pieceEndLine) {
            // No line breaks in this piece
            if (!self.eolNormalized &&
                [buffer characterAtIndex:(NSUInteger)(pieceStartOffset + pieceLength - 1)] == '\r') {
                danglingCR = YES;
                [currentLine appendString:[buffer substringWithRange:
                    NSMakeRange((NSUInteger)pieceStartOffset, (NSUInteger)(pieceLength - 1))]];
            } else {
                [currentLine appendString:[buffer substringWithRange:
                    NSMakeRange((NSUInteger)pieceStartOffset, (NSUInteger)pieceLength)]];
            }
            return YES;
        }

        // Text before first line break in this piece
        NSInteger firstLineEnd;
        if (self.eolNormalized) {
            NSInteger ls1 = lineStarts[(NSUInteger)(pieceStartLine + 1)].integerValue;
            firstLineEnd = MAX(pieceStartOffset, ls1 - self.eolLength);
        } else {
            NSInteger ls1 = lineStarts[(NSUInteger)(pieceStartLine + 1)].integerValue;
            NSString *sub = [buffer substringWithRange:
                NSMakeRange((NSUInteger)pieceStartOffset, (NSUInteger)(ls1 - pieceStartOffset))];
            // strip trailing EOL
            if ([sub hasSuffix:@"\r\n"]) sub = [sub substringToIndex:sub.length - 2];
            else if ([sub hasSuffix:@"\r"] || [sub hasSuffix:@"\n"]) sub = [sub substringToIndex:sub.length - 1];
            [currentLine appendString:sub];
            [lines addObject:[currentLine copy]];
            [currentLine setString:@""];

            for (NSInteger line = pieceStartLine + 1; line < pieceEndLine; line++) {
                NSInteger ls  = lineStarts[(NSUInteger)line].integerValue;
                NSInteger ls2 = lineStarts[(NSUInteger)(line + 1)].integerValue;
                NSString *lineSub = [buffer substringWithRange:
                    NSMakeRange((NSUInteger)ls, (NSUInteger)(ls2 - ls))];
                if ([lineSub hasSuffix:@"\r\n"]) lineSub = [lineSub substringToIndex:lineSub.length - 2];
                else if ([lineSub hasSuffix:@"\r"] || [lineSub hasSuffix:@"\n"]) lineSub = [lineSub substringToIndex:lineSub.length - 1];
                [lines addObject:lineSub];
            }

            NSInteger lastLineStart = lineStarts[(NSUInteger)pieceEndLine].integerValue;
            NSInteger lastLen = piece.end.column;
            if (!self.eolNormalized && lastLen > 0 &&
                [buffer characterAtIndex:(NSUInteger)(lastLineStart + lastLen - 1)] == '\r') {
                danglingCR = YES;
                [currentLine appendString:[buffer substringWithRange:
                    NSMakeRange((NSUInteger)lastLineStart, (NSUInteger)(lastLen - 1))]];
            } else {
                [currentLine appendString:[buffer substringWithRange:
                    NSMakeRange((NSUInteger)lastLineStart, (NSUInteger)lastLen)]];
            }
            return YES;
        }

        // eolNormalized == YES branch (no early return above)
        [currentLine appendString:[buffer substringWithRange:
            NSMakeRange((NSUInteger)pieceStartOffset, (NSUInteger)(firstLineEnd - pieceStartOffset))]];
        [lines addObject:[currentLine copy]];
        [currentLine setString:@""];

        for (NSInteger line = pieceStartLine + 1; line < pieceEndLine; line++) {
            NSInteger ls  = lineStarts[(NSUInteger)line].integerValue;
            NSInteger ls2 = lineStarts[(NSUInteger)(line + 1)].integerValue;
            [lines addObject:[buffer substringWithRange:
                NSMakeRange((NSUInteger)ls, (NSUInteger)(ls2 - self.eolLength - ls))]];
        }

        NSInteger lastLineStart = lineStarts[(NSUInteger)pieceEndLine].integerValue;
        [currentLine appendString:[buffer substringWithRange:
            NSMakeRange((NSUInteger)lastLineStart, (NSUInteger)piece.end.column)]];

        return YES;
    }];

    if (danglingCR) {
        [lines addObject:[currentLine copy]];
        [currentLine setString:@""];
    }
    [lines addObject:[currentLine copy]];
    return [lines copy];
}

// MARK: - _getCharCodeAtNodePos (private helper)

- (NSInteger)_getCharCodeAtNodePos:(PTNodePosition)nodePos {
    UDPieceTreeNode *s = Sentinel();
    if (nodePos.remainder == nodePos.node.piece.length) {
        // The character we want is at the head of the next node
        UDPieceTreeNode *matchingNode = [nodePos.node next];
        if (!matchingNode || matchingNode == s) { return 0; }
        NSString *buffer = self.buffers[(NSUInteger)matchingNode.piece.bufferIndex].buffer;
        NSInteger startOff = [self offsetInBuffer:matchingNode.piece.bufferIndex cursor:matchingNode.piece.start];
        return (NSInteger)[buffer characterAtIndex:(NSUInteger)startOff];
    } else {
        NSString *buffer = self.buffers[(NSUInteger)nodePos.node.piece.bufferIndex].buffer;
        NSInteger startOff = [self offsetInBuffer:nodePos.node.piece.bufferIndex cursor:nodePos.node.piece.start];
        return (NSInteger)[buffer characterAtIndex:(NSUInteger)(startOff + nodePos.remainder)];
    }
}

// MARK: - getLineCharCode:index:

- (NSInteger)getLineCharCode:(NSInteger)lineNumber index:(NSInteger)index {
    PTNodePosition nodePos = [self nodeAt2Line:lineNumber column:index + 1];
    return [self _getCharCodeAtNodePos:nodePos];
}

// MARK: - getCharCode:

- (NSInteger)getCharCode:(NSInteger)offset {
    PTNodePosition nodePos = [self nodeAtOffset:offset];
    return [self _getCharCodeAtNodePos:nodePos];
}

// MARK: - getNearestChunk:

- (NSString *)getNearestChunk:(NSInteger)offset {
    UDPieceTreeNode *s = Sentinel();
    PTNodePosition nodePos = [self nodeAtOffset:offset];
    if (nodePos.remainder == nodePos.node.piece.length) {
        // offset is at the head of the next node
        UDPieceTreeNode *matchingNode = [nodePos.node next];
        if (!matchingNode || matchingNode == s) { return @""; }
        NSString *buffer = self.buffers[(NSUInteger)matchingNode.piece.bufferIndex].buffer;
        NSInteger startOff = [self offsetInBuffer:matchingNode.piece.bufferIndex cursor:matchingNode.piece.start];
        return [buffer substringWithRange:NSMakeRange((NSUInteger)startOff, (NSUInteger)matchingNode.piece.length)];
    } else {
        NSString *buffer = self.buffers[(NSUInteger)nodePos.node.piece.bufferIndex].buffer;
        NSInteger startOff = [self offsetInBuffer:nodePos.node.piece.bufferIndex cursor:nodePos.node.piece.start];
        NSInteger targetOffset = startOff + nodePos.remainder;
        NSInteger targetEnd    = startOff + nodePos.node.piece.length;
        return [buffer substringWithRange:NSMakeRange((NSUInteger)targetOffset,
                                                      (NSUInteger)(targetEnd - targetOffset))];
    }
}

// MARK: - Equality

- (BOOL)isEqualTo:(UDPieceTree *)other {
    if ([self getLength] != [other getLength]) { return NO; }
    if ([self getLineCount] != [other getLineCount]) { return NO; }
    __block NSInteger offset = 0;
    __block BOOL equal = YES;
    [self iterateFrom:self.root callback:^BOOL(UDPieceTreeNode *node) {
        if (node == Sentinel()) { return YES; }
        NSString *str = [self getNodeContent:node];
        NSInteger len = (NSInteger)str.length;
        PTNodePosition sp = [other nodeAtOffset:offset];
        PTNodePosition ep = [other nodeAtOffset:offset + len];
        NSString *val = [other getValueInRange2:sp end:ep];
        offset += len;
        if (![str isEqualToString:val]) { equal = NO; return NO; }
        return YES;
    }];
    return equal;
}

// MARK: - Insert

- (void)insertAtOffset:(NSInteger)offset value:(NSString *)value eolNormalized:(BOOL)eolNormalized {
    self.eolNormalized = self.eolNormalized && eolNormalized;

    UDPieceTreeNode *s = Sentinel();
    if (self.root != s) {
        PTNodePosition pos = [self nodeAtOffset:offset];
        UDPieceTreeNode *node = pos.node;
        NSInteger remainder = pos.remainder;
        NSInteger nodeStartOffset = pos.nodeStartOffset;
        UDPiece *piece = node.piece;
        NSInteger bufferIndex = piece.bufferIndex;
        UDBufferCursor insertPosInBuffer = [self positionInBufferForNode:node remainder:remainder];

        if (node.piece.bufferIndex == 0 &&
            piece.end.line   == self.lastChangeBufferPos.line &&
            piece.end.column == self.lastChangeBufferPos.column &&
            (nodeStartOffset + piece.length == offset) &&
            (NSInteger)value.length < AverageBufferSize) {
            // Append to existing change buffer node
            [self appendToNode:node value:value];
            [self computeBufferMetadata];
            return;
        }

        if (nodeStartOffset == offset) {
            [self insertContentToNodeLeft:value node:node];
            [self validateCacheWithOffset:offset];
        } else if (nodeStartOffset + node.piece.length > offset) {
            // Inserting into the middle of a node
            NSMutableArray<UDPieceTreeNode *> *nodesToDel = [NSMutableArray array];
            NSInteger newRightLFCnt = [self getLineFeedCnt:piece.bufferIndex start:insertPosInBuffer end:piece.end];
            NSInteger newRightLen = [self offsetInBuffer:bufferIndex cursor:piece.end] -
                                    [self offsetInBuffer:bufferIndex cursor:insertPosInBuffer];
            UDPiece *newRightPiece = [[UDPiece alloc] initWithBufferIndex:piece.bufferIndex
                                                                    start:insertPosInBuffer
                                                                      end:piece.end
                                                              lineFeedCnt:newRightLFCnt
                                                                   length:newRightLen];

            if ([self shouldCheckCRLF] && [self endWithCR:value]) {
                unichar headOfRight = [self nodeCharCodeAt:node offset:remainder];
                if (headOfRight == '\n') {
                    UDBufferCursor newStart = PTBufferCursorMake(newRightPiece.start.line + 1, 0);
                    NSInteger lfc = [self getLineFeedCnt:newRightPiece.bufferIndex start:newStart end:newRightPiece.end];
                    NSInteger newLen = newRightPiece.length - 1;
                    newRightPiece = [[UDPiece alloc] initWithBufferIndex:newRightPiece.bufferIndex
                                                                   start:newStart
                                                                     end:newRightPiece.end
                                                             lineFeedCnt:lfc
                                                                  length:newLen];
                    value = [value stringByAppendingString:@"\n"];
                }
            }

            if ([self shouldCheckCRLF] && [self startWithLFString:value]) {
                unichar tailOfLeft = [self nodeCharCodeAt:node offset:remainder - 1];
                if (tailOfLeft == '\r') {
                    UDBufferCursor prevPos = [self positionInBufferForNode:node remainder:remainder - 1];
                    [self deleteNodeTail:node pos:prevPos];
                    value = [@"\r" stringByAppendingString:value];
                    if (node.piece.length == 0) { [nodesToDel addObject:node]; }
                } else {
                    [self deleteNodeTail:node pos:insertPosInBuffer];
                }
            } else {
                [self deleteNodeTail:node pos:insertPosInBuffer];
            }

            NSArray<UDPiece *> *newPieces = [self createNewPieces:value];
            if (newRightPiece.length > 0) {
                [self rbInsertRight:node piece:newRightPiece];
            }
            UDPieceTreeNode *tmpNode = node;
            for (UDPiece *p in newPieces) {
                tmpNode = [self rbInsertRight:tmpNode piece:p];
            }
            [self deleteNodes:nodesToDel];
        } else {
            [self insertContentToNodeRight:value node:node];
        }
    } else {
        NSArray<UDPiece *> *pieces = [self createNewPieces:value];
        UDPieceTreeNode *node = [self rbInsertLeft:nil piece:pieces[0]];
        for (NSUInteger k = 1; k < pieces.count; k++) {
            node = [self rbInsertRight:node piece:pieces[k]];
        }
    }
    [self computeBufferMetadata];
}

// MARK: - Delete

- (void)deleteAtOffset:(NSInteger)offset count:(NSInteger)cnt {
    if (cnt <= 0 || self.root == Sentinel()) { return; }

    PTNodePosition startPos = [self nodeAtOffset:offset];
    PTNodePosition endPos   = [self nodeAtOffset:offset + cnt];
    UDPieceTreeNode *startNode = startPos.node;
    UDPieceTreeNode *endNode   = endPos.node;

    if (startNode == endNode) {
        UDBufferCursor startSplit = [self positionInBufferForNode:startNode remainder:startPos.remainder];
        UDBufferCursor endSplit   = [self positionInBufferForNode:startNode remainder:endPos.remainder];

        if (startPos.nodeStartOffset == offset) {
            if (cnt == startNode.piece.length) {
                UDPieceTreeNode *next = [startNode next];
                RBDelete(self, startNode);
                [self validateCacheWithOffset:offset];
                [self validateCRLFWithPrevNode:next];
                [self computeBufferMetadata];
                return;
            }
            [self deleteNodeHead:startNode pos:endSplit];
            [self validateCacheWithOffset:offset];
            [self validateCRLFWithPrevNode:startNode];
            [self computeBufferMetadata];
            return;
        }
        if (startPos.nodeStartOffset + startNode.piece.length == offset + cnt) {
            [self deleteNodeTail:startNode pos:startSplit];
            [self validateCRLFWithNextNode:startNode];
            [self computeBufferMetadata];
            return;
        }
        [self shrinkNode:startNode start:startSplit end:endSplit];
        [self computeBufferMetadata];
        return;
    }

    NSMutableArray<UDPieceTreeNode *> *nodesToDel = [NSMutableArray array];
    UDBufferCursor startSplit = [self positionInBufferForNode:startNode remainder:startPos.remainder];
    [self deleteNodeTail:startNode pos:startSplit];
    [self validateCacheWithOffset:offset];
    if (startNode.piece.length == 0) { [nodesToDel addObject:startNode]; }

    UDBufferCursor endSplit = [self positionInBufferForNode:endNode remainder:endPos.remainder];
    [self deleteNodeHead:endNode pos:endSplit];
    if (endNode.piece.length == 0) { [nodesToDel addObject:endNode]; }

    UDPieceTreeNode *secondNode = [startNode next];
    UDPieceTreeNode *s = Sentinel();
    for (UDPieceTreeNode *n = secondNode; n != s && n != endNode; n = [n next]) {
        [nodesToDel addObject:n];
    }

    UDPieceTreeNode *prev = (startNode.piece.length == 0) ? [startNode prev] : startNode;
    [self deleteNodes:nodesToDel];
    [self validateCRLFWithNextNode:prev];
    [self computeBufferMetadata];
}

// MARK: - Private helpers: insert left/right to node

- (void)insertContentToNodeLeft:(NSString *)value node:(UDPieceTreeNode *)node {
    NSMutableArray<UDPieceTreeNode *> *nodesToDel = [NSMutableArray array];
    if ([self shouldCheckCRLF] && [self endWithCR:value] && [self startWithLFNode:node]) {
        UDPiece *piece = node.piece;
        UDBufferCursor newStart = PTBufferCursorMake(piece.start.line + 1, 0);
        NSInteger lfc = [self getLineFeedCnt:piece.bufferIndex start:newStart end:piece.end];
        UDPiece *nPiece = [[UDPiece alloc] initWithBufferIndex:piece.bufferIndex
                                                         start:newStart
                                                           end:piece.end
                                                   lineFeedCnt:lfc
                                                        length:piece.length - 1];
        node.piece = nPiece;
        value = [value stringByAppendingString:@"\n"];
        UpdateTreeMetadata(self, node, -1, -1);
        if (node.piece.length == 0) { [nodesToDel addObject:node]; }
    }

    NSArray<UDPiece *> *newPieces = [self createNewPieces:value];
    UDPieceTreeNode *newNode = [self rbInsertLeft:node piece:newPieces[newPieces.count - 1]];
    for (NSInteger k = (NSInteger)newPieces.count - 2; k >= 0; k--) {
        newNode = [self rbInsertLeft:newNode piece:newPieces[(NSUInteger)k]];
    }
    [self validateCRLFWithPrevNode:newNode];
    [self deleteNodes:nodesToDel];
}

- (void)insertContentToNodeRight:(NSString *)value node:(UDPieceTreeNode *)node {
    if ([self adjustCarriageReturnFromNext:value node:node]) {
        value = [value stringByAppendingString:@"\n"];
    }
    NSArray<UDPiece *> *newPieces = [self createNewPieces:value];
    UDPieceTreeNode *newNode = [self rbInsertRight:node piece:newPieces[0]];
    UDPieceTreeNode *tmpNode = newNode;
    for (NSUInteger k = 1; k < newPieces.count; k++) {
        tmpNode = [self rbInsertRight:tmpNode piece:newPieces[k]];
    }
    [self validateCRLFWithPrevNode:newNode];
}

// MARK: - positionInBuffer

- (UDBufferCursor)positionInBufferForNode:(UDPieceTreeNode *)node remainder:(NSInteger)remainder {
    UDPiece *piece = node.piece;
    NSInteger bufferIndex = piece.bufferIndex;
    NSArray<NSNumber *> *lineStarts = self.buffers[(NSUInteger)bufferIndex].lineStarts;
    NSInteger startOff = lineStarts[(NSUInteger)piece.start.line].integerValue + piece.start.column;
    NSInteger offset = startOff + remainder;

    NSInteger low = piece.start.line;
    NSInteger high = piece.end.line;
    NSInteger mid = 0, midStart = 0, midStop = 0;

    while (low <= high) {
        mid = low + (high - low) / 2;
        midStart = lineStarts[(NSUInteger)mid].integerValue;
        if (mid == high) { break; }
        midStop = lineStarts[(NSUInteger)(mid + 1)].integerValue;
        if (offset < midStart) { high = mid - 1; }
        else if (offset >= midStop) { low = mid + 1; }
        else { break; }
    }
    return PTBufferCursorMake(mid, offset - midStart);
}

// MARK: - getLineFeedCnt

- (NSInteger)getLineFeedCnt:(NSInteger)bufferIndex start:(UDBufferCursor)start end:(UDBufferCursor)end {
    if (end.column == 0) { return end.line - start.line; }
    NSArray<NSNumber *> *lineStarts = self.buffers[(NSUInteger)bufferIndex].lineStarts;
    if (end.line == (NSInteger)lineStarts.count - 1) { return end.line - start.line; }
    NSInteger nextLineStartOff = lineStarts[(NSUInteger)(end.line + 1)].integerValue;
    NSInteger endOff = lineStarts[(NSUInteger)end.line].integerValue + end.column;
    if (nextLineStartOff > endOff + 1) { return end.line - start.line; }
    NSString *buffer = self.buffers[(NSUInteger)bufferIndex].buffer;
    unichar prevChar = [buffer characterAtIndex:(NSUInteger)(endOff - 1)];
    return (prevChar == '\r') ? end.line - start.line + 1 : end.line - start.line;
}

// MARK: - offsetInBuffer

- (NSInteger)offsetInBuffer:(NSInteger)bufferIndex cursor:(UDBufferCursor)cursor {
    NSArray<NSNumber *> *lineStarts = self.buffers[(NSUInteger)bufferIndex].lineStarts;
    return lineStarts[(NSUInteger)cursor.line].integerValue + cursor.column;
}

// MARK: - getAccumulatedValue

- (NSInteger)getAccumulatedValue:(UDPieceTreeNode *)node index:(NSInteger)index {
    if (index < 0) { return 0; }
    UDPiece *piece = node.piece;
    NSArray<NSNumber *> *lineStarts = self.buffers[(NSUInteger)piece.bufferIndex].lineStarts;
    NSInteger expectedIdx = piece.start.line + index + 1;
    if (expectedIdx > piece.end.line) {
        return lineStarts[(NSUInteger)piece.end.line].integerValue + piece.end.column
             - lineStarts[(NSUInteger)piece.start.line].integerValue - piece.start.column;
    }
    return lineStarts[(NSUInteger)expectedIdx].integerValue
         - lineStarts[(NSUInteger)piece.start.line].integerValue - piece.start.column;
}

// MARK: - nodeAt (by offset)

- (PTNodePosition)nodeAtOffset:(NSInteger)offset {
    // Check cache
    if (self.cacheNode &&
        self.cacheNodeStartOffset <= offset &&
        self.cacheNodeStartOffset + self.cacheNode.piece.length >= offset) {
        return (PTNodePosition){ self.cacheNode, offset - self.cacheNodeStartOffset, self.cacheNodeStartOffset };
    }

    UDPieceTreeNode *x = self.root;
    UDPieceTreeNode *s = Sentinel();
    NSInteger nodeStartOffset = 0;
    while (x != s) {
        if (x.sizeLeft > offset) {
            x = x.left;
        } else if (x.sizeLeft + x.piece.length >= offset) {
            nodeStartOffset += x.sizeLeft;
            PTNodePosition ret = { x, offset - x.sizeLeft, nodeStartOffset };
            self.cacheNode = x;
            self.cacheNodeStartOffset = nodeStartOffset;
            return ret;
        } else {
            offset -= x.sizeLeft + x.piece.length;
            nodeStartOffset += x.sizeLeft + x.piece.length;
            x = x.right;
        }
    }
    return (PTNodePosition){ nil, 0, 0 };
}

// MARK: - nodeAt2 (by line/column)

- (PTNodePosition)nodeAt2Line:(NSInteger)lineNumber column:(NSInteger)column {
    UDPieceTreeNode *x = self.root;
    UDPieceTreeNode *s = Sentinel();
    NSInteger nodeStartOffset = 0;

    while (x != s) {
        if (x.left != s && x.lfLeft >= lineNumber - 1) {
            x = x.left;
        } else if (x.lfLeft + x.piece.lineFeedCnt > lineNumber - 1) {
            NSInteger prevAcc = [self getAccumulatedValue:x index:lineNumber - x.lfLeft - 2];
            NSInteger acc     = [self getAccumulatedValue:x index:lineNumber - x.lfLeft - 1];
            nodeStartOffset += x.sizeLeft;
            NSInteger rem = MIN(prevAcc + column - 1, acc);
            return (PTNodePosition){ x, rem, nodeStartOffset };
        } else if (x.lfLeft + x.piece.lineFeedCnt == lineNumber - 1) {
            NSInteger prevAcc = [self getAccumulatedValue:x index:lineNumber - x.lfLeft - 2];
            if (prevAcc + column - 1 <= x.piece.length) {
                return (PTNodePosition){ x, prevAcc + column - 1, nodeStartOffset };
            } else {
                column -= x.piece.length - prevAcc;
                break;
            }
        } else {
            lineNumber -= x.lfLeft + x.piece.lineFeedCnt;
            nodeStartOffset += x.sizeLeft + x.piece.length;
            x = x.right;
        }
    }

    // Search in order to find node containing position.column
    x = [x next];
    while (x != s) {
        if (x.piece.lineFeedCnt > 0) {
            NSInteger acc = [self getAccumulatedValue:x index:0];
            NSInteger nso = [self offsetOfNode:x];
            return (PTNodePosition){ x, MIN(column - 1, acc), nso };
        } else {
            if (x.piece.length >= column - 1) {
                NSInteger nso = [self offsetOfNode:x];
                return (PTNodePosition){ x, column - 1, nso };
            } else {
                column -= x.piece.length;
            }
        }
        x = [x next];
    }
    return (PTNodePosition){ nil, 0, 0 };
}

// MARK: - offsetOfNode

- (NSInteger)offsetOfNode:(UDPieceTreeNode *)node {
    if (!node) { return 0; }
    NSInteger pos = node.sizeLeft;
    while (node != self.root) {
        if (node.parent.right == node) {
            pos += node.parent.sizeLeft + node.parent.piece.length;
        }
        node = node.parent;
    }
    return pos;
}

// MARK: - nodeCharCodeAt

- (unichar)nodeCharCodeAt:(UDPieceTreeNode *)node offset:(NSInteger)offset {
    if (node.piece.lineFeedCnt < 1) { return 0; }
    NSString *buffer = self.buffers[(NSUInteger)node.piece.bufferIndex].buffer;
    NSInteger newOffset = [self offsetInBuffer:node.piece.bufferIndex cursor:node.piece.start] + offset;
    return [buffer characterAtIndex:(NSUInteger)newOffset];
}

// MARK: - getNodeContent / getPieceContent

- (NSString *)getNodeContent:(UDPieceTreeNode *)node {
    if (node == Sentinel()) { return @""; }
    NSString *buffer = self.buffers[(NSUInteger)node.piece.bufferIndex].buffer;
    NSInteger startOff = [self offsetInBuffer:node.piece.bufferIndex cursor:node.piece.start];
    NSInteger endOff   = [self offsetInBuffer:node.piece.bufferIndex cursor:node.piece.end];
    return [buffer substringWithRange:NSMakeRange((NSUInteger)startOff, (NSUInteger)(endOff - startOff))];
}

- (NSString *)getPieceContent:(UDPiece *)piece {
    NSString *buffer = self.buffers[(NSUInteger)piece.bufferIndex].buffer;
    NSInteger startOff = [self offsetInBuffer:piece.bufferIndex cursor:piece.start];
    NSInteger endOff   = [self offsetInBuffer:piece.bufferIndex cursor:piece.end];
    return [buffer substringWithRange:NSMakeRange((NSUInteger)startOff, (NSUInteger)(endOff - startOff))];
}

- (NSString *)getContentOfSubTree:(UDPieceTreeNode *)node {
    NSMutableString *str = [NSMutableString stringWithCapacity:self.length];
    [self iterateFrom:node callback:^BOOL(UDPieceTreeNode *n) {
        [str appendString:[self getNodeContent:n]];
        return YES;
    }];
    return [str copy];
}

// MARK: - iterate (in-order)

- (BOOL)iterateFrom:(UDPieceTreeNode *)node callback:(BOOL(^)(UDPieceTreeNode *))callback {
    if (node == Sentinel()) { return callback(Sentinel()); }
    BOOL leftRet = [self iterateFrom:node.left callback:callback];
    if (!leftRet) { return NO; }
    return callback(node) && [self iterateFrom:node.right callback:callback];
}

// MARK: - Node modifications

- (void)deleteNodeTail:(UDPieceTreeNode *)node pos:(UDBufferCursor)pos {
    UDPiece *piece = node.piece;
    NSInteger origLFCnt = piece.lineFeedCnt;
    NSInteger origEndOff = [self offsetInBuffer:piece.bufferIndex cursor:piece.end];
    NSInteger newEndOff = [self offsetInBuffer:piece.bufferIndex cursor:pos];
    NSInteger newLFCnt = [self getLineFeedCnt:piece.bufferIndex start:piece.start end:pos];
    NSInteger lfDelta = newLFCnt - origLFCnt;
    NSInteger sizeDelta = newEndOff - origEndOff;
    NSInteger newLength = piece.length + sizeDelta;
    node.piece = [[UDPiece alloc] initWithBufferIndex:piece.bufferIndex
                                                start:piece.start
                                                  end:pos
                                          lineFeedCnt:newLFCnt
                                               length:newLength];
    UpdateTreeMetadata(self, node, sizeDelta, lfDelta);
}

- (void)deleteNodeHead:(UDPieceTreeNode *)node pos:(UDBufferCursor)pos {
    UDPiece *piece = node.piece;
    NSInteger origLFCnt = piece.lineFeedCnt;
    NSInteger origStartOff = [self offsetInBuffer:piece.bufferIndex cursor:piece.start];
    NSInteger newStartOff = [self offsetInBuffer:piece.bufferIndex cursor:pos];
    NSInteger newLFCnt = [self getLineFeedCnt:piece.bufferIndex start:pos end:piece.end];
    NSInteger lfDelta = newLFCnt - origLFCnt;
    NSInteger sizeDelta = origStartOff - newStartOff;
    NSInteger newLength = piece.length + sizeDelta;
    node.piece = [[UDPiece alloc] initWithBufferIndex:piece.bufferIndex
                                                start:pos
                                                  end:piece.end
                                          lineFeedCnt:newLFCnt
                                               length:newLength];
    UpdateTreeMetadata(self, node, sizeDelta, lfDelta);
}

- (void)shrinkNode:(UDPieceTreeNode *)node start:(UDBufferCursor)start end:(UDBufferCursor)end {
    UDPiece *piece = node.piece;
    UDBufferCursor origEnd = piece.end;
    NSInteger oldLength = piece.length;
    NSInteger oldLFCnt  = piece.lineFeedCnt;
    NSInteger newLFCnt = [self getLineFeedCnt:piece.bufferIndex start:piece.start end:start];
    NSInteger newLength = [self offsetInBuffer:piece.bufferIndex cursor:start] -
                          [self offsetInBuffer:piece.bufferIndex cursor:piece.start];
    node.piece = [[UDPiece alloc] initWithBufferIndex:piece.bufferIndex
                                                start:piece.start
                                                  end:start
                                          lineFeedCnt:newLFCnt
                                               length:newLength];
    UpdateTreeMetadata(self, node, newLength - oldLength, newLFCnt - oldLFCnt);

    UDPiece *newPiece = [[UDPiece alloc] initWithBufferIndex:piece.bufferIndex
                                                       start:end
                                                         end:origEnd
                                                 lineFeedCnt:[self getLineFeedCnt:piece.bufferIndex start:end end:origEnd]
                                                      length:[self offsetInBuffer:piece.bufferIndex cursor:origEnd] -
                                                             [self offsetInBuffer:piece.bufferIndex cursor:end]];
    UDPieceTreeNode *newNode = [self rbInsertRight:node piece:newPiece];
    [self validateCRLFWithPrevNode:newNode];
}

- (void)appendToNode:(UDPieceTreeNode *)node value:(NSString *)value {
    if ([self adjustCarriageReturnFromNext:value node:node]) {
        value = [value stringByAppendingString:@"\n"];
    }
    BOOL hitCRLF = [self shouldCheckCRLF] && [self startWithLFString:value] && [self endWithCRNode:node];
    NSInteger startOffset = (NSInteger)self.buffers[0].buffer.length;

    NSMutableString *buf = [self.buffers[0].buffer mutableCopy];
    [buf appendString:value];
    self.buffers[0].buffer = [buf copy];

    NSMutableArray<NSNumber *> *lineStarts = CreateLineStartsFast(value);
    for (NSUInteger i = 0; i < lineStarts.count; i++) {
        lineStarts[i] = @(lineStarts[i].integerValue + startOffset);
    }
    if (hitCRLF) {
        NSMutableArray<NSNumber *> *ls = self.buffers[0].lineStarts;
        [ls removeLastObject];
        NSInteger prevStartOff = ls[ls.count - 1].integerValue;
        self.lastChangeBufferPos = PTBufferCursorMake(
            self.lastChangeBufferPos.line - 1,
            startOffset - prevStartOff);
    }
    // Append all but first lineStart (which is 0)
    NSMutableArray<NSNumber *> *ls0 = self.buffers[0].lineStarts;
    for (NSUInteger i = 1; i < lineStarts.count; i++) {
        [ls0 addObject:lineStarts[i]];
    }

    NSInteger endIndex = (NSInteger)ls0.count - 1;
    NSInteger endColumn = (NSInteger)self.buffers[0].buffer.length - ls0[(NSUInteger)endIndex].integerValue;
    UDBufferCursor newEnd = PTBufferCursorMake(endIndex, endColumn);
    NSInteger newLength = node.piece.length + (NSInteger)value.length;
    NSInteger oldLFCnt = node.piece.lineFeedCnt;
    NSInteger newLFCnt = [self getLineFeedCnt:0 start:node.piece.start end:newEnd];
    NSInteger lfDelta = newLFCnt - oldLFCnt;

    node.piece = [[UDPiece alloc] initWithBufferIndex:node.piece.bufferIndex
                                                start:node.piece.start
                                                  end:newEnd
                                          lineFeedCnt:newLFCnt
                                               length:newLength];
    self.lastChangeBufferPos = newEnd;
    UpdateTreeMetadata(self, node, (NSInteger)value.length, lfDelta);
}

// MARK: - createNewPieces

- (NSArray<UDPiece *> *)createNewPieces:(NSString *)text {
    NSMutableArray<UDPiece *> *newPieces = [NSMutableArray array];
    NSString *remaining = text;

    if ((NSInteger)text.length > AverageBufferSize) {
        while ((NSInteger)remaining.length > AverageBufferSize) {
            unichar lastChar = [remaining characterAtIndex:(NSUInteger)(AverageBufferSize - 1)];
            NSString *splitText;
            if (lastChar == '\r' || (lastChar >= 0xD800 && lastChar <= 0xDBFF)) {
                splitText = [remaining substringToIndex:(NSUInteger)(AverageBufferSize - 1)];
                remaining = [remaining substringFromIndex:(NSUInteger)(AverageBufferSize - 1)];
            } else {
                splitText = [remaining substringToIndex:(NSUInteger)AverageBufferSize];
                remaining = [remaining substringFromIndex:(NSUInteger)AverageBufferSize];
            }
            NSMutableArray<NSNumber *> *lineStarts = CreateLineStartsFast(splitText);
            NSInteger ls = (NSInteger)lineStarts.count;
            NSInteger bufLen = (NSInteger)splitText.length;
            NSInteger lastLS = lineStarts[(NSUInteger)(ls - 1)].integerValue;
            [newPieces addObject:[[UDPiece alloc] initWithBufferIndex:(NSInteger)self.buffers.count
                                                                start:PTBufferCursorMake(0, 0)
                                                                  end:PTBufferCursorMake(ls - 1, bufLen - lastLS)
                                                          lineFeedCnt:ls - 1
                                                               length:bufLen]];
            [self.buffers addObject:[[UDStringBuffer alloc] initWithBuffer:splitText lineStarts:lineStarts]];
        }
        NSMutableArray<NSNumber *> *lineStarts = CreateLineStartsFast(remaining);
        NSInteger ls = (NSInteger)lineStarts.count;
        NSInteger bufLen = (NSInteger)remaining.length;
        NSInteger lastLS = lineStarts[(NSUInteger)(ls - 1)].integerValue;
        [newPieces addObject:[[UDPiece alloc] initWithBufferIndex:(NSInteger)self.buffers.count
                                                            start:PTBufferCursorMake(0, 0)
                                                              end:PTBufferCursorMake(ls - 1, bufLen - lastLS)
                                                      lineFeedCnt:ls - 1
                                                           length:bufLen]];
        [self.buffers addObject:[[UDStringBuffer alloc] initWithBuffer:remaining lineStarts:lineStarts]];
        return [newPieces copy];
    }

    NSInteger startOffset = (NSInteger)self.buffers[0].buffer.length;
    NSMutableArray<NSNumber *> *lineStarts = CreateLineStartsFast(text);

    UDBufferCursor start = self.lastChangeBufferPos;
    NSArray<NSNumber *> *buf0LS = self.buffers[0].lineStarts;
    if (buf0LS[buf0LS.count - 1].integerValue == startOffset &&
        startOffset != 0 &&
        [self startWithLFString:text] &&
        [self endWithCR:self.buffers[0].buffer]) {

        self.lastChangeBufferPos = PTBufferCursorMake(self.lastChangeBufferPos.line,
                                                      self.lastChangeBufferPos.column + 1);
        start = self.lastChangeBufferPos;
        for (NSUInteger i = 0; i < lineStarts.count; i++) {
            lineStarts[i] = @(lineStarts[i].integerValue + startOffset + 1);
        }
        NSMutableArray *ls0 = self.buffers[0].lineStarts;
        for (NSUInteger i = 1; i < lineStarts.count; i++) { [ls0 addObject:lineStarts[i]]; }
        NSMutableString *b = [self.buffers[0].buffer mutableCopy];
        [b appendString:[@"_" stringByAppendingString:text]];
        self.buffers[0].buffer = [b copy];
        startOffset += 1;
    } else {
        if (startOffset != 0) {
            for (NSUInteger i = 0; i < lineStarts.count; i++) {
                lineStarts[i] = @(lineStarts[i].integerValue + startOffset);
            }
        }
        NSMutableArray *ls0 = self.buffers[0].lineStarts;
        for (NSUInteger i = 1; i < lineStarts.count; i++) { [ls0 addObject:lineStarts[i]]; }
        NSMutableString *b = [self.buffers[0].buffer mutableCopy];
        [b appendString:text];
        self.buffers[0].buffer = [b copy];
    }

    NSInteger endOffset = (NSInteger)self.buffers[0].buffer.length;
    NSInteger endIndex = (NSInteger)self.buffers[0].lineStarts.count - 1;
    NSInteger endColumn = endOffset - self.buffers[0].lineStarts[(NSUInteger)endIndex].integerValue;
    UDBufferCursor endPos = PTBufferCursorMake(endIndex, endColumn);
    UDPiece *newPiece = [[UDPiece alloc] initWithBufferIndex:0
                                                       start:start
                                                         end:endPos
                                                 lineFeedCnt:[self getLineFeedCnt:0 start:start end:endPos]
                                                      length:endOffset - startOffset];
    self.lastChangeBufferPos = endPos;
    return @[newPiece];
}

// MARK: - CRLF helpers

- (BOOL)shouldCheckCRLF {
    return !(self.eolNormalized && [self.eol isEqualToString:@"\n"]);
}

- (BOOL)startWithLFString:(NSString *)val {
    if (val.length == 0) { return NO; }
    return [val characterAtIndex:0] == '\n';
}

- (BOOL)startWithLFNode:(UDPieceTreeNode *)val {
    if (val == Sentinel() || val.piece.lineFeedCnt == 0) { return NO; }
    UDPiece *piece = val.piece;
    NSArray<NSNumber *> *lineStarts = self.buffers[(NSUInteger)piece.bufferIndex].lineStarts;
    NSInteger line = piece.start.line;
    NSInteger startOff = lineStarts[(NSUInteger)line].integerValue + piece.start.column;
    if (line == (NSInteger)lineStarts.count - 1) { return NO; }
    NSInteger nextLineOff = lineStarts[(NSUInteger)(line + 1)].integerValue;
    if (nextLineOff > startOff + 1) { return NO; }
    return [self.buffers[(NSUInteger)piece.bufferIndex].buffer characterAtIndex:(NSUInteger)startOff] == '\n';
}

- (BOOL)endWithCR:(NSString *)val {
    if (val.length == 0) { return NO; }
    return [val characterAtIndex:val.length - 1] == '\r';
}

- (BOOL)endWithCRNode:(UDPieceTreeNode *)val {
    if (val == Sentinel() || val.piece.lineFeedCnt == 0) { return NO; }
    return [self nodeCharCodeAt:val offset:val.piece.length - 1] == '\r';
}

- (void)validateCRLFWithPrevNode:(UDPieceTreeNode *)nextNode {
    if ([self shouldCheckCRLF] && [self startWithLFNode:nextNode]) {
        UDPieceTreeNode *node = [nextNode prev];
        if ([self endWithCRNode:node]) {
            [self fixCRLF:node next:nextNode];
        }
    }
}

- (void)validateCRLFWithNextNode:(UDPieceTreeNode *)node {
    if ([self shouldCheckCRLF] && [self endWithCRNode:node]) {
        UDPieceTreeNode *nextNode = [node next];
        if ([self startWithLFNode:nextNode]) {
            [self fixCRLF:node next:nextNode];
        }
    }
}

- (void)fixCRLF:(UDPieceTreeNode *)prev next:(UDPieceTreeNode *)next {
    NSMutableArray<UDPieceTreeNode *> *nodesToDel = [NSMutableArray array];
    NSArray<NSNumber *> *lineStarts = self.buffers[(NSUInteger)prev.piece.bufferIndex].lineStarts;
    UDBufferCursor newEnd;
    if (prev.piece.end.column == 0) {
        NSInteger line = prev.piece.end.line;
        newEnd = PTBufferCursorMake(line - 1,
            lineStarts[(NSUInteger)line].integerValue - lineStarts[(NSUInteger)(line - 1)].integerValue - 1);
    } else {
        newEnd = PTBufferCursorMake(prev.piece.end.line, prev.piece.end.column - 1);
    }
    prev.piece = [[UDPiece alloc] initWithBufferIndex:prev.piece.bufferIndex
                                                start:prev.piece.start
                                                  end:newEnd
                                          lineFeedCnt:prev.piece.lineFeedCnt - 1
                                               length:prev.piece.length - 1];
    UpdateTreeMetadata(self, prev, -1, -1);
    if (prev.piece.length == 0) { [nodesToDel addObject:prev]; }

    UDBufferCursor newStart = PTBufferCursorMake(next.piece.start.line + 1, 0);
    NSInteger newLFCnt = [self getLineFeedCnt:next.piece.bufferIndex start:newStart end:next.piece.end];
    next.piece = [[UDPiece alloc] initWithBufferIndex:next.piece.bufferIndex
                                                start:newStart
                                                  end:next.piece.end
                                          lineFeedCnt:newLFCnt
                                               length:next.piece.length - 1];
    UpdateTreeMetadata(self, next, -1, -1);
    if (next.piece.length == 0) { [nodesToDel addObject:next]; }

    NSArray<UDPiece *> *pieces = [self createNewPieces:@"\r\n"];
    [self rbInsertRight:prev piece:pieces[0]];
    for (UDPieceTreeNode *n in nodesToDel) { RBDelete(self, n); }
}

- (BOOL)adjustCarriageReturnFromNext:(NSString *)value node:(UDPieceTreeNode *)node {
    if ([self shouldCheckCRLF] && [self endWithCR:value]) {
        UDPieceTreeNode *nextNode = [node next];
        if ([self startWithLFNode:nextNode]) {
            if (nextNode.piece.length == 1) {
                RBDelete(self, nextNode);
            } else {
                UDPiece *piece = nextNode.piece;
                UDBufferCursor newStart = PTBufferCursorMake(piece.start.line + 1, 0);
                NSInteger newLFCnt = [self getLineFeedCnt:piece.bufferIndex start:newStart end:piece.end];
                nextNode.piece = [[UDPiece alloc] initWithBufferIndex:piece.bufferIndex
                                                                start:newStart
                                                                  end:piece.end
                                                          lineFeedCnt:newLFCnt
                                                               length:piece.length - 1];
                UpdateTreeMetadata(self, nextNode, -1, -1);
            }
            return YES;
        }
    }
    return NO;
}

// MARK: - deleteNodes

- (void)deleteNodes:(NSArray<UDPieceTreeNode *> *)nodes {
    for (UDPieceTreeNode *n in nodes) { RBDelete(self, n); }
}

// MARK: - Cache invalidation

- (void)validateCacheWithOffset:(NSInteger)offset {
    if (self.cacheNode && self.cacheNodeStartOffset >= offset) {
        self.cacheNode = nil;
    }
}

// MARK: - RB-tree insertions

- (UDPieceTreeNode *)rbInsertRight:(nullable UDPieceTreeNode *)node piece:(UDPiece *)piece {
    UDPieceTreeNode *s = Sentinel();
    UDPieceTreeNode *z = [[UDPieceTreeNode alloc] initWithPiece:piece color:PTNodeColorRed];
    z.left = s; z.right = s; z.parent = s;
    z.sizeLeft = 0; z.lfLeft = 0;

    if (self.root == s) {
        self.root = z;
        z.color = PTNodeColorBlack;
    } else if (node.right == s) {
        node.right = z;
        z.parent = node;
    } else {
        UDPieceTreeNode *nextNode = Leftest(node.right);
        nextNode.left = z;
        z.parent = nextNode;
    }
    FixInsert(self, z);
    return z;
}

- (UDPieceTreeNode *)rbInsertLeft:(nullable UDPieceTreeNode *)node piece:(UDPiece *)piece {
    UDPieceTreeNode *s = Sentinel();
    UDPieceTreeNode *z = [[UDPieceTreeNode alloc] initWithPiece:piece color:PTNodeColorRed];
    z.left = s; z.right = s; z.parent = s;
    z.sizeLeft = 0; z.lfLeft = 0;

    if (self.root == s) {
        self.root = z;
        z.color = PTNodeColorBlack;
    } else if (node.left == s) {
        node.left = z;
        z.parent = node;
    } else {
        UDPieceTreeNode *prevNode = Rightest(node.left);
        prevNode.right = z;
        z.parent = prevNode;
    }
    FixInsert(self, z);
    return z;
}

// MARK: - Search helpers

/// Port of _findMatchesInLine from pieceTreeBase.ts.
- (NSInteger)_findMatchesInLine:(UDSearchData *)searchData
                        searcher:(UDSearcher *)searcher
                            text:(NSString *)text
                      lineNumber:(NSInteger)lineNumber
                     deltaOffset:(NSInteger)deltaOffset
                       resultLen:(NSInteger)resultLen
                          result:(NSMutableArray<UDFindMatch *> *)result
                  captureMatches:(BOOL)captureMatches
                limitResultCount:(NSInteger)limitResultCount {
    NSInteger textLen = (NSInteger)text.length;
    UDWordCharacterClassifier *wordSeparators = searchData.wordSeparators;

    // Fast path: plain-text, case-sensitive, no capture groups needed
    NSString *simpleSearch = searchData.simpleSearch;
    if (!captureMatches && simpleSearch != nil) {
        NSInteger searchOffset = 0;
        NSInteger searchLen = (NSInteger)simpleSearch.length;
        while (YES) {
            NSRange r = [text rangeOfString:simpleSearch
                                    options:0
                                      range:NSMakeRange((NSUInteger)searchOffset,
                                                        (NSUInteger)(textLen - searchOffset))];
            if (r.location == NSNotFound) { break; }
            NSInteger matchStart = (NSInteger)r.location;
            if (wordSeparators && !PTIsValidMatch(wordSeparators, text, textLen, matchStart, searchLen)) {
                searchOffset = matchStart + 1;
                continue;
            }
            NSInteger startColumn = matchStart + 1 + deltaOffset;
            NSInteger endColumn   = startColumn + searchLen;
            UDFindMatch *m = [[UDFindMatch alloc]
                              initWithRange:PTRangeMake(lineNumber, startColumn, lineNumber, endColumn)
                                    matches:nil];
            [result addObject:m];
            resultLen++;
            if (resultLen >= limitResultCount) { return resultLen; }
            searchOffset = matchStart + searchLen;
        }
        return resultLen;
    }

    // Regex path
    [searcher reset:0];
    while (YES) {
        NSTextCheckingResult *match = [searcher next:text];
        if (!match) { break; }
        NSInteger matchStart  = (NSInteger)match.range.location;
        NSInteger matchLength = (NSInteger)match.range.length;
        NSInteger startColumn = matchStart + 1 + deltaOffset;
        NSInteger endColumn   = startColumn + matchLength;

        NSArray<NSString *> *matches = nil;
        if (captureMatches) {
            NSMutableArray<NSString *> *arr = [NSMutableArray array];
            for (NSUInteger g = 0; g < match.numberOfRanges; g++) {
                NSRange gr = [match rangeAtIndex:g];
                if (gr.location != NSNotFound) {
                    [arr addObject:[text substringWithRange:gr]];
                } else {
                    [arr addObject:@""];
                }
            }
            matches = [arr copy];
        }

        UDFindMatch *fm = [[UDFindMatch alloc]
                           initWithRange:PTRangeMake(lineNumber, startColumn, lineNumber, endColumn)
                                 matches:matches];
        [result addObject:fm];
        resultLen++;
        if (resultLen >= limitResultCount) { return resultLen; }
    }
    return resultLen;
}

/// Port of findMatchesInNode from pieceTreeBase.ts.
- (NSInteger)_findMatchesInNode:(UDPieceTreeNode *)node
                        searcher:(UDSearcher *)searcher
                 startLineNumber:(NSInteger)startLineNumber
                     startColumn:(NSInteger)startColumn
                     startCursor:(UDBufferCursor)startCursor
                       endCursor:(UDBufferCursor)endCursor
                      searchData:(UDSearchData *)searchData
                  captureMatches:(BOOL)captureMatches
                limitResultCount:(NSInteger)limitResultCount
                       resultLen:(NSInteger)resultLen
                          result:(NSMutableArray<UDFindMatch *> *)result {
    NSInteger bufIdx = node.piece.bufferIndex;
    UDStringBuffer *buffer = self.buffers[(NSUInteger)bufIdx];
    NSInteger startAbsOffset = [self offsetInBuffer:bufIdx cursor:startCursor];
    NSInteger endAbsOffset   = [self offsetInBuffer:bufIdx cursor:endCursor];
    NSInteger pieceStartAbsOffset = [self offsetInBuffer:bufIdx cursor:node.piece.start];
    UDWordCharacterClassifier *wordSeparators = searchData.wordSeparators;

    if (wordSeparators) {
        // Extract just the relevant substring so PTIsValidMatch can use text.length
        NSString *searchText = [buffer.buffer
                                substringWithRange:NSMakeRange((NSUInteger)startAbsOffset,
                                                               (NSUInteger)(endAbsOffset - startAbsOffset))];
        [searcher reset:0];
        while (YES) {
            NSTextCheckingResult *match = [searcher next:searchText];
            if (!match) { break; }
            NSInteger relStart = (NSInteger)match.range.location;
            NSInteger absStart = relStart + startAbsOffset;
            if (absStart >= endAbsOffset) { break; }

            NSInteger matchLength = (NSInteger)match.range.length;
            NSInteger remainder   = absStart - pieceStartAbsOffset;
            UDBufferCursor ret    = [self positionInBufferForNode:node remainder:remainder];
            NSInteger lineFeedCnt = [self getLineFeedCnt:bufIdx start:startCursor end:ret];
            NSInteger retStartColumn = (ret.line == startCursor.line)
                ? ret.column - startCursor.column + startColumn
                : ret.column + 1;
            NSInteger retEndColumn = retStartColumn + matchLength;

            NSArray<NSString *> *matches = nil;
            if (captureMatches) {
                NSMutableArray<NSString *> *arr = [NSMutableArray array];
                for (NSUInteger g = 0; g < match.numberOfRanges; g++) {
                    NSRange gr = [match rangeAtIndex:g];
                    if (gr.location != NSNotFound) {
                        [arr addObject:[searchText substringWithRange:gr]];
                    } else {
                        [arr addObject:@""];
                    }
                }
                matches = [arr copy];
            }

            UDFindMatch *fm = [[UDFindMatch alloc]
                               initWithRange:PTRangeMake(startLineNumber + lineFeedCnt, retStartColumn,
                                                         startLineNumber + lineFeedCnt, retEndColumn)
                                     matches:matches];
            [result addObject:fm];
            resultLen++;
            if (absStart + matchLength >= endAbsOffset) { break; }
            if (resultLen >= limitResultCount) { break; }
        }
    } else {
        [searcher reset:startAbsOffset];
        while (YES) {
            NSTextCheckingResult *match = [searcher next:buffer.buffer];
            if (!match) { break; }
            NSInteger absStart = (NSInteger)match.range.location;
            if (absStart >= endAbsOffset) { break; }

            NSInteger matchLength = (NSInteger)match.range.length;
            NSInteger remainder   = absStart - pieceStartAbsOffset;
            UDBufferCursor ret    = [self positionInBufferForNode:node remainder:remainder];
            NSInteger lineFeedCnt = [self getLineFeedCnt:bufIdx start:startCursor end:ret];
            NSInteger retStartColumn = (ret.line == startCursor.line)
                ? ret.column - startCursor.column + startColumn
                : ret.column + 1;
            NSInteger retEndColumn = retStartColumn + matchLength;

            NSArray<NSString *> *matches = nil;
            if (captureMatches) {
                NSMutableArray<NSString *> *arr = [NSMutableArray array];
                for (NSUInteger g = 0; g < match.numberOfRanges; g++) {
                    NSRange gr = [match rangeAtIndex:g];
                    if (gr.location != NSNotFound) {
                        [arr addObject:[buffer.buffer substringWithRange:gr]];
                    } else {
                        [arr addObject:@""];
                    }
                }
                matches = [arr copy];
            }

            UDFindMatch *fm = [[UDFindMatch alloc]
                               initWithRange:PTRangeMake(startLineNumber + lineFeedCnt, retStartColumn,
                                                         startLineNumber + lineFeedCnt, retEndColumn)
                                     matches:matches];
            [result addObject:fm];
            resultLen++;
            if (absStart + matchLength >= endAbsOffset) { break; }
            if (resultLen >= limitResultCount) { break; }
        }
    }
    return resultLen;
}

/// Port of findMatchesLineByLine from pieceTreeBase.ts.
- (NSArray<UDFindMatch *> *)findMatchesLineByLine:(UDRange)searchRange
                                       searchData:(UDSearchData *)searchData
                                   captureMatches:(BOOL)captureMatches
                                 limitResultCount:(NSInteger)limitResultCount {
    NSMutableArray<UDFindMatch *> *result = [NSMutableArray array];
    NSInteger resultLen = 0;

    UDSearcher *searcher = [[UDSearcher alloc] initWithWordSeparators:searchData.wordSeparators
                                                          searchRegex:searchData.regex];

    PTNodePosition startPos = [self nodeAt2Line:searchRange.startLineNumber
                                         column:searchRange.startColumn];
    PTNodePosition endPos   = [self nodeAt2Line:searchRange.endLineNumber
                                         column:searchRange.endColumn];

    if (!startPos.node || !endPos.node) { return result; }

    UDBufferCursor startCursor = [self positionInBufferForNode:startPos.node
                                                     remainder:startPos.remainder];
    UDBufferCursor endCursor   = [self positionInBufferForNode:endPos.node
                                                     remainder:endPos.remainder];

    // Case A: same node
    if (startPos.node == endPos.node) {
        [self _findMatchesInNode:startPos.node
                        searcher:searcher
                 startLineNumber:searchRange.startLineNumber
                     startColumn:searchRange.startColumn
                     startCursor:startCursor
                       endCursor:endCursor
                      searchData:searchData
                  captureMatches:captureMatches
                limitResultCount:limitResultCount
                       resultLen:resultLen
                          result:result];
        return result;
    }

    // Case B: multiple nodes
    NSInteger startLineNumber = searchRange.startLineNumber;
    UDPieceTreeNode *currentNode = startPos.node;
    UDBufferCursor start = startCursor;
    NSInteger startCol = searchRange.startColumn;

    while (currentNode != endPos.node) {
        NSInteger bufIdx = currentNode.piece.bufferIndex;
        NSInteger lineBreakCnt = [self getLineFeedCnt:bufIdx start:start end:currentNode.piece.end];

        if (lineBreakCnt >= 1) {
            // Search the multi-line portion of this node in the buffer
            UDBufferCursor loopEndCursor = PTBufferCursorMake(start.line + lineBreakCnt, 0);
            resultLen = [self _findMatchesInNode:currentNode
                                        searcher:searcher
                                 startLineNumber:startLineNumber
                                     startColumn:startCol
                                     startCursor:start
                                       endCursor:loopEndCursor
                                      searchData:searchData
                                  captureMatches:captureMatches
                                limitResultCount:limitResultCount
                                       resultLen:resultLen
                                          result:result];
            if (resultLen >= limitResultCount) { return result; }
            startLineNumber += lineBreakCnt;
        }

        // Handle the tail fragment (last line of the current node) via line API
        NSString *lastLineFragment = [self getLineContent:startLineNumber];
        resultLen = [self _findMatchesInLine:searchData
                                    searcher:searcher
                                        text:lastLineFragment
                                  lineNumber:startLineNumber
                                 deltaOffset:0
                                   resultLen:resultLen
                                      result:result
                              captureMatches:captureMatches
                            limitResultCount:limitResultCount];
        if (resultLen >= limitResultCount) { return result; }
        startLineNumber += 1;

        // Advance to the next node
        PTNodePosition nextPos = [self nodeAt2Line:startLineNumber column:1];
        if (nextPos.node) {
            currentNode = nextPos.node;
            start = [self positionInBufferForNode:nextPos.node remainder:nextPos.remainder];
            startCol = 1;
        } else {
            break;
        }
    }

    // Handle the last node
    if (startLineNumber == searchRange.endLineNumber) {
        NSString *lastLine = [self getLineContent:startLineNumber];
        [self _findMatchesInLine:searchData
                        searcher:searcher
                            text:lastLine
                      lineNumber:startLineNumber
                     deltaOffset:0
                       resultLen:resultLen
                          result:result
                  captureMatches:captureMatches
                limitResultCount:limitResultCount];
    } else {
        [self _findMatchesInNode:endPos.node
                        searcher:searcher
                 startLineNumber:startLineNumber
                     startColumn:startCol
                     startCursor:start
                       endCursor:endCursor
                      searchData:searchData
                  captureMatches:captureMatches
                limitResultCount:limitResultCount
                       resultLen:resultLen
                          result:result];
    }

    return result;
}

@end

// MARK: - Tree rotation / fixup (C static functions)

static void LeftRotate(UDPieceTree *tree, UDPieceTreeNode *x) {
    UDPieceTreeNode *s = Sentinel();
    UDPieceTreeNode *y = x.right;
    y.sizeLeft += x.sizeLeft + (x.piece ? x.piece.length : 0);
    y.lfLeft   += x.lfLeft   + (x.piece ? x.piece.lineFeedCnt : 0);
    x.right = y.left;
    if (y.left != s) { y.left.parent = x; }
    y.parent = x.parent;
    if (x.parent == s) { tree.root = y; }
    else if (x.parent.left == x) { x.parent.left = y; }
    else { x.parent.right = y; }
    y.left = x;
    x.parent = y;
}

static void RightRotate(UDPieceTree *tree, UDPieceTreeNode *y) {
    UDPieceTreeNode *s = Sentinel();
    UDPieceTreeNode *x = y.left;
    y.left = x.right;
    if (x.right != s) { x.right.parent = y; }
    x.parent = y.parent;
    y.sizeLeft -= x.sizeLeft + (x.piece ? x.piece.length : 0);
    y.lfLeft   -= x.lfLeft   + (x.piece ? x.piece.lineFeedCnt : 0);
    if (y.parent == s) { tree.root = x; }
    else if (y == y.parent.right) { y.parent.right = x; }
    else { y.parent.left = x; }
    x.right = y;
    y.parent = x;
}

static void UpdateTreeMetadata(UDPieceTree *tree, UDPieceTreeNode *x, NSInteger delta, NSInteger lfDelta) {
    UDPieceTreeNode *s = Sentinel();
    while (x != tree.root && x != s) {
        if (x.parent.left == x) {
            x.parent.sizeLeft += delta;
            x.parent.lfLeft   += lfDelta;
        }
        x = x.parent;
    }
}

static void RecomputeTreeMetadata(UDPieceTree *tree, UDPieceTreeNode *x) {
    UDPieceTreeNode *s = Sentinel();
    if (x == tree.root) { return; }
    while (x != tree.root && x == x.parent.right) { x = x.parent; }
    if (x == tree.root) { return; }
    x = x.parent;
    NSInteger delta   = CalculateSize(x.left) - x.sizeLeft;
    NSInteger lfDelta = CalculateLF(x.left)   - x.lfLeft;
    x.sizeLeft += delta;
    x.lfLeft   += lfDelta;
    while (x != tree.root && (delta != 0 || lfDelta != 0)) {
        if (x.parent.left == x) {
            x.parent.sizeLeft += delta;
            x.parent.lfLeft   += lfDelta;
        }
        x = x.parent;
    }
}

static void FixInsert(UDPieceTree *tree, UDPieceTreeNode *x) {
    RecomputeTreeMetadata(tree, x);
    UDPieceTreeNode *s = Sentinel();
    while (x != tree.root && x.parent.color == PTNodeColorRed) {
        if (x.parent == x.parent.parent.left) {
            UDPieceTreeNode *y = x.parent.parent.right;
            if (y.color == PTNodeColorRed) {
                x.parent.color = PTNodeColorBlack;
                y.color = PTNodeColorBlack;
                x.parent.parent.color = PTNodeColorRed;
                x = x.parent.parent;
            } else {
                if (x == x.parent.right) { x = x.parent; LeftRotate(tree, x); }
                x.parent.color = PTNodeColorBlack;
                x.parent.parent.color = PTNodeColorRed;
                RightRotate(tree, x.parent.parent);
            }
        } else {
            UDPieceTreeNode *y = x.parent.parent.left;
            if (y.color == PTNodeColorRed) {
                x.parent.color = PTNodeColorBlack;
                y.color = PTNodeColorBlack;
                x.parent.parent.color = PTNodeColorRed;
                x = x.parent.parent;
            } else {
                if (x == x.parent.left) { x = x.parent; RightRotate(tree, x); }
                x.parent.color = PTNodeColorBlack;
                x.parent.parent.color = PTNodeColorRed;
                LeftRotate(tree, x.parent.parent);
            }
        }
    }
    tree.root.color = PTNodeColorBlack;
}

static void RBDelete(UDPieceTree *tree, UDPieceTreeNode *z) {
    UDPieceTreeNode *s = Sentinel();
    UDPieceTreeNode *x, *y;

    if (z.left == s) { y = z; x = y.right; }
    else if (z.right == s) { y = z; x = y.left; }
    else { y = Leftest(z.right); x = y.right; }

    if (y == tree.root) {
        tree.root = x;
        x.color = PTNodeColorBlack;
        [z detach];
        ResetSentinel();
        tree.root.parent = s;
        return;
    }

    BOOL yWasRed = (y.color == PTNodeColorRed);
    if (y == y.parent.left) { y.parent.left = x; }
    else { y.parent.right = x; }

    if (y == z) {
        x.parent = y.parent;
        RecomputeTreeMetadata(tree, x);
    } else {
        x.parent = (y.parent == z) ? y : y.parent;
        RecomputeTreeMetadata(tree, x);
        y.left = z.left; y.right = z.right; y.parent = z.parent; y.color = z.color;
        if (z == tree.root) { tree.root = y; }
        else {
            if (z == z.parent.left) { z.parent.left = y; }
            else { z.parent.right = y; }
        }
        if (y.left != s) { y.left.parent = y; }
        if (y.right != s) { y.right.parent = y; }
        y.sizeLeft = z.sizeLeft;
        y.lfLeft   = z.lfLeft;
        RecomputeTreeMetadata(tree, y);
    }

    [z detach];

    if (x.parent.left == x) {
        NSInteger newSizeLeft = CalculateSize(x);
        NSInteger newLFLeft   = CalculateLF(x);
        if (newSizeLeft != x.parent.sizeLeft || newLFLeft != x.parent.lfLeft) {
            NSInteger delta   = newSizeLeft - x.parent.sizeLeft;
            NSInteger lfDelta = newLFLeft   - x.parent.lfLeft;
            x.parent.sizeLeft = newSizeLeft;
            x.parent.lfLeft   = newLFLeft;
            UpdateTreeMetadata(tree, x.parent, delta, lfDelta);
        }
    }
    RecomputeTreeMetadata(tree, x.parent);

    if (yWasRed) { ResetSentinel(); return; }

    // RB-DELETE-FIXUP
    UDPieceTreeNode *w;
    while (x != tree.root && x.color == PTNodeColorBlack) {
        if (x == x.parent.left) {
            w = x.parent.right;
            if (w.color == PTNodeColorRed) {
                w.color = PTNodeColorBlack;
                x.parent.color = PTNodeColorRed;
                LeftRotate(tree, x.parent);
                w = x.parent.right;
            }
            if (w.left.color == PTNodeColorBlack && w.right.color == PTNodeColorBlack) {
                w.color = PTNodeColorRed;
                x = x.parent;
            } else {
                if (w.right.color == PTNodeColorBlack) {
                    w.left.color = PTNodeColorBlack;
                    w.color = PTNodeColorRed;
                    RightRotate(tree, w);
                    w = x.parent.right;
                }
                w.color = x.parent.color;
                x.parent.color = PTNodeColorBlack;
                w.right.color = PTNodeColorBlack;
                LeftRotate(tree, x.parent);
                x = tree.root;
            }
        } else {
            w = x.parent.left;
            if (w.color == PTNodeColorRed) {
                w.color = PTNodeColorBlack;
                x.parent.color = PTNodeColorRed;
                RightRotate(tree, x.parent);
                w = x.parent.left;
            }
            if (w.left.color == PTNodeColorBlack && w.right.color == PTNodeColorBlack) {
                w.color = PTNodeColorRed;
                x = x.parent;
            } else {
                if (w.left.color == PTNodeColorBlack) {
                    w.right.color = PTNodeColorBlack;
                    w.color = PTNodeColorRed;
                    LeftRotate(tree, w);
                    w = x.parent.left;
                }
                w.color = x.parent.color;
                x.parent.color = PTNodeColorBlack;
                w.left.color = PTNodeColorBlack;
                RightRotate(tree, x.parent);
                x = tree.root;
            }
        }
    }
    x.color = PTNodeColorBlack;
    ResetSentinel();
}
