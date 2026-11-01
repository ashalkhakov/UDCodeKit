/*---------------------------------------------------------------------------------------------
 *  UDSQLQbE.m
 *--------------------------------------------------------------------------------------------*/

#import "UDSQLQbE.h"

NSString *const UDSQLQbEColumnErrorKey = @"UDSQLQbEColumn";
NSString *const UDSQLQbERowErrorKey = @"UDSQLQbERow";

static const NSTimeInterval UDDay = 86400;

/// A value as typed, read for its column: a number, text, or a Core Data
/// date (its day's end too, when only a day was typed).
@interface UDQbEValue : NSObject
@property (nonatomic, strong) id value;
@property (nonatomic, strong, nullable) id dayEnd;
@end

@implementation UDQbEValue
@end

@implementation UDSQLQbE {
    UDSQLSchema *_schema;           // a store's entities and dates
    NSMutableArray *_parameters;    // the one being written
    BOOL _literals;                 // its values written in, not as parameters
}

- (instancetype)initWithTable:(UDSQLTable *)table schema:(UDSQLSchema *)schema dialect:(UDSQLDialect)dialect {
    self = [super init];
    if (self) {
        _table = table;
        _schema = schema;
        _dialect = dialect;
        _conditions = @[];
        _order = @[];
    }
    return self;
}

+ (NSString *)quotedIdentifier:(NSString *)name dialect:(UDSQLDialect)dialect {
    if (dialect == UDSQLDialectMySQL) return [NSString stringWithFormat:@"`%@`", [name stringByReplacingOccurrencesOfString:@"`" withString:@"``"]];
    return [NSString stringWithFormat:@"\"%@\"", [name stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""]];
}

- (NSString *)_quoted:(NSString *)name {
    return [[self class] quotedIdentifier:name dialect:_dialect];
}

- (NSString *)_tableName {
    NSString *name = [self _quoted:_table.name];
    return _table.schema.length ? [NSString stringWithFormat:@"%@.%@", [self _quoted:_table.schema], name] : name;
}

// ---------------------------------------------------------------------------
// MARK: - Values: a parameter, or written in
// ---------------------------------------------------------------------------

- (NSString *)_literal:(id)value {
    if ([value isKindOfClass:[NSNumber class]]) return [value description];
    NSString *text = [value description];
    if (_dialect == UDSQLDialectMySQL) text = [text stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    return [NSString stringWithFormat:@"'%@'", [text stringByReplacingOccurrencesOfString:@"'" withString:@"''"]];
}

/// @a value's place in the statement: a placeholder in the dialect's
/// style (its value kept), or the value written in.
- (NSString *)_place:(id)value {
    if (_literals) return [self _literal:value];
    [_parameters addObject:value];
    return _dialect == UDSQLDialectPostgreSQL ? [NSString stringWithFormat:@"$%lu", (unsigned long)_parameters.count] : @"?";
}

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

- (BOOL)_isCoreDataDate:(UDSQLColumnInfo *)column {
    return _schema.coreDataStore && [column.type caseInsensitiveCompare:@"TIMESTAMP"] == NSOrderedSame;
}

/// @a text as a value of @a column; quoted, always text.
- (UDQbEValue *)_valueOf:(NSString *)text column:(UDSQLColumnInfo *)column quoted:(BOOL)quoted {
    UDQbEValue *value = [[UDQbEValue alloc] init];
    value.value = text;
    if (quoted) return value;
    if ([self _isCoreDataDate:column]) {
        BOOL day = NO;
        NSDate *date = UDDateOf(text, &day);
        if (date) {
            value.value = @(date.timeIntervalSinceReferenceDate);
            if (day) value.dayEnd = @(date.timeIntervalSinceReferenceDate + UDDay);
            return value;
        }
    }
    if (_schema.coreDataStore && [column.name isEqualToString:@"Z_ENT"]) {
        for (NSNumber *entity in _schema.coreDataEntities) {
            if ([_schema.coreDataEntities[entity] caseInsensitiveCompare:text] == NSOrderedSame) {
                value.value = entity;
                return value;
            }
        }
    }
    NSNumber *number = UDIsNumeric(column.type ?: @"") ? UDNumberOf(text) : nil;
    if (number) value.value = number;
    return value;
}

// ---------------------------------------------------------------------------
// MARK: - A condition
// ---------------------------------------------------------------------------

static NSError *UDConditionError(NSString *message, NSString *column, NSUInteger row) {
    return [NSError errorWithDomain:UDSQLErrorDomain code:-1 userInfo:@{
        NSLocalizedDescriptionKey: [NSString stringWithFormat:@"%@: %@", column, message],
        UDSQLQbEColumnErrorKey: column, UDSQLQbERowErrorKey: @(row) }];
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

/// The comparison of @a name with a value: a Core Data day's, the whole
/// day (> a day: after it; <= a day: up to its end).
- (NSString *)_compare:(NSString *)name op:(NSString *)op value:(UDQbEValue *)value {
    if (!value.dayEnd) return [NSString stringWithFormat:@"%@ %@ %@", name, op, [self _place:value.value]];
    if ([op isEqualToString:@"="]) {
        NSString *from = [self _place:value.value];
        return [NSString stringWithFormat:@"(%@ >= %@ AND %@ < %@)", name, from, name, [self _place:value.dayEnd]];
    }
    if ([op isEqualToString:@"<>"]) {
        NSString *from = [self _place:value.value];
        return [NSString stringWithFormat:@"(%@ < %@ OR %@ >= %@)", name, from, name, [self _place:value.dayEnd]];
    }
    if ([op isEqualToString:@">"]) return [NSString stringWithFormat:@"%@ >= %@", name, [self _place:value.dayEnd]];
    if ([op isEqualToString:@"<="]) return [NSString stringWithFormat:@"%@ < %@", name, [self _place:value.dayEnd]];
    return [NSString stringWithFormat:@"%@ %@ %@", name, op, [self _place:value.value]];
}

/// The SQL of @a text typed under @a column; nil and @a message when it
/// can't be read.
- (nullable NSString *)_conditionOf:(NSString *)typed column:(UDSQLColumnInfo *)column message:(NSString **)message {
    NSString *text = [typed stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *name = [self _quoted:column.name];
    NSString *lower = text.lowercaseString;
    if ([@[ @"null", @"is null", @"= null" ] containsObject:lower]) return [name stringByAppendingString:@" IS NULL"];
    if ([@[ @"not null", @"!null", @"! null", @"is not null", @"<> null", @"!= null" ] containsObject:lower]) {
        return [name stringByAppendingString:@" IS NOT NULL"];
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
        *message = @"not what?";
        return nil;
    }
    NSString *condition = nil;
    if (unquoted) {
        condition = [self _compare:name op:@"=" value:[self _valueOf:unquoted column:column quoted:YES]];
    } else {
        // a comparison
        for (NSString *op in @[ @">=", @"<=", @"<>", @"!=", @">", @"<", @"=" ]) {
            if (![text hasPrefix:op]) continue;
            NSString *rest = [[text substringFromIndex:op.length] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (!rest.length) {
                *message = [NSString stringWithFormat:@"%@ what?", op];
                return nil;
            }
            NSString *operand = UDUnquoted(rest) ?: rest;
            condition = [self _compare:name op:[op isEqualToString:@"!="] ? @"<>" : op
                                 value:[self _valueOf:operand column:column quoted:UDUnquoted(rest) != nil]];
            break;
        }
    }
    if (!condition) {
        NSArray *range = UDSplit(text, @"..");
        NSArray *list = UDSplit(text, @",");
        if (range.count == 2 && [range[0] length] && [range[1] length]) {
            UDQbEValue *from = [self _valueOf:UDUnquoted(range[0]) ?: range[0] column:column quoted:UDUnquoted(range[0]) != nil];
            UDQbEValue *to = [self _valueOf:UDUnquoted(range[1]) ?: range[1] column:column quoted:UDUnquoted(range[1]) != nil];
            NSString *low = [self _place:from.value];
            condition = to.dayEnd ? [NSString stringWithFormat:@"(%@ >= %@ AND %@ < %@)", name, low, name, [self _place:to.dayEnd]]
                                  : [NSString stringWithFormat:@"%@ BETWEEN %@ AND %@", name, low, [self _place:to.value]];
        } else if (list.count > 1) {
            NSMutableArray *places = [NSMutableArray array];
            for (NSString *part in list) {
                if (!part.length) continue;
                [places addObject:[self _place:[self _valueOf:UDUnquoted(part) ?: part column:column quoted:UDUnquoted(part) != nil].value]];
            }
            condition = [NSString stringWithFormat:@"%@ IN (%@)", name, [places componentsJoinedByString:@", "]];
        } else if ([text rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"*%"]].location != NSNotFound) {
            // like it, case not minded: PostgreSQL's ILIKE, of the column's text
            NSString *pattern = [self _place:[text stringByReplacingOccurrencesOfString:@"*" withString:@"%"]];
            condition = _dialect == UDSQLDialectPostgreSQL ? [NSString stringWithFormat:@"CAST(%@ AS TEXT) ILIKE %@", name, pattern]
                                                           : [NSString stringWithFormat:@"%@ LIKE %@", name, pattern];
        } else {
            condition = [self _compare:name op:@"=" value:[self _valueOf:text column:column quoted:NO]];
        }
    }
    return negated ? [NSString stringWithFormat:@"NOT (%@)", condition] : condition;
}

// ---------------------------------------------------------------------------
// MARK: - Operators, examples, help
// ---------------------------------------------------------------------------

/// What is typed without its comparison or negation: its value.
static NSString *UDOperandOf(NSString *text) {
    NSString *operand = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSString *lower = operand.lowercaseString;
    if ([@[ @"null", @"not null", @"is null", @"is not null", @"!null" ] containsObject:lower]) return @"";
    if ([operand hasPrefix:@"!"] && ![operand hasPrefix:@"!="]) operand = [operand substringFromIndex:1];
    else if ([lower hasPrefix:@"not "]) operand = [operand substringFromIndex:4];
    for (NSString *op in @[ @">=", @"<=", @"<>", @"!=", @">", @"<", @"=" ]) {
        if ([operand hasPrefix:op]) {
            operand = [operand substringFromIndex:op.length];
            break;
        }
    }
    return [operand stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

+ (NSString *)condition:(NSString *)text withOperator:(UDSQLQbEOperator)op complete:(BOOL *)complete {
    NSString *trimmed = [text ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSString *operand = UDOperandOf(trimmed);
    NSString *made = nil;
    BOOL done = operand.length > 0;
    switch (op) {
        case UDSQLQbEEqual: made = operand; break;
        case UDSQLQbENotEqual: made = [@"<> " stringByAppendingString:operand]; break;
        case UDSQLQbEGreater: made = [@"> " stringByAppendingString:operand]; break;
        case UDSQLQbEAtLeast: made = [@">= " stringByAppendingString:operand]; break;
        case UDSQLQbELess: made = [@"< " stringByAppendingString:operand]; break;
        case UDSQLQbEAtMost: made = [@"<= " stringByAppendingString:operand]; break;
        case UDSQLQbELike:
            made = [operand rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"*%"]].location != NSNotFound
                ? operand : [operand stringByAppendingString:@"*"];
            break;
        case UDSQLQbEBetween:
            // the other end still to type, unless it is there
            done = [operand rangeOfString:@".."].location != NSNotFound && ![operand hasSuffix:@".."];
            made = done ? operand : [operand stringByAppendingString:@".."];
            break;
        case UDSQLQbEOneOf:
            done = NO;
            made = operand.length ? [operand stringByAppendingString:@", "] : @"";
            break;
        case UDSQLQbENull: made = @"NULL"; done = YES; break;
        case UDSQLQbENotNull: made = @"NOT NULL"; done = YES; break;
        case UDSQLQbENot:
            // not so, or so again
            if ([trimmed hasPrefix:@"!"] && ![trimmed hasPrefix:@"!="]) made = [trimmed substringFromIndex:1];
            else if ([trimmed.lowercaseString isEqualToString:@"null"]) made = @"NOT NULL";
            else if ([trimmed.lowercaseString isEqualToString:@"not null"]) made = @"NULL";
            else made = [@"!" stringByAppendingString:trimmed];
            done = UDOperandOf(made).length > 0 || [made.lowercaseString hasSuffix:@"null"];
            break;
        case UDSQLQbEClear: made = @""; done = YES; break;
    }
    if (complete) *complete = done;
    return made ?: trimmed;
}

/// The kind of value a column holds, as its examples tell it.
typedef NS_ENUM(NSInteger, UDColumnKind) { UDColumnText, UDColumnNumber, UDColumnDate, UDColumnEntity };

static UDColumnKind UDKindOf(UDSQLColumnInfo *column, UDSQLSchema *schema) {
    if (schema.coreDataStore && [column.name isEqualToString:@"Z_ENT"]) return UDColumnEntity;
    if (schema.coreDataStore && [column.type caseInsensitiveCompare:@"TIMESTAMP"] == NSOrderedSame) return UDColumnDate;
    NSString *lower = column.type.lowercaseString ?: @"";
    if ([lower containsString:@"date"] || [lower containsString:@"time"]) return UDColumnDate;
    return UDIsNumeric(column.type ?: @"") ? UDColumnNumber : UDColumnText;
}

+ (NSString *)exampleForColumn:(UDSQLColumnInfo *)column schema:(UDSQLSchema *)schema {
    switch (UDKindOf(column, schema)) {
        case UDColumnNumber: return @"e.g. > 5";
        case UDColumnDate: return @"e.g. > 2024-05-01";
        case UDColumnEntity: return [@"e.g. " stringByAppendingString:schema.coreDataEntities.allValues.firstObject ?: @"Entity"];
        case UDColumnText: return @"e.g. Ann*";
    }
    return @"";
}

+ (NSString *)helpForColumn:(UDSQLColumnInfo *)column schema:(UDSQLSchema *)schema {
    NSString *value = @"Ann", *other = @"Bob", *low = @"A", *high = @"M";
    switch (UDKindOf(column, schema)) {
        case UDColumnNumber: value = @"5"; other = @"7"; low = @"1"; high = @"10"; break;
        case UDColumnDate: value = @"2024-05-01"; other = @"2024-06-01"; low = @"2024-05-01"; high = @"2024-05-31"; break;
        case UDColumnEntity: value = schema.coreDataEntities.allValues.firstObject ?: @"Entity"; other = value; break;
        case UDColumnText: break;
    }
    NSMutableArray *lines = [NSMutableArray arrayWithObject:[NSString stringWithFormat:@"%@ (%@): rows whose value is", column.name, column.type ?: @"?"]];
    [lines addObjectsFromArray:@[ [NSString stringWithFormat:@"  %@ — that", value],
                                  [NSString stringWithFormat:@"  > %@, >= %@, < %@, <= %@, <> %@ — compared", value, value, value, value, value],
                                  [NSString stringWithFormat:@"  %@..%@ — between, both included", low, high],
                                  [NSString stringWithFormat:@"  %@, %@ — one of them", value, other],
                                  @"  NULL, NOT NULL",
                                  [NSString stringWithFormat:@"  !%@ — not so (any of these)", value] ]];
    if (UDKindOf(column, schema) == UDColumnText) [lines insertObject:@"  Ann* — like it (* any text, case aside)" atIndex:3];
    if (UDKindOf(column, schema) == UDColumnDate && schema.coreDataStore) [lines addObject:@"  a day alone is the whole day"];
    [lines addObject:@"Its ▾ (or a right-click) offers them; Or adds a row of conditions."];
    return [lines componentsJoinedByString:@"\n"];
}

// ---------------------------------------------------------------------------
// MARK: - The statements
// ---------------------------------------------------------------------------

/// " WHERE …" (or nothing), its values in _parameters or written in.
- (nullable NSString *)_where:(NSError **)error {
    NSMutableArray<NSArray<NSString *> *> *rows = [NSMutableArray array];
    for (NSUInteger row = 0; row < _conditions.count; row++) {
        NSMutableArray *parts = [NSMutableArray array];
        for (UDSQLColumnInfo *column in _table.columns) {
            NSString *typed = _conditions[row][column.name];
            if (![typed stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length) continue;
            NSString *message = nil;
            NSString *condition = [self _conditionOf:typed column:column message:&message];
            if (!condition) {
                if (error) *error = UDConditionError(message, column.name, row);
                return nil;
            }
            [parts addObject:condition];
        }
        if (parts.count) [rows addObject:parts];
    }
    // a row's conditions all, any row: parenthesized only where it matters
    NSMutableArray *alternatives = [NSMutableArray array];
    for (NSArray *parts in rows) {
        NSString *all = [parts componentsJoinedByString:@" AND "];
        [alternatives addObject:rows.count > 1 && parts.count > 1 ? [NSString stringWithFormat:@"(%@)", all] : all];
    }
    NSMutableArray *clauses = [NSMutableArray array];
    if (_restriction.length) [clauses addObject:_restriction];
    if (alternatives.count) {
        NSString *any = [alternatives componentsJoinedByString:@" OR "];
        [clauses addObject:_restriction.length && alternatives.count > 1 ? [NSString stringWithFormat:@"(%@)", any] : any];
    }
    return clauses.count ? [@" WHERE " stringByAppendingString:[clauses componentsJoinedByString:@" AND "]] : @"";
}

- (NSString *)_orderBy {
    NSMutableArray *terms = [NSMutableArray array];
    for (NSSortDescriptor *descriptor in _order) {
        [terms addObject:[NSString stringWithFormat:@"%@%@", [self _quoted:descriptor.key], descriptor.ascending ? @"" : @" DESC"]];
    }
    if (!terms.count) {
        for (UDSQLColumnInfo *column in _table.columns) if (column.primaryKey) [terms addObject:[self _quoted:column.name]];
    }
    return terms.count ? [@" ORDER BY " stringByAppendingString:[terms componentsJoinedByString:@", "]] : @"";
}

- (nullable NSString *)_selectWithLimit:(NSUInteger)limit offset:(NSUInteger)offset error:(NSError **)error {
    NSString *where = [self _where:error];
    if (!where) return nil;
    NSString *page = offset ? [NSString stringWithFormat:@" LIMIT %lu OFFSET %lu", (unsigned long)limit, (unsigned long)offset]
                            : [NSString stringWithFormat:@" LIMIT %lu", (unsigned long)limit];
    return [NSString stringWithFormat:@"SELECT * FROM %@%@%@%@", [self _tableName], where, [self _orderBy], page];
}

- (UDSQLStatement *)selectStatementWithLimit:(NSUInteger)limit offset:(NSUInteger)offset error:(NSError **)error {
    _literals = NO;
    _parameters = [NSMutableArray array];
    NSString *sql = [self _selectWithLimit:limit offset:offset error:error];
    return sql ? [[UDSQLStatement alloc] initWithText:sql SQL:sql parameters:_parameters] : nil;
}

- (UDSQLStatement *)countStatement:(NSError **)error {
    _literals = NO;
    _parameters = [NSMutableArray array];
    NSString *where = [self _where:error];
    if (!where) return nil;
    NSString *sql = [NSString stringWithFormat:@"SELECT count(*) FROM %@%@", [self _tableName], where];
    return [[UDSQLStatement alloc] initWithText:sql SQL:sql parameters:_parameters];
}

- (NSString *)SQLWithLimit:(NSUInteger)limit offset:(NSUInteger)offset error:(NSError **)error {
    _literals = YES;
    NSString *sql = [self _selectWithLimit:limit offset:offset error:error];
    _literals = NO;
    return sql;
}

@end
