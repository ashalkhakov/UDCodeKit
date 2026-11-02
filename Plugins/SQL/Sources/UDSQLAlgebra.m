/*---------------------------------------------------------------------------------------------
 *  UDSQLAlgebra.m
 *
 *  Written as SELECT blocks: a chain of tables, joins and selections is one
 *  block's FROM and WHERE; a projection its columns; an order and a page
 *  its ORDER BY and LIMIT; a union (and what orders, pages or counts one)
 *  is wrapped: SELECT … FROM (… UNION …) AS "q".
 *--------------------------------------------------------------------------------------------*/

#import "UDSQLAlgebra.h"

NSString *UDSQLQuoted(NSString *name, UDSQLDialect dialect) {
    if (dialect == UDSQLDialectMySQL) return [NSString stringWithFormat:@"`%@`", [name stringByReplacingOccurrencesOfString:@"`" withString:@"``"]];
    return [NSString stringWithFormat:@"\"%@\"", [name stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""]];
}

/// What is written as it is written: its dialect, whether columns are
/// qualified, its parameters (nil: values written in).
@interface UDSQLWriter : NSObject
@property (nonatomic) UDSQLDialect dialect;
@property (nonatomic) BOOL qualified;
@property (nonatomic, strong, nullable) NSMutableArray *parameters;
@end

@implementation UDSQLWriter
@end

// ---------------------------------------------------------------------------
// MARK: - Expressions
// ---------------------------------------------------------------------------

@implementation UDSQLExpression {
    NSString *_operator;            // an arithmetic's (its left the argument): + - * /, or "-" alone
    UDSQLExpression *_right;
}

+ (instancetype)column:(NSString *)name of:(NSString *)variable {
    UDSQLExpression *expression = [[self alloc] init];
    expression->_name = [name copy];
    expression->_variable = [variable copy];
    return expression;
}

+ (instancetype)outputColumn:(NSString *)name {
    UDSQLExpression *expression = [[self alloc] init];
    expression->_name = [name copy];
    return expression;
}

+ (instancetype)value:(id)value {
    UDSQLExpression *expression = [[self alloc] init];
    expression->_value = value;
    return expression;
}

+ (instancetype)arithmetic:(NSString *)op left:(UDSQLExpression *)left right:(UDSQLExpression *)right {
    UDSQLExpression *expression = [[self alloc] init];
    expression->_operator = [op copy];
    expression->_argument = left;
    expression->_right = right;
    return expression;
}

+ (instancetype)negative:(UDSQLExpression *)operand {
    UDSQLExpression *expression = [[self alloc] init];
    expression->_operator = @"-";
    expression->_argument = operand;
    return expression;
}

+ (instancetype)aggregate:(NSString *)function of:(UDSQLExpression *)argument distinct:(BOOL)distinct {
    UDSQLExpression *expression = [[self alloc] init];
    expression->_function = [function copy];
    expression->_argument = argument;
    expression->_distinct = distinct;
    return expression;
}

static NSString *UDLiteral(id value, UDSQLDialect dialect) {
    if (value == [NSNull null]) return @"NULL";
    if ([value isKindOfClass:[NSNumber class]]) return [value description];
    NSString *text = [value description];
    if (dialect == UDSQLDialectMySQL) text = [text stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    return [NSString stringWithFormat:@"'%@'", [text stringByReplacingOccurrencesOfString:@"'" withString:@"''"]];
}

- (NSString *)_SQLWith:(UDSQLWriter *)writer {
    if (_operator) {
        NSString *left = [_argument _SQLWith:writer];
        return _right ? [NSString stringWithFormat:@"(%@ %@ %@)", left, _operator, [_right _SQLWith:writer]]
                      : [NSString stringWithFormat:@"-%@", left];
    }
    if (_function) {
        if (!_argument) return [NSString stringWithFormat:@"%@(*)", _function];
        return [NSString stringWithFormat:@"%@(%@%@)", _function, _distinct ? @"DISTINCT " : @"", [_argument _SQLWith:writer]];
    }
    if (_name) {
        NSString *name = UDSQLQuoted(_name, writer.dialect);
        return _variable && writer.qualified ? [NSString stringWithFormat:@"%@.%@", UDSQLQuoted(_variable, writer.dialect), name] : name;
    }
    if (!writer.parameters) return UDLiteral(_value, writer.dialect);
    [writer.parameters addObject:_value];
    return writer.dialect == UDSQLDialectPostgreSQL ? [NSString stringWithFormat:@"$%lu", (unsigned long)writer.parameters.count] : @"?";
}

@end

// ---------------------------------------------------------------------------
// MARK: - Predicates
// ---------------------------------------------------------------------------

typedef NS_ENUM(NSInteger, UDPredicateKind) {
    UDCompare, UDIsNull, UDLike, UDIn, UDBetween, UDAnd, UDOr, UDNot, UDExists,
};

typedef NS_ENUM(NSInteger, UDRelationKind) {
    UDTable, UDJoin, UDSelect, UDGroup, UDProject, UDUnion, UDOrder, UDPage, UDCount,
};

@interface UDSQLRelation ()
- (NSString *)_SQLWith:(UDSQLWriter *)writer;
- (NSUInteger)_variables;
- (UDRelationKind)_kind;
@end

@implementation UDSQLPredicate {
    UDPredicateKind _kind;
    UDSQLComparison _op;
    NSArray<UDSQLExpression *> *_expressions;   // the compared, the tested, its values
    NSArray<UDSQLPredicate *> *_predicates;     // and, or, not's
    UDSQLRelation *_relation;                   // exists'
}

static UDSQLPredicate *UDPredicate(UDPredicateKind kind, NSArray *expressions, NSArray *predicates) {
    UDSQLPredicate *predicate = [[UDSQLPredicate alloc] init];
    predicate->_kind = kind;
    predicate->_expressions = expressions ?: @[];
    predicate->_predicates = predicates ?: @[];
    return predicate;
}

+ (instancetype)compare:(UDSQLExpression *)left op:(UDSQLComparison)op to:(UDSQLExpression *)right {
    UDSQLPredicate *predicate = UDPredicate(UDCompare, @[ left, right ], nil);
    predicate->_op = op;
    return predicate;
}

+ (instancetype)isNull:(UDSQLExpression *)expression {
    return UDPredicate(UDIsNull, @[ expression ], nil);
}

+ (instancetype)like:(UDSQLExpression *)expression pattern:(UDSQLExpression *)pattern {
    return UDPredicate(UDLike, @[ expression, pattern ], nil);
}

+ (instancetype)in:(UDSQLExpression *)expression values:(NSArray<UDSQLExpression *> *)values {
    return UDPredicate(UDIn, [@[ expression ] arrayByAddingObjectsFromArray:values], nil);
}

+ (instancetype)between:(UDSQLExpression *)expression low:(UDSQLExpression *)low high:(UDSQLExpression *)high {
    return UDPredicate(UDBetween, @[ expression, low, high ], nil);
}

+ (instancetype)and:(NSArray<UDSQLPredicate *> *)predicates {
    // and's within: one and
    NSMutableArray *flat = [NSMutableArray array];
    for (UDSQLPredicate *predicate in predicates) {
        if (predicate->_kind == UDAnd) [flat addObjectsFromArray:predicate->_predicates];
        else [flat addObject:predicate];
    }
    return flat.count == 1 ? flat.firstObject : UDPredicate(UDAnd, nil, flat);
}

+ (instancetype)or:(NSArray<UDSQLPredicate *> *)predicates {
    NSMutableArray *flat = [NSMutableArray array];
    for (UDSQLPredicate *predicate in predicates) {
        if (predicate->_kind == UDOr) [flat addObjectsFromArray:predicate->_predicates];
        else [flat addObject:predicate];
    }
    return flat.count == 1 ? flat.firstObject : UDPredicate(UDOr, nil, flat);
}

+ (instancetype)not:(UDSQLPredicate *)predicate {
    return UDPredicate(UDNot, nil, @[ predicate ]);
}

+ (instancetype)exists:(UDSQLRelation *)relation {
    UDSQLPredicate *predicate = UDPredicate(UDExists, nil, nil);
    predicate->_relation = relation;
    return predicate;
}

- (NSUInteger)_variables {
    NSUInteger count = _relation ? [_relation _variables] : 0;
    for (UDSQLPredicate *predicate in _predicates) count += [predicate _variables];
    return count;
}

/// Its SQL, parenthesized when within a predicate of another kind (an or
/// within an and, an and within an or).
- (NSString *)_SQLWith:(UDSQLWriter *)writer within:(UDPredicateKind)outer {
    NSString *sql = [self _SQLWith:writer];
    BOOL group = (_kind == UDAnd && outer == UDOr) || (_kind == UDOr && outer == UDAnd);
    return group ? [NSString stringWithFormat:@"(%@)", sql] : sql;
}

static NSString *UDOperator(UDSQLComparison op) {
    switch (op) {
        case UDSQLEqual: return @"=";
        case UDSQLNotEqual: return @"<>";
        case UDSQLLess: return @"<";
        case UDSQLLessOrEqual: return @"<=";
        case UDSQLGreater: return @">";
        case UDSQLGreaterOrEqual: return @">=";
    }
    return @"=";
}

- (NSString *)_SQLWith:(UDSQLWriter *)writer {
    switch (_kind) {
        case UDCompare: {
            NSString *left = [_expressions[0] _SQLWith:writer];
            return [NSString stringWithFormat:@"%@ %@ %@", left, UDOperator(_op), [_expressions[1] _SQLWith:writer]];
        }
        case UDIsNull:
            return [[_expressions[0] _SQLWith:writer] stringByAppendingString:@" IS NULL"];
        case UDLike: {
            NSString *tested = [_expressions[0] _SQLWith:writer];
            NSString *pattern = [_expressions[1] _SQLWith:writer];
            return writer.dialect == UDSQLDialectPostgreSQL ? [NSString stringWithFormat:@"CAST(%@ AS TEXT) ILIKE %@", tested, pattern]
                                                            : [NSString stringWithFormat:@"%@ LIKE %@", tested, pattern];
        }
        case UDIn: {
            NSString *tested = [_expressions[0] _SQLWith:writer];
            NSMutableArray *values = [NSMutableArray array];
            for (NSUInteger i = 1; i < _expressions.count; i++) [values addObject:[_expressions[i] _SQLWith:writer]];
            return [NSString stringWithFormat:@"%@ IN (%@)", tested, [values componentsJoinedByString:@", "]];
        }
        case UDBetween: {
            NSString *tested = [_expressions[0] _SQLWith:writer];
            NSString *low = [_expressions[1] _SQLWith:writer];
            return [NSString stringWithFormat:@"%@ BETWEEN %@ AND %@", tested, low, [_expressions[2] _SQLWith:writer]];
        }
        case UDAnd:
        case UDOr: {
            if (!_predicates.count) return _kind == UDAnd ? @"1 = 1" : @"1 = 0";
            NSMutableArray *parts = [NSMutableArray array];
            for (UDSQLPredicate *predicate in _predicates) [parts addObject:[predicate _SQLWith:writer within:_kind]];
            return [parts componentsJoinedByString:_kind == UDAnd ? @" AND " : @" OR "];
        }
        case UDNot: {
            UDSQLPredicate *inner = _predicates.firstObject;
            if (inner->_kind == UDIsNull) return [[inner->_expressions[0] _SQLWith:writer] stringByAppendingString:@" IS NOT NULL"];
            if (inner->_kind == UDExists) return [@"NOT " stringByAppendingString:[inner _SQLWith:writer]];
            return [NSString stringWithFormat:@"NOT (%@)", [inner _SQLWith:writer]];
        }
        case UDExists:
            return [NSString stringWithFormat:@"EXISTS (%@)", [_relation _SQLWith:writer]];
    }
    return @"";
}

- (NSString *)SQLForDialect:(UDSQLDialect)dialect qualified:(BOOL)qualified parameters:(NSMutableArray *)parameters {
    UDSQLWriter *writer = [[UDSQLWriter alloc] init];
    writer.dialect = dialect;
    writer.qualified = qualified;
    writer.parameters = parameters;
    return [self _SQLWith:writer];
}

@end

// ---------------------------------------------------------------------------
// MARK: - Relations
// ---------------------------------------------------------------------------

@implementation UDSQLOrderKey

+ (instancetype)key:(UDSQLExpression *)expression ascending:(BOOL)ascending {
    UDSQLOrderKey *key = [[self alloc] init];
    key->_expression = expression;
    key->_ascending = ascending;
    return key;
}

@end

@implementation UDSQLRelation {
    UDRelationKind _kind;
    UDSQLTable *_table;
    NSString *_variable;                        // a table's; a projection's all-of
    UDSQLRelation *_input;                      // a join's left, a select's, project's, order's, page's, count's
    UDSQLRelation *_right;                      // a join's
    UDSQLJoinKind _joinKind;
    UDSQLPredicate *_predicate;                 // a join's on, a select's
    NSArray<UDSQLExpression *> *_columns;       // a projection's (nil: all)
    NSArray<NSString *> *_names;
    NSArray<UDSQLRelation *> *_relations;       // a union's
    NSArray<UDSQLOrderKey *> *_keys;
    NSArray<UDSQLExpression *> *_groupKeys;     // a group's
    NSUInteger _offset, _limit;
}

+ (NSString *)prettyPrinted:(NSString *)sql {
    return UDSQLPrettyPrinted(sql);
}

static UDSQLRelation *UDRelation(UDRelationKind kind, UDSQLRelation *input) {
    UDSQLRelation *relation = [[UDSQLRelation alloc] init];
    relation->_kind = kind;
    relation->_input = input;
    return relation;
}

+ (instancetype)table:(UDSQLTable *)table variable:(NSString *)variable {
    UDSQLRelation *relation = UDRelation(UDTable, nil);
    relation->_table = table;
    relation->_variable = [variable copy];
    return relation;
}

- (UDSQLRelation *)join:(UDSQLRelation *)right on:(UDSQLPredicate *)on kind:(UDSQLJoinKind)kind {
    UDSQLRelation *relation = UDRelation(UDJoin, self);
    relation->_right = right;
    relation->_predicate = on;
    relation->_joinKind = kind;
    return relation;
}

- (UDSQLRelation *)select:(UDSQLPredicate *)predicate {
    UDSQLRelation *relation = UDRelation(UDSelect, self);
    relation->_predicate = predicate;
    return relation;
}

- (UDSQLRelation *)group:(NSArray<UDSQLExpression *> *)keys {
    return [self group:keys having:nil];
}

- (UDSQLRelation *)group:(NSArray<UDSQLExpression *> *)keys having:(UDSQLPredicate *)having {
    UDSQLRelation *relation = UDRelation(UDGroup, self);
    relation->_groupKeys = [keys copy];
    relation->_predicate = having;
    return relation;
}

- (UDSQLRelation *)project:(NSArray<UDSQLExpression *> *)columns names:(NSArray<NSString *> *)names {
    UDSQLRelation *relation = UDRelation(UDProject, self);
    relation->_columns = [columns copy];
    relation->_names = [names copy];
    return relation;
}

- (UDSQLRelation *)projectAllOf:(NSString *)variable {
    UDSQLRelation *relation = UDRelation(UDProject, self);
    relation->_variable = [variable copy];
    return relation;
}

+ (UDSQLRelation *)union:(NSArray<UDSQLRelation *> *)relations {
    if (relations.count == 1) return relations.firstObject;
    UDSQLRelation *relation = UDRelation(UDUnion, nil);
    relation->_relations = [relations copy];
    return relation;
}

- (UDSQLRelation *)order:(NSArray<UDSQLOrderKey *> *)keys {
    UDSQLRelation *relation = UDRelation(UDOrder, self);
    relation->_keys = [keys copy];
    return relation;
}

- (UDSQLRelation *)pageFrom:(NSUInteger)offset limit:(NSUInteger)limit {
    UDSQLRelation *relation = UDRelation(UDPage, self);
    relation->_offset = offset;
    relation->_limit = limit;
    return relation;
}

- (UDSQLRelation *)count {
    return UDRelation(UDCount, self);
}

- (NSUInteger)_variables {
    switch (_kind) {
        case UDTable: return 1;
        case UDJoin: return [_input _variables] + [_right _variables] + [_predicate _variables];
        case UDSelect: return [_input _variables] + [_predicate _variables];
        case UDUnion: {
            NSUInteger most = 0;
            for (UDSQLRelation *relation in _relations) most = MAX(most, [relation _variables]);
            return most;
        }
        default: return [_input _variables];
    }
}

- (NSUInteger)variableCount {
    return [self _variables];
}

/// A table as FROM names it: its name, its variable when another.
- (NSString *)_fromItemWith:(UDSQLWriter *)writer {
    NSString *name = UDSQLQuoted(_table.name, writer.dialect);
    if (_table.schema.length) name = [NSString stringWithFormat:@"%@.%@", UDSQLQuoted(_table.schema, writer.dialect), name];
    return [_variable isEqualToString:_table.name] ? name : [NSString stringWithFormat:@"%@ AS %@", name, UDSQLQuoted(_variable, writer.dialect)];
}

/// A chain of tables, joins and selections: its FROM, its WHERE's
/// predicates; nil when it is something else (to be wrapped).
- (nullable NSString *)_fromWith:(UDSQLWriter *)writer where:(NSMutableArray<UDSQLPredicate *> *)where {
    switch (_kind) {
        case UDTable:
            return [self _fromItemWith:writer];
        case UDJoin: {
            NSString *left = [_input _fromWith:writer where:where];
            NSString *right = _right->_kind == UDTable ? [_right _fromItemWith:writer]
                                                       : [NSString stringWithFormat:@"(%@) AS %@", [_right _SQLWith:writer], UDSQLQuoted(@"j", writer.dialect)];
            if (!left) return nil;
            return [NSString stringWithFormat:@"%@ %@ %@ ON %@", left, _joinKind == UDSQLJoinLeft ? @"LEFT JOIN" : @"JOIN", right,
                                              [_predicate _SQLWith:writer]];
        }
        case UDSelect: {
            NSString *from = [_input _fromWith:writer where:where];
            [where addObject:_predicate];
            return from;
        }
        default:
            return nil;
    }
}

/// SELECT @a columns of a chain, or of what is wrapped.
- (NSString *)_selectColumns:(NSString *)columns of:(UDSQLRelation *)source with:(UDSQLWriter *)writer {
    NSMutableArray *where = [NSMutableArray array];
    // its FROM written before its WHERE: parameters in the order they are written
    NSString *from = [source _fromWith:writer where:where];
    if (!from) from = [NSString stringWithFormat:@"(%@) AS %@", [source _SQLWith:writer], UDSQLQuoted(@"q", writer.dialect)];
    NSMutableString *sql = [NSMutableString stringWithFormat:@"SELECT %@ FROM %@", columns, from];
    if (where.count) [sql appendFormat:@" WHERE %@", [[UDSQLPredicate and:where] _SQLWith:writer]];
    return sql;
}

- (NSString *)_columnsWith:(UDSQLWriter *)writer {
    if (_variable) return writer.qualified ? [UDSQLQuoted(_variable, writer.dialect) stringByAppendingString:@".*"] : @"*";
    if (!_columns.count) return @"*";
    NSMutableArray *parts = [NSMutableArray array];
    for (NSUInteger i = 0; i < _columns.count; i++) {
        NSString *column = [_columns[i] _SQLWith:writer];
        NSString *name = i < _names.count ? _names[i] : nil;
        [parts addObject:name && ![name isEqualToString:_columns[i].name] ? [NSString stringWithFormat:@"%@ AS %@", column, UDSQLQuoted(name, writer.dialect)]
                                                                          : column];
    }
    return [parts componentsJoinedByString:@", "];
}

/// Its block: a projection's columns (else all) of its chain; of a
/// group's, GROUP BY its keys.
- (NSString *)_blockWith:(UDSQLWriter *)writer {
    if (_kind == UDProject && _input->_kind == UDGroup) {
        UDSQLRelation *group = _input;
        // its columns written first: parameters in the order they are written
        NSString *columns = [self _columnsWith:writer];
        NSString *sql = [self _selectColumns:columns of:group->_input with:writer];
        NSMutableArray *keys = [NSMutableArray array];
        for (UDSQLExpression *key in group->_groupKeys) [keys addObject:[key _SQLWith:writer]];
        // HAVING without keys: all its rows one group (SQLite before 3.39
        // wants a GROUP BY: of a constant, but for no rows at all, the same)
        if (!keys.count && group->_predicate && writer.dialect == UDSQLDialectSQLite) [keys addObject:@"NULL"];
        if (keys.count) sql = [NSString stringWithFormat:@"%@ GROUP BY %@", sql, [keys componentsJoinedByString:@", "]];
        if (group->_predicate) sql = [NSString stringWithFormat:@"%@ HAVING %@", sql, [group->_predicate _SQLWith:writer]];
        return sql;
    }
    if (_kind == UDProject) return [self _selectColumns:[self _columnsWith:writer] of:_input with:writer];
    return [self _selectColumns:@"*" of:self with:writer];
}

- (NSString *)_SQLWith:(UDSQLWriter *)writer {
    switch (_kind) {
        case UDUnion: {
            NSMutableArray *parts = [NSMutableArray array];
            for (UDSQLRelation *relation in _relations) [parts addObject:[relation _SQLWith:writer]];
            return [parts componentsJoinedByString:@" UNION "];
        }
        case UDOrder: {
            NSString *sql = [_input _kind] == UDUnion ? [self _selectColumns:@"*" of:_input with:writer] : [_input _SQLWith:writer];
            NSMutableArray *keys = [NSMutableArray array];
            for (UDSQLOrderKey *key in _keys) {
                [keys addObject:[NSString stringWithFormat:@"%@%@", [key.expression _SQLWith:writer], key.ascending ? @"" : @" DESC"]];
            }
            return keys.count ? [NSString stringWithFormat:@"%@ ORDER BY %@", sql, [keys componentsJoinedByString:@", "]] : sql;
        }
        case UDPage: {
            NSString *sql = [_input _kind] == UDUnion ? [self _selectColumns:@"*" of:_input with:writer] : [_input _SQLWith:writer];
            return _offset ? [NSString stringWithFormat:@"%@ LIMIT %lu OFFSET %lu", sql, (unsigned long)_limit, (unsigned long)_offset]
                           : [NSString stringWithFormat:@"%@ LIMIT %lu", sql, (unsigned long)_limit];
        }
        case UDCount: {
            // a chain's rows counted as they are; a projection's or union's, wrapped
            UDSQLRelation *source = _input;
            while (source->_kind == UDOrder) source = source->_input;
            if (source->_kind == UDProject && !source->_variable && !source->_columns.count) source = source->_input;
            return [self _selectColumns:@"count(*)" of:source with:writer];
        }
        default:
            return [self _blockWith:writer];
    }
}

- (UDRelationKind)_kind {
    return _kind;
}

- (NSString *)SQLForDialect:(UDSQLDialect)dialect parameters:(NSMutableArray *)parameters {
    UDSQLWriter *writer = [[UDSQLWriter alloc] init];
    writer.dialect = dialect;
    writer.qualified = [self _variables] > 1;
    writer.parameters = parameters;
    return [self _SQLWith:writer];
}

@end

// ---------------------------------------------------------------------------
// MARK: - Its SQL, as written by hand
// ---------------------------------------------------------------------------

/// What starts a line of its own, longest first (LEFT JOIN before JOIN).
static NSArray<NSString *> *UDClauses(void) {
    return @[ @"LEFT JOIN ", @"ORDER BY ", @"GROUP BY ", @"FROM ", @"JOIN ", @"WHERE ", @"LIMIT ", @"UNION ", @"HAVING " ];
}

static BOOL UDStartsWith(NSString *sql, NSUInteger at, NSString *word) {
    return at + word.length <= sql.length && [sql compare:word options:NSLiteralSearch range:NSMakeRange(at, word.length)] == NSOrderedSame;
}

NSString *UDSQLPrettyPrinted(NSString *sql) {
    NSMutableString *out = [NSMutableString string];
    // each "(" open: whether a subquery's (its lines indented), and whether
    // its clause is a WHERE (its ANDs a line each), BETWEEN's AND aside
    NSMutableArray<NSNumber *> *subqueries = [NSMutableArray array];
    BOOL inWhere = NO;
    NSUInteger betweens = 0;
    NSMutableArray<NSArray *> *saved = [NSMutableArray array];     // [inWhere, betweens] of the "(" around
    __block NSUInteger depth = 0;   // subqueries open
    unichar quote = 0;
    NSString *(^indent)(void) = ^NSString *{
        return [@"" stringByPaddingToLength:depth * 2 withString:@" " startingAtIndex:0];
    };
    for (NSUInteger i = 0; i < sql.length; i++) {
        unichar c = [sql characterAtIndex:i];
        if (quote) {
            [out appendFormat:@"%C", c];
            if (c == quote) quote = 0;      // a doubled one opens again at once
            continue;
        }
        if (c == '\'' || c == '"' || c == '`') {
            quote = c;
            [out appendFormat:@"%C", c];
            continue;
        }
        if (c == '(') {
            BOOL subquery = UDStartsWith(sql, i + 1, @"SELECT ");
            [subqueries addObject:@(subquery)];
            [saved addObject:@[ @(inWhere), @(betweens) ]];
            [out appendString:@"("];
            if (subquery) {
                depth++;
                [out appendFormat:@"\n%@", indent()];
                inWhere = NO;
                betweens = 0;
            } else {
                inWhere = NO;   // a plain expression's: its ANDs inline
            }
            continue;
        }
        if (c == ')' && subqueries.count) {
            BOOL subquery = subqueries.lastObject.boolValue;
            [subqueries removeLastObject];
            NSArray *was = saved.lastObject;
            [saved removeLastObject];
            inWhere = [was[0] boolValue];
            betweens = [was[1] unsignedIntegerValue];
            if (subquery) {
                depth--;
                [out appendFormat:@"\n%@)", indent()];
            } else {
                [out appendString:@")"];
            }
            continue;
        }
        if (c == ' ') {
            NSString *clause = nil;
            for (NSString *word in UDClauses()) if (UDStartsWith(sql, i + 1, word)) { clause = word; break; }
            if (clause) {
                inWhere = [clause isEqualToString:@"WHERE "];
                betweens = 0;
                // the clause's words at once (LEFT JOIN's JOIN not again)
                [out appendFormat:@"\n%@%@", indent(), [clause substringToIndex:clause.length - 1]];
                i += clause.length - 1;
                continue;
            }
            if (UDStartsWith(sql, i + 1, @"BETWEEN ")) betweens++;
            if (UDStartsWith(sql, i + 1, @"AND ")) {
                if (betweens) betweens--;
                else if (inWhere) {
                    [out appendFormat:@"\n%@  ", indent()];
                    continue;
                }
            }
        }
        [out appendFormat:@"%C", c];
    }
    return out;
}
