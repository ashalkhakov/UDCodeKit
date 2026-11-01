/*---------------------------------------------------------------------------------------------
 *  UDSQLQueryDesign.m
 *--------------------------------------------------------------------------------------------*/

#import "UDSQLQueryDesign.h"

@interface UDSQLQueryTable ()
@property (nonatomic, readwrite) UDSQLTable *table;
@property (nonatomic, readwrite, copy) NSString *alias;
@end

@implementation UDSQLQueryTable
@end

@interface UDSQLQueryJoin ()
@property (nonatomic, readwrite, copy) NSString *from;
@property (nonatomic, readwrite, copy) NSString *fromColumn;
@property (nonatomic, readwrite, copy) NSString *to;
@property (nonatomic, readwrite, copy) NSString *toColumn;
@end

@implementation UDSQLQueryJoin
@end

@interface UDSQLQueryField ()
@property (nonatomic, readwrite, copy) NSString *alias;
@property (nonatomic, readwrite, copy) NSString *column;
@end

@implementation UDSQLQueryField
@end

@implementation UDSQLQueryDesign {
    NSMutableArray<UDSQLQueryTable *> *_tables;
    NSMutableArray<UDSQLQueryJoin *> *_joins;
    NSMutableArray<UDSQLQueryField *> *_fields;
}

- (instancetype)initWithSchema:(UDSQLSchema *)schema dialect:(UDSQLDialect)dialect {
    self = [super init];
    if (self) {
        _schema = schema;
        _dialect = dialect;
        _tables = [NSMutableArray array];
        _joins = [NSMutableArray array];
        _fields = [NSMutableArray array];
        _conditionRows = 1;
    }
    return self;
}

- (NSArray<UDSQLQueryTable *> *)tables {
    return [_tables copy];
}

- (NSArray<UDSQLQueryJoin *> *)joins {
    return [_joins copy];
}

- (NSArray<UDSQLQueryField *> *)fields {
    return [_fields copy];
}

- (void)setConditionRows:(NSUInteger)rows {
    _conditionRows = MAX(1u, rows);
}

- (UDSQLQueryTable *)tableWithAlias:(NSString *)alias {
    for (UDSQLQueryTable *table in _tables) if ([table.alias isEqualToString:alias]) return table;
    return nil;
}

// ---------------------------------------------------------------------------
// MARK: - Tables and joins
// ---------------------------------------------------------------------------

/// The columns @a key refers to: its own, else the table's primary key's.
static NSArray<NSString *> *UDReferenced(UDSQLForeignKey *key, UDSQLTable *table) {
    if (key.referencedColumns.count) return key.referencedColumns;
    NSMutableArray *names = [NSMutableArray array];
    for (UDSQLColumnInfo *column in table.columns) if (column.primaryKey) [names addObject:column.name];
    return names;
}

/// @a from's foreign keys to @a to's table, as joins.
- (void)_joinKeysOf:(UDSQLQueryTable *)from to:(UDSQLQueryTable *)to {
    for (UDSQLForeignKey *key in from.table.foreignKeys) {
        if ([key.referencedTable caseInsensitiveCompare:to.table.name] != NSOrderedSame) continue;
        NSArray *referenced = UDReferenced(key, to.table);
        for (NSUInteger i = 0; i < MIN(key.columns.count, referenced.count); i++) {
            [self joinTable:from.alias column:key.columns[i] toTable:to.alias column:referenced[i] kind:UDSQLJoinInner];
        }
    }
}

- (UDSQLQueryTable *)addTable:(UDSQLTable *)table {
    NSString *alias = table.name;
    for (NSUInteger n = 2; [self tableWithAlias:alias]; n++) alias = [NSString stringWithFormat:@"%@%lu", table.name, (unsigned long)n];
    UDSQLQueryTable *added = [[UDSQLQueryTable alloc] init];
    added.table = table;
    added.alias = alias;
    NSArray *before = [_tables copy];
    [_tables addObject:added];
    // joined along their keys: its to theirs, theirs to it (a table's to
    // itself once, from the one added)
    for (UDSQLQueryTable *other in before) {
        [self _joinKeysOf:added to:other];
        if (other.table != table) [self _joinKeysOf:other to:added];
    }
    return added;
}

- (void)removeTable:(NSString *)alias {
    UDSQLQueryTable *table = [self tableWithAlias:alias];
    if (!table) return;
    [_tables removeObjectIdenticalTo:table];
    [_joins filterUsingPredicate:[NSPredicate predicateWithFormat:@"from != %@ AND to != %@", alias, alias]];
    [_fields filterUsingPredicate:[NSPredicate predicateWithFormat:@"alias != %@", alias]];
}

- (UDSQLQueryJoin *)joinTable:(NSString *)from column:(NSString *)fromColumn toTable:(NSString *)to column:(NSString *)toColumn
                         kind:(UDSQLJoinKind)kind {
    for (UDSQLQueryJoin *join in _joins) {
        BOOL same = [join.from isEqualToString:from] && [join.fromColumn isEqualToString:fromColumn] &&
                    [join.to isEqualToString:to] && [join.toColumn isEqualToString:toColumn];
        if (same) return join;
    }
    UDSQLQueryJoin *join = [[UDSQLQueryJoin alloc] init];
    join.from = from;
    join.fromColumn = fromColumn;
    join.to = to;
    join.toColumn = toColumn;
    join.kind = kind;
    [_joins addObject:join];
    return join;
}

- (void)removeJoin:(UDSQLQueryJoin *)join {
    [_joins removeObjectIdenticalTo:join];
}

// ---------------------------------------------------------------------------
// MARK: - Fields
// ---------------------------------------------------------------------------

- (UDSQLQueryField *)fieldOf:(NSString *)column table:(NSString *)alias {
    for (UDSQLQueryField *field in _fields) {
        if ([field.alias isEqualToString:alias] && [field.column isEqualToString:column]) return field;
    }
    return nil;
}

- (UDSQLQueryField *)addField:(NSString *)column ofTable:(NSString *)alias {
    UDSQLQueryField *field = [self fieldOf:column table:alias];
    if (field) return field;
    field = [[UDSQLQueryField alloc] init];
    field.alias = alias;
    field.column = column;
    field.shown = YES;
    field.conditions = @[];
    [_fields addObject:field];
    return field;
}

- (void)removeField:(UDSQLQueryField *)field {
    [_fields removeObjectIdenticalTo:field];
}

- (void)moveField:(UDSQLQueryField *)field toIndex:(NSUInteger)index {
    if ([_fields indexOfObjectIdenticalTo:field] == NSNotFound) return;
    [_fields removeObjectIdenticalTo:field];
    [_fields insertObject:field atIndex:MIN(index, _fields.count)];
}

// ---------------------------------------------------------------------------
// MARK: - Its SQL
// ---------------------------------------------------------------------------

- (NSString *)_quoted:(NSString *)name {
    return [UDSQLQbE quotedIdentifier:name dialect:_dialect];
}

- (NSString *)_columnOf:(NSString *)alias name:(NSString *)column {
    return [NSString stringWithFormat:@"%@.%@", [self _quoted:alias], [self _quoted:column]];
}

/// A table as FROM names it: its name, its alias after when another.
- (NSString *)_fromItemOf:(UDSQLQueryTable *)table {
    NSString *name = [self _quoted:table.table.name];
    if (table.table.schema.length) name = [NSString stringWithFormat:@"%@.%@", [self _quoted:table.table.schema], name];
    return [table.alias isEqualToString:table.table.name] ? name : [NSString stringWithFormat:@"%@ AS %@", name, [self _quoted:table.alias]];
}

/// The first table: one no left join keeps every row of another against
/// (so its left joins are written as LEFT, not RIGHT), else the first.
- (UDSQLQueryTable *)_start {
    for (UDSQLQueryTable *table in _tables) {
        BOOL kept = NO;
        for (UDSQLQueryJoin *join in _joins) if (join.kind == UDSQLJoinLeft && [join.to isEqualToString:table.alias]) kept = YES;
        if (!kept) return table;
    }
    return _tables.firstObject;
}

/// FROM's tables and joins, from the first, each as it is connected; the
/// ones connected to none crossed (in @a crossed); the joins between tables
/// joined already (a loop's) conditions of their own (in @a loops).
- (NSString *)_from:(NSMutableArray<NSString *> *)crossed loops:(NSMutableArray<NSString *> *)loops {
    if (!_tables.count) return @"";
    UDSQLQueryTable *start = [self _start];
    NSMutableSet *included = [NSMutableSet setWithObject:start.alias];
    NSMutableArray *pending = [_joins mutableCopy];
    NSMutableString *from = [NSMutableString stringWithString:[self _fromItemOf:start]];
    while (included.count < _tables.count) {
        // a table a join connects to those in: it, on all its joins to them
        UDSQLQueryTable *next = nil;
        for (UDSQLQueryJoin *join in pending) {
            BOOL fromIn = [included containsObject:join.from], toIn = [included containsObject:join.to];
            if (fromIn != toIn) {
                next = [self tableWithAlias:fromIn ? join.to : join.from];
                break;
            }
        }
        if (!next) {
            // connected to none: crossed
            for (UDSQLQueryTable *table in _tables) {
                if ([included containsObject:table.alias]) continue;
                [from appendFormat:@" CROSS JOIN %@", [self _fromItemOf:table]];
                [included addObject:table.alias];
                [crossed addObject:table.alias];
                break;
            }
            continue;
        }
        NSMutableArray *on = [NSMutableArray array];
        NSString *kind = @"JOIN";
        for (UDSQLQueryJoin *join in [pending copy]) {
            BOOL fromNext = [join.from isEqualToString:next.alias], toNext = [join.to isEqualToString:next.alias];
            BOOL other = fromNext ? [included containsObject:join.to] : toNext && [included containsObject:join.from];
            if (!other) continue;
            [on addObject:[NSString stringWithFormat:@"%@ = %@", [self _columnOf:join.from name:join.fromColumn],
                                                      [self _columnOf:join.to name:join.toColumn]]];
            // every row of the left (from) one: LEFT when it is in already, RIGHT when it is the one joined
            if (join.kind == UDSQLJoinLeft) kind = toNext ? @"LEFT JOIN" : @"RIGHT JOIN";
            [pending removeObjectIdenticalTo:join];
        }
        [from appendFormat:@" %@ %@ ON %@", kind, [self _fromItemOf:next], [on componentsJoinedByString:@" AND "]];
        [included addObject:next.alias];
    }
    for (UDSQLQueryJoin *join in pending) {
        [loops addObject:[NSString stringWithFormat:@"%@ = %@", [self _columnOf:join.from name:join.fromColumn],
                                                     [self _columnOf:join.to name:join.toColumn]]];
    }
    return from;
}

- (NSArray<NSString *> *)unjoinedTables {
    NSMutableArray *crossed = [NSMutableArray array];
    [self _from:crossed loops:[NSMutableArray array]];
    return crossed;
}

- (nullable NSString *)_selectWithParameters:(nullable NSMutableArray *)parameters error:(NSError **)error {
    if (!_tables.count) {
        if (error) *error = [NSError errorWithDomain:UDSQLErrorDomain code:-1
                                            userInfo:@{ NSLocalizedDescriptionKey: @"Add a table to the query." }];
        return nil;
    }
    // what is shown: its fields (named apart where two share a name), else everything
    NSMutableArray *shown = [NSMutableArray array];
    NSCountedSet *names = [NSCountedSet set];
    for (UDSQLQueryField *field in _fields) if (field.shown) [names addObject:field.column];
    for (UDSQLQueryField *field in _fields) {
        if (!field.shown) continue;
        NSString *column = [self _columnOf:field.alias name:field.column];
        [shown addObject:[names countForObject:field.column] > 1
            ? [NSString stringWithFormat:@"%@ AS %@", column, [self _quoted:[NSString stringWithFormat:@"%@.%@", field.alias, field.column]]]
            : column];
    }
    NSMutableArray *clauses = [NSMutableArray array];
    NSString *from = [self _from:[NSMutableArray array] loops:clauses];
    // the conditions: a row of them all, any row
    NSMutableArray<NSArray *> *rows = [NSMutableArray array];
    for (NSUInteger row = 0; row < _conditionRows; row++) {
        NSMutableArray *parts = [NSMutableArray array];
        for (NSUInteger index = 0; index < _fields.count; index++) {
            UDSQLQueryField *field = _fields[index];
            NSString *typed = row < field.conditions.count ? field.conditions[row] : @"";
            if (![typed stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].length) continue;
            UDSQLColumnInfo *column = nil;
            for (UDSQLColumnInfo *info in [self tableWithAlias:field.alias].table.columns) {
                if ([info.name isEqualToString:field.column]) column = info;
            }
            NSString *message = nil;
            NSString *condition = column ? [UDSQLQbE conditionOf:typed column:column expression:[self _columnOf:field.alias name:field.column]
                                                         schema:_schema dialect:_dialect parameters:parameters message:&message]
                                         : nil;
            if (!condition) {
                if (error) *error = [NSError errorWithDomain:UDSQLErrorDomain code:-1 userInfo:@{
                    NSLocalizedDescriptionKey: [NSString stringWithFormat:@"%@.%@: %@", field.alias, field.column, message ?: @"no such column"],
                    UDSQLQbEColumnErrorKey: @(index), UDSQLQbERowErrorKey: @(row) }];
                return nil;
            }
            [parts addObject:condition];
        }
        if (parts.count) [rows addObject:parts];
    }
    NSMutableArray *alternatives = [NSMutableArray array];
    for (NSArray *parts in rows) {
        NSString *all = [parts componentsJoinedByString:@" AND "];
        [alternatives addObject:rows.count > 1 && parts.count > 1 ? [NSString stringWithFormat:@"(%@)", all] : all];
    }
    if (alternatives.count) {
        NSString *any = [alternatives componentsJoinedByString:@" OR "];
        [clauses addObject:clauses.count && alternatives.count > 1 ? [NSString stringWithFormat:@"(%@)", any] : any];
    }
    NSMutableArray *order = [NSMutableArray array];
    for (UDSQLQueryField *field in _fields) {
        if (field.sort == UDSQLFieldUnsorted) continue;
        [order addObject:[NSString stringWithFormat:@"%@%@", [self _columnOf:field.alias name:field.column],
                                                     field.sort == UDSQLFieldDescending ? @" DESC" : @""]];
    }
    NSMutableString *sql = [NSMutableString stringWithFormat:@"SELECT %@\nFROM %@", shown.count ? [shown componentsJoinedByString:@", "] : @"*", from];
    if (clauses.count) [sql appendFormat:@"\nWHERE %@", [clauses componentsJoinedByString:@" AND "]];
    if (order.count) [sql appendFormat:@"\nORDER BY %@", [order componentsJoinedByString:@", "]];
    return sql;
}

- (UDSQLStatement *)statement:(NSError **)error {
    NSMutableArray *parameters = [NSMutableArray array];
    NSString *sql = [self _selectWithParameters:parameters error:error];
    return sql ? [[UDSQLStatement alloc] initWithText:sql SQL:sql parameters:parameters] : nil;
}

- (NSString *)SQL:(NSError **)error {
    return [self _selectWithParameters:nil error:error];
}

@end
