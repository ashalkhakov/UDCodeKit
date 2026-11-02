/*---------------------------------------------------------------------------------------------
 *  UDSQLExampleEntry.m
 *--------------------------------------------------------------------------------------------*/

#import "UDSQLExampleEntry.h"
#import "UDSQLExampleCondition.h"

static NSString *UDTrimmed(NSString *text) {
    return [text ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static BOOL UDIsElementText(NSString *text) {
    NSRegularExpression *element = [NSRegularExpression regularExpressionWithPattern:@"^_[A-Za-z0-9_]+$" options:0 error:NULL];
    return [element firstMatchInString:text options:0 range:NSMakeRange(0, text.length)] != nil;
}

/// Whether @a text is in quotes, whole ('x', "5, 6").
static BOOL UDIsQuoted(NSString *text) {
    if (text.length < 2) return NO;
    unichar first = [text characterAtIndex:0];
    return (first == '\'' || first == '"') && [text characterAtIndex:text.length - 1] == first;
}

/// The comparisons, longest first, and what each is.
static NSArray<NSArray *> *UDComparisons(void) {
    return @[ @[ @"<=", @(UDSQLExampleOperatorAtMost) ], @[ @">=", @(UDSQLExampleOperatorAtLeast) ],
              @[ @"<>", @(UDSQLExampleOperatorNotEqual) ], @[ @"!=", @(UDSQLExampleOperatorNotEqual) ],
              @[ @"=", @(UDSQLExampleOperatorEqual) ], @[ @"<", @(UDSQLExampleOperatorLess) ], @[ @">", @(UDSQLExampleOperatorGreater) ] ];
}

/// The aggregates, as typed, and what each is.
static NSDictionary<NSString *, NSNumber *> *UDTotals(void) {
    return @{ @"SUM": @(UDSQLExampleTotalSum), @"AVG": @(UDSQLExampleTotalAverage), @"MIN": @(UDSQLExampleTotalMinimum),
              @"MAX": @(UDSQLExampleTotalMaximum), @"COUNT": @(UDSQLExampleTotalCount) };
}

@implementation UDSQLExampleEntry

- (instancetype)init {
    self = [super init];
    if (self) {
        _value = @"";
        _to = @"";
    }
    return self;
}

/// What follows P., G. and an aggregate, read: its operator, value, To.
- (void)_readCondition:(NSString *)rest {
    NSString *text = UDTrimmed(rest);
    NSString *upper = text.uppercaseString;
    _value = @"";
    _to = @"";
    if (!text.length) {
        _op = UDSQLExampleOperatorNone;
        return;
    }
    if (UDIsElementText(text)) {
        _op = UDSQLExampleOperatorEqual;
        _value = text;
        return;
    }
    if ([@[ @"NULL", @"IS NULL", @"= NULL" ] containsObject:upper]) {
        _op = UDSQLExampleOperatorIsNull;
        return;
    }
    if ([@[ @"NOT NULL", @"!NULL", @"! NULL", @"IS NOT NULL", @"<> NULL", @"!= NULL" ] containsObject:upper]) {
        _op = UDSQLExampleOperatorIsNotNull;
        return;
    }
    if (UDIsQuoted(text)) {
        _op = UDSQLExampleOperatorEqual;
        _value = text;
        return;
    }
    for (NSArray *comparison in UDComparisons()) {
        if (![text hasPrefix:comparison[0]]) continue;
        _op = [comparison[1] integerValue];
        _value = UDTrimmed([text substringFromIndex:[comparison[0] length]]);
        return;
    }
    if ([text hasPrefix:@"!"] || [upper hasPrefix:@"NOT "]) {
        _op = UDSQLExampleOperatorNot;
        _value = UDTrimmed([text substringFromIndex:[text hasPrefix:@"!"] ? 1 : 4]);
        return;
    }
    // a range, an end still to type too (A.., ..P)
    NSRange range = [text rangeOfString:@".."];
    if (range.location != NSNotFound && text.length > 2) {
        _op = UDSQLExampleOperatorBetween;
        _value = UDTrimmed([text substringToIndex:range.location]);
        _to = UDTrimmed([text substringFromIndex:NSMaxRange(range)]);
        return;
    }
    if ([text containsString:@","]) {
        _op = UDSQLExampleOperatorOneOf;
        _value = text;
        return;
    }
    if ([text rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"*%"]].location != NSNotFound) {
        _op = UDSQLExampleOperatorLike;
        _value = text;
        return;
    }
    _op = UDSQLExampleOperatorEqual;
    _value = text;
}

+ (instancetype)entryOfText:(NSString *)typed {
    UDSQLExampleEntry *entry = [[self alloc] init];
    NSString *text = UDTrimmed(typed);
    BOOL grouped = NO;
    for (BOOL more = YES; more;) {
        more = NO;
        if ([text.uppercaseString hasPrefix:@"P."]) entry->_shown = more = YES;
        else if ([text.uppercaseString hasPrefix:@"G."]) grouped = more = YES;
        if (more) text = UDTrimmed([text substringFromIndex:2]);
    }
    BOOL distinct = NO;
    NSString *rest = nil;
    NSString *function = UDSQLAggregateOf(text, &rest, &distinct);
    if (function) {
        entry->_total = distinct && [function isEqualToString:@"COUNT"] ? UDSQLExampleTotalCountDistinct : [UDTotals()[function] integerValue];
        text = rest;
    } else if (grouped) {
        entry->_total = UDSQLExampleTotalGroup;
    }
    [entry _readCondition:text];
    return entry;
}

/// Its value as the operator writes it; a value typed whole (> 5 under
/// =), as typed.
- (NSString *)_condition {
    NSString *value = UDTrimmed(_value);
    if (_op == UDSQLExampleOperatorIsNull) return @"NULL";
    if (_op == UDSQLExampleOperatorIsNotNull) return @"NOT NULL";
    if (_op == UDSQLExampleOperatorNone || !value.length) return value;
    UDSQLExampleEntry *typed = [[UDSQLExampleEntry alloc] init];
    [typed _readCondition:value];
    if (typed.op != UDSQLExampleOperatorEqual && typed.op != UDSQLExampleOperatorNone && _op != UDSQLExampleOperatorLike &&
        _op != UDSQLExampleOperatorOneOf) {
        return value;
    }
    switch (_op) {
        case UDSQLExampleOperatorNotEqual: return [@"<> " stringByAppendingString:value];
        case UDSQLExampleOperatorGreater: return [@"> " stringByAppendingString:value];
        case UDSQLExampleOperatorAtLeast: return [@">= " stringByAppendingString:value];
        case UDSQLExampleOperatorLess: return [@"< " stringByAppendingString:value];
        case UDSQLExampleOperatorAtMost: return [@"<= " stringByAppendingString:value];
        case UDSQLExampleOperatorBetween: return [NSString stringWithFormat:@"%@..%@", value, UDTrimmed(_to)];
        case UDSQLExampleOperatorLike:
            // a pattern: its * where none is typed
            return [value rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"*%"]].location == NSNotFound
                ? [value stringByAppendingString:@"*"] : value;
        case UDSQLExampleOperatorNot: return [@"!" stringByAppendingString:value];
        default: return value;      // =, one of: as it is
    }
}

- (NSString *)text {
    NSMutableString *head = [NSMutableString stringWithString:_shown ? @"P." : @""];
    NSDictionary *zloof = @{ @(UDSQLExampleTotalGroup): @"G.", @(UDSQLExampleTotalSum): @"SUM.", @(UDSQLExampleTotalAverage): @"AVG.",
                             @(UDSQLExampleTotalMinimum): @"MIN.", @(UDSQLExampleTotalMaximum): @"MAX.",
                             @(UDSQLExampleTotalCount): @"CNT.", @(UDSQLExampleTotalCountDistinct): @"CNT.UNQ." };
    NSString *total = zloof[@(_total)];
    if (total) [head appendString:total];
    NSString *condition = [self _condition];
    if (!condition.length) return head;
    // an aggregate's condition apart from it (P.SUM. > 5); P.'s, not (P.> 5)
    BOOL spaced = _total != UDSQLExampleTotalNone && _total != UDSQLExampleTotalGroup;
    return [NSString stringWithFormat:@"%@%@%@", head, spaced ? @" " : @"", condition];
}

@end
