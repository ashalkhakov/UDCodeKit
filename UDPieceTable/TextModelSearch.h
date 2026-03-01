/*---------------------------------------------------------------------------------------------
 *  Portions Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See LICENSE.txt for license information.
 *
 *  Objective-C port of VS Code's textModelSearch.ts
 *  Original source: https://github.com/microsoft/vscode/blob/main/src/vs/editor/common/model/textModelSearch.ts
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// MARK: - PTRange  (1-based line/column range)

typedef struct {
    NSInteger startLineNumber;   // 1-based
    NSInteger startColumn;       // 1-based
    NSInteger endLineNumber;
    NSInteger endColumn;
} PTRange;

static inline PTRange PTRangeMake(NSInteger sl, NSInteger sc, NSInteger el, NSInteger ec) {
    return (PTRange){sl, sc, el, ec};
}

// MARK: - PTFindMatch

@interface PTFindMatch : NSObject
@property (nonatomic, readonly) PTRange range;
@property (nonatomic, readonly, nullable) NSArray<NSString *> *matches; // nil if captureMatches==NO
- (instancetype)initWithRange:(PTRange)range matches:(nullable NSArray<NSString *> *)matches;
@end

// MARK: - PTWordCharacterClassifier
// Classifies Unicode code points as "word" or "separator".
// Ported from VS Code's WordCharacterClassifier / getMapForWordSeparators.
@interface PTWordCharacterClassifier : NSObject
- (instancetype)initWithWordSeparators:(NSString *)separators intlChars:(NSArray<NSString *> *)intlChars;
- (BOOL)isWordCharacter:(unichar)ch;  // YES = word char, NO = separator
@end

// MARK: - PTSearchData  (immutable value object)

@interface PTSearchData : NSObject
@property (nonatomic, readonly, strong) NSRegularExpression *regex;
@property (nonatomic, readonly, nullable) PTWordCharacterClassifier *wordSeparators;
@property (nonatomic, readonly, nullable) NSString *simpleSearch; // non-nil → fast indexOf path
- (instancetype)initWithRegex:(NSRegularExpression *)regex
               wordSeparators:(nullable PTWordCharacterClassifier *)wordSeparators
                 simpleSearch:(nullable NSString *)simpleSearch;
@end

// MARK: - PTSearchParams

@interface PTSearchParams : NSObject
- (instancetype)initWithSearchString:(NSString *)searchString
                             isRegex:(BOOL)isRegex
                           matchCase:(BOOL)matchCase
                      wordSeparators:(nullable NSString *)wordSeparators;
/// Returns nil if the pattern is empty or invalid.
- (nullable PTSearchData *)parseSearchRequest;
@end

// MARK: - PTSearcher

@interface PTSearcher : NSObject
- (instancetype)initWithWordSeparators:(nullable PTWordCharacterClassifier *)wordSeparators
                           searchRegex:(NSRegularExpression *)regex;
/// Reset the search cursor to `lastIndex` within subsequent calls to -next:.
- (void)reset:(NSInteger)lastIndex;
/// Returns the next match in `text`, or nil. Advances the internal cursor.
/// Guards against infinite loops on zero-length matches.
/// Validates word boundaries when wordSeparators is set.
- (nullable NSTextCheckingResult *)next:(NSString *)text;
@end

/// Returns YES if the match at [matchStart, matchStart+matchLength) respects word boundaries.
BOOL PTIsValidMatch(PTWordCharacterClassifier *classifier,
                    NSString *text, NSInteger textLength,
                    NSInteger matchStart, NSInteger matchLength);

NS_ASSUME_NONNULL_END
