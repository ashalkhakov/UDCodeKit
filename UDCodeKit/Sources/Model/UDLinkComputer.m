/*---------------------------------------------------------------------------------------------
 *  Portions Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See LICENSE.txt for license information.
 *
 *  UDLinkComputer.m  —  VS Code's LinkComputer, line by line.
 *--------------------------------------------------------------------------------------------*/

#import "UDLinkComputer.h"
#import "UDExtension.h"

typedef NS_ENUM(NSInteger, UDLinkState) {
    UDLinkStateInvalid = 0,
    UDLinkStateStart,
    UDLinkStateH,
    UDLinkStateHT,
    UDLinkStateHTT,
    UDLinkStateHTTP,
    UDLinkStateF,
    UDLinkStateFI,
    UDLinkStateFIL,
    UDLinkStateBeforeColon,
    UDLinkStateAfterColon,
    UDLinkStateAlmostThere,
    UDLinkStateEnd,
    UDLinkStateAccept,
};

typedef NS_ENUM(NSInteger, UDLinkCharacterClass) {
    UDLinkCharacterNone = 0,
    UDLinkCharacterForceTermination,
    UDLinkCharacterCannotEndIn,
};

/// The state machine for http://, https:// or file://.
static UDLinkState UDNextState(UDLinkState state, unichar c) {
    unichar lower = (c >= 'A' && c <= 'Z') ? (unichar)(c + ('a' - 'A')) : c;
    switch (state) {
        case UDLinkStateStart:       return lower == 'h' ? UDLinkStateH : lower == 'f' ? UDLinkStateF : UDLinkStateInvalid;
        case UDLinkStateH:           return lower == 't' ? UDLinkStateHT : UDLinkStateInvalid;
        case UDLinkStateHT:          return lower == 't' ? UDLinkStateHTT : UDLinkStateInvalid;
        case UDLinkStateHTT:         return lower == 'p' ? UDLinkStateHTTP : UDLinkStateInvalid;
        case UDLinkStateHTTP:        return lower == 's' ? UDLinkStateBeforeColon : c == ':' ? UDLinkStateAfterColon : UDLinkStateInvalid;
        case UDLinkStateF:           return lower == 'i' ? UDLinkStateFI : UDLinkStateInvalid;
        case UDLinkStateFI:          return lower == 'l' ? UDLinkStateFIL : UDLinkStateInvalid;
        case UDLinkStateFIL:         return lower == 'e' ? UDLinkStateBeforeColon : UDLinkStateInvalid;
        case UDLinkStateBeforeColon: return c == ':' ? UDLinkStateAfterColon : UDLinkStateInvalid;
        case UDLinkStateAfterColon:  return c == '/' ? UDLinkStateAlmostThere : UDLinkStateInvalid;
        case UDLinkStateAlmostThere: return c == '/' ? UDLinkStateEnd : UDLinkStateInvalid;
        default:                     return UDLinkStateInvalid;
    }
}

static UDLinkCharacterClass UDClassOf(unichar c) {
    static NSCharacterSet *terminating, *cannotEndIn;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        terminating = [NSCharacterSet characterSetWithCharactersInString:
            @" \t<>'\"、。｡､，．：；‘〈「『〔（［｛｢｣｝］）〕』」〉’｀～…|"];
        cannotEndIn = [NSCharacterSet characterSetWithCharactersInString:@".,;:"];
    });
    if ([terminating characterIsMember:c]) return UDLinkCharacterForceTermination;
    if ([cannotEndIn characterIsMember:c]) return UDLinkCharacterCannotEndIn;
    return UDLinkCharacterNone;
}

@implementation UDLinkComputer

/// The link from @a begin to @a end of the line starting at @a lineStart: not
/// ending in . , ; :, nor in the ) ] } of a ( [ { just before it.
+ (void)_addLinkIn:(const unichar *)chars lineStart:(NSUInteger)lineStart begin:(NSUInteger)begin end:(NSUInteger)end
              text:(NSString *)text to:(NSMutableArray<NSDictionary<NSString *, id> *> *)links {
    NSUInteger last = end - 1;
    do {
        if (UDClassOf(chars[last]) != UDLinkCharacterCannotEndIn) break;
        last--;
    } while (last > begin);

    if (begin > lineStart) {
        unichar before = chars[begin - 1], lastChar = chars[last];
        if ((before == '(' && lastChar == ')') || (before == '[' && lastChar == ']') || (before == '{' && lastChar == '}')) {
            last--;
        }
    }

    NSRange range = NSMakeRange(begin, last + 1 - begin);
    NSString *address = [text substringWithRange:range];
    NSURL *url = [NSURL URLWithString:address];
    if (!url) {
        NSString *escaped = [address stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLFragmentAllowedCharacterSet]];
        url = escaped ? [NSURL URLWithString:escaped] : nil;
    }
    if (url) [links addObject:@{ UDLinkRangeKey: [NSValue valueWithRange:range], UDLinkURLKey: url }];
}

+ (NSArray<NSDictionary<NSString *, id> *> *)linksInText:(NSString *)text {
    NSUInteger length = text.length;
    NSMutableArray<NSDictionary<NSString *, id> *> *links = [NSMutableArray array];
    if (length == 0) return links;
    unichar *chars = malloc(length * sizeof(unichar));
    [text getCharacters:chars range:NSMakeRange(0, length)];

    for (NSUInteger lineStart = 0; lineStart < length;) {
        NSUInteger lineEnd = lineStart;
        while (lineEnd < length && chars[lineEnd] != '\n' && chars[lineEnd] != '\r') lineEnd++;

        NSUInteger begin = lineStart;
        unichar beginChar = 0;
        UDLinkState state = UDLinkStateStart;
        BOOL hasOpenParens = NO, hasOpenSquareBracket = NO, inSquareBrackets = NO, hasOpenCurlyBracket = NO;

        for (NSUInteger j = lineStart; j < lineEnd; j++) {
            BOOL reset = NO;
            unichar c = chars[j];

            if (state == UDLinkStateAccept) {
                UDLinkCharacterClass class;
                switch (c) {
                    case '(':
                        hasOpenParens = YES;
                        class = UDLinkCharacterNone;
                        break;
                    case ')':
                        class = hasOpenParens ? UDLinkCharacterNone : UDLinkCharacterForceTermination;
                        break;
                    case '[':
                        inSquareBrackets = YES;
                        hasOpenSquareBracket = YES;
                        class = UDLinkCharacterNone;
                        break;
                    case ']':
                        inSquareBrackets = NO;
                        class = hasOpenSquareBracket ? UDLinkCharacterNone : UDLinkCharacterForceTermination;
                        break;
                    case '{':
                        hasOpenCurlyBracket = YES;
                        class = UDLinkCharacterNone;
                        break;
                    case '}':
                        class = hasOpenCurlyBracket ? UDLinkCharacterNone : UDLinkCharacterForceTermination;
                        break;
                    // ' " ` inside a link only when another of them wraps it
                    case '\'':
                    case '"':
                    case '`':
                        if (beginChar == c) class = UDLinkCharacterForceTermination;
                        else if (beginChar == '\'' || beginChar == '"' || beginChar == '`') class = UDLinkCharacterNone;
                        else class = UDLinkCharacterForceTermination;
                        break;
                    case '*':
                        class = beginChar == '*' ? UDLinkCharacterForceTermination : UDLinkCharacterNone;
                        break;
                    case ' ':
                        class = inSquareBrackets ? UDLinkCharacterNone : UDLinkCharacterForceTermination;
                        break;
                    default:
                        class = UDClassOf(c);
                }
                if (class == UDLinkCharacterForceTermination) {
                    [self _addLinkIn:chars lineStart:lineStart begin:begin end:j text:text to:links];
                    reset = YES;
                }
            } else if (state == UDLinkStateEnd) {
                UDLinkCharacterClass class;
                if (c == '[') {
                    // an IPv6 address's [ ]
                    hasOpenSquareBracket = YES;
                    class = UDLinkCharacterNone;
                } else {
                    class = UDClassOf(c);
                }
                if (class == UDLinkCharacterForceTermination) reset = YES;
                else state = UDLinkStateAccept;
            } else {
                state = UDNextState(state, c);
                if (state == UDLinkStateInvalid) reset = YES;
            }

            if (reset) {
                state = UDLinkStateStart;
                hasOpenParens = NO;
                hasOpenSquareBracket = NO;
                hasOpenCurlyBracket = NO;
                begin = j + 1;
                beginChar = c;
            }
        }
        if (state == UDLinkStateAccept) [self _addLinkIn:chars lineStart:lineStart begin:begin end:lineEnd text:text to:links];

        lineStart = lineEnd;
        if (lineStart < length && chars[lineStart] == '\r') lineStart++;
        if (lineStart < length && chars[lineStart] == '\n') lineStart++;
    }
    free(chars);
    return links;
}

@end
