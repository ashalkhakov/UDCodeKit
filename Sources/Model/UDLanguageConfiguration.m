/*---------------------------------------------------------------------------------------------
 *  UDLanguageConfiguration.m
 *--------------------------------------------------------------------------------------------*/

#import "UDLanguageConfiguration.h"

// ---------------------------------------------------------------------------
// MARK: - UDAutoClosingPair
// ---------------------------------------------------------------------------

@implementation UDAutoClosingPair

- (instancetype)initWithOpen:(NSString *)open
                       close:(NSString *)close
                       notIn:(NSArray<NSString *> *)notIn {
    self = [super init];
    if (!self) return nil;
    _open  = [open  copy];
    _close = [close copy];
    _notIn = [notIn copy];
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %@ → %@%@>",
            NSStringFromClass(self.class), _open, _close,
            _notIn.count ? [NSString stringWithFormat:@" notIn:%@", _notIn] : @""];
}

@end

// ---------------------------------------------------------------------------
// MARK: - UDLanguageConfiguration (private init)
// ---------------------------------------------------------------------------

@interface UDLanguageConfiguration ()
- (instancetype)_initWithLineCommentString:(nullable NSString *)lineCommentString
                         blockCommentStart:(nullable NSString *)blockCommentStart
                           blockCommentEnd:(nullable NSString *)blockCommentEnd
                                  brackets:(NSArray<NSArray<NSString *> *> *)brackets
                          autoClosingPairs:(NSArray<UDAutoClosingPair *> *)autoClosingPairs
                           autoCloseBefore:(nullable NSString *)autoCloseBefore
                          surroundingPairs:(NSArray<NSArray<NSString *> *> *)surroundingPairs
                       foldingStartPattern:(nullable NSString *)foldingStartPattern
                         foldingEndPattern:(nullable NSString *)foldingEndPattern
    NS_DESIGNATED_INITIALIZER;
@end

// ---------------------------------------------------------------------------
// MARK: - UDLanguageConfiguration implementation
// ---------------------------------------------------------------------------

@implementation UDLanguageConfiguration

- (instancetype)_initWithLineCommentString:(nullable NSString *)lineCommentString
                         blockCommentStart:(nullable NSString *)blockCommentStart
                           blockCommentEnd:(nullable NSString *)blockCommentEnd
                                  brackets:(NSArray<NSArray<NSString *> *> *)brackets
                          autoClosingPairs:(NSArray<UDAutoClosingPair *> *)autoClosingPairs
                           autoCloseBefore:(nullable NSString *)autoCloseBefore
                          surroundingPairs:(NSArray<NSArray<NSString *> *> *)surroundingPairs
                       foldingStartPattern:(nullable NSString *)foldingStartPattern
                         foldingEndPattern:(nullable NSString *)foldingEndPattern {
    self = [super init];
    if (!self) return nil;
    _lineCommentString  = [lineCommentString  copy];
    _blockCommentStart  = [blockCommentStart  copy];
    _blockCommentEnd    = [blockCommentEnd    copy];
    _brackets           = [brackets           copy];
    _autoClosingPairs   = [autoClosingPairs   copy];
    _autoCloseBefore    = [autoCloseBefore    copy];
    _surroundingPairs   = [surroundingPairs   copy];
    _foldingStartPattern = [foldingStartPattern copy];
    _foldingEndPattern   = [foldingEndPattern   copy];
    return self;
}

// ---------------------------------------------------------------------------
// MARK: - Factory helpers
// ---------------------------------------------------------------------------

+ (instancetype)emptyConfiguration {
    return [[self alloc] _initWithLineCommentString:nil
                                  blockCommentStart:nil
                                    blockCommentEnd:nil
                                           brackets:@[]
                                   autoClosingPairs:@[]
                                    autoCloseBefore:nil
                                   surroundingPairs:@[]
                                foldingStartPattern:nil
                                  foldingEndPattern:nil];
}

+ (instancetype)configurationFromDictionary:(nullable NSDictionary *)dict {
    if (!dict) return [self emptyConfiguration];

    // ── Comments ──────────────────────────────────────────────────────────
    NSString *lineCommentString = nil;
    NSString *blockCommentStart = nil;
    NSString *blockCommentEnd   = nil;

    NSDictionary *comments = dict[@"comments"];
    if ([comments isKindOfClass:[NSDictionary class]]) {
        lineCommentString = [comments[@"lineComment"] isKindOfClass:[NSString class]]
                          ? comments[@"lineComment"] : nil;
        NSArray *blockPair = [comments[@"blockComment"] isKindOfClass:[NSArray class]]
                           ? comments[@"blockComment"] : nil;
        if (blockPair.count >= 2
                && [blockPair[0] isKindOfClass:[NSString class]]
                && [blockPair[1] isKindOfClass:[NSString class]]) {
            blockCommentStart = blockPair[0];
            blockCommentEnd   = blockPair[1];
        }
    }

    // ── Brackets ──────────────────────────────────────────────────────────
    NSMutableArray<NSArray<NSString *> *> *brackets = [NSMutableArray array];
    NSArray *rawBrackets = [dict[@"brackets"] isKindOfClass:[NSArray class]]
                         ? dict[@"brackets"] : @[];
    for (id pair in rawBrackets) {
        if ([pair isKindOfClass:[NSArray class]] && [pair count] >= 2
                && [pair[0] isKindOfClass:[NSString class]]
                && [pair[1] isKindOfClass:[NSString class]]) {
            [brackets addObject:@[pair[0], pair[1]]];
        }
    }

    // ── Auto-closing pairs ────────────────────────────────────────────────
    NSMutableArray<UDAutoClosingPair *> *autoClosingPairs = [NSMutableArray array];
    NSArray *rawACP = [dict[@"autoClosingPairs"] isKindOfClass:[NSArray class]]
                    ? dict[@"autoClosingPairs"] : @[];
    for (id item in rawACP) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        NSString *open  = [item[@"open"]  isKindOfClass:[NSString class]] ? item[@"open"]  : nil;
        NSString *close = [item[@"close"] isKindOfClass:[NSString class]] ? item[@"close"] : nil;
        if (!open.length || !close.length) continue;
        NSArray *notIn = [item[@"notIn"] isKindOfClass:[NSArray class]] ? item[@"notIn"] : @[];
        NSMutableArray *filteredNotIn = [NSMutableArray array];
        for (id s in notIn) {
            if ([s isKindOfClass:[NSString class]]) [filteredNotIn addObject:s];
        }
        [autoClosingPairs addObject:[[UDAutoClosingPair alloc] initWithOpen:open
                                                                      close:close
                                                                      notIn:filteredNotIn]];
    }

    // ── Auto close before ─────────────────────────────────────────────────
    NSString *autoCloseBefore = [dict[@"autoCloseBefore"] isKindOfClass:[NSString class]]
                               ? dict[@"autoCloseBefore"] : nil;

    // ── Surrounding pairs ─────────────────────────────────────────────────
    NSMutableArray<NSArray<NSString *> *> *surroundingPairs = [NSMutableArray array];
    NSArray *rawSP = [dict[@"surroundingPairs"] isKindOfClass:[NSArray class]]
                   ? dict[@"surroundingPairs"] : @[];
    for (id pair in rawSP) {
        if ([pair isKindOfClass:[NSArray class]] && [pair count] >= 2
                && [pair[0] isKindOfClass:[NSString class]]
                && [pair[1] isKindOfClass:[NSString class]]) {
            [surroundingPairs addObject:@[pair[0], pair[1]]];
        }
    }

    // ── Folding ───────────────────────────────────────────────────────────
    NSString *foldingStart = nil;
    NSString *foldingEnd   = nil;

    NSDictionary *folding = dict[@"folding"];
    if ([folding isKindOfClass:[NSDictionary class]]) {
        NSDictionary *markers = folding[@"markers"];
        if ([markers isKindOfClass:[NSDictionary class]]) {
            foldingStart = [markers[@"start"] isKindOfClass:[NSString class]]
                         ? markers[@"start"] : nil;
            foldingEnd   = [markers[@"end"]   isKindOfClass:[NSString class]]
                         ? markers[@"end"]   : nil;
        }
    }

    return [[self alloc] _initWithLineCommentString:lineCommentString
                                  blockCommentStart:blockCommentStart
                                    blockCommentEnd:blockCommentEnd
                                           brackets:brackets
                                   autoClosingPairs:autoClosingPairs
                                    autoCloseBefore:autoCloseBefore
                                   surroundingPairs:surroundingPairs
                                foldingStartPattern:foldingStart
                                  foldingEndPattern:foldingEnd];
}

// ---------------------------------------------------------------------------
// MARK: - Convenience
// ---------------------------------------------------------------------------

/// Returns the set of opening bracket characters from `brackets`, as a character set.
/// Useful for fast character-level checks in the editor (e.g. electric-pair detection).
- (NSString *)openBracketCharacters {
    NSMutableString *s = [NSMutableString string];
    for (NSArray<NSString *> *pair in _brackets) {
        if (pair.firstObject.length) [s appendString:pair.firstObject];
    }
    return [s copy];
}

/// Returns the set of closing bracket characters from `brackets`.
- (NSString *)closeBracketCharacters {
    NSMutableString *s = [NSMutableString string];
    for (NSArray<NSString *> *pair in _brackets) {
        if (pair.lastObject.length) [s appendString:pair.lastObject];
    }
    return [s copy];
}

/// Returns the closing bracket string that corresponds to the given opening bracket.
/// Returns `nil` when `open` is not a known opening bracket.
- (nullable NSString *)closingBracketForOpen:(NSString *)open {
    for (NSArray<NSString *> *pair in _brackets) {
        if ([pair.firstObject isEqualToString:open]) return pair.lastObject;
    }
    return nil;
}

- (NSString *)description {
    return [NSString stringWithFormat:
            @"<%@: lineComment=%@ blockComment=[%@ %@] brackets=%lu autoClosingPairs=%lu>",
            NSStringFromClass(self.class),
            _lineCommentString ?: @"(none)",
            _blockCommentStart ?: @"(none)", _blockCommentEnd ?: @"(none)",
            (unsigned long)_brackets.count,
            (unsigned long)_autoClosingPairs.count];
}

@end
