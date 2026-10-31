//
//  UDSQLTests.m
//
//  The SQL extension's databases, below its windows: SQL read as far as
//  running it needs (statements, the one at the caret, parameters in each
//  driver's style); SQLite's connection, a statement's columns and rows,
//  parameters, errors; the schema (tables, views, columns, keys, indexes);
//  a Core Data store read as one; a run of statements, stopping at its first
//  failure. PostgreSQL, MySQL and MariaDB against a server when
//  UD_TEST_POSTGRES_URL, UD_TEST_MYSQL_URL or UD_TEST_MARIADB_URL names one
//  (or the CI's POSTGRES_URL, MYSQL_URL, MARIADB_URL), skipped else.
//

#import <XCTest/XCTest.h>
#import "UDCodeTestCase.h"
#import <UDCodeKit/UDCodeKit.h>
#import "UDSQLConnection.h"
#import "UDSQLText.h"
#import "UDSQLSchema.h"
#import "UDSQLRunner.h"

/// The SQL extension's classes: its bundle (UDCode.app's) loaded, reached by name.
static Class UDPluginClass(NSString *name) {
    (void)[UDLanguageModeRegistry sharedRegistry];
    return NSClassFromString(name);
}
#define UDPlugin(name) ((id)UDPluginClass(@#name))

@interface UDSQLTests : UDCodeTestCase
@property (nonatomic, copy) NSString *path;
@end

@implementation UDSQLTests

- (void)setUp {
    [super setUp];
    _path = [UDRealPath(NSTemporaryDirectory()) stringByAppendingPathComponent:[[[NSUUID UUID] UUIDString] stringByAppendingPathExtension:@"sqlite"]];
    // an empty file is an empty SQLite database (a connection makes none)
    [[NSData data] writeToFile:_path atomically:YES];
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtPath:_path error:NULL];
    [super tearDown];
}

- (UDSQLConnection *)connect {
    NSError *error = nil;
    UDSQLConnection *connection = [UDPlugin(UDSQLConnection) connectionToURL:[NSURL fileURLWithPath:_path] password:nil error:&error];
    XCTAssertNotNil(connection, @"%@", error);
    return connection;
}

- (UDSQLResult *)run:(NSString *)sql on:(UDSQLConnection *)connection {
    NSError *error = nil;
    UDSQLResult *result = [connection execute:sql parameters:@[] maxRows:1000 error:&error];
    XCTAssertNotNil(result, @"%@: %@", sql, error);
    return result;
}

- (void)testSQLAsText {
    Class text = UDPluginClass(@"UDSQLText");
    NSString *script = @"-- a script\nSELECT 'a;b' AS x; -- a comment; with a semicolon\n"
                        "INSERT INTO t VALUES (1, \"q;\");\n/* only a comment; */ ;\nSELECT 2";
    NSMutableArray *statements = [NSMutableArray array];
    for (NSValue *range in [text statementRangesOfText:script dialect:UDSQLDialectSQLite]) {
        [statements addObject:[script substringWithRange:range.rangeValue]];
    }
    XCTAssertEqualObjects(statements, (@[ @"-- a script\nSELECT 'a;b' AS x", @"-- a comment; with a semicolon\nINSERT INTO t VALUES (1, \"q;\")",
                                          @"SELECT 2" ]));
    NSRange atCaret = [text statementRangeAtIndex:[script rangeOfString:@"VALUES"].location ofText:script dialect:UDSQLDialectSQLite];
    XCTAssertTrue(([[script substringWithRange:atCaret] hasSuffix:@"(1, \"q;\")"]));

    // PostgreSQL's dollar quoting and casts: no statement ends, no parameters, inside them
    NSString *function = @"CREATE FUNCTION f() RETURNS int AS $$ SELECT 1; $$ LANGUAGE sql; SELECT x::int FROM t WHERE a = $1 AND b = :name";
    XCTAssertEqual([text statementRangesOfText:function dialect:UDSQLDialectPostgreSQL].count, 2u);
    NSString *last = [function substringWithRange:[[text statementRangesOfText:function dialect:UDSQLDialectPostgreSQL].lastObject rangeValue]];
    XCTAssertEqualObjects([text parametersOfStatement:last dialect:UDSQLDialectPostgreSQL], (@[ @"$1", @":name" ]));

    // each driver's style
    NSString *query = @"SELECT * FROM t WHERE a = :a AND b = ? AND c = :a AND d = 'not :here'";
    XCTAssertEqualObjects([text parametersOfStatement:query dialect:UDSQLDialectSQLite], (@[ @":a", @"?1" ]));
    NSArray *order = nil;
    XCTAssertEqualObjects([text statement:query convertedForDialect:UDSQLDialectPostgreSQL order:&order],
                          @"SELECT * FROM t WHERE a = $1 AND b = $2 AND c = $1 AND d = 'not :here'");
    XCTAssertEqualObjects(order, (@[ @":a", @"?1" ]));
    XCTAssertEqualObjects([text statement:query convertedForDialect:UDSQLDialectMySQL order:&order],
                          @"SELECT * FROM t WHERE a = ? AND b = ? AND c = ? AND d = 'not :here'");
    XCTAssertEqualObjects(order, (@[ @":a", @"?1", @":a" ]), @"one value for each ?");
    XCTAssertEqualObjects([text parametersOfStatement:@"SET @x = 1; SELECT @x" dialect:UDSQLDialectMySQL], @[],
                          @"MySQL's @x: a variable");
    XCTAssertEqualObjects(([text statement:@"SELECT ?, '?', ?" withParametersReplacedBy:@[ @"1", @"'two'" ] dialect:UDSQLDialectMySQL]),
                          @"SELECT 1, '?', 'two'");
}

- (void)testSQLite {
    UDSQLConnection *connection = [self connect];
    XCTAssertEqual(connection.dialect, UDSQLDialectSQLite);
    XCTAssertTrue([connection.serverDescription hasPrefix:@"SQLite 3"]);
    [self run:@"CREATE TABLE people (id INTEGER PRIMARY KEY, name TEXT NOT NULL, photo BLOB, height REAL)" on:connection];
    UDSQLResult *inserted = [self run:@"INSERT INTO people (name, height) VALUES ('Ann', 1.7), ('Bob', NULL)" on:connection];
    XCTAssertEqual(inserted.rowsAffected, 2);

    NSError *error = nil;
    UDSQLResult *rows = [connection execute:@"SELECT id, name, height, photo FROM people WHERE name <> ? ORDER BY id"
                                 parameters:@[ @"Zed" ] maxRows:1 error:&error];
    XCTAssertEqualObjects([rows.columns valueForKey:@"name"], (@[ @"id", @"name", @"height", @"photo" ]));
    XCTAssertEqualObjects([rows.columns valueForKey:@"type"], (@[ @"INTEGER", @"TEXT", @"REAL", @"BLOB" ]));
    XCTAssertEqual(rows.rows.count, 1u, @"the first only");
    XCTAssertTrue(rows.truncated);
    XCTAssertEqualObjects(rows.rows[0], (@[ @1, @"Ann", @1.7, [NSNull null] ]));

    UDSQLResult *failed = [connection execute:@"SELECT missing FROM nowhere" parameters:@[] maxRows:10 error:&error];
    XCTAssertNil(failed);
    XCTAssertTrue([error.localizedDescription containsString:@"nowhere"], @"%@", error);
    [connection close];

    NSError *missing = nil;
    XCTAssertNil([UDPlugin(UDSQLConnection) connectionToURL:[NSURL fileURLWithPath:@"/nonexistent/x.sqlite"] password:nil error:&missing]);
    XCTAssertFalse([[NSFileManager defaultManager] fileExistsAtPath:@"/nonexistent/x.sqlite"], @"none made");
}

- (void)testTheSchema {
    UDSQLConnection *connection = [self connect];
    [self run:@"CREATE TABLE teams (id INTEGER PRIMARY KEY, title TEXT UNIQUE)" on:connection];
    [self run:@"CREATE TABLE people (id INTEGER PRIMARY KEY, name TEXT NOT NULL DEFAULT 'x', team INTEGER REFERENCES teams(id))" on:connection];
    [self run:@"CREATE INDEX people_name ON people (name)" on:connection];
    [self run:@"CREATE VIEW names AS SELECT name FROM people" on:connection];
    NSError *error = nil;
    UDSQLSchema *schema = [UDPlugin(UDSQLSchema) schemaOfConnection:connection error:&error];
    XCTAssertEqualObjects([schema.tables valueForKey:@"name"], (@[ @"names", @"people", @"teams" ]));
    UDSQLTable *people = [schema tableNamed:@"people"];
    XCTAssertTrue([schema tableNamed:@"names"].view);
    XCTAssertEqualObjects([people.columns valueForKey:@"name"], (@[ @"id", @"name", @"team" ]));
    XCTAssertTrue(people.columns[0].primaryKey);
    XCTAssertFalse(people.columns[1].nullable);
    XCTAssertEqualObjects(people.columns[1].defaultValue, @"'x'");
    XCTAssertEqual(people.foreignKeys.count, 1u);
    XCTAssertEqualObjects(people.foreignKeys[0].referencedTable, @"teams");
    XCTAssertEqualObjects(people.foreignKeys[0].columns, @[ @"team" ]);
    XCTAssertEqualObjects(people.foreignKeys[0].referencedColumns, @[ @"id" ]);
    XCTAssertEqualObjects([people.indexes valueForKey:@"name"], @[ @"people_name" ]);
    XCTAssertEqualObjects(people.indexes[0].columns, @[ @"name" ]);
    XCTAssertTrue([[schema tableNamed:@"teams"].indexes.firstObject unique], @"title's");
    XCTAssertFalse(schema.coreDataStore);
}

- (void)testACoreDataStore {
    // as Core Data lays out a store of Person and its subentity Employee
    UDSQLConnection *connection = [self connect];
    [self run:@"CREATE TABLE Z_PRIMARYKEY (Z_ENT INTEGER PRIMARY KEY, Z_NAME VARCHAR, Z_SUPER INTEGER, Z_MAX INTEGER)" on:connection];
    [self run:@"INSERT INTO Z_PRIMARYKEY VALUES (1, 'Person', 0, 2), (2, 'Employee', 1, 0), (3, 'Team', 0, 1)" on:connection];
    [self run:@"CREATE TABLE Z_METADATA (Z_VERSION INTEGER PRIMARY KEY, Z_UUID VARCHAR(255), Z_PLIST BLOB)" on:connection];
    NSData *plist = [NSPropertyListSerialization dataWithPropertyList:@{ @"NSStoreType": @"SQLite", @"NSStoreUUID": @"ABC" }
                                                               format:NSPropertyListXMLFormat_v1_0 options:0 error:NULL];
    NSError *error = nil;
    XCTAssertNotNil(([connection execute:@"INSERT INTO Z_METADATA VALUES (1, 'ABC', ?)" parameters:@[ plist ] maxRows:1 error:&error]), @"%@", error);
    [self run:@"CREATE TABLE ZPERSON (Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZNAME VARCHAR, ZBIRTHDAY TIMESTAMP)" on:connection];
    [self run:@"CREATE TABLE ZTEAM (Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZTITLE VARCHAR)" on:connection];
    [self run:@"INSERT INTO ZPERSON VALUES (1, 1, 1, 'Ann', 0), (2, 2, 1, 'Bob', 0), (3, 2, 1, 'Cy', 0)" on:connection];
    [self run:@"CREATE TABLE Z_1TEAMS (Z_1PEOPLE INTEGER, Z_3TEAMS INTEGER)" on:connection];
    UDSQLSchema *schema = [UDPlugin(UDSQLSchema) schemaOfConnection:connection error:&error];
    XCTAssertTrue(schema.coreDataStore);
    XCTAssertEqualObjects([schema tableNamed:@"ZPERSON"].entities, (@[ @"Person", @"Employee" ]), @"a subentity's rows are its root's");
    XCTAssertEqualObjects([schema tableNamed:@"ZTEAM"].entities, @[ @"Team" ]);
    XCTAssertEqualObjects(schema.coreDataEntities[@2], @"Employee");
    XCTAssertEqualObjects(schema.coreDataSuperentities[@2], @1);
    XCTAssertEqualObjects([schema coreDataSubentitiesOf:nil], (@[ @1, @3 ]), @"the roots, by name: Person, Team");
    XCTAssertEqualObjects([schema coreDataSubentitiesOf:@1], @[ @2 ]);
    XCTAssertEqualObjects(schema.coreDataTables[@2].name, @"ZPERSON", @"a subentity's rows are its root's table's");
    XCTAssertEqualObjects(schema.coreDataRowCounts, (@{ @1: @1, @2: @2, @3: @0 }), @"each entity's own rows");
    XCTAssertEqualObjects([schema tableNamed:@"Z_1TEAMS"].joinOf, @"Person.teams", @"a many-to-many join table");
    XCTAssertEqualObjects([schema coreDataRowsOfEntity:@1 connection:connection limit:100],
                          @"SELECT * FROM \"ZPERSON\" ORDER BY \"Z_PK\" LIMIT 100", @"Person's and Employee's: the whole table");
    XCTAssertEqualObjects([schema coreDataRowsOfEntity:@2 connection:connection limit:100],
                          @"SELECT * FROM \"ZPERSON\" WHERE \"Z_ENT\" IN (2) ORDER BY \"Z_PK\" LIMIT 100", @"Employee's only");
    XCTAssertEqualObjects(schema.coreDataMetadata[@"NSStoreType"], @"SQLite");
    UDSQLTable *person = [schema tableNamed:@"ZPERSON"];
    XCTAssertEqualObjects(person.columns[1].coreDataMeaning, @"The row's entity (Z_PRIMARYKEY's Z_ENT)");
    XCTAssertEqualObjects(person.columns[4].coreDataMeaning, @"A date: seconds since 2001-01-01");
}

- (void)testARunStopsAtItsFirstFailure {
    UDSQLRunner *runner = [[UDPluginClass(@"UDSQLRunner") alloc] initWithURL:[NSURL fileURLWithPath:_path] password:nil];
    Class statement = UDPluginClass(@"UDSQLStatement");
    NSArray *statements = @[ [[statement alloc] initWithText:@"CREATE TABLE t (x)" SQL:@"CREATE TABLE t (x)" parameters:@[]],
                             [[statement alloc] initWithText:@"INSERT" SQL:@"INSERT INTO t VALUES (?)" parameters:@[ @42 ]],
                             [[statement alloc] initWithText:@"bad" SQL:@"SELECT FROM" parameters:@[]],
                             [[statement alloc] initWithText:@"never" SQL:@"DELETE FROM t" parameters:@[]] ];
    UDSQLRun *run = [runner runAndWait:statements maxRows:100];
    XCTAssertTrue(run.finished);
    XCTAssertEqual(run.results.count, 2u);
    XCTAssertEqual(run.results[1].rowsAffected, 1);
    XCTAssertNotNil(run.error);
    XCTAssertEqual(run.failedStatement, 2u);
    UDSQLRun *count = [runner runAndWait:@[ [[statement alloc] initWithText:@"count" SQL:@"SELECT count(*), x FROM t" parameters:@[]] ] maxRows:10];
    XCTAssertEqualObjects(count.results[0].rows[0], (@[ @1, @42 ]), @"the run before it stopped before the DELETE");
    [runner close];
}

/// A server's: its connection and schema, and a run (when a URL names one).
- (void)checkServer:(NSArray<NSString *> *)variables {
    NSString *address = nil;
    for (NSString *variable in variables) address = address ?: [[NSProcessInfo processInfo] environment][variable];
    if (!address.length) return;      // no server: skipped
    NSError *error = nil;
    UDSQLConnection *connection = [UDPlugin(UDSQLConnection) connectionToURL:[NSURL URLWithString:address] password:nil error:&error];
    XCTAssertNotNil(connection, @"%@", error);
    NSString *table = [connection quotedIdentifier:@"ud_sql_test"];
    [connection execute:[NSString stringWithFormat:@"DROP TABLE IF EXISTS %@", table] parameters:@[] maxRows:1 error:NULL];
    XCTAssertNotNil(([connection execute:[NSString stringWithFormat:@"CREATE TABLE %@ (id INTEGER PRIMARY KEY, name VARCHAR(40))", table]
                             parameters:@[] maxRows:1 error:&error]), @"%@", error);
    Class text = UDPluginClass(@"UDSQLText");
    NSString *insert = [NSString stringWithFormat:@"INSERT INTO %@ VALUES (:id, :name)", table];
    NSArray *order = nil;
    NSString *converted = [text statement:insert convertedForDialect:connection.dialect order:&order];
    NSDictionary *values = @{ @":id": @7, @":name": @"O'Hara" };
    UDSQLResult *inserted = [connection execute:converted parameters:[values objectsForKeys:order notFoundMarker:[NSNull null]] maxRows:1 error:&error];
    XCTAssertEqual(inserted.rowsAffected, 1, @"%@", error);
    UDSQLResult *rows = [connection execute:[NSString stringWithFormat:@"SELECT id, name FROM %@", table] parameters:@[] maxRows:10 error:&error];
    XCTAssertEqualObjects(rows.rows.firstObject, (@[ @7, @"O'Hara" ]), @"%@", error);
    UDSQLSchema *schema = [UDPlugin(UDSQLSchema) schemaOfConnection:connection error:&error];
    UDSQLTable *made = [schema tableNamed:@"ud_sql_test"];
    XCTAssertEqualObjects([made.columns valueForKey:@"name"], (@[ @"id", @"name" ]), @"%@", error);
    XCTAssertTrue(made.columns.firstObject.primaryKey);
    UDSQLResult *failed = [connection execute:@"SELECT * FROM ud_nowhere" parameters:@[] maxRows:1 error:&error];
    XCTAssertNil(failed);
    XCTAssertNotNil(error.userInfo[@"UDSQLState"], @"its SQLSTATE");
    [connection execute:[NSString stringWithFormat:@"DROP TABLE %@", table] parameters:@[] maxRows:1 error:NULL];
    [connection close];
}

- (void)testPostgreSQL {
    [self checkServer:@[ @"UD_TEST_POSTGRES_URL", @"POSTGRES_URL" ]];
}

- (void)testMySQL {
    [self checkServer:@[ @"UD_TEST_MYSQL_URL", @"MYSQL_URL" ]];
}

- (void)testMariaDB {
    [self checkServer:@[ @"UD_TEST_MARIADB_URL", @"MARIADB_URL" ]];
}

@end
