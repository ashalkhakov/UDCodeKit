/*---------------------------------------------------------------------------------------------
 *  Portions Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See LICENSE.txt for license information.
 *
 *  Objective-C port of VS Code's textModelSearch.ts
 *  Original source: https://github.com/microsoft/vscode/blob/main/src/vs/editor/common/model/textModelSearch.ts
 *--------------------------------------------------------------------------------------------*/

#import "UDTextModelSearch.h"

// MARK: - PTFindMatch

@implementation UDFindMatch

- (instancetype)initWithRange:(UDRange)range matches:(nullable NSArray<NSString *> *)matches {
    self = [super init];
    if (self) {
        _range = range;
        _matches = [matches copy];
    }
    return self;
}

@end

// MARK: - PTWordCharacterClassifier

@implementation UDWordCharacterClassifier {
    NSMutableSet<NSNumber *> *_separators;
}

- (instancetype)initWithWordSeparators:(NSString *)separators intlChars:(NSArray<NSString *> *)intlChars {
    self = [super init];
    if (self) {
        _separators = [NSMutableSet set];
        // Add each character in the separators string
        NSInteger len = (NSInteger)separators.length;
        for (NSInteger i = 0; i < len; i++) {
            unichar ch = [separators characterAtIndex:(NSUInteger)i];
            [_separators addObject:@(ch)];
        }
        // Add each string in intlChars (first code point only)
        for (NSString *s in intlChars) {
            if (s.length > 0) {
                unichar ch = [s characterAtIndex:0];
                [_separators addObject:@(ch)];
            }
        }
    }
    return self;
}

- (BOOL)isWordCharacter:(unichar)ch {
    return ![_separators containsObject:@(ch)];
}

@end

// MARK: - PTIsValidMatch

BOOL PTIsValidMatch(UDWordCharacterClassifier *classifier,
                    NSString *text, NSInteger textLength,
                    NSInteger matchStart, NSInteger matchLength) {
    if (matchStart > 0) {
        unichar charBefore = [text characterAtIndex:(NSUInteger)(matchStart - 1)];
        if ([classifier isWordCharacter:charBefore]) {
            return NO;
        }
    }
    NSInteger matchEnd = matchStart + matchLength;
    if (matchEnd < textLength) {
        unichar charAfter = [text characterAtIndex:(NSUInteger)matchEnd];
        if ([classifier isWordCharacter:charAfter]) {
            return NO;
        }
    }
    return YES;
}

// MARK: - PTSearchData

@implementation UDSearchData

- (instancetype)initWithRegex:(NSRegularExpression *)regex
               wordSeparators:(nullable UDWordCharacterClassifier *)wordSeparators
                 simpleSearch:(nullable NSString *)simpleSearch {
    self = [super init];
    if (self) {
        _regex = regex;
        _wordSeparators = wordSeparators;
        _simpleSearch = [simpleSearch copy];
    }
    return self;
}

@end

// MARK: - isMultilineRegexSource (private helper)

static BOOL IsMultilineRegexSource(NSString *searchString) {
    NSInteger len = (NSInteger)searchString.length;
    for (NSInteger i = 0; i < len; i++) {
        unichar ch = [searchString characterAtIndex:(NSUInteger)i];
        if (ch == '\\') {
            i++;
            if (i >= len) { break; }
            unichar next = [searchString characterAtIndex:(NSUInteger)i];
            if (next == 'n' || next == 'r' || next == 'W' || next == 'w' ||
                next == 's' || next == 'S') {
                return YES;
            }
        } else if (ch == '\n') {
            return YES;
        }
    }
    return NO;
}

// MARK: - PTSearchParams

@implementation UDSearchParams {
    NSString *_searchString;
    BOOL _isRegex;
    BOOL _matchCase;
    NSString *_wordSeparators;
}

- (instancetype)initWithSearchString:(NSString *)searchString
                             isRegex:(BOOL)isRegex
                           matchCase:(BOOL)matchCase
                      wordSeparators:(nullable NSString *)wordSeparators {
    self = [super init];
    if (self) {
        _searchString = [searchString copy];
        _isRegex = isRegex;
        _matchCase = matchCase;
        _wordSeparators = [wordSeparators copy];
    }
    return self;
}

- (nullable UDSearchData *)parseSearchRequest {
    if (_searchString.length == 0) {
        return nil;
    }

    BOOL multiline;
    if (_isRegex) {
        multiline = IsMultilineRegexSource(_searchString);
    } else {
        multiline = [_searchString containsString:@"\n"];
    }

    NSRegularExpressionOptions options = 0;
    if (!_matchCase) {
        options |= NSRegularExpressionCaseInsensitive;
    }
    if (multiline) {
        options |= NSRegularExpressionAnchorsMatchLines | NSRegularExpressionDotMatchesLineSeparators;
    }

    // Escape the search string if not a regex
    NSString *pattern = _isRegex
        ? _searchString
        : [NSRegularExpression escapedPatternForString:_searchString];

    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                           options:options
                                                                             error:&error];
    if (!regex || error) {
        return nil;
    }

    // simpleSearch is only valid for plain, case-sensitive, single-line searches
    NSString *simpleSearch = (!_isRegex && !multiline && _matchCase) ? _searchString : nil;

    UDWordCharacterClassifier *wordSeparatorClassifier = nil;
    if (_wordSeparators) {
        wordSeparatorClassifier = [[UDWordCharacterClassifier alloc]
                                   initWithWordSeparators:_wordSeparators
                                               intlChars:@[]];
    }

    return [[UDSearchData alloc] initWithRegex:regex
                                wordSeparators:wordSeparatorClassifier
                                  simpleSearch:simpleSearch];
}

@end

// MARK: - PTSearcher

@implementation UDSearcher {
    UDWordCharacterClassifier *_wordSeparators;
    NSRegularExpression *_regex;
    NSInteger _lastIndex;
    NSInteger _prevMatchStart;
    NSInteger _prevMatchLength;
}

- (instancetype)initWithWordSeparators:(nullable UDWordCharacterClassifier *)wordSeparators
                           searchRegex:(NSRegularExpression *)regex {
    self = [super init];
    if (self) {
        _wordSeparators = wordSeparators;
        _regex = regex;
        _lastIndex = 0;
        _prevMatchStart = -1;
        _prevMatchLength = 0;
    }
    return self;
}

- (void)reset:(NSInteger)lastIndex {
    _lastIndex = lastIndex;
    _prevMatchStart = -1;
    _prevMatchLength = 0;
}

- (nullable NSTextCheckingResult *)next:(NSString *)text {
    NSInteger textLen = (NSInteger)text.length;
    while (YES) {
        // Guard against infinite loop on zero-length matches
        if (_prevMatchStart >= 0 && _prevMatchLength == 0 && _lastIndex == _prevMatchStart) {
            _lastIndex++;
        }
        if (_lastIndex > textLen) { return nil; }
        NSRange searchRange = NSMakeRange((NSUInteger)_lastIndex,
                                          (NSUInteger)(textLen - _lastIndex));
        NSTextCheckingResult *match = [_regex firstMatchInString:text
                                                         options:NSMatchingWithoutAnchoringBounds
                                                           range:searchRange];
        if (!match) { return nil; }

        _prevMatchStart  = (NSInteger)match.range.location;
        _prevMatchLength = (NSInteger)match.range.length;

        if (_wordSeparators) {
            if (!PTIsValidMatch(_wordSeparators, text, textLen,
                                (NSInteger)match.range.location,
                                (NSInteger)match.range.length)) {
                _lastIndex = (NSInteger)match.range.location + 1;
                continue;
            }
        }

        _lastIndex = (NSInteger)(match.range.location + match.range.length);
        return match;
    }
}

@end
