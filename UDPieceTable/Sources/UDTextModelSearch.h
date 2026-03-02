/*---------------------------------------------------------------------------------------------
 *  Portions Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See LICENSE.txt for license information.
 *
 *  Objective-C port of VS Code's textModelSearch.ts
 *  Original source: https://github.com/microsoft/vscode/blob/main/src/vs/editor/common/model/textModelSearch.ts
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>

#import <UDPieceTable/UDTypes.h>

NS_ASSUME_NONNULL_BEGIN

// MARK: - UDFindMatch

@interface UDFindMatch : NSObject
@property (nonatomic, readonly) UDRange range;
@property (nonatomic, readonly, nullable) NSArray<NSString *> *matches; // nil if captureMatches==NO
- (instancetype)initWithRange:(UDRange)range matches:(nullable NSArray<NSString *> *)matches;
@end

// MARK: - UDWordCharacterClassifier
// Classifies Unicode code points as "word" or "separator".
// Ported from VS Code's WordCharacterClassifier / getMapForWordSeparators.
@interface UDWordCharacterClassifier : NSObject
- (instancetype)initWithWordSeparators:(NSString *)separators intlChars:(NSArray<NSString *> *)intlChars;
- (BOOL)isWordCharacter:(unichar)ch;  // YES = word char, NO = separator
@end

// MARK: - UDSearchData  (immutable value object)

@interface UDSearchData : NSObject
@property (nonatomic, readonly, strong) NSRegularExpression *regex;
@property (nonatomic, readonly, nullable) UDWordCharacterClassifier *wordSeparators;
@property (nonatomic, readonly, nullable) NSString *simpleSearch; // non-nil → fast indexOf path
- (instancetype)initWithRegex:(NSRegularExpression *)regex
               wordSeparators:(nullable UDWordCharacterClassifier *)wordSeparators
                 simpleSearch:(nullable NSString *)simpleSearch;
@end

// MARK: - UDSearchParams

@interface UDSearchParams : NSObject
- (instancetype)initWithSearchString:(NSString *)searchString
                             isRegex:(BOOL)isRegex
                           matchCase:(BOOL)matchCase
                      wordSeparators:(nullable NSString *)wordSeparators;
/// Returns nil if the pattern is empty or invalid.
- (nullable UDSearchData *)parseSearchRequest;
@end

// MARK: - UDSearcher

@interface UDSearcher : NSObject
- (instancetype)initWithWordSeparators:(nullable UDWordCharacterClassifier *)wordSeparators
                           searchRegex:(NSRegularExpression *)regex;
/// Reset the search cursor to `lastIndex` within subsequent calls to -next:.
- (void)reset:(NSInteger)lastIndex;
/// Returns the next match in `text`, or nil. Advances the internal cursor.
/// Guards against infinite loops on zero-length matches.
/// Validates word boundaries when wordSeparators is set.
- (nullable NSTextCheckingResult *)next:(NSString *)text;
@end

/// Returns YES if the match at [matchStart, matchStart+matchLength) respects word boundaries.
BOOL PTIsValidMatch(UDWordCharacterClassifier *classifier,
                    NSString *text, NSInteger textLength,
                    NSInteger matchStart, NSInteger matchLength);

NS_ASSUME_NONNULL_END
