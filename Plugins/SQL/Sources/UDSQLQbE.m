/*---------------------------------------------------------------------------------------------
 *  UDSQLQbE.m
 *--------------------------------------------------------------------------------------------*/

#import "UDSQLQbE.h"
#import "UDSQLExampleQuery.h"

NSString *const UDSQLQbEColumnErrorKey = @"UDSQLQbEColumn";
NSString *const UDSQLQbERowErrorKey = @"UDSQLQbERow";

@implementation UDSQLQbE {
    UDSQLSchema *_schema;           // a store's entities and dates
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
    return UDSQLQuoted(name, dialect);
}

static BOOL UDIsNumeric(NSString *type) {
    NSString *lower = type.lowercaseString;
    if ([lower hasPrefix:@"interval"] || [lower hasPrefix:@"point"]) return NO;
    for (NSString *prefix in @[ @"int", @"tinyint", @"smallint", @"mediumint", @"bigint", @"real", @"numeric", @"decimal", @"float",
                                @"double", @"serial", @"bigserial", @"smallserial", @"money" ]) {
        if ([lower hasPrefix:prefix]) return YES;
    }
    return [lower containsString:@"int"];
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
// MARK: - The statements: query by example's, of one skeleton
// ---------------------------------------------------------------------------

/// Its query: one skeleton (its table), a row of it a row of conditions.
- (UDSQLExampleQuery *)_query {
    UDSQLExampleQuery *query = [[UDSQLExampleQuery alloc] initWithSchema:_schema dialect:_dialect];
    NSMutableArray *rows = [NSMutableArray array];
    for (NSDictionary *conditions in _conditions) [rows addObject:[UDSQLExampleRow rowWithEntries:conditions]];
    query.skeletons = @[ [UDSQLExampleSkeleton skeletonOf:_table rows:rows] ];
    query.order = _order;
    query.restrictionColumn = _restrictionColumn;
    query.restrictionValues = _restrictionValues;
    return query;
}

/// Its query's error, as the browser's: by column name and row.
static NSError *UDBrowserError(NSError *error) {
    if (!error) return nil;
    NSMutableDictionary *info = [error.userInfo mutableCopy];
    if (info[UDSQLExampleColumnErrorKey]) info[UDSQLQbEColumnErrorKey] = info[UDSQLExampleColumnErrorKey];
    if (info[UDSQLExampleRowErrorKey]) info[UDSQLQbERowErrorKey] = info[UDSQLExampleRowErrorKey];
    return [NSError errorWithDomain:error.domain code:error.code userInfo:info];
}

- (UDSQLStatement *)selectStatementWithLimit:(NSUInteger)limit offset:(NSUInteger)offset error:(NSError **)error {
    NSError *failure = nil;
    UDSQLStatement *statement = [[self _query] selectStatementWithLimit:limit offset:offset error:&failure];
    if (!statement && error) *error = UDBrowserError(failure);
    return statement;
}

- (UDSQLStatement *)countStatement:(NSError **)error {
    NSError *failure = nil;
    UDSQLStatement *statement = [[self _query] countStatement:&failure];
    if (!statement && error) *error = UDBrowserError(failure);
    return statement;
}

- (NSString *)SQLWithLimit:(NSUInteger)limit offset:(NSUInteger)offset error:(NSError **)error {
    NSError *failure = nil;
    NSString *sql = [[self _query] SQLWithLimit:limit offset:offset error:&failure];
    if (!sql && error) *error = UDBrowserError(failure);
    return sql;
}

@end
