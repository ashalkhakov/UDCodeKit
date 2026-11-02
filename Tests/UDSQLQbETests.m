//
//  UDSQLQbETests.m
//
//  Query by example: what is typed under a table's columns, run against a
//  SQLite table (which rows each condition finds), and the SQL it makes
//  for PostgreSQL and MySQL (their placeholders, ILIKE, their quoting); a
//  Core Data store's dates and entities typed as such; its pages, its
//  count, its order, and what can't be read.
//

#import <XCTest/XCTest.h>
#import "UDCodeTestCase.h"
#import <UDCodeKit/UDCodeKit.h>
#import "UDSQLConnection.h"
#import "UDSQLSchema.h"
#import "UDSQLQbE.h"

static Class UDPluginClass(NSString *name) {
    (void)[UDLanguageModeRegistry sharedRegistry];
    return NSClassFromString(name);
}
#define UDPlugin(name) ((id)UDPluginClass(@#name))

@interface UDSQLQbETests : UDCodeTestCase
@property (nonatomic, copy) NSString *path;
@property (nonatomic, strong) UDSQLConnection *connection;
@property (nonatomic, strong) UDSQLSchema *schema;
@end

@implementation UDSQLQbETests

- (void)setUp {
    [super setUp];
    _path = [UDRealPath(NSTemporaryDirectory()) stringByAppendingPathComponent:[[[NSUUID UUID] UUIDString] stringByAppendingPathExtension:@"sqlite"]];
    [[NSData data] writeToFile:_path atomically:YES];
    NSError *error = nil;
    _connection = [UDPlugin(UDSQLConnection) connectionToURL:[NSURL fileURLWithPath:_path] password:nil error:&error];
    XCTAssertNotNil(_connection, @"%@", error);
}

- (void)tearDown {
    [_connection close];
    [[NSFileManager defaultManager] removeItemAtPath:_path error:NULL];
    [super tearDown];
}

- (void)run:(NSArray<NSString *> *)statements {
    NSError *error = nil;
    for (NSString *sql in statements) XCTAssertNotNil([_connection execute:sql parameters:@[] maxRows:1 error:&error], @"%@: %@", sql, error);
    _schema = [UDPlugin(UDSQLSchema) schemaOfConnection:_connection error:&error];
    XCTAssertNotNil(_schema, @"%@", error);
}

- (void)people {
    [self run:@[ @"CREATE TABLE people (id INTEGER PRIMARY KEY, name TEXT, age INTEGER, city TEXT)",
                 @"INSERT INTO people VALUES (1, 'Ann', 31, 'Oslo'), (2, 'Bob', 25, NULL), (3, 'Cy', 47, 'Rome'), "
                  "(4, 'annabel', 19, 'Oslo'), (5, 'Dee, Jr', 31, 'Paris'), (6, '5', 60, 'Rome')" ]];
}

- (UDSQLQbE *)qbeOf:(NSString *)table dialect:(UDSQLDialect)dialect {
    return [[UDPluginClass(@"UDSQLQbE") alloc] initWithTable:[_schema tableNamed:table] schema:_schema dialect:dialect];
}

/// The ids of the rows @a conditions find (each row of them a dictionary).
- (NSArray *)idsOf:(NSArray<NSDictionary *> *)conditions {
    UDSQLQbE *qbe = [self qbeOf:@"people" dialect:UDSQLDialectSQLite];
    qbe.conditions = conditions;
    NSError *error = nil;
    UDSQLStatement *select = [qbe selectStatementWithLimit:100 offset:0 error:&error];
    XCTAssertNotNil(select, @"%@", error);
    UDSQLResult *result = [_connection execute:select.SQL parameters:select.parameters maxRows:100 error:&error];
    XCTAssertNotNil(result, @"%@: %@", select.SQL, error);
    NSMutableArray *ids = [NSMutableArray array];
    for (NSArray *row in result.rows) [ids addObject:row[0]];
    return ids;
}

/// Each row's first value.
static NSArray *UDFirsts(UDSQLResult *result) {
    NSMutableArray *firsts = [NSMutableArray array];
    for (NSArray *row in result.rows) [firsts addObject:row.firstObject];
    return firsts;
}

- (NSArray *)idsOf:(NSString *)text under:(NSString *)column {
    return [self idsOf:@[ @{ column: text } ]];
}

- (void)testWhatEachConditionFinds {
    [self people];
    XCTAssertEqualObjects([self idsOf:@"" under:@"name"], (@[ @1, @2, @3, @4, @5, @6 ]), @"nothing typed: all, by the key");
    XCTAssertEqualObjects([self idsOf:@"Ann" under:@"name"], @[ @1 ]);
    XCTAssertEqualObjects([self idsOf:@"31" under:@"age"], (@[ @1, @5 ]), @"a number, as one");
    XCTAssertEqualObjects([self idsOf:@"> 30" under:@"age"], (@[ @1, @3, @5, @6 ]));
    XCTAssertEqualObjects([self idsOf:@"<=25" under:@"age"], (@[ @2, @4 ]));
    XCTAssertEqualObjects([self idsOf:@"<> Oslo" under:@"city"], (@[ @3, @5, @6 ]), @"NULL is neither");
    XCTAssertEqualObjects([self idsOf:@"!= Oslo" under:@"city"], (@[ @3, @5, @6 ]));
    XCTAssertEqualObjects([self idsOf:@"NULL" under:@"city"], @[ @2 ]);
    XCTAssertEqualObjects([self idsOf:@"not null" under:@"city"], (@[ @1, @3, @4, @5, @6 ]));
    XCTAssertEqualObjects([self idsOf:@"ann*" under:@"name"], (@[ @1, @4 ]), @"like it, case not minded");
    XCTAssertEqualObjects([self idsOf:@"%e%" under:@"name"], (@[ @4, @5 ]));
    XCTAssertEqualObjects([self idsOf:@"25..31" under:@"age"], (@[ @1, @2, @5 ]), @"both ends in");
    XCTAssertEqualObjects([self idsOf:@"Rome, Paris" under:@"city"], (@[ @3, @5, @6 ]));
    XCTAssertEqualObjects([self idsOf:@"!Oslo" under:@"city"], (@[ @3, @5, @6 ]));
    XCTAssertEqualObjects([self idsOf:@"not ann*" under:@"name"], (@[ @2, @3, @5, @6 ]));
    XCTAssertEqualObjects([self idsOf:@"! Rome, Paris" under:@"city"], (@[ @1, @4 ]));
    XCTAssertEqualObjects([self idsOf:@"'Dee, Jr'" under:@"name"], @[ @5 ], @"quoted: the text as it is, its comma too");
    XCTAssertEqualObjects([self idsOf:@"\"5\"" under:@"name"], @[ @6 ]);
    XCTAssertEqualObjects([self idsOf:@"=   Cy  " under:@"name"], @[ @3 ]);

    // a row's conditions all; any row
    XCTAssertEqualObjects(([self idsOf:@[ @{ @"city": @"Oslo", @"age": @"> 20" } ]]), @[ @1 ]);
    XCTAssertEqualObjects(([self idsOf:@[ @{ @"city": @"Oslo", @"age": @"> 20" }, @{ @"name": @"Cy" } ]]), (@[ @1, @3 ]));
    XCTAssertEqualObjects(([self idsOf:@[ @{ @"name": @"Cy" }, @{} ]]), @[ @3 ], @"an empty row: no condition, not all rows");
}

- (void)testItsPagesCountAndOrder {
    [self people];
    UDSQLQbE *qbe = [self qbeOf:@"people" dialect:UDSQLDialectSQLite];
    qbe.conditions = @[ @{ @"age": @"> 20" } ];
    qbe.order = @[ [NSSortDescriptor sortDescriptorWithKey:@"age" ascending:NO], [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES] ];
    NSError *error = nil;
    UDSQLStatement *page = [qbe selectStatementWithLimit:2 offset:2 error:&error];
    XCTAssertEqualObjects(page.SQL, @"SELECT * FROM \"people\" WHERE \"age\" > ? ORDER BY \"age\" DESC, \"name\" LIMIT 2 OFFSET 2");
    XCTAssertEqualObjects(page.parameters, @[ @20 ]);
    UDSQLResult *rows = [_connection execute:page.SQL parameters:page.parameters maxRows:10 error:&error];
    XCTAssertEqualObjects(UDFirsts(rows), (@[ @1, @5 ]), @"60, 47 | 31 Ann, 31 Dee | 25");
    UDSQLStatement *count = [qbe countStatement:&error];
    XCTAssertEqualObjects(count.SQL, @"SELECT count(*) FROM \"people\" WHERE \"age\" > ?");
    XCTAssertEqualObjects([[_connection execute:count.SQL parameters:count.parameters maxRows:1 error:&error].rows[0] firstObject], @5);
    XCTAssertEqualObjects([qbe SQLWithLimit:100 offset:0 error:&error],
                          @"SELECT * FROM \"people\" WHERE \"age\" > 20 ORDER BY \"age\" DESC, \"name\" LIMIT 100", @"its values written in");
    qbe.conditions = @[ @{ @"name": @"O'Brien" } ];
    qbe.order = @[];
    XCTAssertEqualObjects([qbe SQLWithLimit:10 offset:0 error:&error], @"SELECT * FROM \"people\" WHERE \"name\" = 'O''Brien' ORDER BY \"id\" LIMIT 10");
}

- (void)testWhatCantBeRead {
    [self people];
    UDSQLQbE *qbe = [self qbeOf:@"people" dialect:UDSQLDialectSQLite];
    qbe.conditions = @[ @{ @"name": @"Ann" }, @{ @"age": @">=" } ];
    NSError *error = nil;
    XCTAssertNil([qbe selectStatementWithLimit:10 offset:0 error:&error]);
    XCTAssertEqualObjects(error.localizedDescription, @"age: >= what?");
    XCTAssertEqualObjects(error.userInfo[@"UDSQLQbEColumn"], @"age");
    XCTAssertEqualObjects(error.userInfo[@"UDSQLQbERow"], @1);
    qbe.conditions = @[ @{ @"city": @"!" } ];
    XCTAssertNil([qbe countStatement:&error]);
    XCTAssertEqualObjects(error.localizedDescription, @"city: not what?");
}

- (void)testOtherDialectsSQL {
    [self people];
    NSError *error = nil;
    UDSQLQbE *postgres = [self qbeOf:@"people" dialect:UDSQLDialectPostgreSQL];
    postgres.conditions = @[ @{ @"name": @"ann*", @"age": @"20..40" } ];
    UDSQLStatement *select = [postgres selectStatementWithLimit:50 offset:0 error:&error];
    XCTAssertEqualObjects(select.SQL, @"SELECT * FROM \"people\" WHERE CAST(\"name\" AS TEXT) ILIKE $1 AND \"age\" BETWEEN $2 AND $3 ORDER BY \"id\" LIMIT 50",
                          @"PostgreSQL's $n, its ILIKE, of the column's text");
    XCTAssertEqualObjects(select.parameters, (@[ @"ann%", @20, @40 ]));
    UDSQLQbE *mysql = [self qbeOf:@"people" dialect:UDSQLDialectMySQL];
    mysql.conditions = @[ @{ @"city": @"Rome, Paris" } ];
    XCTAssertEqualObjects([mysql selectStatementWithLimit:50 offset:0 error:&error].SQL,
                          @"SELECT * FROM `people` WHERE `city` IN (?, ?) ORDER BY `id` LIMIT 50");
    mysql.conditions = @[ @{ @"name": @"a\\b" } ];
    XCTAssertEqualObjects([mysql SQLWithLimit:1 offset:0 error:&error], @"SELECT * FROM `people` WHERE `name` = 'a\\\\b' ORDER BY `id` LIMIT 1",
                          @"MySQL's backslashes, doubled");
}

- (void)testACoreDataStoresDatesAndEntities {
    // 2001-01-02 is day 1 (86400) since NSDate's reference date; Bob at noon
    [self run:@[ @"CREATE TABLE Z_PRIMARYKEY (Z_ENT INTEGER PRIMARY KEY, Z_NAME VARCHAR, Z_SUPER INTEGER, Z_MAX INTEGER)",
                 @"INSERT INTO Z_PRIMARYKEY VALUES (1, 'Person', 0, 3), (2, 'Employee', 1, 0)",
                 @"CREATE TABLE Z_METADATA (Z_VERSION INTEGER PRIMARY KEY, Z_UUID VARCHAR(255), Z_PLIST BLOB)",
                 @"CREATE TABLE ZPERSON (Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZNAME VARCHAR, ZBORN TIMESTAMP)",
                 @"INSERT INTO ZPERSON VALUES (1, 1, 1, 'Ann', 0), (2, 2, 1, 'Bob', 129600), (3, 2, 1, 'Cy', 172800)" ]];
    UDSQLQbE *qbe = [self qbeOf:@"ZPERSON" dialect:UDSQLDialectSQLite];
    NSTimeZone *zone = [NSTimeZone defaultTimeZone];
    [NSTimeZone setDefaultTimeZone:[NSTimeZone timeZoneForSecondsFromGMT:0]];
    NSDictionary *cases = @{ @"2001-01-02": @[ @2 ], @"> 2001-01-01": (@[ @2, @3 ]), @"<= 2001-01-02": (@[ @1, @2 ]),
                             @"2001-01-01..2001-01-02": (@[ @1, @2 ]), @"2001-01-02 12:00": @[ @2 ], @"!2001-01-02": (@[ @1, @3 ]) };
    for (NSString *typed in cases) {
        qbe.conditions = @[ @{ @"ZBORN": typed } ];
        NSError *error = nil;
        UDSQLStatement *select = [qbe selectStatementWithLimit:10 offset:0 error:&error];
        UDSQLResult *rows = [_connection execute:select.SQL parameters:select.parameters maxRows:10 error:&error];
        XCTAssertEqualObjects(UDFirsts(rows), cases[typed], @"%@: %@ %@", typed, select.SQL, select.parameters);
    }
    [NSTimeZone setDefaultTimeZone:zone];
    qbe.conditions = @[ @{ @"Z_ENT": @"employee" } ];
    qbe.restrictionColumn = @"Z_ENT";
    qbe.restrictionValues = @[ @1, @2 ];
    NSError *error = nil;
    UDSQLStatement *select = [qbe selectStatementWithLimit:10 offset:0 error:&error];
    XCTAssertEqualObjects(select.SQL, @"SELECT * FROM \"ZPERSON\" WHERE \"Z_ENT\" IN (?, ?) AND \"Z_ENT\" = ? ORDER BY \"Z_PK\" LIMIT 10");
    XCTAssertEqualObjects(select.parameters, (@[ @1, @2, @2 ]), @"an entity by its name");
}


- (void)testOperatorsMadeOfWhatIsTyped {
    Class qbe = UDPluginClass(@"UDSQLQbE");
    NSArray *cases = @[
        @[ @"5", @(UDSQLQbEGreater), @"> 5", @YES ], @[ @"> 5", @(UDSQLQbEAtMost), @"<= 5", @YES ],
        @[ @"", @(UDSQLQbEGreater), @"> ", @NO ], @[ @"!= x", @(UDSQLQbEEqual), @"x", @YES ], @[ @"x", @(UDSQLQbENotEqual), @"<> x", @YES ],
        @[ @"Ann", @(UDSQLQbELike), @"Ann*", @YES ], @[ @"%nn%", @(UDSQLQbELike), @"%nn%", @YES ], @[ @"", @(UDSQLQbELike), @"*", @NO ],
        @[ @"1", @(UDSQLQbEBetween), @"1..", @NO ], @[ @"1..5", @(UDSQLQbEBetween), @"1..5", @YES ],
        @[ @"a", @(UDSQLQbEOneOf), @"a, ", @NO ],
        @[ @"x", @(UDSQLQbENull), @"NULL", @YES ], @[ @"", @(UDSQLQbENotNull), @"NOT NULL", @YES ],
        @[ @"Ann", @(UDSQLQbENot), @"!Ann", @YES ], @[ @"!Ann", @(UDSQLQbENot), @"Ann", @YES ],
        @[ @"NULL", @(UDSQLQbENot), @"NOT NULL", @YES ], @[ @"", @(UDSQLQbENot), @"!", @NO ],
        @[ @"> 5", @(UDSQLQbEClear), @"", @YES ] ];
    for (NSArray *c in cases) {
        BOOL complete = !c[3];
        NSString *made = [qbe condition:c[0] withOperator:(UDSQLQbEOperator)[c[1] integerValue] complete:&complete];
        XCTAssertEqualObjects(made, c[2], @"%@ with %@", c[0], c[1]);
        XCTAssertEqual(complete, [c[3] boolValue], @"%@ with %@: %@", c[0], c[1], made);
    }
}

- (void)testWhatMayBeTypedIsShown {
    [self people];
    Class qbe = UDPluginClass(@"UDSQLQbE");
    UDSQLTable *people = [_schema tableNamed:@"people"];
    XCTAssertEqualObjects([qbe exampleForColumn:people.columns[2] schema:_schema], @"e.g. > 5", @"age: a number's");
    XCTAssertEqualObjects([qbe exampleForColumn:people.columns[1] schema:_schema], @"e.g. Ann*", @"name: text's");
    NSString *help = [qbe helpForColumn:people.columns[1] schema:_schema];
    XCTAssertTrue([help hasPrefix:@"name (TEXT): rows whose value is"], @"%@", help);
    XCTAssertTrue([help containsString:@"Ann* — like it"]);
    XCTAssertFalse([[qbe helpForColumn:people.columns[2] schema:_schema] containsString:@"like it"], @"no LIKE offered for a number");
}

@end
