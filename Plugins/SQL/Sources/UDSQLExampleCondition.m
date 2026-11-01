/*---------------------------------------------------------------------------------------------
 *  UDSQLExampleCondition.m
 *
 *  Read by recursive descent into a tree (arrays: its kind, then its
 *  parts), made a predicate once its elements' columns are known:
 *
 *    condition   := disjunction
 *    disjunction := conjunction (OR conjunction)*
 *    conjunction := negation (AND negation)*
 *    negation    := NOT negation | ( disjunction ) | comparison
 *    comparison  := sum (= | <> | != | < | <= | > | >=) sum | sum IS [NOT] NULL
 *    sum         := product ((+ | -) product)*
 *    product     := factor ((* | /) factor)*
 *    factor      := number | 'text' | _element | AGG. [ALL. | UNQ.] _element
 *                 | - factor | ( sum )
 *--------------------------------------------------------------------------------------------*/

#import "UDSQLExampleCondition.h"

static NSDictionary<NSString *, NSString *> *UDAggregateNames(void) {
    return @{ @"SUM": @"SUM", @"AVG": @"AVG", @"MIN": @"MIN", @"MAX": @"MAX", @"CNT": @"COUNT" };
}

NSString *UDSQLAggregateOf(NSString *text, NSString **rest, BOOL *distinct) {
    NSString *upper = text.uppercaseString;
    for (NSString *zloof in UDAggregateNames()) {
        NSString *prefix = [zloof stringByAppendingString:@"."];
        if (![upper hasPrefix:prefix]) continue;
        NSString *after = [[text substringFromIndex:prefix.length] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        BOOL unique = NO;
        if ([after.uppercaseString hasPrefix:@"ALL."] || [after.uppercaseString hasPrefix:@"UNQ."]) {
            unique = [after.uppercaseString hasPrefix:@"UNQ."];
            after = [[after substringFromIndex:4] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        }
        if (rest) *rest = after;
        if (distinct) *distinct = unique;
        return UDAggregateNames()[zloof];
    }
    return nil;
}

NSString *UDSQLZloofName(NSString *function) {
    return [function isEqualToString:@"COUNT"] ? @"CNT" : function;
}

// ---------------------------------------------------------------------------
// MARK: - Its tokens
// ---------------------------------------------------------------------------

/// A token: its kind (number, text, element, aggregate, word, symbol),
/// its value, where it begins.
@interface UDToken : NSObject
@property (nonatomic, copy) NSString *kind;
@property (nonatomic, strong) id value;
@property (nonatomic) BOOL distinct;        // an aggregate's UNQ.
@property (nonatomic) NSUInteger location;
@end

@implementation UDToken
@end

static NSArray<UDToken *> *UDTokens(NSString *text, NSString **message) {
    NSMutableArray *tokens = [NSMutableArray array];
    NSCharacterSet *letters = [NSCharacterSet letterCharacterSet];
    NSCharacterSet *digits = [NSCharacterSet decimalDigitCharacterSet];
    NSUInteger i = 0, n = text.length;
    while (i < n) {
        unichar c = [text characterAtIndex:i];
        if ([[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:c]) { i++; continue; }
        UDToken *token = [[UDToken alloc] init];
        token.location = i;
        if (c == '\'') {
            // text, '' a quote
            NSMutableString *value = [NSMutableString string];
            NSUInteger j = i + 1;
            BOOL closed = NO;
            while (j < n) {
                unichar d = [text characterAtIndex:j];
                if (d == '\'') {
                    if (j + 1 < n && [text characterAtIndex:j + 1] == '\'') { [value appendString:@"'"]; j += 2; continue; }
                    closed = YES;
                    j++;
                    break;
                }
                [value appendFormat:@"%C", d];
                j++;
            }
            if (!closed) {
                if (message) *message = @"a text's closing ' is missing";
                return nil;
            }
            token.kind = @"text";
            token.value = value;
            i = j;
        } else if ([digits characterIsMember:c] || (c == '.' && i + 1 < n && [digits characterIsMember:[text characterAtIndex:i + 1]])) {
            NSUInteger j = i;
            while (j < n && ([digits characterIsMember:[text characterAtIndex:j]] || [text characterAtIndex:j] == '.')) j++;
            NSString *number = [text substringWithRange:NSMakeRange(i, j - i)];
            token.kind = @"number";
            token.value = [number containsString:@"."] ? @([number doubleValue]) : @([number longLongValue]);
            i = j;
        } else if (c == '_') {
            NSUInteger j = i + 1;
            while (j < n && ([letters characterIsMember:[text characterAtIndex:j]] || [digits characterIsMember:[text characterAtIndex:j]] ||
                             [text characterAtIndex:j] == '_')) j++;
            if (j == i + 1) {
                if (message) *message = @"an example element is named: _x";
                return nil;
            }
            token.kind = @"element";
            token.value = [text substringWithRange:NSMakeRange(i, j - i)];
            i = j;
        } else if ([letters characterIsMember:c]) {
            NSUInteger j = i;
            while (j < n && [letters characterIsMember:[text characterAtIndex:j]]) j++;
            NSString *word = [text substringWithRange:NSMakeRange(i, j - i)];
            if (j < n && [text characterAtIndex:j] == '.') {
                // an aggregate: SUM. CNT.ALL. AVG.UNQ.
                NSString *function = UDAggregateNames()[word.uppercaseString];
                if (!function) {
                    if (message) *message = [NSString stringWithFormat:@"%@. isn't an aggregate (SUM. AVG. MIN. MAX. CNT.)", word];
                    return nil;
                }
                j++;
                NSString *after = [[text substringFromIndex:j] uppercaseString];
                if ([after hasPrefix:@"ALL."] || [after hasPrefix:@"UNQ."]) {
                    token.distinct = [after hasPrefix:@"UNQ."];
                    j += 4;
                }
                token.kind = @"aggregate";
                token.value = function;
                i = j;
            } else {
                token.kind = @"word";
                token.value = word.uppercaseString;
                i = j;
            }
        } else {
            NSString *two = i + 1 < n ? [text substringWithRange:NSMakeRange(i, 2)] : @"";
            NSString *symbol = [@[ @"<>", @"!=", @"<=", @">=" ] containsObject:two] ? two : [NSString stringWithFormat:@"%C", c];
            if (![@[ @"<>", @"!=", @"<=", @">=", @"=", @"<", @">", @"+", @"-", @"*", @"/", @"(", @")" ] containsObject:symbol]) {
                if (message) *message = [NSString stringWithFormat:@"“%@” can't be read", symbol];
                return nil;
            }
            token.kind = @"symbol";
            token.value = symbol;
            i += symbol.length;
        }
        [tokens addObject:token];
    }
    return tokens;
}

// ---------------------------------------------------------------------------
// MARK: - Read
// ---------------------------------------------------------------------------

@interface UDConditionReader : NSObject {
@public
    NSArray<UDToken *> *_tokens;
    NSUInteger _at;
    NSString *_message;
    NSMutableSet *_elements;
    BOOL _aggregates;
}
@end

@implementation UDConditionReader

- (UDToken *)_peek {
    return _at < _tokens.count ? _tokens[_at] : nil;
}

- (BOOL)_is:(NSString *)kind value:(NSString *)value {
    UDToken *token = [self _peek];
    return token && [token.kind isEqualToString:kind] && (!value || [token.value isEqual:value]);
}

- (BOOL)_take:(NSString *)kind value:(NSString *)value {
    if (![self _is:kind value:value]) return NO;
    _at++;
    return YES;
}

- (id)_fail:(NSString *)message {
    if (!_message) {
        UDToken *token = [self _peek];
        _message = token ? [NSString stringWithFormat:@"%@, at “%@”", message, [token.value description]] : [message stringByAppendingString:@", at its end"];
    }
    return nil;
}

- (NSArray *)disjunction {
    NSArray *first = [self conjunction];
    if (!first) return nil;
    NSMutableArray *parts = [NSMutableArray arrayWithObject:first];
    while ([self _take:@"word" value:@"OR"]) {
        NSArray *next = [self conjunction];
        if (!next) return nil;
        [parts addObject:next];
    }
    return parts.count == 1 ? first : [@[ @"or" ] arrayByAddingObjectsFromArray:parts];
}

- (NSArray *)conjunction {
    NSArray *first = [self negation];
    if (!first) return nil;
    NSMutableArray *parts = [NSMutableArray arrayWithObject:first];
    while ([self _take:@"word" value:@"AND"]) {
        NSArray *next = [self negation];
        if (!next) return nil;
        [parts addObject:next];
    }
    return parts.count == 1 ? first : [@[ @"and" ] arrayByAddingObjectsFromArray:parts];
}

- (NSArray *)negation {
    if ([self _take:@"word" value:@"NOT"]) {
        NSArray *inner = [self negation];
        return inner ? @[ @"not", inner ] : nil;
    }
    if ([self _is:@"symbol" value:@"("]) {
        // a condition in parentheses, unless a sum is (then compared)
        NSUInteger start = _at;
        NSString *message = _message;
        _at++;
        NSArray *inner = [self disjunction];
        if (inner && [self _take:@"symbol" value:@")"] &&
            ([self _peek] == nil || [self _is:@"word" value:@"AND"] || [self _is:@"word" value:@"OR"] || [self _is:@"symbol" value:@")"])) {
            return inner;
        }
        _at = start;
        _message = message;
    }
    return [self comparison];
}

- (NSArray *)comparison {
    NSArray *left = [self sum];
    if (!left) return nil;
    if ([self _take:@"word" value:@"IS"]) {
        BOOL negated = [self _take:@"word" value:@"NOT"];
        if (![self _take:@"word" value:@"NULL"]) return [self _fail:@"IS (NOT) NULL is all IS says"];
        return @[ @"null", left, @(negated) ];
    }
    UDToken *token = [self _peek];
    NSArray *ops = @[ @"=", @"<>", @"!=", @"<", @"<=", @">", @">=" ];
    if (!token || ![token.kind isEqualToString:@"symbol"] || ![ops containsObject:token.value]) {
        return [self _fail:@"a comparison wanted (=, <>, <, <=, >, >=, IS NULL)"];
    }
    _at++;
    NSArray *right = [self sum];
    return right ? @[ @"compare", token.value, left, right ] : nil;
}

- (NSArray *)sum {
    NSArray *left = [self product];
    while (left && ([self _is:@"symbol" value:@"+"] || [self _is:@"symbol" value:@"-"])) {
        NSString *op = [self _peek].value;
        _at++;
        NSArray *right = [self product];
        left = right ? @[ @"arithmetic", op, left, right ] : nil;
    }
    return left;
}

- (NSArray *)product {
    NSArray *left = [self factor];
    while (left && ([self _is:@"symbol" value:@"*"] || [self _is:@"symbol" value:@"/"])) {
        NSString *op = [self _peek].value;
        _at++;
        NSArray *right = [self factor];
        left = right ? @[ @"arithmetic", op, left, right ] : nil;
    }
    return left;
}

- (NSArray *)factor {
    UDToken *token = [self _peek];
    if (!token) return [self _fail:@"a value wanted"];
    if ([token.kind isEqualToString:@"number"] || [token.kind isEqualToString:@"text"]) {
        _at++;
        return @[ @"value", token.value ];
    }
    if ([token.kind isEqualToString:@"element"]) {
        _at++;
        [_elements addObject:token.value];
        return @[ @"element", token.value ];
    }
    if ([token.kind isEqualToString:@"aggregate"]) {
        _at++;
        UDToken *element = [self _peek];
        if (!element || ![element.kind isEqualToString:@"element"]) {
            return [self _fail:[NSString stringWithFormat:@"%@. aggregates an example element's values: %@.ALL._x",
                                                          UDSQLZloofName(token.value), UDSQLZloofName(token.value)]];
        }
        _at++;
        [_elements addObject:element.value];
        _aggregates = YES;
        return @[ @"aggregate", token.value, @(token.distinct), element.value ];
    }
    if ([self _take:@"symbol" value:@"-"]) {
        NSArray *inner = [self factor];
        return inner ? @[ @"negative", inner ] : nil;
    }
    if ([self _take:@"symbol" value:@"("]) {
        NSArray *inner = [self sum];
        if (!inner) return nil;
        if (![self _take:@"symbol" value:@")"]) return [self _fail:@"a ) wanted"];
        return inner;
    }
    return [self _fail:@"a value wanted"];
}

@end

// ---------------------------------------------------------------------------
// MARK: - The condition
// ---------------------------------------------------------------------------

@implementation UDSQLExampleCondition {
    NSArray *_tree;
}

+ (instancetype)conditionOf:(NSString *)text message:(NSString **)message {
    NSString *failure = nil;
    NSArray *tokens = UDTokens(text, &failure);
    if (!tokens) {
        if (message) *message = failure;
        return nil;
    }
    if (!tokens.count) {
        if (message) *message = @"nothing to read";
        return nil;
    }
    UDConditionReader *reader = [[UDConditionReader alloc] init];
    reader->_tokens = tokens;
    reader->_elements = [NSMutableSet set];
    NSArray *tree = [reader disjunction];
    if (tree && reader->_at < tokens.count) tree = [reader _fail:@"AND or OR wanted"];
    if (!tree) {
        if (message) *message = reader->_message ?: @"it can't be read";
        return nil;
    }
    if (!reader->_elements.count) {
        if (message) *message = @"it names no example element (_x): it is of nothing";
        return nil;
    }
    UDSQLExampleCondition *condition = [[self alloc] init];
    condition->_text = [text copy];
    condition->_tree = tree;
    condition->_elements = [reader->_elements copy];
    condition->_aggregates = reader->_aggregates;
    return condition;
}

static UDSQLComparison UDComparison(NSString *op) {
    if ([op isEqualToString:@"<>"] || [op isEqualToString:@"!="]) return UDSQLNotEqual;
    if ([op isEqualToString:@"<"]) return UDSQLLess;
    if ([op isEqualToString:@"<="]) return UDSQLLessOrEqual;
    if ([op isEqualToString:@">"]) return UDSQLGreater;
    if ([op isEqualToString:@">="]) return UDSQLGreaterOrEqual;
    return UDSQLEqual;
}

- (UDSQLExpression *)_expressionOf:(NSArray *)node bound:(NSDictionary *)bound message:(NSString **)message {
    NSString *kind = node[0];
    if ([kind isEqualToString:@"value"]) return [UDSQLExpression value:node[1]];
    if ([kind isEqualToString:@"element"] || [kind isEqualToString:@"aggregate"]) {
        NSString *element = [kind isEqualToString:@"element"] ? node[1] : node[3];
        UDSQLExpression *column = bound[element];
        if (!column) {
            if (message) *message = [NSString stringWithFormat:@"%@ is given a value by no row: put it alone under a column", element];
            return nil;
        }
        return [kind isEqualToString:@"element"] ? column : [UDSQLExpression aggregate:node[1] of:column distinct:[node[2] boolValue]];
    }
    if ([kind isEqualToString:@"negative"]) {
        UDSQLExpression *inner = [self _expressionOf:node[1] bound:bound message:message];
        return inner ? [UDSQLExpression negative:inner] : nil;
    }
    UDSQLExpression *left = [self _expressionOf:node[2] bound:bound message:message];
    UDSQLExpression *right = left ? [self _expressionOf:node[3] bound:bound message:message] : nil;
    return right ? [UDSQLExpression arithmetic:node[1] left:left right:right] : nil;
}

- (UDSQLPredicate *)_predicateOf:(NSArray *)node bound:(NSDictionary *)bound message:(NSString **)message {
    NSString *kind = node[0];
    if ([kind isEqualToString:@"or"] || [kind isEqualToString:@"and"]) {
        NSMutableArray *parts = [NSMutableArray array];
        for (NSUInteger i = 1; i < node.count; i++) {
            UDSQLPredicate *part = [self _predicateOf:node[i] bound:bound message:message];
            if (!part) return nil;
            [parts addObject:part];
        }
        return [kind isEqualToString:@"or"] ? [UDSQLPredicate or:parts] : [UDSQLPredicate and:parts];
    }
    if ([kind isEqualToString:@"not"]) {
        UDSQLPredicate *inner = [self _predicateOf:node[1] bound:bound message:message];
        return inner ? [UDSQLPredicate not:inner] : nil;
    }
    if ([kind isEqualToString:@"null"]) {
        UDSQLExpression *tested = [self _expressionOf:node[1] bound:bound message:message];
        if (!tested) return nil;
        UDSQLPredicate *null = [UDSQLPredicate isNull:tested];
        return [node[2] boolValue] ? [UDSQLPredicate not:null] : null;
    }
    UDSQLExpression *left = [self _expressionOf:node[2] bound:bound message:message];
    UDSQLExpression *right = left ? [self _expressionOf:node[3] bound:bound message:message] : nil;
    return right ? [UDSQLPredicate compare:left op:UDComparison(node[1]) to:right] : nil;
}

- (UDSQLPredicate *)predicateWithBound:(NSDictionary<NSString *, UDSQLExpression *> *)bound message:(NSString **)message {
    return [self _predicateOf:_tree bound:bound message:message];
}

@end
