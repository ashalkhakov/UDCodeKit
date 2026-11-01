/*---------------------------------------------------------------------------------------------
 *  UDSQLExampleQuery.m
 *--------------------------------------------------------------------------------------------*/

#import "UDSQLExampleQuery.h"

NSString *const UDSQLExampleSkeletonErrorKey = @"UDSQLExampleSkeleton";
NSString *const UDSQLExampleRowErrorKey = @"UDSQLExampleRow";
NSString *const UDSQLExampleColumnErrorKey = @"UDSQLExampleColumn";

static const NSTimeInterval UDDay = 86400;

@implementation UDSQLExampleRow

+ (instancetype)rowWithEntries:(NSDictionary<NSString *, NSString *> *)entries {
    UDSQLExampleRow *row = [[self alloc] init];
    row.entries = entries;
    return row;
}

- (BOOL)isEmpty {
    if (_negated || _inclusive) return NO;
    for (NSString *typed in _entries.allValues) {
        if ([typed stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length) return NO;
    }
    return YES;
}

@end

@implementation UDSQLExampleSkeleton

+ (instancetype)skeletonOf:(UDSQLTable *)table rows:(NSArray<UDSQLExampleRow *> *)rows {
    UDSQLExampleSkeleton *skeleton = [[self alloc] init];
    skeleton->_table = table;
    skeleton.rows = rows;
    return skeleton;
}

@end

// ---------------------------------------------------------------------------
// MARK: - Values and conditions: the browser's, as predicates
// ---------------------------------------------------------------------------

/// A value as typed, read for its column: a number, text, or a Core Data
/// date (its day's end too, when only a day was typed).
@interface UDExampleValue : NSObject
@property (nonatomic, strong) id value;
@property (nonatomic, strong, nullable) id dayEnd;
@end

@implementation UDExampleValue
@end

static BOOL UDIsNumeric(NSString *type) {
    NSString *lower = type.lowercaseString;
    if ([lower hasPrefix:@"interval"] || [lower hasPrefix:@"point"]) return NO;
    for (NSString *prefix in @[ @"int", @"tinyint", @"smallint", @"mediumint", @"bigint", @"real", @"numeric", @"decimal", @"float",
                                @"double", @"serial", @"bigserial", @"smallserial", @"money" ]) {
        if ([lower hasPrefix:prefix]) return YES;
    }
    // SQLite's affinity: a type naming INT is an integer's
    return [lower containsString:@"int"];
}

static NSNumber *UDNumberOf(NSString *text) {
    NSScanner *scanner = [NSScanner scannerWithString:text];
    double number;
    if (![scanner scanDouble:&number] || !scanner.isAtEnd) return nil;
    if ([text rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@".eE"]].location == NSNotFound) {
        return @([text longLongValue]);
    }
    return @(number);
}

/// A date as typed, and whether only its day was.
static NSDate *UDDateOf(NSString *text, BOOL *day) {
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"];
    for (NSString *format in @[ @"yyyy-MM-dd HH:mm:ss", @"yyyy-MM-dd HH:mm", @"yyyy-MM-dd" ]) {
        formatter.dateFormat = format;
        NSDate *date = [formatter dateFromString:text];
        if (date) {
            *day = format.length == 10;
            return date;
        }
    }
    return nil;
}

/// @a text as a value of @a column; quoted, always text.
static UDExampleValue *UDValueOf(NSString *text, UDSQLColumnInfo *column, UDSQLSchema *schema, BOOL quoted) {
    UDExampleValue *value = [[UDExampleValue alloc] init];
    value.value = text;
    if (quoted) return value;
    if (schema.coreDataStore && [column.type caseInsensitiveCompare:@"TIMESTAMP"] == NSOrderedSame) {
        BOOL day = NO;
        NSDate *date = UDDateOf(text, &day);
        if (date) {
            value.value = @(date.timeIntervalSinceReferenceDate);
            if (day) value.dayEnd = @(date.timeIntervalSinceReferenceDate + UDDay);
            return value;
        }
    }
    if (schema.coreDataStore && [column.name isEqualToString:@"Z_ENT"]) {
        for (NSNumber *entity in schema.coreDataEntities) {
            if ([schema.coreDataEntities[entity] caseInsensitiveCompare:text] == NSOrderedSame) {
                value.value = entity;
                return value;
            }
        }
    }
    NSNumber *number = UDIsNumeric(column.type ?: @"") ? UDNumberOf(text) : nil;
    if (number) value.value = number;
    return value;
}

/// @a text without its quotes, if it is all one quoted string.
static NSString *UDUnquoted(NSString *text) {
    if (text.length < 2) return nil;
    unichar first = [text characterAtIndex:0];
    if ((first != '\'' && first != '"') || [text characterAtIndex:text.length - 1] != first) return nil;
    NSString *quote = [NSString stringWithCharacters:&first length:1];
    NSString *inside = [text substringWithRange:NSMakeRange(1, text.length - 2)];
    return [inside stringByReplacingOccurrencesOfString:[quote stringByAppendingString:quote] withString:quote];
}

/// @a text split at @a separator, outside quotes.
static NSArray<NSString *> *UDSplit(NSString *text, NSString *separator) {
    NSMutableArray *parts = [NSMutableArray array];
    unichar quote = 0;
    NSUInteger start = 0;
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        if (quote) {
            if (c == quote) quote = 0;
        } else if (c == '\'' || c == '"') {
            quote = c;
        } else if ([[text substringFromIndex:i] hasPrefix:separator]) {
            [parts addObject:[[text substringWithRange:NSMakeRange(start, i - start)]
                                 stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
            start = i + separator.length;
            i = start - 1;
        }
    }
    [parts addObject:[[text substringFromIndex:start] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]];
    return parts;
}

static NSArray<NSString *> *UDOperators(void) {
    return @[ @">=", @"<=", @"<>", @"!=", @">", @"<", @"=" ];
}

static UDSQLComparison UDComparisonOf(NSString *op) {
    if ([op isEqualToString:@">="]) return UDSQLGreaterOrEqual;
    if ([op isEqualToString:@"<="]) return UDSQLLessOrEqual;
    if ([op isEqualToString:@"<>"] || [op isEqualToString:@"!="]) return UDSQLNotEqual;
    if ([op isEqualToString:@">"]) return UDSQLGreater;
    if ([op isEqualToString:@"<"]) return UDSQLLess;
    return UDSQLEqual;
}

/// @a column compared with a value: a Core Data day's, the whole day (> a
/// day: after it; <= a day: up to its end).
static UDSQLPredicate *UDCompare(UDSQLExpression *column, UDSQLComparison op, UDExampleValue *value) {
    UDSQLExpression *from = [UDSQLExpression value:value.value];
    if (!value.dayEnd) return [UDSQLPredicate compare:column op:op to:from];
    UDSQLExpression *end = [UDSQLExpression value:value.dayEnd];
    switch (op) {
        case UDSQLEqual:
            return [UDSQLPredicate and:@[ [UDSQLPredicate compare:column op:UDSQLGreaterOrEqual to:from],
                                          [UDSQLPredicate compare:column op:UDSQLLess to:end] ]];
        case UDSQLNotEqual:
            return [UDSQLPredicate or:@[ [UDSQLPredicate compare:column op:UDSQLLess to:from],
                                         [UDSQLPredicate compare:column op:UDSQLGreaterOrEqual to:end] ]];
        case UDSQLGreater: return [UDSQLPredicate compare:column op:UDSQLGreaterOrEqual to:end];
        case UDSQLLessOrEqual: return [UDSQLPredicate compare:column op:UDSQLLess to:end];
        default: return [UDSQLPredicate compare:column op:op to:from];
    }
}

// ---------------------------------------------------------------------------
// MARK: - Entries: printed, example elements, comparisons, conditions
// ---------------------------------------------------------------------------

/// A column's entry, read.
@interface UDExampleEntry : NSObject
@property (nonatomic, strong) UDSQLColumnInfo *column;
@property (nonatomic) BOOL printed;
@property (nonatomic, copy, nullable) NSString *element;    // bound to it
@property (nonatomic, copy, nullable) NSString *compared;   // compared with it…
@property (nonatomic) UDSQLComparison comparison;           // …so
@property (nonatomic, copy, nullable) NSString *condition;  // its value's, as typed
@end

@implementation UDExampleEntry
@end

/// A row of a skeleton: a tuple variable.
@interface UDExampleTuple : NSObject
@property (nonatomic) NSUInteger skeleton, row;
@property (nonatomic, strong) UDSQLTable *table;
@property (nonatomic, strong) UDSQLExampleRow *source;
@property (nonatomic, strong) NSArray<UDExampleEntry *> *entries;
@property (nonatomic, copy) NSString *variable;             // in its alternative
@property (nonatomic, readonly) NSSet<NSString *> *elements;
@end

@implementation UDExampleTuple

- (NSSet<NSString *> *)elements {
    NSMutableSet *elements = [NSMutableSet set];
    for (UDExampleEntry *entry in _entries) {
        if (entry.element) [elements addObject:entry.element];
        if (entry.compared) [elements addObject:entry.compared];
    }
    return elements;
}

@end

static BOOL UDIsElement(NSString *text) {
    static NSRegularExpression *element;
    if (!element) element = [NSRegularExpression regularExpressionWithPattern:@"^_[A-Za-z0-9_]+$" options:0 error:NULL];
    return [element firstMatchInString:text options:0 range:NSMakeRange(0, text.length)] != nil;
}

@implementation UDSQLExampleQuery

+ (UDSQLPredicate *)predicateOf:(NSString *)typed column:(UDSQLColumnInfo *)column variable:(NSString *)variable
                         schema:(UDSQLSchema *)schema message:(NSString **)message {
    NSString *text = [typed stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    UDSQLExpression *name = [UDSQLExpression column:column.name of:variable];
    NSString *lower = text.lowercaseString;
    if ([@[ @"null", @"is null", @"= null" ] containsObject:lower]) return [UDSQLPredicate isNull:name];
    if ([@[ @"not null", @"!null", @"! null", @"is not null", @"<> null", @"!= null" ] containsObject:lower]) {
        return [UDSQLPredicate not:[UDSQLPredicate isNull:name]];
    }
    // the value as it is, quoted
    NSString *unquoted = UDUnquoted(text);
    BOOL negated = NO;
    if (!unquoted && [text hasPrefix:@"!"] && ![text hasPrefix:@"!="]) {
        negated = YES;
        text = [[text substringFromIndex:1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    } else if (!unquoted && [lower hasPrefix:@"not "]) {
        negated = YES;
        text = [[text substringFromIndex:4] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    }
    if (negated) unquoted = UDUnquoted(text);
    if (!text.length) {
        if (message) *message = @"not what?";
        return nil;
    }
    UDSQLPredicate *condition = nil;
    if (unquoted) {
        condition = UDCompare(name, UDSQLEqual, UDValueOf(unquoted, column, schema, YES));
    } else {
        // a comparison
        for (NSString *op in UDOperators()) {
            if (![text hasPrefix:op]) continue;
            NSString *rest = [[text substringFromIndex:op.length] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (!rest.length) {
                if (message) *message = [NSString stringWithFormat:@"%@ what?", op];
                return nil;
            }
            NSString *operand = UDUnquoted(rest) ?: rest;
            condition = UDCompare(name, UDComparisonOf(op), UDValueOf(operand, column, schema, UDUnquoted(rest) != nil));
            break;
        }
    }
    if (!condition) {
        NSArray *range = UDSplit(text, @"..");
        NSArray *list = UDSplit(text, @",");
        if (range.count == 2 && [range[0] length] && [range[1] length]) {
            UDExampleValue *from = UDValueOf(UDUnquoted(range[0]) ?: range[0], column, schema, UDUnquoted(range[0]) != nil);
            UDExampleValue *to = UDValueOf(UDUnquoted(range[1]) ?: range[1], column, schema, UDUnquoted(range[1]) != nil);
            condition = to.dayEnd
                ? [UDSQLPredicate and:@[ [UDSQLPredicate compare:name op:UDSQLGreaterOrEqual to:[UDSQLExpression value:from.value]],
                                         [UDSQLPredicate compare:name op:UDSQLLess to:[UDSQLExpression value:to.dayEnd]] ]]
                : [UDSQLPredicate between:name low:[UDSQLExpression value:from.value] high:[UDSQLExpression value:to.value]];
        } else if (list.count > 1) {
            NSMutableArray *values = [NSMutableArray array];
            for (NSString *part in list) {
                if (!part.length) continue;
                [values addObject:[UDSQLExpression value:UDValueOf(UDUnquoted(part) ?: part, column, schema, UDUnquoted(part) != nil).value]];
            }
            condition = [UDSQLPredicate in:name values:values];
        } else if ([text rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"*%"]].location != NSNotFound) {
            // like it, case aside
            condition = [UDSQLPredicate like:name pattern:[UDSQLExpression value:[text stringByReplacingOccurrencesOfString:@"*" withString:@"%"]]];
        } else {
            condition = UDCompare(name, UDSQLEqual, UDValueOf(text, column, schema, NO));
        }
    }
    return negated ? [UDSQLPredicate not:condition] : condition;
}

- (instancetype)initWithSchema:(UDSQLSchema *)schema dialect:(UDSQLDialect)dialect {
    self = [super init];
    if (self) {
        _schema = schema;
        _dialect = dialect;
        _skeletons = @[];
        _order = @[];
    }
    return self;
}

static NSError *UDError(NSString *message, NSUInteger skeleton, NSUInteger row, NSString *column) {
    NSMutableDictionary *info = [@{ NSLocalizedDescriptionKey: message, UDSQLExampleSkeletonErrorKey: @(skeleton),
                                    UDSQLExampleRowErrorKey: @(row) } mutableCopy];
    if (column) info[UDSQLExampleColumnErrorKey] = column;
    return [NSError errorWithDomain:UDSQLErrorDomain code:-1 userInfo:info];
}

/// The rows asked of, read; nil and why in @a error.
- (nullable NSArray<UDExampleTuple *> *)_tuples:(NSError **)error {
    NSMutableArray *tuples = [NSMutableArray array];
    for (NSUInteger k = 0; k < _skeletons.count; k++) {
        UDSQLExampleSkeleton *skeleton = _skeletons[k];
        for (NSUInteger j = 0; j < skeleton.rows.count; j++) {
            UDSQLExampleRow *row = skeleton.rows[j];
            if (row.empty) continue;
            UDExampleTuple *tuple = [[UDExampleTuple alloc] init];
            tuple.skeleton = k;
            tuple.row = j;
            tuple.table = skeleton.table;
            tuple.source = row;
            NSMutableArray *entries = [NSMutableArray array];
            for (UDSQLColumnInfo *column in skeleton.table.columns) {
                NSString *text = [row.entries[column.name] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (!text.length) continue;
                UDExampleEntry *entry = [[UDExampleEntry alloc] init];
                entry.column = column;
                if ([text.uppercaseString hasPrefix:@"P."]) {
                    entry.printed = YES;
                    text = [[text substringFromIndex:2] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                }
                if (UDIsElement(text)) entry.element = text;
                else if (text.length) {
                    for (NSString *op in UDOperators()) {
                        if (![text hasPrefix:op]) continue;
                        NSString *rest = [[text substringFromIndex:op.length] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
                        if (UDIsElement(rest)) {
                            entry.compared = rest;
                            entry.comparison = UDComparisonOf(op);
                        }
                        break;
                    }
                    if (!entry.compared) {
                        // a condition on its value: read now, to say what can't be
                        NSString *message = nil;
                        if (![[self class] predicateOf:text column:column variable:skeleton.table.name schema:_schema message:&message]) {
                            if (error) *error = UDError([NSString stringWithFormat:@"%@: %@", column.name, message], k, j, column.name);
                            return nil;
                        }
                        entry.condition = text;
                    }
                }
                if (entry.printed && row.negated) {
                    if (error) *error = UDError([NSString stringWithFormat:@"%@: a row that is not there (¬) prints nothing", column.name], k, j, column.name);
                    return nil;
                }
                [entries addObject:entry];
            }
            tuple.entries = entries;
            [tuples addObject:tuple];
        }
    }
    return tuples;
}

/// The tuples linked by their example elements: the alternatives.
static NSArray<NSArray<UDExampleTuple *> *> *UDAlternatives(NSArray<UDExampleTuple *> *tuples) {
    NSMutableArray *alternatives = [NSMutableArray array];
    NSMutableSet *placed = [NSMutableSet set];
    for (UDExampleTuple *tuple in tuples) {
        if ([placed containsObject:tuple]) continue;
        NSMutableArray *alternative = [NSMutableArray arrayWithObject:tuple];
        [placed addObject:tuple];
        for (NSUInteger i = 0; i < alternative.count; i++) {
            NSSet *elements = [alternative[i] elements];
            for (UDExampleTuple *other in tuples) {
                if (![placed containsObject:other] && [other.elements intersectsSet:elements]) {
                    [alternative addObject:other];
                    [placed addObject:other];
                }
            }
        }
        // in the skeletons' order
        [alternative sortUsingDescriptors:@[ [NSSortDescriptor sortDescriptorWithKey:@"skeleton" ascending:YES],
                                             [NSSortDescriptor sortDescriptorWithKey:@"row" ascending:YES] ]];
        [alternatives addObject:alternative];
    }
    return alternatives;
}

// ---------------------------------------------------------------------------
// MARK: - Its relation
// ---------------------------------------------------------------------------

- (nullable UDSQLPredicate *)_restrictionOf:(NSString *)variable {
    if (!_restrictionColumn.length || !_restrictionValues.count) return nil;
    NSMutableArray *values = [NSMutableArray array];
    for (id value in _restrictionValues) [values addObject:[UDSQLExpression value:value]];
    return [UDSQLPredicate in:[UDSQLExpression column:_restrictionColumn of:variable] values:values];
}

- (NSArray<UDSQLPredicate *> *)_conditionsOf:(UDExampleTuple *)tuple {
    NSMutableArray *conditions = [NSMutableArray array];
    for (UDExampleEntry *entry in tuple.entries) {
        if (entry.condition) {
            [conditions addObject:[[self class] predicateOf:entry.condition column:entry.column variable:tuple.variable schema:_schema message:NULL]];
        }
    }
    return conditions;
}

/// What it prints, in the skeletons' and columns' order: the expressions
/// and their names (two of a name told apart by their variables).
- (void)_printsOf:(NSArray<UDExampleTuple *> *)alternative columns:(NSMutableArray *)columns names:(NSMutableArray *)names {
    NSCountedSet *seen = [NSCountedSet set];
    for (UDExampleTuple *tuple in alternative) {
        for (UDExampleEntry *entry in tuple.entries) if (entry.printed) [seen addObject:entry.column.name];
    }
    for (UDExampleTuple *tuple in alternative) {
        for (UDExampleEntry *entry in tuple.entries) {
            if (!entry.printed) continue;
            [columns addObject:[UDSQLExpression column:entry.column.name of:tuple.variable]];
            [names addObject:[seen countForObject:entry.column.name] > 1
                ? [NSString stringWithFormat:@"%@.%@", tuple.variable, entry.column.name] : entry.column.name];
        }
    }
}

/// An alternative as a relation: its first row's table joined to its
/// others as they are linked, selected, projected; nil and why.
- (nullable UDSQLRelation *)_relationOf:(NSArray<UDExampleTuple *> *)alternative anyPrinted:(BOOL)anyPrinted error:(NSError **)error {
    UDExampleTuple *first = alternative.firstObject;
    if (first.skeleton != 0) {
        if (error) *error = UDError([NSString stringWithFormat:@"This row of %@ is linked to no row of %@: give one of its columns an example element (_x) one of them has",
                                     first.table.name, _skeletons.firstObject.table.name], first.skeleton, first.row, nil);
        return nil;
    }
    // each its variable: its table's name, then name2…
    NSMutableDictionary *counts = [NSMutableDictionary dictionary];
    for (UDExampleTuple *tuple in alternative) {
        NSUInteger n = [counts[tuple.table.name] unsignedIntegerValue] + 1;
        counts[tuple.table.name] = @(n);
        tuple.variable = n == 1 ? tuple.table.name : [NSString stringWithFormat:@"%@%lu", tuple.table.name, (unsigned long)n];
    }
    NSMutableDictionary<NSString *, UDSQLExpression *> *bound = [NSMutableDictionary dictionary];
    NSMutableArray<UDSQLPredicate *> *where = [NSMutableArray array];
    NSMutableArray *deferred = [NSMutableArray array];     // comparisons with elements bound later: [tuple, entry]
    UDSQLRelation *relation = [UDSQLRelation table:first.table variable:first.variable];
    NSMutableArray *joined = [NSMutableArray arrayWithObject:first];
    [self _link:first bound:bound into:where deferred:deferred];
    [where addObjectsFromArray:[self _conditionsOf:first]];
    if ([self _restrictionOf:first.variable]) [where addObject:[self _restrictionOf:first.variable]];
    NSMutableArray *positive = [NSMutableArray array], *negated = [NSMutableArray array];
    for (UDExampleTuple *tuple in alternative) {
        if (tuple == first) continue;
        [tuple.source.negated ? negated : positive addObject:tuple];
    }
    // the others, each once linked to those joined
    while (positive.count) {
        UDExampleTuple *next = nil;
        for (UDExampleTuple *tuple in positive) {
            for (UDExampleTuple *done in joined) if ([tuple.elements intersectsSet:done.elements]) next = tuple;
            if (next) break;
        }
        if (!next) {
            UDExampleTuple *tuple = positive.firstObject;
            if (error) *error = UDError([NSString stringWithFormat:@"This row of %@ is linked to the rest only through a row that is not there (¬)",
                                         tuple.table.name], tuple.skeleton, tuple.row, nil);
            return nil;
        }
        [positive removeObject:next];
        NSMutableArray *on = [NSMutableArray array];
        [self _link:next bound:bound into:on deferred:deferred];
        // comparisons waiting for an element it binds: in its join
        for (NSArray *pair in [deferred copy]) {
            UDExampleEntry *entry = pair[1];
            if (!bound[entry.compared] || pair[0] == next) continue;
            UDExampleTuple *tuple = pair[0];
            [on addObject:[UDSQLPredicate compare:[UDSQLExpression column:entry.column.name of:tuple.variable] op:entry.comparison
                                               to:bound[entry.compared]]];
            [deferred removeObjectIdenticalTo:pair];
        }
        if (next.skeleton == 0 && [self _restrictionOf:next.variable]) [on addObject:[self _restrictionOf:next.variable]];
        if (next.source.inclusive) [on addObjectsFromArray:[self _conditionsOf:next]];
        else [where addObjectsFromArray:[self _conditionsOf:next]];
        relation = [relation join:[UDSQLRelation table:next.table variable:next.variable] on:[UDSQLPredicate and:on]
                             kind:next.source.inclusive ? UDSQLJoinLeft : UDSQLJoinInner];
        [joined addObject:next];
    }
    // the comparisons with elements bound after them
    for (NSArray *pair in deferred) {
        UDExampleTuple *tuple = pair[0];
        UDExampleEntry *entry = pair[1];
        UDSQLExpression *value = bound[entry.compared];
        if (!value) {
            if (error) *error = UDError([NSString stringWithFormat:@"%@: %@ is never given a value: put it alone under a column of a row that is there",
                                         entry.column.name, entry.compared], tuple.skeleton, tuple.row, entry.column.name);
            return nil;
        }
        [where addObject:[UDSQLPredicate compare:[UDSQLExpression column:entry.column.name of:tuple.variable] op:entry.comparison to:value]];
    }
    // the rows that are not there: NOT EXISTS
    for (UDExampleTuple *tuple in negated) {
        NSMutableDictionary *local = [bound mutableCopy];
        NSMutableArray *inner = [NSMutableArray array], *pending = [NSMutableArray array];
        [self _link:tuple bound:local into:inner deferred:pending];
        for (NSArray *pair in pending) {
            UDExampleEntry *entry = pair[1];
            UDSQLExpression *value = local[entry.compared];
            if (!value) {
                if (error) *error = UDError([NSString stringWithFormat:@"%@: %@ is never given a value", entry.column.name, entry.compared],
                                            tuple.skeleton, tuple.row, entry.column.name);
                return nil;
            }
            [inner addObject:[UDSQLPredicate compare:[UDSQLExpression column:entry.column.name of:tuple.variable] op:entry.comparison to:value]];
        }
        [inner addObjectsFromArray:[self _conditionsOf:tuple]];
        UDSQLRelation *absent = [UDSQLRelation table:tuple.table variable:tuple.variable];
        if (inner.count) absent = [absent select:[UDSQLPredicate and:inner]];
        [where addObject:[UDSQLPredicate not:[UDSQLPredicate exists:absent]]];
    }
    if (where.count) relation = [relation select:[UDSQLPredicate and:where]];
    if (!anyPrinted) return [relation projectAllOf:first.variable];
    NSMutableArray *columns = [NSMutableArray array], *names = [NSMutableArray array];
    [self _printsOf:alternative columns:columns names:names];
    return [relation project:columns names:names];
}

/// A row's example elements: bound (the first time, else equal to it) and
/// compared (with one bound, else later).
- (void)_link:(UDExampleTuple *)tuple bound:(NSMutableDictionary *)bound into:(NSMutableArray *)into deferred:(NSMutableArray *)deferred {
    for (UDExampleEntry *entry in tuple.entries) {
        if (!entry.element) continue;
        UDSQLExpression *column = [UDSQLExpression column:entry.column.name of:tuple.variable];
        if (bound[entry.element]) [into addObject:[UDSQLPredicate compare:column op:UDSQLEqual to:bound[entry.element]]];
        else bound[entry.element] = column;
    }
    for (UDExampleEntry *entry in tuple.entries) {
        if (!entry.compared) continue;
        if (bound[entry.compared]) {
            [into addObject:[UDSQLPredicate compare:[UDSQLExpression column:entry.column.name of:tuple.variable] op:entry.comparison
                                                 to:bound[entry.compared]]];
        } else {
            [deferred addObject:@[ tuple, entry ]];
        }
    }
}

/// Whether an alternative is a row of the first skeleton alone, asking of
/// its values only (alternatives of those are one OR).
static BOOL UDIsPlain(NSArray<UDExampleTuple *> *alternative) {
    if (alternative.count != 1) return NO;
    UDExampleTuple *tuple = alternative.firstObject;
    return tuple.skeleton == 0 && !tuple.source.negated && !tuple.source.inclusive && tuple.elements.count == 0;
}

static NSArray<NSString *> *UDPrintedNames(NSArray<UDExampleTuple *> *alternative) {
    NSMutableArray *names = [NSMutableArray array];
    for (UDExampleTuple *tuple in alternative) for (UDExampleEntry *entry in tuple.entries) if (entry.printed) [names addObject:entry.column.name];
    return names;
}

/// Its relation, and whether it is one table's alone (its columns then
/// unqualified, its order by them); what it prints, by name, and (one
/// SELECT's, not a union's) as what.
- (nullable UDSQLRelation *)_relation:(NSError **)error plain:(BOOL *)plain printed:(NSMutableArray *)printed
                          expressions:(NSMutableArray *)expressions {
    UDSQLTable *base = _skeletons.firstObject.table;
    if (!base) {
        if (error) *error = [NSError errorWithDomain:UDSQLErrorDomain code:-1 userInfo:@{ NSLocalizedDescriptionKey: @"Nothing to ask of." }];
        return nil;
    }
    NSArray *tuples = [self _tuples:error];
    if (!tuples) return nil;
    BOOL anyPrinted = NO;
    for (UDExampleTuple *tuple in tuples) for (UDExampleEntry *entry in tuple.entries) if (entry.printed) anyPrinted = YES;
    NSArray *alternatives = UDAlternatives(tuples);
    // none, or each a row of the first table alone printing alike: one OR
    BOOL allPlain = YES;
    for (NSArray *alternative in alternatives) {
        if (!UDIsPlain(alternative) || ![UDPrintedNames(alternative) isEqual:UDPrintedNames(alternatives.firstObject)]) allPlain = NO;
    }
    if (allPlain) {
        *plain = YES;
        NSMutableArray *rows = [NSMutableArray array];
        for (NSArray *alternative in alternatives) {
            UDExampleTuple *tuple = alternative.firstObject;
            tuple.variable = base.name;
            [rows addObject:[UDSQLPredicate and:[self _conditionsOf:tuple]]];
        }
        NSMutableArray *where = [NSMutableArray array];
        UDSQLPredicate *restriction = [self _restrictionOf:base.name];
        if (restriction) [where addObject:restriction];
        if (rows.count) [where addObject:[UDSQLPredicate or:rows]];
        UDSQLRelation *relation = [UDSQLRelation table:base variable:base.name];
        if (where.count) relation = [relation select:[UDSQLPredicate and:where]];
        NSArray *names = alternatives.count ? UDPrintedNames(alternatives.firstObject) : @[];
        if (!anyPrinted || !names.count) names = [base.columns valueForKey:@"name"];
        NSMutableArray *columns = [NSMutableArray array];
        for (NSString *name in names) [columns addObject:[UDSQLExpression column:name of:base.name]];
        [printed addObjectsFromArray:names];
        [expressions addObjectsFromArray:columns];
        return anyPrinted && names.count ? [relation project:columns names:names] : relation;
    }
    *plain = NO;
    NSMutableArray *relations = [NSMutableArray array];
    NSUInteger width = NSNotFound;
    for (NSArray<UDExampleTuple *> *alternative in alternatives) {
        UDSQLRelation *relation = [self _relationOf:alternative anyPrinted:anyPrinted error:error];
        if (!relation) return nil;
        NSMutableArray *columns = [NSMutableArray array], *names = [NSMutableArray array];
        if (anyPrinted) [self _printsOf:alternative columns:columns names:names];
        else {
            for (UDSQLColumnInfo *column in base.columns) {
                [names addObject:column.name];
                [columns addObject:[UDSQLExpression column:column.name of:alternative.firstObject.variable]];
            }
        }
        if (width != NSNotFound && names.count != width) {
            UDExampleTuple *tuple = alternative.firstObject;
            if (error) *error = UDError(@"Its alternatives print different columns: give each the same P. columns", tuple.skeleton, tuple.row, nil);
            return nil;
        }
        if (width == NSNotFound) {
            [printed addObjectsFromArray:names];
            if (alternatives.count == 1) [expressions addObjectsFromArray:columns];
        }
        width = names.count;
        [relations addObject:relation];
    }
    return [UDSQLRelation union:relations];
}

- (UDSQLRelation *)relation:(NSError **)error {
    BOOL plain = NO;
    return [self _relation:error plain:&plain printed:[NSMutableArray array] expressions:[NSMutableArray array]];
}

- (NSArray<NSString *> *)printedColumns:(NSError **)error {
    BOOL plain = NO;
    NSMutableArray *printed = [NSMutableArray array];
    return [self _relation:error plain:&plain printed:printed expressions:[NSMutableArray array]] ? printed : nil;
}

/// Its order: as asked, else by the first table's primary key where it is
/// printed; by what is printed (a union's: by its name).
- (NSArray<UDSQLOrderKey *> *)_keysOf:(NSArray<NSString *> *)printed expressions:(NSArray<UDSQLExpression *> *)expressions {
    NSMutableArray *names = [NSMutableArray array], *ascending = [NSMutableArray array];
    for (NSSortDescriptor *descriptor in _order) {
        [names addObject:descriptor.key];
        [ascending addObject:@(descriptor.ascending)];
    }
    if (!names.count) {
        for (UDSQLColumnInfo *column in _skeletons.firstObject.table.columns) {
            if (!column.primaryKey || ![printed containsObject:column.name]) continue;
            [names addObject:column.name];
            [ascending addObject:@YES];
        }
    }
    NSMutableArray *keys = [NSMutableArray array];
    for (NSUInteger i = 0; i < names.count; i++) {
        NSUInteger index = [printed indexOfObject:names[i]];
        UDSQLExpression *expression = index != NSNotFound && index < expressions.count ? expressions[index] : [UDSQLExpression outputColumn:names[i]];
        [keys addObject:[UDSQLOrderKey key:expression ascending:[ascending[i] boolValue]]];
    }
    return keys;
}

- (nullable UDSQLRelation *)_pageWithLimit:(NSUInteger)limit offset:(NSUInteger)offset error:(NSError **)error {
    BOOL plain = NO;
    NSMutableArray *printed = [NSMutableArray array], *expressions = [NSMutableArray array];
    UDSQLRelation *relation = [self _relation:error plain:&plain printed:printed expressions:expressions];
    if (!relation) return nil;
    NSArray *keys = [self _keysOf:printed expressions:expressions];
    if (keys.count) relation = [relation order:keys];
    return [relation pageFrom:offset limit:limit];
}

- (UDSQLStatement *)selectStatementWithLimit:(NSUInteger)limit offset:(NSUInteger)offset error:(NSError **)error {
    UDSQLRelation *page = [self _pageWithLimit:limit offset:offset error:error];
    if (!page) return nil;
    NSMutableArray *parameters = [NSMutableArray array];
    NSString *sql = [page SQLForDialect:_dialect parameters:parameters];
    return [[UDSQLStatement alloc] initWithText:sql SQL:sql parameters:parameters];
}

- (UDSQLStatement *)countStatement:(NSError **)error {
    UDSQLRelation *relation = [self relation:error];
    if (!relation) return nil;
    NSMutableArray *parameters = [NSMutableArray array];
    NSString *sql = [[relation count] SQLForDialect:_dialect parameters:parameters];
    return [[UDSQLStatement alloc] initWithText:sql SQL:sql parameters:parameters];
}

- (NSString *)SQL:(NSError **)error {
    BOOL plain = NO;
    NSMutableArray *printed = [NSMutableArray array], *expressions = [NSMutableArray array];
    UDSQLRelation *relation = [self _relation:error plain:&plain printed:printed expressions:expressions];
    if (!relation) return nil;
    NSArray *keys = [self _keysOf:printed expressions:expressions];
    return [(keys.count ? [relation order:keys] : relation) SQLForDialect:_dialect parameters:nil];
}

- (NSString *)SQLWithLimit:(NSUInteger)limit offset:(NSUInteger)offset error:(NSError **)error {
    return [[self _pageWithLimit:limit offset:offset error:error] SQLForDialect:_dialect parameters:nil];
}

@end
