/*---------------------------------------------------------------------------------------------
 *  UDSQLSchema.m
 *--------------------------------------------------------------------------------------------*/

#import "UDSQLSchema.h"

NSDate *UDSQLDateOfCoreDataTimestamp(double seconds) {
    return [NSDate dateWithTimeIntervalSinceReferenceDate:seconds];
}

@implementation UDSQLColumnInfo
@end

@implementation UDSQLForeignKey
@end

@implementation UDSQLIndex
@end

@implementation UDSQLTable

- (instancetype)init {
    self = [super init];
    if (self) {
        _columns = @[];
        _foreignKeys = @[];
        _indexes = @[];
        _entities = @[];
    }
    return self;
}

- (NSString *)qualifiedNameFor:(UDSQLConnection *)connection {
    NSString *name = [connection quotedIdentifier:_name];
    return _schema.length ? [NSString stringWithFormat:@"%@.%@", [connection quotedIdentifier:_schema], name] : name;
}

@end

/// A value of a catalogue's row as a string ("" for NULL).
static NSString *UDString(NSArray *row, NSUInteger column) {
    id value = column < row.count ? row[column] : nil;
    if (!value || value == [NSNull null]) return @"";
    if ([value isKindOfClass:[NSData class]]) return [[NSString alloc] initWithData:value encoding:NSUTF8StringEncoding] ?: @"";
    return [value description];
}

static BOOL UDTrue(NSArray *row, NSUInteger column) {
    id value = column < row.count ? row[column] : nil;
    if ([value isKindOfClass:[NSNumber class]]) return [value boolValue];
    NSString *text = UDString(row, column).uppercaseString;
    return [text isEqualToString:@"1"] || [text isEqualToString:@"YES"] || [text isEqualToString:@"T"] || [text isEqualToString:@"TRUE"];
}

@implementation UDSQLSchema {
    NSArray<UDSQLTable *> *_tables;
}

static const NSUInteger UDCatalogueRows = 100000;

+ (instancetype)schemaOfConnection:(UDSQLConnection *)connection error:(NSError **)error {
    UDSQLSchema *schema = [[UDSQLSchema alloc] init];
    NSArray<UDSQLTable *> *tables = nil;
    switch (connection.dialect) {
        case UDSQLDialectSQLite: tables = [self _sqliteTables:connection error:error]; break;
        case UDSQLDialectPostgreSQL: tables = [self _postgreSQLTables:connection error:error]; break;
        case UDSQLDialectMySQL: tables = [self _mySQLTables:connection error:error]; break;
    }
    if (!tables) return nil;
    schema->_tables = tables;
    schema->_coreDataMetadata = @{};
    schema->_coreDataEntities = @{};
    [schema _readCoreData:connection];
    return schema;
}

- (UDSQLTable *)tableNamed:(NSString *)name {
    for (UDSQLTable *table in _tables) {
        if ([table.name caseInsensitiveCompare:name] == NSOrderedSame) return table;
    }
    return nil;
}

// ---------------------------------------------------------------------------
// MARK: - SQLite: sqlite_master and its PRAGMAs
// ---------------------------------------------------------------------------

+ (NSArray<UDSQLTable *> *)_sqliteTables:(UDSQLConnection *)connection error:(NSError **)error {
    UDSQLResult *list = [connection execute:@"SELECT name, type FROM sqlite_master WHERE type IN ('table', 'view') "
                                             "AND name NOT LIKE 'sqlite_%' ORDER BY name"
                                 parameters:@[] maxRows:UDCatalogueRows error:error];
    if (!list) return nil;
    NSMutableArray<UDSQLTable *> *tables = [NSMutableArray array];
    for (NSArray *row in list.rows) {
        UDSQLTable *table = [[UDSQLTable alloc] init];
        table.name = UDString(row, 0);
        table.view = [UDString(row, 1) isEqualToString:@"view"];
        NSString *quoted = [connection quotedIdentifier:table.name];
        NSMutableArray *columns = [NSMutableArray array];
        UDSQLResult *info = [connection execute:[NSString stringWithFormat:@"PRAGMA table_info(%@)", quoted]
                                     parameters:@[] maxRows:UDCatalogueRows error:NULL];
        for (NSArray *column in info.rows) {
            // cid, name, type, notnull, dflt_value, pk
            UDSQLColumnInfo *made = [[UDSQLColumnInfo alloc] init];
            made.name = UDString(column, 1);
            made.type = UDString(column, 2);
            made.nullable = !UDTrue(column, 3);
            made.defaultValue = column[4] == [NSNull null] ? nil : UDString(column, 4);
            made.primaryKey = [column[5] integerValue] > 0;
            [columns addObject:made];
        }
        table.columns = columns;
        if (!table.view) {
            NSMutableDictionary<NSString *, UDSQLForeignKey *> *keys = [NSMutableDictionary dictionary];
            NSMutableArray<NSString *> *order = [NSMutableArray array];
            UDSQLResult *foreign = [connection execute:[NSString stringWithFormat:@"PRAGMA foreign_key_list(%@)", quoted]
                                            parameters:@[] maxRows:UDCatalogueRows error:NULL];
            for (NSArray *key in foreign.rows) {
                // id, seq, table, from, to, …
                NSString *identifier = UDString(key, 0);
                UDSQLForeignKey *made = keys[identifier];
                if (!made) {
                    made = [[UDSQLForeignKey alloc] init];
                    made.referencedTable = UDString(key, 2);
                    made.columns = @[];
                    made.referencedColumns = @[];
                    keys[identifier] = made;
                    [order addObject:identifier];
                }
                made.columns = [made.columns arrayByAddingObject:UDString(key, 3)];
                made.referencedColumns = [made.referencedColumns arrayByAddingObject:UDString(key, 4)];
            }
            table.foreignKeys = [keys objectsForKeys:order notFoundMarker:[NSNull null]];
            NSMutableArray *indexes = [NSMutableArray array];
            UDSQLResult *list = [connection execute:[NSString stringWithFormat:@"PRAGMA index_list(%@)", quoted]
                                         parameters:@[] maxRows:UDCatalogueRows error:NULL];
            for (NSArray *index in list.rows) {
                // seq, name, unique, origin, partial
                UDSQLIndex *made = [[UDSQLIndex alloc] init];
                made.name = UDString(index, 1);
                made.unique = UDTrue(index, 2);
                NSMutableArray *names = [NSMutableArray array];
                UDSQLResult *info = [connection execute:[NSString stringWithFormat:@"PRAGMA index_info(%@)",
                                                         [connection quotedIdentifier:made.name]]
                                             parameters:@[] maxRows:UDCatalogueRows error:NULL];
                for (NSArray *column in info.rows) [names addObject:UDString(column, 2)];
                made.columns = names;
                [indexes addObject:made];
            }
            table.indexes = indexes;
        }
        [tables addObject:table];
    }
    return tables;
}

// ---------------------------------------------------------------------------
// MARK: - PostgreSQL and MySQL: information_schema
// ---------------------------------------------------------------------------

/// The tables of a server's catalogue: @a tablesSQL gives schema, name,
/// type; @a columnsSQL schema, table, name, type, nullable, default, key
/// ("PRI" for a primary key's column, MySQL's; else empty); @a keysSQL
/// schema, table, constraint, column, referenced schema, table, column.
+ (NSArray<UDSQLTable *> *)_serverTables:(UDSQLConnection *)connection tables:(NSString *)tablesSQL
                                 columns:(NSString *)columnsSQL primaryKeys:(nullable NSString *)primarySQL
                             foreignKeys:(NSString *)keysSQL indexes:(NSString *)indexesSQL
                         qualifySchemas:(BOOL)qualify error:(NSError **)error {
    UDSQLResult *list = [connection execute:tablesSQL parameters:@[] maxRows:UDCatalogueRows error:error];
    if (!list) return nil;
    NSMutableArray<UDSQLTable *> *tables = [NSMutableArray array];
    NSMutableDictionary<NSString *, UDSQLTable *> *byName = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, NSMutableArray *> *columns = [NSMutableDictionary dictionary];
    for (NSArray *row in list.rows) {
        UDSQLTable *table = [[UDSQLTable alloc] init];
        table.schema = qualify ? UDString(row, 0) : nil;
        table.name = UDString(row, 1);
        table.view = [UDString(row, 2) rangeOfString:@"VIEW" options:NSCaseInsensitiveSearch].location != NSNotFound;
        NSString *key = [NSString stringWithFormat:@"%@.%@", UDString(row, 0), table.name];
        byName[key] = table;
        columns[key] = [NSMutableArray array];
        [tables addObject:table];
    }
    UDSQLResult *info = [connection execute:columnsSQL parameters:@[] maxRows:UDCatalogueRows error:NULL];
    for (NSArray *row in info.rows) {
        NSString *key = [NSString stringWithFormat:@"%@.%@", UDString(row, 0), UDString(row, 1)];
        UDSQLColumnInfo *made = [[UDSQLColumnInfo alloc] init];
        made.name = UDString(row, 2);
        made.type = UDString(row, 3);
        made.nullable = [UDString(row, 4) isEqualToString:@"YES"];
        made.defaultValue = row[5] == [NSNull null] ? nil : UDString(row, 5);
        made.primaryKey = [UDString(row, 6) isEqualToString:@"PRI"];
        [columns[key] addObject:made];
    }
    for (NSString *key in columns) byName[key].columns = columns[key];
    if (primarySQL) {
        UDSQLResult *primary = [connection execute:primarySQL parameters:@[] maxRows:UDCatalogueRows error:NULL];
        for (NSArray *row in primary.rows) {
            UDSQLTable *table = byName[[NSString stringWithFormat:@"%@.%@", UDString(row, 0), UDString(row, 1)]];
            for (UDSQLColumnInfo *column in table.columns) {
                if ([column.name isEqualToString:UDString(row, 2)]) column.primaryKey = YES;
            }
        }
    }
    NSMutableDictionary<NSString *, UDSQLForeignKey *> *keys = [NSMutableDictionary dictionary];
    UDSQLResult *foreign = [connection execute:keysSQL parameters:@[] maxRows:UDCatalogueRows error:NULL];
    for (NSArray *row in foreign.rows) {
        NSString *tableKey = [NSString stringWithFormat:@"%@.%@", UDString(row, 0), UDString(row, 1)];
        UDSQLTable *table = byName[tableKey];
        if (!table) continue;
        NSString *constraint = [NSString stringWithFormat:@"%@.%@", tableKey, UDString(row, 2)];
        UDSQLForeignKey *made = keys[constraint];
        if (!made) {
            made = [[UDSQLForeignKey alloc] init];
            made.columns = @[];
            made.referencedColumns = @[];
            made.referencedTable = qualify && ![UDString(row, 4) isEqualToString:UDString(row, 0)]
                ? [NSString stringWithFormat:@"%@.%@", UDString(row, 4), UDString(row, 5)] : UDString(row, 5);
            keys[constraint] = made;
            table.foreignKeys = [table.foreignKeys arrayByAddingObject:made];
        }
        if (![made.columns containsObject:UDString(row, 3)]) made.columns = [made.columns arrayByAddingObject:UDString(row, 3)];
        if (![made.referencedColumns containsObject:UDString(row, 6)]) {
            made.referencedColumns = [made.referencedColumns arrayByAddingObject:UDString(row, 6)];
        }
    }
    NSMutableDictionary<NSString *, UDSQLIndex *> *indexes = [NSMutableDictionary dictionary];
    UDSQLResult *listed = [connection execute:indexesSQL parameters:@[] maxRows:UDCatalogueRows error:NULL];
    for (NSArray *row in listed.rows) {
        // schema, table, index, unique, column
        NSString *tableKey = [NSString stringWithFormat:@"%@.%@", UDString(row, 0), UDString(row, 1)];
        UDSQLTable *table = byName[tableKey];
        if (!table) continue;
        NSString *indexKey = [NSString stringWithFormat:@"%@.%@", tableKey, UDString(row, 2)];
        UDSQLIndex *made = indexes[indexKey];
        if (!made) {
            made = [[UDSQLIndex alloc] init];
            made.name = UDString(row, 2);
            made.unique = UDTrue(row, 3);
            made.columns = @[];
            indexes[indexKey] = made;
            table.indexes = [table.indexes arrayByAddingObject:made];
        }
        if (UDString(row, 4).length) made.columns = [made.columns arrayByAddingObject:UDString(row, 4)];
    }
    return tables;
}

+ (NSArray<UDSQLTable *> *)_postgreSQLTables:(UDSQLConnection *)connection error:(NSError **)error {
    NSString *mine = @"NOT IN ('pg_catalog', 'information_schema') AND %@ NOT LIKE 'pg_toast%%'";
    NSString *tables = [NSString stringWithFormat:@"SELECT table_schema, table_name, table_type FROM information_schema.tables "
                        "WHERE table_schema %@ ORDER BY table_schema, table_name", [NSString stringWithFormat:mine, @"table_schema"]];
    NSString *columns = [NSString stringWithFormat:@"SELECT table_schema, table_name, column_name, data_type, is_nullable, column_default, '' "
                         "FROM information_schema.columns WHERE table_schema %@ ORDER BY table_schema, table_name, ordinal_position",
                         [NSString stringWithFormat:mine, @"table_schema"]];
    NSString *primary = [NSString stringWithFormat:@"SELECT tc.table_schema, tc.table_name, kcu.column_name "
                         "FROM information_schema.table_constraints tc JOIN information_schema.key_column_usage kcu "
                         "ON kcu.constraint_name = tc.constraint_name AND kcu.constraint_schema = tc.constraint_schema "
                         "WHERE tc.constraint_type = 'PRIMARY KEY' AND tc.table_schema %@", [NSString stringWithFormat:mine, @"tc.table_schema"]];
    NSString *keys = [NSString stringWithFormat:@"SELECT tc.table_schema, tc.table_name, tc.constraint_name, kcu.column_name, "
                      "ccu.table_schema, ccu.table_name, ccu.column_name "
                      "FROM information_schema.table_constraints tc JOIN information_schema.key_column_usage kcu "
                      "ON kcu.constraint_name = tc.constraint_name AND kcu.constraint_schema = tc.constraint_schema "
                      "JOIN information_schema.constraint_column_usage ccu "
                      "ON ccu.constraint_name = tc.constraint_name AND ccu.constraint_schema = tc.constraint_schema "
                      "WHERE tc.constraint_type = 'FOREIGN KEY' AND tc.table_schema %@ ORDER BY kcu.ordinal_position",
                      [NSString stringWithFormat:mine, @"tc.table_schema"]];
    NSString *indexes = [NSString stringWithFormat:@"SELECT n.nspname, t.relname, i.relname, ix.indisunique, a.attname "
                         "FROM pg_index ix JOIN pg_class i ON i.oid = ix.indexrelid JOIN pg_class t ON t.oid = ix.indrelid "
                         "JOIN pg_namespace n ON n.oid = t.relnamespace "
                         "LEFT JOIN LATERAL unnest(ix.indkey) WITH ORDINALITY AS k(attnum, ord) ON true "
                         "LEFT JOIN pg_attribute a ON a.attrelid = t.oid AND a.attnum = k.attnum "
                         "WHERE n.nspname %@ ORDER BY n.nspname, t.relname, i.relname, k.ord",
                         [NSString stringWithFormat:mine, @"n.nspname"]];
    return [self _serverTables:connection tables:tables columns:columns primaryKeys:primary foreignKeys:keys indexes:indexes
                qualifySchemas:YES error:error];
}

+ (NSArray<UDSQLTable *> *)_mySQLTables:(UDSQLConnection *)connection error:(NSError **)error {
    NSString *tables = @"SELECT table_schema, table_name, table_type FROM information_schema.tables "
                        "WHERE table_schema = DATABASE() ORDER BY table_name";
    NSString *columns = @"SELECT table_schema, table_name, column_name, column_type, is_nullable, column_default, column_key "
                         "FROM information_schema.columns WHERE table_schema = DATABASE() ORDER BY table_name, ordinal_position";
    NSString *keys = @"SELECT table_schema, table_name, constraint_name, column_name, referenced_table_schema, "
                      "referenced_table_name, referenced_column_name FROM information_schema.key_column_usage "
                      "WHERE table_schema = DATABASE() AND referenced_table_name IS NOT NULL ORDER BY ordinal_position";
    NSString *indexes = @"SELECT table_schema, table_name, index_name, 1 - non_unique, column_name "
                         "FROM information_schema.statistics WHERE table_schema = DATABASE() "
                         "ORDER BY table_name, index_name, seq_in_index";
    return [self _serverTables:connection tables:tables columns:columns primaryKeys:nil foreignKeys:keys indexes:indexes
                qualifySchemas:NO error:error];
}

// ---------------------------------------------------------------------------
// MARK: - A Core Data store
// ---------------------------------------------------------------------------

- (void)_readCoreData:(UDSQLConnection *)connection {
    UDSQLTable *primary = [self tableNamed:@"Z_PRIMARYKEY"], *metadata = [self tableNamed:@"Z_METADATA"];
    if (!primary || !metadata) return;
    // its columns quoted: a server's store keeps Core Data's upper case
    NSString *ent = [connection quotedIdentifier:@"Z_ENT"];
    UDSQLResult *entities = [connection execute:[NSString stringWithFormat:@"SELECT %@, %@, %@ FROM %@ ORDER BY %@", ent,
                                                 [connection quotedIdentifier:@"Z_NAME"], [connection quotedIdentifier:@"Z_SUPER"],
                                                 [primary qualifiedNameFor:connection], ent]
                                     parameters:@[] maxRows:UDCatalogueRows error:NULL];
    if (!entities) return;
    _coreDataStore = YES;
    NSMutableDictionary<NSNumber *, NSString *> *names = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSNumber *, NSNumber *> *supers = [NSMutableDictionary dictionary];
    for (NSArray *row in entities.rows) {
        NSNumber *entity = @([UDString(row, 0) integerValue]);
        names[entity] = UDString(row, 1);
        supers[entity] = @([UDString(row, 2) integerValue]);
    }
    _coreDataEntities = names;
    // each entity's rows: its root's table (Z + the root's name, upper case)
    for (NSNumber *entity in [names.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
        NSNumber *root = entity;
        for (NSUInteger depth = 0; [supers[root] integerValue] > 0 && depth < names.count; depth++) root = supers[root];
        UDSQLTable *table = [self tableNamed:[@"Z" stringByAppendingString:[names[root] uppercaseString]]];
        if (table && ![table.entities containsObject:names[entity]]) {
            table.entities = [entity isEqual:root] ? [@[ names[entity] ] arrayByAddingObjectsFromArray:table.entities]
                                                   : [table.entities arrayByAddingObject:names[entity]];
        }
    }
    for (UDSQLTable *table in _tables) {
        for (UDSQLColumnInfo *column in table.columns) {
            if ([column.name isEqualToString:@"Z_PK"]) column.coreDataMeaning = @"The row's key";
            else if ([column.name isEqualToString:@"Z_ENT"]) column.coreDataMeaning = @"The row's entity (Z_PRIMARYKEY's Z_ENT)";
            else if ([column.name isEqualToString:@"Z_OPT"]) column.coreDataMeaning = @"The row's version, for optimistic locking";
            else if ([column.type caseInsensitiveCompare:@"TIMESTAMP"] == NSOrderedSame) {
                column.coreDataMeaning = @"A date: seconds since 2001-01-01";
            }
        }
    }
    UDSQLResult *plist = [connection execute:[NSString stringWithFormat:@"SELECT %@ FROM %@", [connection quotedIdentifier:@"Z_PLIST"],
                                              [metadata qualifiedNameFor:connection]]
                                  parameters:@[] maxRows:1 error:NULL];
    id blob = plist.rows.firstObject.firstObject;
    if ([blob isKindOfClass:[NSString class]]) blob = [blob dataUsingEncoding:NSUTF8StringEncoding];
    if ([blob isKindOfClass:[NSData class]]) {
        id read = [NSPropertyListSerialization propertyListWithData:blob options:NSPropertyListImmutable format:NULL error:NULL];
        if ([read isKindOfClass:[NSDictionary class]]) _coreDataMetadata = read;
    }
}

@end
