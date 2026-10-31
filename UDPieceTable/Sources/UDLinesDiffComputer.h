/*---------------------------------------------------------------------------------------------
 *  Portions Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See LICENSE.txt for license information.
 *
 *  Objective-C port of VS Code's DefaultLinesDiffComputer (the diff editor's
 *  "advanced" algorithm): lines aligned (dynamic programming for small
 *  texts, Myers' O(ND) otherwise), then each changed block refined to the
 *  characters that differ, with VS Code's heuristics (shifting, joining,
 *  extending to whole words). Moved code is not detected.
 *  Original source: https://github.com/microsoft/vscode/tree/main/src/vs/editor/common/diff
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import <UDPieceTable/UDTypes.h>

NS_ASSUME_NONNULL_BEGIN

/// Lines [startLineNumber, endLineNumberExclusive), 1-based: VS Code's LineRange.
typedef struct {
    NSInteger startLineNumber;
    NSInteger endLineNumberExclusive;
} UDLineRange;

static inline UDLineRange UDLineRangeMake(NSInteger start, NSInteger endExclusive) {
    return (UDLineRange){ start, endExclusive };
}

static inline NSInteger UDLineRangeLength(UDLineRange r) {
    return r.endLineNumberExclusive - r.startLineNumber;
}

/// A range of the original text and the range of the modified text it
/// became: VS Code's RangeMapping.
@interface UDRangeMapping : NSObject
@property (nonatomic, readonly) UDRange originalRange;
@property (nonatomic, readonly) UDRange modifiedRange;
- (instancetype)initWithOriginalRange:(UDRange)original modifiedRange:(UDRange)modified;
@end

/// Lines of the original and the lines they became, with the characters
/// that changed in them: VS Code's DetailedLineRangeMapping.
@interface UDDetailedLineRangeMapping : NSObject
@property (nonatomic, readonly) UDLineRange original;
@property (nonatomic, readonly) UDLineRange modified;
@property (nonatomic, readonly, copy) NSArray<UDRangeMapping *> *innerChanges;
- (instancetype)initWithOriginal:(UDLineRange)original modified:(UDLineRange)modified
                    innerChanges:(NSArray<UDRangeMapping *> *)innerChanges;
@end

/// The changes, in the texts' order; hitTimeout when the computation ran out
/// of time and they are an approximation.
@interface UDLinesDiff : NSObject
@property (nonatomic, readonly, copy) NSArray<UDDetailedLineRangeMapping *> *changes;
@property (nonatomic, readonly) BOOL hitTimeout;
@end

@interface UDLinesDiffComputer : NSObject

/// The diff of @a originalLines to @a modifiedLines (without their line
/// breaks). @a ignoreTrimWhitespace: a line's leading and trailing white
/// space is no change. @a maxComputationTime: seconds before it settles for
/// an approximation (0: no limit; VS Code's editor gives it 5).
+ (UDLinesDiff *)diffOfOriginalLines:(NSArray<NSString *> *)originalLines
                       modifiedLines:(NSArray<NSString *> *)modifiedLines
                ignoreTrimWhitespace:(BOOL)ignoreTrimWhitespace
                  maxComputationTime:(NSTimeInterval)maxComputationTime;

@end

NS_ASSUME_NONNULL_END
