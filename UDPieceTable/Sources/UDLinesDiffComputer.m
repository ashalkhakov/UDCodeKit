/*---------------------------------------------------------------------------------------------
 *  Portions Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See LICENSE.txt for license information.
 *
 *  Objective-C port of VS Code's defaultLinesDiffComputer.ts and what it
 *  uses: algorithms/diffAlgorithm.ts, myersDiffAlgorithm.ts,
 *  dynamicProgrammingDiffing.ts, heuristicSequenceOptimizations.ts,
 *  lineSequence.ts, linesSliceCharSequence.ts and rangeMapping.ts's
 *  lineRangeMappingFromRangeMappings. Function for function, in their order.
 *--------------------------------------------------------------------------------------------*/

#import "UDLinesDiffComputer.h"
#include <math.h>

// ---------------------------------------------------------------------------
// MARK: - Results
// ---------------------------------------------------------------------------

@implementation UDRangeMapping
- (instancetype)initWithOriginalRange:(UDRange)original modifiedRange:(UDRange)modified {
    self = [super init];
    if (self) {
        _originalRange = original;
        _modifiedRange = modified;
    }
    return self;
}
- (NSString *)description {
    return [NSString stringWithFormat:@"{[%ld,%ld -> %ld,%ld]->[%ld,%ld -> %ld,%ld]}",
            (long)_originalRange.startLineNumber, (long)_originalRange.startColumn,
            (long)_originalRange.endLineNumber, (long)_originalRange.endColumn,
            (long)_modifiedRange.startLineNumber, (long)_modifiedRange.startColumn,
            (long)_modifiedRange.endLineNumber, (long)_modifiedRange.endColumn];
}
@end

@implementation UDDetailedLineRangeMapping
- (instancetype)initWithOriginal:(UDLineRange)original modified:(UDLineRange)modified
                    innerChanges:(NSArray<UDRangeMapping *> *)innerChanges {
    self = [super init];
    if (self) {
        _original = original;
        _modified = modified;
        _innerChanges = [innerChanges copy];
    }
    return self;
}
- (NSString *)description {
    return [NSString stringWithFormat:@"{[%ld,%ld)->[%ld,%ld)}",
            (long)_original.startLineNumber, (long)_original.endLineNumberExclusive,
            (long)_modified.startLineNumber, (long)_modified.endLineNumberExclusive];
}
@end

@interface UDLinesDiff ()
- (instancetype)initWithChanges:(NSArray<UDDetailedLineRangeMapping *> *)changes hitTimeout:(BOOL)hitTimeout;
@end

@implementation UDLinesDiff
- (instancetype)initWithChanges:(NSArray<UDDetailedLineRangeMapping *> *)changes hitTimeout:(BOOL)hitTimeout {
    self = [super init];
    if (self) {
        _changes = [changes copy];
        _hitTimeout = hitTimeout;
    }
    return self;
}
@end

// ---------------------------------------------------------------------------
// MARK: - Offset ranges, sequence diffs (diffAlgorithm.ts, offsetRange.ts)
// ---------------------------------------------------------------------------

typedef struct { NSInteger start, end; } UDOffsetRange;            // [start, end)
typedef struct { UDOffsetRange s1, s2; } UDSequenceDiff;
typedef struct { NSInteger o1, o2; } UDOffsetPair;

static inline UDOffsetRange UDOR(NSInteger start, NSInteger end) { return (UDOffsetRange){ start, end }; }
static inline BOOL UDOREmpty(UDOffsetRange r) { return r.start == r.end; }
static inline NSInteger UDORLength(UDOffsetRange r) { return r.end - r.start; }
static inline UDOffsetRange UDORJoin(UDOffsetRange a, UDOffsetRange b) { return UDOR(MIN(a.start, b.start), MAX(a.end, b.end)); }
static inline UDOffsetRange UDORDelta(UDOffsetRange r, NSInteger d) { return UDOR(r.start + d, r.end + d); }
/// [start, end) both have, when they overlap or touch.
static inline BOOL UDORIntersect(UDOffsetRange a, UDOffsetRange b, UDOffsetRange *out) {
    NSInteger start = MAX(a.start, b.start), end = MIN(a.end, b.end);
    if (start > end) return NO;
    if (out) *out = UDOR(start, end);
    return YES;
}
static inline BOOL UDORIntersects(UDOffsetRange a, UDOffsetRange b) { return MAX(a.start, b.start) < MIN(a.end, b.end); }

static inline UDSequenceDiff UDSD(UDOffsetRange s1, UDOffsetRange s2) { return (UDSequenceDiff){ s1, s2 }; }
static inline UDSequenceDiff UDSDSwap(UDSequenceDiff d) { return UDSD(d.s2, d.s1); }
static inline UDSequenceDiff UDSDJoin(UDSequenceDiff a, UDSequenceDiff b) { return UDSD(UDORJoin(a.s1, b.s1), UDORJoin(a.s2, b.s2)); }
static inline UDSequenceDiff UDSDDelta(UDSequenceDiff d, NSInteger o) { return UDSD(UDORDelta(d.s1, o), UDORDelta(d.s2, o)); }
static inline UDSequenceDiff UDSDDeltaStart(UDSequenceDiff d, NSInteger o) {
    return UDSD(UDOR(d.s1.start + o, d.s1.end), UDOR(d.s2.start + o, d.s2.end));
}
static inline UDSequenceDiff UDSDDeltaEnd(UDSequenceDiff d, NSInteger o) {
    return UDSD(UDOR(d.s1.start, d.s1.end + o), UDOR(d.s2.start, d.s2.end + o));
}
static inline BOOL UDSDIntersect(UDSequenceDiff a, UDSequenceDiff b, UDSequenceDiff *out) {
    UDOffsetRange i1, i2;
    if (!UDORIntersect(a.s1, b.s1, &i1) || !UDORIntersect(a.s2, b.s2, &i2)) return NO;
    if (out) *out = UDSD(i1, i2);
    return YES;
}
static inline UDOffsetPair UDSDStarts(UDSequenceDiff d) { return (UDOffsetPair){ d.s1.start, d.s2.start }; }
static inline UDOffsetPair UDSDEnds(UDSequenceDiff d) { return (UDOffsetPair){ d.s1.end, d.s2.end }; }
static inline UDSequenceDiff UDSDFromPairs(UDOffsetPair start, UDOffsetPair end) {
    return UDSD(UDOR(start.o1, end.o1), UDOR(start.o2, end.o2));
}

/// A growable array of sequence diffs.
@interface UDDiffs : NSObject {
@public
    NSMutableData *_data;
}
@end

@implementation UDDiffs
- (instancetype)init {
    self = [super init];
    if (self) _data = [NSMutableData data];
    return self;
}
@end

static inline NSInteger UDCount(UDDiffs *d) { return (NSInteger)(d->_data.length / sizeof(UDSequenceDiff)); }
static inline UDSequenceDiff *UDItems(UDDiffs *d) { return (UDSequenceDiff *)d->_data.mutableBytes; }
static inline UDSequenceDiff UDAt(UDDiffs *d, NSInteger i) { return UDItems(d)[i]; }
static inline UDSequenceDiff UDLast(UDDiffs *d) { return UDItems(d)[UDCount(d) - 1]; }
static inline void UDSet(UDDiffs *d, NSInteger i, UDSequenceDiff v) { UDItems(d)[i] = v; }
static inline void UDSetLast(UDDiffs *d, UDSequenceDiff v) { UDItems(d)[UDCount(d) - 1] = v; }
static inline void UDPush(UDDiffs *d, UDSequenceDiff v) { [d->_data appendBytes:&v length:sizeof v]; }
static void UDReverse(UDDiffs *d) {
    UDSequenceDiff *items = UDItems(d);
    for (NSInteger i = 0, j = UDCount(d) - 1; i < j; i++, j--) {
        UDSequenceDiff t = items[i];
        items[i] = items[j];
        items[j] = t;
    }
}

/// SequenceDiff.invert: the equal stretches between @a diffs.
static UDDiffs *UDInvert(UDDiffs *diffs, NSInteger doc1Length) {
    UDDiffs *result = [UDDiffs new];
    NSInteger count = UDCount(diffs);
    for (NSInteger i = 0; i <= count; i++) {
        BOOL hasA = i > 0, hasB = i < count;
        UDSequenceDiff a = hasA ? UDAt(diffs, i - 1) : (UDSequenceDiff){ { 0, 0 }, { 0, 0 } };
        UDSequenceDiff b = hasB ? UDAt(diffs, i) : (UDSequenceDiff){ { 0, 0 }, { 0, 0 } };
        UDOffsetPair start = hasA ? UDSDEnds(a) : (UDOffsetPair){ 0, 0 };
        UDOffsetPair end = hasB ? UDSDStarts(b)
                                : (UDOffsetPair){ doc1Length, (hasA ? a.s2.end - a.s1.end : 0) + doc1Length };
        UDPush(result, UDSDFromPairs(start, end));
    }
    return result;
}

typedef struct {
    UDDiffs *diffs;
    BOOL hitTimeout;
} UDDiffResult;

static UDDiffResult UDTrivial(NSInteger length1, NSInteger length2, BOOL timedOut) {
    UDDiffs *diffs = [UDDiffs new];
    UDPush(diffs, UDSD(UDOR(0, length1), UDOR(0, length2)));
    return (UDDiffResult){ diffs, timedOut };
}

/// ITimeout: DateTimeout, or none (limit 0).
typedef struct {
    NSTimeInterval start;
    NSTimeInterval limit;
    BOOL valid;
} UDTimeout;

static BOOL UDTimeoutIsValid(UDTimeout *timeout) {
    if (timeout->limit <= 0) return YES;
    if (timeout->valid && [NSDate timeIntervalSinceReferenceDate] - timeout->start >= timeout->limit) timeout->valid = NO;
    return timeout->valid;
}

// ---------------------------------------------------------------------------
// MARK: - Sequences (ISequence: lineSequence.ts, linesSliceCharSequence.ts)
// ---------------------------------------------------------------------------

/// JavaScript's white space (String.prototype.trim, /\s/).
static NSCharacterSet *UDJSWhitespace(void) {
    static NSCharacterSet *set;
    if (!set) {
        set = [NSCharacterSet characterSetWithCharactersInString:
            @"\t\n\v\f\r              "
            @"    　﻿"];
    }
    return set;
}

static NSString *UDTrimStart(NSString *s) {
    NSCharacterSet *ws = UDJSWhitespace();
    NSUInteger i = 0, n = s.length;
    while (i < n && [ws characterIsMember:[s characterAtIndex:i]]) i++;
    return i ? [s substringFromIndex:i] : s;
}

static NSString *UDTrimEnd(NSString *s) {
    NSCharacterSet *ws = UDJSWhitespace();
    NSUInteger n = s.length;
    while (n > 0 && [ws characterIsMember:[s characterAtIndex:n - 1]]) n--;
    return n < s.length ? [s substringToIndex:n] : s;
}

static NSString *UDTrim(NSString *s) { return UDTrimEnd(UDTrimStart(s)); }

/// A sequence of elements to diff: lines (their hashes) or characters.
@interface UDDiffSequence : NSObject {
@public
    const int32_t *_elements;
    NSInteger _length;
}
/// The higher, the better a place to split the sequence (at @a length).
- (NSInteger)boundaryScore:(NSInteger)length;
- (BOOL)isStronglyEqual:(NSInteger)offset1 :(NSInteger)offset2;
@end

@implementation UDDiffSequence
- (NSInteger)boundaryScore:(NSInteger)length { return 0; }
- (BOOL)isStronglyEqual:(NSInteger)offset1 :(NSInteger)offset2 { return _elements[offset1] == _elements[offset2]; }
@end

static NSInteger UDIndentation(NSString *s) {
    NSUInteger i = 0, n = s.length;
    while (i < n && ([s characterAtIndex:i] == ' ' || [s characterAtIndex:i] == '\t')) i++;
    return (NSInteger)i;
}

@interface UDLineSequence : UDDiffSequence
- (instancetype)initWithHashes:(NSData *)hashes lines:(NSArray<NSString *> *)lines;
- (NSString *)textIn:(UDOffsetRange)range;
@end

@implementation UDLineSequence {
    NSData *_hashes;
    NSArray<NSString *> *_lines;
}

- (instancetype)initWithHashes:(NSData *)hashes lines:(NSArray<NSString *> *)lines {
    self = [super init];
    if (self) {
        _hashes = hashes;
        _lines = lines;
        _elements = hashes.bytes;
        _length = (NSInteger)(hashes.length / sizeof(int32_t));
    }
    return self;
}

- (NSInteger)boundaryScore:(NSInteger)length {
    NSInteger before = length == 0 ? 0 : UDIndentation(_lines[length - 1]);
    NSInteger after = length == (NSInteger)_lines.count ? 0 : UDIndentation(_lines[length]);
    return 1000 - (before + after);
}

- (NSString *)textIn:(UDOffsetRange)range {
    return [[_lines subarrayWithRange:NSMakeRange(range.start, range.end - range.start)] componentsJoinedByString:@"\n"];
}

- (BOOL)isStronglyEqual:(NSInteger)offset1 :(NSInteger)offset2 {
    return [_lines[offset1] isEqualToString:_lines[offset2]];
}

@end

typedef NS_ENUM(NSInteger, UDCharCategory) {
    UDCharWordLower,
    UDCharWordUpper,
    UDCharWordNumber,
    UDCharEnd,
    UDCharOther,
    UDCharSeparator,
    UDCharSpace,
    UDCharLineBreakCR,
    UDCharLineBreakLF,
};

static UDCharCategory UDCategoryOf(NSInteger c) {
    if (c == '\n') return UDCharLineBreakLF;
    if (c == '\r') return UDCharLineBreakCR;
    if (c == ' ' || c == '\t') return UDCharSpace;
    if (c >= 'a' && c <= 'z') return UDCharWordLower;
    if (c >= 'A' && c <= 'Z') return UDCharWordUpper;
    if (c >= '0' && c <= '9') return UDCharWordNumber;
    if (c == -1) return UDCharEnd;
    if (c == ',' || c == ';') return UDCharSeparator;
    return UDCharOther;
}

static NSInteger UDCategoryScore(UDCharCategory category) {
    static const NSInteger scores[] = { 0, 0, 0, 10, 2, 30, 3, 10, 10 };
    return scores[category];
}

static inline BOOL UDIsWordChar(NSInteger c) {
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9');
}

/// The characters of lines @a range covers, "\n" between them (without each
/// line's leading and trailing white space when it is no change).
@interface UDLinesSliceCharSequence : UDDiffSequence
- (instancetype)initWithLines:(NSArray<NSString *> *)lines range:(UDRange)range considerWhitespaceChanges:(BOOL)considerWhitespace;
- (NSString *)textIn:(UDOffsetRange)range;
- (UDPosition)translateOffset:(NSInteger)offset left:(BOOL)left;
- (UDRange)translateRange:(UDOffsetRange)range;
- (BOOL)findWordContaining:(NSInteger)offset range:(UDOffsetRange *)range;
- (NSInteger)countLinesIn:(UDOffsetRange)range;
- (UDOffsetRange)extendToFullLines:(UDOffsetRange)range;
@end

@implementation UDLinesSliceCharSequence {
    NSMutableData *_store;
    NSMutableData *_firstElementOffsetByLineIdx;   // NSInteger
    NSMutableData *_lineStartOffsets;
    NSMutableData *_trimmedWsLengthsByLineIdx;
    UDRange _range;
}

static inline void UDAppendInteger(NSMutableData *data, NSInteger v) { [data appendBytes:&v length:sizeof v]; }
static inline const NSInteger *UDIntegers(NSData *data) { return data.bytes; }
static inline NSInteger UDIntegerCount(NSData *data) { return (NSInteger)(data.length / sizeof(NSInteger)); }

- (instancetype)initWithLines:(NSArray<NSString *> *)lines range:(UDRange)range considerWhitespaceChanges:(BOOL)considerWhitespace {
    self = [super init];
    if (self) {
        _range = range;
        _store = [NSMutableData data];
        _firstElementOffsetByLineIdx = [NSMutableData data];
        _lineStartOffsets = [NSMutableData data];
        _trimmedWsLengthsByLineIdx = [NSMutableData data];
        UDAppendInteger(_firstElementOffsetByLineIdx, 0);
        NSInteger count = 0;
        for (NSInteger lineNumber = range.startLineNumber; lineNumber <= range.endLineNumber; lineNumber++) {
            NSString *line = lines[lineNumber - 1];
            NSInteger lineStartOffset = 0;
            if (lineNumber == range.startLineNumber && range.startColumn > 1) {
                lineStartOffset = range.startColumn - 1;
                line = [line substringFromIndex:MIN((NSUInteger)lineStartOffset, line.length)];
            }
            UDAppendInteger(_lineStartOffsets, lineStartOffset);

            NSInteger trimmedWsLength = 0;
            if (!considerWhitespace) {
                NSString *trimmedStart = UDTrimStart(line);
                trimmedWsLength = (NSInteger)(line.length - trimmedStart.length);
                line = UDTrimEnd(trimmedStart);
            }
            UDAppendInteger(_trimmedWsLengthsByLineIdx, trimmedWsLength);

            NSInteger lineLength = lineNumber == range.endLineNumber
                ? MIN(range.endColumn - 1 - lineStartOffset - trimmedWsLength, (NSInteger)line.length)
                : (NSInteger)line.length;
            for (NSInteger i = 0; i < lineLength; i++) {
                int32_t c = [line characterAtIndex:(NSUInteger)i];
                [_store appendBytes:&c length:sizeof c];
                count++;
            }
            if (lineNumber < range.endLineNumber) {
                int32_t lf = '\n';
                [_store appendBytes:&lf length:sizeof lf];
                count++;
                UDAppendInteger(_firstElementOffsetByLineIdx, count);
            }
        }
        _elements = _store.bytes;
        _length = count;
    }
    return self;
}

- (NSString *)textIn:(UDOffsetRange)range {
    NSMutableString *text = [NSMutableString stringWithCapacity:(NSUInteger)MAX(0, UDORLength(range))];
    for (NSInteger i = range.start; i < range.end; i++) [text appendFormat:@"%C", (unichar)_elements[i]];
    return text;
}

- (NSInteger)boundaryScore:(NSInteger)length {
    UDCharCategory prev = UDCategoryOf(length > 0 ? _elements[length - 1] : -1);
    UDCharCategory next = UDCategoryOf(length < _length ? _elements[length] : -1);
    if (prev == UDCharLineBreakCR && next == UDCharLineBreakLF) return 0;   // not between \r and \n
    if (prev == UDCharLineBreakLF) return 150;                              // the line break before the change
    NSInteger score = 0;
    if (prev != next) {
        score += 10;
        if (prev == UDCharWordLower && next == UDCharWordUpper) score += 1;
    }
    return score + UDCategoryScore(prev) + UDCategoryScore(next);
}

- (UDPosition)translateOffset:(NSInteger)offset left:(BOOL)left {
    const NSInteger *firsts = UDIntegers(_firstElementOffsetByLineIdx);
    NSInteger count = UDIntegerCount(_firstElementOffsetByLineIdx);
    // the last line that starts at or before offset (findLastIdxMonotonous)
    NSInteger lo = 0, hi = count;
    while (lo < hi) {
        NSInteger mid = (lo + hi) / 2;
        if (firsts[mid] <= offset) lo = mid + 1;
        else hi = mid;
    }
    NSInteger i = lo - 1;
    NSInteger lineOffset = offset - firsts[i];
    NSInteger trimmed = (lineOffset == 0 && left) ? 0 : UDIntegers(_trimmedWsLengthsByLineIdx)[i];
    return (UDPosition){ _range.startLineNumber + i, 1 + UDIntegers(_lineStartOffsets)[i] + lineOffset + trimmed };
}

static inline BOOL UDPositionIsBefore(UDPosition a, UDPosition b) {
    return a.line < b.line || (a.line == b.line && a.column < b.column);
}

- (UDRange)translateRange:(UDOffsetRange)range {
    UDPosition pos1 = [self translateOffset:range.start left:NO];
    UDPosition pos2 = [self translateOffset:range.end left:YES];
    if (UDPositionIsBefore(pos2, pos1)) return PTRangeMake(pos2.line, pos2.column, pos2.line, pos2.column);
    return PTRangeMake(pos1.line, pos1.column, pos2.line, pos2.column);
}

- (BOOL)findWordContaining:(NSInteger)offset range:(UDOffsetRange *)range {
    if (offset < 0 || offset >= _length || !UDIsWordChar(_elements[offset])) return NO;
    NSInteger start = offset;
    while (start > 0 && UDIsWordChar(_elements[start - 1])) start--;
    NSInteger end = offset;
    while (end < _length && UDIsWordChar(_elements[end])) end++;
    *range = UDOR(start, end);
    return YES;
}

- (NSInteger)countLinesIn:(UDOffsetRange)range {
    return [self translateOffset:range.end left:NO].line - [self translateOffset:range.start left:NO].line;
}

- (UDOffsetRange)extendToFullLines:(UDOffsetRange)range {
    const NSInteger *firsts = UDIntegers(_firstElementOffsetByLineIdx);
    NSInteger count = UDIntegerCount(_firstElementOffsetByLineIdx);
    NSInteger start = 0, end = _length;
    for (NSInteger i = 0; i < count; i++) {
        if (firsts[i] <= range.start) start = firsts[i];
    }
    for (NSInteger i = 0; i < count; i++) {
        if (range.end <= firsts[i]) {
            end = firsts[i];
            break;
        }
    }
    return UDOR(start, end);
}

@end

// ---------------------------------------------------------------------------
// MARK: - Myers (myersDiffAlgorithm.ts): O(ND)
// ---------------------------------------------------------------------------

typedef struct {
    NSInteger prev;          // index in the pool; -1: none
    NSInteger x, y, length;
} UDSnakePath;

/// The x after the diagonal (the equal elements) from (x, y).
static NSInteger UDXAfterSnake(const int32_t *X, NSInteger n, const int32_t *Y, NSInteger m, NSInteger x, NSInteger y) {
    while (x < n && y >= 0 && y < m && X[x] == Y[y]) {
        x++;
        y++;
    }
    return x;
}

/// A snake path added to @a pool: its index.
static NSInteger UDNewSnakePath(NSMutableData *pool, NSInteger prev, NSInteger x, NSInteger y, NSInteger length) {
    UDSnakePath path = { prev, x, y, length };
    [pool appendBytes:&path length:sizeof path];
    return (NSInteger)(pool.length / sizeof(UDSnakePath)) - 1;
}

static UDDiffResult UDMyers(UDDiffSequence *seqX, UDDiffSequence *seqY, UDTimeout *timeout) {
    NSInteger n = seqX->_length, m = seqY->_length;
    if (n == 0 || m == 0) return UDTrivial(n, m, NO);
    const int32_t *X = seqX->_elements, *Y = seqY->_elements;

    // V[k] and paths[k], k from -(m+2) to n+2
    NSInteger offset = m + 3, size = n + m + 7;
    NSMutableData *vData = [NSMutableData dataWithLength:(NSUInteger)size * sizeof(NSInteger)];
    NSMutableData *pathData = [NSMutableData dataWithLength:(NSUInteger)size * sizeof(NSInteger)];
    NSInteger *V = (NSInteger *)vData.mutableBytes + offset;
    NSInteger *paths = (NSInteger *)pathData.mutableBytes + offset;
    for (NSInteger i = -offset; i < size - offset; i++) paths[i] = -1;
    NSMutableData *pool = [NSMutableData data];

    V[0] = UDXAfterSnake(X, n, Y, m, 0, 0);
    paths[0] = V[0] == 0 ? -1 : UDNewSnakePath(pool, -1, 0, 0, V[0]);

    NSInteger d = 0, k = 0;
    BOOL done = NO;
    while (!done) {
        d++;
        if (!UDTimeoutIsValid(timeout)) return UDTrivial(n, m, YES);
        NSInteger lowerBound = -MIN(d, m + (d % 2));
        NSInteger upperBound = MIN(d, n + (d % 2));
        for (k = lowerBound; k <= upperBound; k += 2) {
            NSInteger maxXofDLineTop = k == upperBound ? -1 : V[k + 1];
            NSInteger maxXofDLineLeft = k == lowerBound ? -1 : V[k - 1] + 1;
            NSInteger x = MIN(MAX(maxXofDLineTop, maxXofDLineLeft), n);
            NSInteger y = x - k;
            if (x > n || y > m) continue;
            NSInteger newMaxX = UDXAfterSnake(X, n, Y, m, x, y);
            V[k] = newMaxX;
            NSInteger lastPath = x == maxXofDLineTop ? paths[k + 1] : paths[k - 1];
            paths[k] = newMaxX != x ? UDNewSnakePath(pool, lastPath, x, y, newMaxX - x) : lastPath;
            if (V[k] == n && V[k] - k == m) {
                done = YES;
                break;
            }
        }
    }

    UDDiffs *result = [UDDiffs new];
    NSInteger path = paths[k];
    NSInteger lastAligningPosS1 = n, lastAligningPosS2 = m;
    while (YES) {
        const UDSnakePath *p = path >= 0 ? (const UDSnakePath *)pool.bytes + path : NULL;
        NSInteger endX = p ? p->x + p->length : 0;
        NSInteger endY = p ? p->y + p->length : 0;
        if (endX != lastAligningPosS1 || endY != lastAligningPosS2) {
            UDPush(result, UDSD(UDOR(endX, lastAligningPosS1), UDOR(endY, lastAligningPosS2)));
        }
        if (!p) break;
        lastAligningPosS1 = p->x;
        lastAligningPosS2 = p->y;
        path = p->prev;
    }
    UDReverse(result);
    return (UDDiffResult){ result, NO };
}

// ---------------------------------------------------------------------------
// MARK: - Dynamic programming (dynamicProgrammingDiffing.ts): O(MN), scored
// ---------------------------------------------------------------------------

/// The score of equal lines (defaultLinesDiffComputer.ts's): the longer, the
/// better; an empty one little; lines equal only trimmed, less than one.
static double UDLineEqualityScore(NSArray<NSString *> *originalLines, NSArray<NSString *> *modifiedLines,
                                  NSInteger offset1, NSInteger offset2) {
    NSString *modified = modifiedLines[offset2];
    if (![originalLines[offset1] isEqualToString:modified]) return 0.99;
    return modified.length == 0 ? 0.1 : 1 + log(1 + (double)modified.length);
}

/// An aligned pair, the diff since the last one (backtracking).
static void UDReportAligning(UDDiffs *result, NSInteger *lastAligningPosS1, NSInteger *lastAligningPosS2,
                             NSInteger s1, NSInteger s2) {
    if (s1 + 1 != *lastAligningPosS1 || s2 + 1 != *lastAligningPosS2) {
        UDPush(result, UDSD(UDOR(s1 + 1, *lastAligningPosS1), UDOR(s2 + 1, *lastAligningPosS2)));
    }
    *lastAligningPosS1 = s1;
    *lastAligningPosS2 = s2;
}

/// Equal elements score 1, or, given the lines (sequences of lines),
/// UDLineEqualityScore.
static UDDiffResult UDDynamicProgramming(UDDiffSequence *sequence1, UDDiffSequence *sequence2, UDTimeout *timeout,
                                         NSArray<NSString *> *_Nullable originalLines,
                                         NSArray<NSString *> *_Nullable modifiedLines) {
    NSInteger n = sequence1->_length, m = sequence2->_length;
    if (n == 0 || m == 0) return UDTrivial(n, m, NO);
    const int32_t *A = sequence1->_elements, *B = sequence2->_elements;

    NSMutableData *lcsData = [NSMutableData dataWithLength:(NSUInteger)(n * m) * sizeof(double)];
    NSMutableData *directionsData = [NSMutableData dataWithLength:(NSUInteger)(n * m)];
    NSMutableData *lengthsData = [NSMutableData dataWithLength:(NSUInteger)(n * m) * sizeof(int32_t)];
    double *lcsLengths = lcsData.mutableBytes;
    uint8_t *directions = directionsData.mutableBytes;
    int32_t *lengths = lengthsData.mutableBytes;
#define UD_AT(x, y) ((x) + (y) * n)

    for (NSInteger s1 = 0; s1 < n; s1++) {
        if (!UDTimeoutIsValid(timeout)) return UDTrivial(n, m, YES);
        for (NSInteger s2 = 0; s2 < m; s2++) {
            double horizontalLen = s1 == 0 ? 0 : lcsLengths[UD_AT(s1 - 1, s2)];
            double verticalLen = s2 == 0 ? 0 : lcsLengths[UD_AT(s1, s2 - 1)];

            double extendedSeqScore;
            if (A[s1] == B[s2]) {
                extendedSeqScore = (s1 == 0 || s2 == 0) ? 0 : lcsLengths[UD_AT(s1 - 1, s2 - 1)];
                if (s1 > 0 && s2 > 0 && directions[UD_AT(s1 - 1, s2 - 1)] == 3) {
                    extendedSeqScore += lengths[UD_AT(s1 - 1, s2 - 1)];   // consecutive diagonals preferred
                }
                extendedSeqScore += originalLines ? UDLineEqualityScore(originalLines, modifiedLines, s1, s2) : 1;
            } else {
                extendedSeqScore = -1;
            }

            double newValue = MAX(MAX(horizontalLen, verticalLen), extendedSeqScore);
            if (newValue == extendedSeqScore) {
                int32_t prevLen = s1 > 0 && s2 > 0 ? lengths[UD_AT(s1 - 1, s2 - 1)] : 0;
                lengths[UD_AT(s1, s2)] = prevLen + 1;
                directions[UD_AT(s1, s2)] = 3;
            } else if (newValue == horizontalLen) {
                lengths[UD_AT(s1, s2)] = 0;
                directions[UD_AT(s1, s2)] = 1;
            } else if (newValue == verticalLen) {
                lengths[UD_AT(s1, s2)] = 0;
                directions[UD_AT(s1, s2)] = 2;
            }
            lcsLengths[UD_AT(s1, s2)] = newValue;
        }
    }

    UDDiffs *result = [UDDiffs new];
    NSInteger lastAligningPosS1 = n, lastAligningPosS2 = m;
    NSInteger s1 = n - 1, s2 = m - 1;
    while (s1 >= 0 && s2 >= 0) {
        if (directions[UD_AT(s1, s2)] == 3) {
            UDReportAligning(result, &lastAligningPosS1, &lastAligningPosS2, s1, s2);
            s1--;
            s2--;
        } else if (directions[UD_AT(s1, s2)] == 1) {
            s1--;
        } else {
            s2--;
        }
    }
#undef UD_AT
    UDReportAligning(result, &lastAligningPosS1, &lastAligningPosS2, -1, -1);
    UDReverse(result);
    return (UDDiffResult){ result, NO };
}

// ---------------------------------------------------------------------------
// MARK: - Heuristics (heuristicSequenceOptimizations.ts)
// ---------------------------------------------------------------------------

/// Moved left as far as they go and joined, then right.
static UDDiffs *UDJoinSequenceDiffsByShifting(UDDiffSequence *sequence1, UDDiffSequence *sequence2, UDDiffs *sequenceDiffs) {
    if (UDCount(sequenceDiffs) == 0) return sequenceDiffs;
    const int32_t *e1 = sequence1->_elements, *e2 = sequence2->_elements;

    UDDiffs *result = [UDDiffs new];
    UDPush(result, UDAt(sequenceDiffs, 0));
    for (NSInteger i = 1; i < UDCount(sequenceDiffs); i++) {
        UDSequenceDiff prevResult = UDLast(result);
        UDSequenceDiff cur = UDAt(sequenceDiffs, i);
        if (UDOREmpty(cur.s1) || UDOREmpty(cur.s2)) {
            NSInteger length = cur.s1.start - prevResult.s1.end;
            NSInteger d;
            for (d = 1; d <= length; d++) {
                if (e1[cur.s1.start - d] != e1[cur.s1.end - d] || e2[cur.s2.start - d] != e2[cur.s2.end - d]) break;
            }
            d--;
            if (d == length) {
                UDSetLast(result, UDSD(UDOR(prevResult.s1.start, cur.s1.end - length),
                                       UDOR(prevResult.s2.start, cur.s2.end - length)));
                continue;
            }
            cur = UDSDDelta(cur, -d);
        }
        UDPush(result, cur);
    }

    UDDiffs *result2 = [UDDiffs new];
    for (NSInteger i = 0; i < UDCount(result) - 1; i++) {
        UDSequenceDiff nextResult = UDAt(result, i + 1);
        UDSequenceDiff cur = UDAt(result, i);
        if (UDOREmpty(cur.s1) || UDOREmpty(cur.s2)) {
            NSInteger length = nextResult.s1.start - cur.s1.end;
            NSInteger d;
            for (d = 0; d < length; d++) {
                if (![sequence1 isStronglyEqual:cur.s1.start + d :cur.s1.end + d] ||
                    ![sequence2 isStronglyEqual:cur.s2.start + d :cur.s2.end + d]) {
                    break;
                }
            }
            if (d == length) {
                UDSet(result, i + 1, UDSD(UDOR(cur.s1.start + length, nextResult.s1.end),
                                          UDOR(cur.s2.start + length, nextResult.s2.end)));
                continue;
            }
            if (d > 0) cur = UDSDDelta(cur, d);
        }
        UDPush(result2, cur);
    }
    if (UDCount(result) > 0) UDPush(result2, UDLast(result));
    return result2;
}

static UDSequenceDiff UDShiftDiffToBetterPosition(UDSequenceDiff diff, UDDiffSequence *sequence1, UDDiffSequence *sequence2,
                                                  UDOffsetRange seq1ValidRange, UDOffsetRange seq2ValidRange) {
    const NSInteger maxShiftLimit = 100;
    NSInteger deltaBefore = 1;
    while (diff.s1.start - deltaBefore >= seq1ValidRange.start &&
           diff.s2.start - deltaBefore >= seq2ValidRange.start &&
           [sequence2 isStronglyEqual:diff.s2.start - deltaBefore :diff.s2.end - deltaBefore] && deltaBefore < maxShiftLimit) {
        deltaBefore++;
    }
    deltaBefore--;

    NSInteger deltaAfter = 0;
    while (diff.s1.start + deltaAfter < seq1ValidRange.end &&
           diff.s2.end + deltaAfter < seq2ValidRange.end &&
           [sequence2 isStronglyEqual:diff.s2.start + deltaAfter :diff.s2.end + deltaAfter] && deltaAfter < maxShiftLimit) {
        deltaAfter++;
    }
    if (deltaBefore == 0 && deltaAfter == 0) return diff;

    NSInteger bestDelta = 0, bestScore = -1;
    for (NSInteger delta = -deltaBefore; delta <= deltaAfter; delta++) {
        NSInteger score = [sequence1 boundaryScore:diff.s1.start + delta] +
                          [sequence2 boundaryScore:diff.s2.start + delta] +
                          [sequence2 boundaryScore:diff.s2.end + delta];
        if (score > bestScore) {
            bestScore = score;
            bestDelta = delta;
        }
    }
    return UDSDDelta(diff, bestDelta);
}

/// Insertions and deletions moved to where they split best (white space,
/// line breaks).
static UDDiffs *UDShiftSequenceDiffs(UDDiffSequence *sequence1, UDDiffSequence *sequence2, UDDiffs *sequenceDiffs) {
    NSInteger count = UDCount(sequenceDiffs);
    for (NSInteger i = 0; i < count; i++) {
        BOOL hasPrev = i > 0, hasNext = i + 1 < count;
        UDSequenceDiff diff = UDAt(sequenceDiffs, i);
        UDSequenceDiff prev = hasPrev ? UDAt(sequenceDiffs, i - 1) : diff;
        UDSequenceDiff next = hasNext ? UDAt(sequenceDiffs, i + 1) : diff;
        UDOffsetRange seq1ValidRange = UDOR(hasPrev ? prev.s1.end + 1 : 0, hasNext ? next.s1.start - 1 : sequence1->_length);
        UDOffsetRange seq2ValidRange = UDOR(hasPrev ? prev.s2.end + 1 : 0, hasNext ? next.s2.start - 1 : sequence2->_length);
        if (UDOREmpty(diff.s1)) {
            UDSet(sequenceDiffs, i, UDShiftDiffToBetterPosition(diff, sequence1, sequence2, seq1ValidRange, seq2ValidRange));
        } else if (UDOREmpty(diff.s2)) {
            UDSet(sequenceDiffs, i, UDSDSwap(UDShiftDiffToBetterPosition(UDSDSwap(diff), sequence2, sequence1,
                                                                          seq2ValidRange, seq1ValidRange)));
        }
    }
    return sequenceDiffs;
}

static UDDiffs *UDOptimizeSequenceDiffs(UDDiffSequence *sequence1, UDDiffSequence *sequence2, UDDiffs *sequenceDiffs) {
    UDDiffs *result = sequenceDiffs;
    result = UDJoinSequenceDiffsByShifting(sequence1, sequence2, result);
    result = UDJoinSequenceDiffsByShifting(sequence1, sequence2, result);   // twice: sometimes better
    result = UDShiftSequenceDiffs(sequence1, sequence2, result);
    return result;
}

static UDDiffs *UDRemoveShortMatches(UDDiffs *sequenceDiffs) {
    UDDiffs *result = [UDDiffs new];
    for (NSInteger i = 0; i < UDCount(sequenceDiffs); i++) {
        UDSequenceDiff s = UDAt(sequenceDiffs, i);
        if (UDCount(result) == 0) {
            UDPush(result, s);
            continue;
        }
        UDSequenceDiff last = UDLast(result);
        if (s.s1.start - last.s1.end <= 2 || s.s2.start - last.s2.end <= 2) {
            UDSetLast(result, UDSDJoin(last, s));
        } else {
            UDPush(result, s);
        }
    }
    return result;
}

static UDDiffs *UDMergeSequenceDiffs(UDDiffs *sequenceDiffs1, UDDiffs *sequenceDiffs2) {
    UDDiffs *result = [UDDiffs new];
    NSInteger i1 = 0, i2 = 0, n1 = UDCount(sequenceDiffs1), n2 = UDCount(sequenceDiffs2);
    while (i1 < n1 || i2 < n2) {
        UDSequenceDiff next;
        if (i1 < n1 && (i2 >= n2 || UDAt(sequenceDiffs1, i1).s1.start < UDAt(sequenceDiffs2, i2).s1.start)) {
            next = UDAt(sequenceDiffs1, i1++);
        } else {
            next = UDAt(sequenceDiffs2, i2++);
        }
        if (UDCount(result) > 0 && UDLast(result).s1.end >= next.s1.start) {
            UDSetLast(result, UDSDJoin(UDLast(result), next));
        } else {
            UDPush(result, next);
        }
    }
    return result;
}

/// extendDiffsToEntireWordIfAppropriate's scanWord: the words at @a pair,
/// joined with the next equal stretches' words they reach (taken from the
/// queue @a equalMappings, from *head); the whole of them a change of its
/// own when they are mostly changed.
static void UDScanWord(UDLinesSliceCharSequence *sequence1, UDLinesSliceCharSequence *sequence2,
                       UDDiffs *equalMappings, NSInteger *head, UDDiffs *additional, UDOffsetPair *lastPoint,
                       UDOffsetPair pair, UDSequenceDiff equalMapping) {
    if (pair.o1 < lastPoint->o1 || pair.o2 < lastPoint->o2) return;
    UDOffsetRange w1, w2;
    if (![sequence1 findWordContaining:pair.o1 range:&w1] || ![sequence2 findWordContaining:pair.o2 range:&w2]) return;
    UDSequenceDiff w = UDSD(w1, w2);
    UDSequenceDiff equalPart = UDSD(UDOR(0, 0), UDOR(0, 0));
    UDSDIntersect(w, equalMapping, &equalPart);
    NSInteger equalChars1 = UDORLength(equalPart.s1), equalChars2 = UDORLength(equalPart.s2);

    while (*head < UDCount(equalMappings)) {
        UDSequenceDiff next = UDAt(equalMappings, *head);
        if (!UDORIntersects(next.s1, w.s1) && !UDORIntersects(next.s2, w.s2)) break;
        UDOffsetRange v1, v2;
        if (![sequence1 findWordContaining:next.s1.start range:&v1] ||
            ![sequence2 findWordContaining:next.s2.start range:&v2]) {
            break;
        }
        UDSequenceDiff v = UDSD(v1, v2);
        UDSequenceDiff part = UDSD(UDOR(0, 0), UDOR(0, 0));
        UDSDIntersect(v, next, &part);
        equalChars1 += UDORLength(part.s1);
        equalChars2 += UDORLength(part.s2);
        w = UDSDJoin(w, v);
        if (w.s1.end >= next.s1.end) {
            (*head)++;                                // the word goes beyond the equal stretch
        } else {
            break;
        }
    }

    if ((double)(equalChars1 + equalChars2) < (double)(UDORLength(w.s1) + UDORLength(w.s2)) * 2.0 / 3.0) {
        UDPush(additional, w);
    }
    *lastPoint = UDSDEnds(w);
}

/// A change in a word that is mostly changed: the whole word.
static UDDiffs *UDExtendDiffsToEntireWordIfAppropriate(UDLinesSliceCharSequence *sequence1, UDLinesSliceCharSequence *sequence2,
                                                      UDDiffs *sequenceDiffs) {
    UDDiffs *equalMappings = UDInvert(sequenceDiffs, sequence1->_length);
    NSInteger head = 0;                               // equalMappings, a queue
    UDDiffs *additional = [UDDiffs new];
    UDOffsetPair lastPoint = { 0, 0 };
    while (head < UDCount(equalMappings)) {
        UDSequenceDiff next = UDAt(equalMappings, head++);
        if (UDOREmpty(next.s1)) continue;
        UDScanWord(sequence1, sequence2, equalMappings, &head, additional, &lastPoint, UDSDStarts(next), next);
        UDOffsetPair end = UDSDEnds(next);
        // equal there, as the stretch is not empty
        UDScanWord(sequence1, sequence2, equalMappings, &head, additional, &lastPoint, (UDOffsetPair){ end.o1 - 1, end.o2 - 1 }, next);
    }
    return UDMergeSequenceDiffs(sequenceDiffs, additional);
}

static NSString *UDWithoutWhitespace(NSString *text) {
    return [[text componentsSeparatedByCharactersInSet:UDJSWhitespace()] componentsJoinedByString:@""];
}

static UDDiffs *UDRemoveVeryShortMatchingLinesBetweenDiffs(UDLineSequence *sequence1, UDDiffs *sequenceDiffs) {
    UDDiffs *diffs = sequenceDiffs;
    if (UDCount(diffs) == 0) return diffs;
    NSInteger counter = 0;
    BOOL shouldRepeat;
    do {
        shouldRepeat = NO;
        UDDiffs *result = [UDDiffs new];
        UDPush(result, UDAt(diffs, 0));
        for (NSInteger i = 1; i < UDCount(diffs); i++) {
            UDSequenceDiff cur = UDAt(diffs, i);
            UDSequenceDiff lastResult = UDLast(result);
            NSString *unchangedText = [sequence1 textIn:UDOR(lastResult.s1.end, cur.s1.start)];
            BOOL shouldJoin = UDWithoutWhitespace(unchangedText).length <= 4 &&
                (UDORLength(lastResult.s1) + UDORLength(lastResult.s2) > 5 || UDORLength(cur.s1) + UDORLength(cur.s2) > 5);
            if (shouldJoin) {
                shouldRepeat = YES;
                UDSetLast(result, UDSDJoin(lastResult, cur));
            } else {
                UDPush(result, cur);
            }
        }
        diffs = result;
    } while (counter++ < 10 && shouldRepeat);
    return diffs;
}

static const double UDLongDiffCap = 2 * 40 + 50;

static inline double UDCapped(double v) {
    return MIN(v, UDLongDiffCap);
}

/// Two long changes with a little unchanged text between them: one change.
static BOOL UDShouldJoinLongDiffs(UDLinesSliceCharSequence *sequence1, UDLinesSliceCharSequence *sequence2,
                                  UDSequenceDiff before, UDSequenceDiff after) {
    UDOffsetRange unchangedRange = UDOR(before.s1.end, after.s1.start);
    NSInteger unchangedLineCount = [sequence1 countLinesIn:unchangedRange];
    if (unchangedLineCount > 5 || UDORLength(unchangedRange) > 500) return NO;
    NSString *unchangedText = UDTrim([sequence1 textIn:unchangedRange]);
    if (unchangedText.length > 20 ||
        [unchangedText rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"\r\n"]].location != NSNotFound) {
        return NO;
    }
    double beforeLineCount1 = [sequence1 countLinesIn:before.s1], beforeSeq1Length = UDORLength(before.s1);
    double beforeLineCount2 = [sequence2 countLinesIn:before.s2], beforeSeq2Length = UDORLength(before.s2);
    double afterLineCount1 = [sequence1 countLinesIn:after.s1], afterSeq1Length = UDORLength(after.s1);
    double afterLineCount2 = [sequence2 countLinesIn:after.s2], afterSeq2Length = UDORLength(after.s2);
    return pow(pow(UDCapped(beforeLineCount1 * 40 + beforeSeq1Length), 1.5) + pow(UDCapped(beforeLineCount2 * 40 + beforeSeq2Length), 1.5), 1.5)
         + pow(pow(UDCapped(afterLineCount1 * 40 + afterSeq1Length), 1.5) + pow(UDCapped(afterLineCount2 * 40 + afterSeq2Length), 1.5), 1.5)
         > pow(pow(UDLongDiffCap, 1.5), 1.5) * 1.3;
}

/// A long change's short prefix or suffix (white space and up to three
/// characters on its line): changed too.
static BOOL UDShouldMarkAsChanged(NSString *text, UDSequenceDiff change) {
    return text.length > 0 && UDTrim(text).length <= 3 && UDORLength(change.s1) + UDORLength(change.s2) > 100;
}

static UDDiffs *UDRemoveVeryShortMatchingTextBetweenLongDiffs(UDLinesSliceCharSequence *sequence1, UDLinesSliceCharSequence *sequence2,
                                                             UDDiffs *sequenceDiffs) {
    UDDiffs *diffs = sequenceDiffs;
    if (UDCount(diffs) == 0) return diffs;

    NSInteger counter = 0;
    BOOL shouldRepeat;
    do {
        shouldRepeat = NO;
        UDDiffs *result = [UDDiffs new];
        UDPush(result, UDAt(diffs, 0));
        for (NSInteger i = 1; i < UDCount(diffs); i++) {
            UDSequenceDiff cur = UDAt(diffs, i);
            UDSequenceDiff lastResult = UDLast(result);
            if (UDShouldJoinLongDiffs(sequence1, sequence2, lastResult, cur)) {
                shouldRepeat = YES;
                UDSetLast(result, UDSDJoin(lastResult, cur));
            } else {
                UDPush(result, cur);
            }
        }
        diffs = result;
    } while (counter++ < 10 && shouldRepeat);

    // short prefixes and suffixes of long changes: changed too
    UDDiffs *newDiffs = [UDDiffs new];
    NSInteger count = UDCount(diffs);
    for (NSInteger i = 0; i < count; i++) {
        UDSequenceDiff cur = UDAt(diffs, i);
        UDSequenceDiff newDiff = cur;
        UDOffsetRange fullRange1 = [sequence1 extendToFullLines:cur.s1];
        NSString *prefix = [sequence1 textIn:UDOR(fullRange1.start, cur.s1.start)];
        if (UDShouldMarkAsChanged(prefix, cur)) newDiff = UDSDDeltaStart(newDiff, -(NSInteger)prefix.length);
        NSString *suffix = [sequence1 textIn:UDOR(cur.s1.end, fullRange1.end)];
        if (UDShouldMarkAsChanged(suffix, cur)) newDiff = UDSDDeltaEnd(newDiff, (NSInteger)suffix.length);

        UDOffsetPair start = i > 0 ? UDSDEnds(UDAt(diffs, i - 1)) : (UDOffsetPair){ 0, 0 };
        UDOffsetPair end = i + 1 < count ? UDSDStarts(UDAt(diffs, i + 1)) : (UDOffsetPair){ NSIntegerMax / 4, NSIntegerMax / 4 };
        UDSequenceDiff result = newDiff;
        UDSDIntersect(newDiff, UDSDFromPairs(start, end), &result);
        if (UDCount(newDiffs) > 0 && UDSDStarts(result).o1 == UDSDEnds(UDLast(newDiffs)).o1 &&
            UDSDStarts(result).o2 == UDSDEnds(UDLast(newDiffs)).o2) {
            UDSetLast(newDiffs, UDSDJoin(UDLast(newDiffs), result));
        } else {
            UDPush(newDiffs, result);
        }
    }
    return newDiffs;
}

// ---------------------------------------------------------------------------
// MARK: - The computer (defaultLinesDiffComputer.ts)
// ---------------------------------------------------------------------------

static inline UDLineRange UDLineRangeJoin(UDLineRange a, UDLineRange b) {
    return UDLineRangeMake(MIN(a.startLineNumber, b.startLineNumber), MAX(a.endLineNumberExclusive, b.endLineNumberExclusive));
}

static inline BOOL UDLineRangeIntersectsOrTouches(UDLineRange a, UDLineRange b) {
    return a.startLineNumber <= b.endLineNumberExclusive && b.startLineNumber <= a.endLineNumberExclusive;
}

static UDPosition UDNormalizePosition(UDPosition position, NSArray<NSString *> *content) {
    if (position.line < 1) return (UDPosition){ 1, 1 };
    if (position.line > (NSInteger)content.count) {
        return (UDPosition){ (NSInteger)content.count, (NSInteger)content.lastObject.length + 1 };
    }
    NSInteger length = (NSInteger)content[position.line - 1].length;
    if (position.column > length + 1) return (UDPosition){ position.line, length + 1 };
    return position;
}

static inline UDRange UDRangeFromPositions(UDPosition a, UDPosition b) {
    if (UDPositionIsBefore(b, a)) return PTRangeMake(b.line, b.column, a.line, a.column);
    return PTRangeMake(a.line, a.column, b.line, b.column);
}

static inline BOOL UDIsValidLineNumber(NSInteger lineNumber, NSArray *lines) {
    return lineNumber >= 1 && lineNumber <= (NSInteger)lines.count;
}

/// LineRangeMapping.toRangeMapping2: the lines as a range of characters.
static void UDToRangeMapping2(UDLineRange original, UDLineRange modified,
                              NSArray<NSString *> *originalLines, NSArray<NSString *> *modifiedLines,
                              UDRange *originalRange, UDRange *modifiedRange) {
    const NSInteger lineEnd = NSIntegerMax / 4;   // past any line's end
    if (UDIsValidLineNumber(original.endLineNumberExclusive, originalLines) &&
        UDIsValidLineNumber(modified.endLineNumberExclusive, modifiedLines)) {
        *originalRange = PTRangeMake(original.startLineNumber, 1, original.endLineNumberExclusive, 1);
        *modifiedRange = PTRangeMake(modified.startLineNumber, 1, modified.endLineNumberExclusive, 1);
    } else if (UDLineRangeLength(original) > 0 && UDLineRangeLength(modified) > 0) {
        *originalRange = UDRangeFromPositions((UDPosition){ original.startLineNumber, 1 },
            UDNormalizePosition((UDPosition){ original.endLineNumberExclusive - 1, lineEnd }, originalLines));
        *modifiedRange = UDRangeFromPositions((UDPosition){ modified.startLineNumber, 1 },
            UDNormalizePosition((UDPosition){ modified.endLineNumberExclusive - 1, lineEnd }, modifiedLines));
    } else {
        // (both start after line 1: one range is empty and one touches the last line)
        *originalRange = UDRangeFromPositions(
            UDNormalizePosition((UDPosition){ original.startLineNumber - 1, lineEnd }, originalLines),
            UDNormalizePosition((UDPosition){ original.endLineNumberExclusive - 1, lineEnd }, originalLines));
        *modifiedRange = UDRangeFromPositions(
            UDNormalizePosition((UDPosition){ modified.startLineNumber - 1, lineEnd }, modifiedLines),
            UDNormalizePosition((UDPosition){ modified.endLineNumberExclusive - 1, lineEnd }, modifiedLines));
    }
}

static NSInteger UDLineLength(NSArray<NSString *> *lines, NSInteger lineNumber) {
    return lineNumber >= 1 && lineNumber <= (NSInteger)lines.count ? (NSInteger)lines[lineNumber - 1].length : 0;
}

/// rangeMapping.ts's getLineRangeMapping: the lines a character change is of.
static void UDLinesOfRangeMapping(UDRangeMapping *mapping, NSArray<NSString *> *originalLines, NSArray<NSString *> *modifiedLines,
                                  UDLineRange *original, UDLineRange *modified) {
    UDRange o = mapping.originalRange, m = mapping.modifiedRange;
    NSInteger lineStartDelta = 0, lineEndDelta = 0;
    // original: ]xxx \n <- this line is not modified
    // modified: ]xx  \n
    if (m.endColumn == 1 && o.endColumn == 1 &&
        o.startLineNumber + lineStartDelta <= o.endLineNumber && m.startLineNumber + lineStartDelta <= m.endLineNumber) {
        lineEndDelta = -1;
    }
    // original: xxx[ \n <- this line is not modified
    // modified: xxx[ \n
    if (m.startColumn - 1 >= UDLineLength(modifiedLines, m.startLineNumber) &&
        o.startColumn - 1 >= UDLineLength(originalLines, o.startLineNumber) &&
        o.startLineNumber <= o.endLineNumber + lineEndDelta && m.startLineNumber <= m.endLineNumber + lineEndDelta) {
        lineStartDelta = 1;
    }
    *original = UDLineRangeMake(o.startLineNumber + lineStartDelta, o.endLineNumber + 1 + lineEndDelta);
    *modified = UDLineRangeMake(m.startLineNumber + lineStartDelta, m.endLineNumber + 1 + lineEndDelta);
}

/// lineRangeMappingFromRangeMappings: character changes grouped by the lines
/// they touch.
static NSArray<UDDetailedLineRangeMapping *> *UDLineRangeMappings(NSArray<UDRangeMapping *> *alignments,
                                                                  NSArray<NSString *> *originalLines,
                                                                  NSArray<NSString *> *modifiedLines) {
    NSMutableArray<UDDetailedLineRangeMapping *> *changes = [NSMutableArray array];
    UDLineRange groupOriginal = { 0, 0 }, groupModified = { 0, 0 }, lastOriginal = { 0, 0 }, lastModified = { 0, 0 };
    NSMutableArray<UDRangeMapping *> *group = nil;
    for (UDRangeMapping *alignment in alignments) {
        UDLineRange original, modified;
        UDLinesOfRangeMapping(alignment, originalLines, modifiedLines, &original, &modified);
        if (group && (UDLineRangeIntersectsOrTouches(lastOriginal, original) || UDLineRangeIntersectsOrTouches(lastModified, modified))) {
            [group addObject:alignment];
        } else {
            if (group) {
                [changes addObject:[[UDDetailedLineRangeMapping alloc] initWithOriginal:UDLineRangeJoin(groupOriginal, lastOriginal)
                                                                               modified:UDLineRangeJoin(groupModified, lastModified)
                                                                           innerChanges:group]];
            }
            group = [NSMutableArray arrayWithObject:alignment];
            groupOriginal = original;
            groupModified = modified;
        }
        lastOriginal = original;
        lastModified = modified;
    }
    if (group) {
        [changes addObject:[[UDDetailedLineRangeMapping alloc] initWithOriginal:UDLineRangeJoin(groupOriginal, lastOriginal)
                                                                       modified:UDLineRangeJoin(groupModified, lastModified)
                                                                   innerChanges:group]];
    }
    return changes;
}

/// A number for each line (trimmed), the same for the same line in either
/// text (@a perfectHashes, the numbers so far).
static NSData *UDTrimmedLineHashes(NSArray<NSString *> *lines, NSMutableDictionary<NSString *, NSNumber *> *perfectHashes) {
    NSMutableData *data = [NSMutableData dataWithLength:lines.count * sizeof(int32_t)];
    int32_t *values = data.mutableBytes;
    NSUInteger i = 0;
    for (NSString *line in lines) {
        NSString *key = UDTrim(line);
        NSNumber *hash = perfectHashes[key];
        if (!hash) {
            hash = @((int32_t)perfectHashes.count);
            perfectHashes[key] = hash;
        }
        values[i++] = hash.intValue;
    }
    return data;
}

@implementation UDLinesDiffComputer

/// The characters that changed in lines @a diff aligns.
+ (NSArray<UDRangeMapping *> *)refineDiff:(UDSequenceDiff)diff
                            originalLines:(NSArray<NSString *> *)originalLines
                            modifiedLines:(NSArray<NSString *> *)modifiedLines
                                  timeout:(UDTimeout *)timeout
                considerWhitespaceChanges:(BOOL)considerWhitespaceChanges
                               hitTimeout:(BOOL *)hitTimeout {
    UDRange originalRange, modifiedRange;
    UDToRangeMapping2(UDLineRangeMake(diff.s1.start + 1, diff.s1.end + 1), UDLineRangeMake(diff.s2.start + 1, diff.s2.end + 1),
                      originalLines, modifiedLines, &originalRange, &modifiedRange);

    UDLinesSliceCharSequence *slice1 = [[UDLinesSliceCharSequence alloc] initWithLines:originalLines range:originalRange
                                                              considerWhitespaceChanges:considerWhitespaceChanges];
    UDLinesSliceCharSequence *slice2 = [[UDLinesSliceCharSequence alloc] initWithLines:modifiedLines range:modifiedRange
                                                              considerWhitespaceChanges:considerWhitespaceChanges];
    UDDiffResult diffResult = slice1->_length + slice2->_length < 500
        ? UDDynamicProgramming(slice1, slice2, timeout, nil, nil)
        : UDMyers(slice1, slice2, timeout);
    if (diffResult.hitTimeout) *hitTimeout = YES;

    UDDiffs *diffs = diffResult.diffs;
    diffs = UDOptimizeSequenceDiffs(slice1, slice2, diffs);
    diffs = UDExtendDiffsToEntireWordIfAppropriate(slice1, slice2, diffs);
    diffs = UDRemoveShortMatches(diffs);
    diffs = UDRemoveVeryShortMatchingTextBetweenLongDiffs(slice1, slice2, diffs);

    NSMutableArray<UDRangeMapping *> *result = [NSMutableArray arrayWithCapacity:(NSUInteger)UDCount(diffs)];
    for (NSInteger i = 0; i < UDCount(diffs); i++) {
        UDSequenceDiff d = UDAt(diffs, i);
        [result addObject:[[UDRangeMapping alloc] initWithOriginalRange:[slice1 translateRange:d.s1]
                                                          modifiedRange:[slice2 translateRange:d.s2]]];
    }
    return result;
}

/// scanForWhitespaceChanges: of the @a count lines equal (trimmed) from
/// @a start1 and @a start2, those that differ in their white space, diffed.
+ (void)addWhitespaceChangesFrom:(NSInteger)start1 :(NSInteger)start2 count:(NSInteger)count
                   originalLines:(NSArray<NSString *> *)originalLines
                   modifiedLines:(NSArray<NSString *> *)modifiedLines
                         timeout:(UDTimeout *)timeout
                              to:(NSMutableArray<UDRangeMapping *> *)alignments
                      hitTimeout:(BOOL *)hitTimeout {
    for (NSInteger i = 0; i < count; i++) {
        NSInteger seq1Offset = start1 + i, seq2Offset = start2 + i;
        if ([originalLines[seq1Offset] isEqualToString:modifiedLines[seq2Offset]]) continue;
        [alignments addObjectsFromArray:[self refineDiff:UDSD(UDOR(seq1Offset, seq1Offset + 1), UDOR(seq2Offset, seq2Offset + 1))
                                           originalLines:originalLines modifiedLines:modifiedLines
                                                 timeout:timeout considerWhitespaceChanges:YES
                                              hitTimeout:hitTimeout]];
    }
}

+ (UDLinesDiff *)diffOfOriginalLines:(NSArray<NSString *> *)originalLines
                       modifiedLines:(NSArray<NSString *> *)modifiedLines
                ignoreTrimWhitespace:(BOOL)ignoreTrimWhitespace
                  maxComputationTime:(NSTimeInterval)maxComputationTime {
    if (originalLines.count <= 1 && [originalLines isEqualToArray:modifiedLines]) {
        return [[UDLinesDiff alloc] initWithChanges:@[] hitTimeout:NO];
    }
    if ((originalLines.count == 1 && originalLines[0].length == 0) || (modifiedLines.count == 1 && modifiedLines[0].length == 0)) {
        NSInteger o = (NSInteger)originalLines.count, m = (NSInteger)modifiedLines.count;
        UDRangeMapping *all = [[UDRangeMapping alloc]
            initWithOriginalRange:PTRangeMake(1, 1, o, (NSInteger)originalLines.lastObject.length + 1)
                    modifiedRange:PTRangeMake(1, 1, m, (NSInteger)modifiedLines.lastObject.length + 1)];
        UDDetailedLineRangeMapping *change = [[UDDetailedLineRangeMapping alloc] initWithOriginal:UDLineRangeMake(1, o + 1)
                                                                                         modified:UDLineRangeMake(1, m + 1)
                                                                                     innerChanges:@[ all ]];
        return [[UDLinesDiff alloc] initWithChanges:@[ change ] hitTimeout:NO];
    }

    UDTimeout timeout = { [NSDate timeIntervalSinceReferenceDate], maxComputationTime, YES };
    BOOL considerWhitespaceChanges = !ignoreTrimWhitespace;

    NSMutableDictionary<NSString *, NSNumber *> *perfectHashes = [NSMutableDictionary dictionary];
    UDLineSequence *sequence1 = [[UDLineSequence alloc] initWithHashes:UDTrimmedLineHashes(originalLines, perfectHashes)
                                                                 lines:originalLines];
    UDLineSequence *sequence2 = [[UDLineSequence alloc] initWithHashes:UDTrimmedLineHashes(modifiedLines, perfectHashes)
                                                                 lines:modifiedLines];

    UDDiffResult lineAlignmentResult;
    if (sequence1->_length + sequence2->_length < 1700) {
        // the better algorithm, for small texts
        lineAlignmentResult = UDDynamicProgramming(sequence1, sequence2, &timeout, originalLines, modifiedLines);
    } else {
        lineAlignmentResult = UDMyers(sequence1, sequence2, &timeout);
    }

    UDDiffs *lineAlignments = lineAlignmentResult.diffs;
    BOOL hitTimeout = lineAlignmentResult.hitTimeout;
    lineAlignments = UDOptimizeSequenceDiffs(sequence1, sequence2, lineAlignments);
    lineAlignments = UDRemoveVeryShortMatchingLinesBetweenDiffs(sequence1, lineAlignments);

    NSMutableArray<UDRangeMapping *> *alignments = [NSMutableArray array];
    NSInteger seq1LastStart = 0, seq2LastStart = 0;
    for (NSInteger i = 0; i < UDCount(lineAlignments); i++) {
        UDSequenceDiff diff = UDAt(lineAlignments, i);
        if (considerWhitespaceChanges) {
            [self addWhitespaceChangesFrom:seq1LastStart :seq2LastStart count:diff.s1.start - seq1LastStart
                             originalLines:originalLines modifiedLines:modifiedLines timeout:&timeout
                                        to:alignments hitTimeout:&hitTimeout];
        }
        seq1LastStart = diff.s1.end;
        seq2LastStart = diff.s2.end;
        [alignments addObjectsFromArray:[self refineDiff:diff originalLines:originalLines modifiedLines:modifiedLines
                                                 timeout:&timeout considerWhitespaceChanges:considerWhitespaceChanges
                                              hitTimeout:&hitTimeout]];
    }
    if (considerWhitespaceChanges) {
        [self addWhitespaceChangesFrom:seq1LastStart :seq2LastStart count:(NSInteger)originalLines.count - seq1LastStart
                         originalLines:originalLines modifiedLines:modifiedLines timeout:&timeout
                                    to:alignments hitTimeout:&hitTimeout];
    }

    return [[UDLinesDiff alloc] initWithChanges:UDLineRangeMappings(alignments, originalLines, modifiedLines)
                                     hitTimeout:hitTimeout];
}

@end
