//
//  UDSQLQueryDesignTests.m
//
//  A query as the builder designs it: tables joined along their foreign
//  keys when added (one in twice under an alias of its own; one to itself
//  once), inner and left joins, fields shown, sorted, their conditions (a
//  row all, any row), a table joined to none crossed; its SQL run against
//  SQLite (the rows it finds), and written with its values in.
//

#import <XCTest/XCTest.h>
#import "UDCodeTestCase.h"
#import <UDCodeKit/UDCodeKit.h>
#import "UDSQLConnection.h"
#import "UDSQLSchema.h"
#import "UDSQLQueryDesign.h"

static Class UDPluginClass(NSString *name) {
    (void)[UDLanguageModeRegistry sharedRegistry];
    return NSClassFromString(name);
}
#define UDPlugin(name) ((id)UDPluginClass(@#name))

@interface UDSQLQueryDesignTests : UDCodeTestCase
@property (nonatomic, copy) NSString *path;
@property (nonatomic, strong) UDSQLConnection *connection;
@property (nonatomic, strong) UDSQLSchema *schema;
@end

@implementation UDSQLQueryDesignTests

- (void)setUp {
    [super setUp];
    _path = [UDRealPath(NSTemporaryDirectory()) stringByAppendingPathComponent:[[[NSUUID UUID] UUIDString] stringByAppendingPathExtension:@"sqlite"]];
    [[NSData data] writeToFile:_path atomically:YES];
    NSError *error = nil;
    _connection = [UDPlugin(UDSQLConnection) connectionToURL:[NSURL fileURLWithPath:_path] password:nil error:&error];
    for (NSString *sql in @[
             @"CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT, city TEXT)",
             @"CREATE TABLE orders (id INTEGER PRIMARY KEY, customer INTEGER NOT NULL REFERENCES customers(id), total REAL)",
             @"CREATE TABLE people (id INTEGER PRIMARY KEY, name TEXT, mentor INTEGER REFERENCES people)",
             @"CREATE TABLE notes (id INTEGER PRIMARY KEY, text TEXT)",
             @"INSERT INTO customers VALUES (1, 'Ann', 'Oslo'), (2, 'Bob', 'Rome'), (3, 'Cy', 'Oslo')",
             @"INSERT INTO orders VALUES (10, 1, 5.5), (11, 1, 20), (12, 2, 7)",
             @"INSERT INTO people VALUES (1, 'Ada', NULL), (2, 'Ben', 1)",
             @"INSERT INTO notes VALUES (1, 'x'), (2, 'y')" ]) {
        XCTAssertNotNil([_connection execute:sql parameters:@[] maxRows:1 error:&error], @"%@: %@", sql, error);
    }
    _schema = [UDPlugin(UDSQLSchema) schemaOfConnection:_connection error:&error];
}

- (void)tearDown {
    [_connection close];
    [[NSFileManager defaultManager] removeItemAtPath:_path error:NULL];
    [super tearDown];
}

- (UDSQLQueryDesign *)design {
    return [[UDPluginClass(@"UDSQLQueryDesign") alloc] initWithSchema:_schema dialect:UDSQLDialectSQLite];
}

- (NSArray *)rowsOf:(UDSQLQueryDesign *)design {
    NSError *error = nil;
    UDSQLStatement *statement = [design statement:&error];
    XCTAssertNotNil(statement, @"%@", error);
    UDSQLResult *result = [_connection execute:statement.SQL parameters:statement.parameters maxRows:100 error:&error];
    XCTAssertNotNil(result, @"%@: %@", statement.SQL, error);
    return result.rows;
}

- (void)testTablesJoinedAlongTheirKeys {
    UDSQLQueryDesign *design = [self design];
    [design addTable:[_schema tableNamed:@"orders"]];
    [design addTable:[_schema tableNamed:@"customers"]];
    XCTAssertEqual(design.joins.count, 1u, @"along the key, from either side");
    UDSQLQueryJoin *join = design.joins.firstObject;
    XCTAssertEqualObjects((@[ join.from, join.fromColumn, join.to, join.toColumn ]), (@[ @"orders", @"customer", @"customers", @"id" ]));
    [design addField:@"name" ofTable:@"customers"];
    [design addField:@"total" ofTable:@"orders"].sort = UDSQLFieldDescending;
    NSError *error = nil;
    XCTAssertEqualObjects([design SQL:&error], @"SELECT \"customers\".\"name\", \"orders\".\"total\"\n"
                                                "FROM \"orders\" JOIN \"customers\" ON \"orders\".\"customer\" = \"customers\".\"id\"\n"
                                                "ORDER BY \"orders\".\"total\" DESC");
    XCTAssertEqualObjects([self rowsOf:design], (@[ @[ @"Ann", @20 ], @[ @"Bob", @7 ], @[ @"Ann", @5.5 ] ]));
    XCTAssertEqualObjects([design unjoinedTables], @[]);
}

- (void)testALeftJoinKeepsEveryRow {
    UDSQLQueryDesign *design = [self design];
    [design addTable:[_schema tableNamed:@"orders"]];
    [design addTable:[_schema tableNamed:@"customers"]];
    [design.joins.firstObject setKind:UDSQLJoinLeft];
    XCTAssertTrue([[design SQL:NULL] containsString:@"FROM \"orders\" LEFT JOIN \"customers\""]);
    // every customer, their orders where they have some: customers left-joined
    UDSQLQueryDesign *every = [self design];
    [every addTable:[_schema tableNamed:@"customers"]];
    [every addTable:[_schema tableNamed:@"orders"]];
    [every removeJoin:every.joins.firstObject];
    [every joinTable:@"customers" column:@"id" toTable:@"orders" column:@"customer" kind:UDSQLJoinLeft];
    [every addField:@"name" ofTable:@"customers"].sort = UDSQLFieldAscending;
    [every addField:@"id" ofTable:@"orders"].sort = UDSQLFieldAscending;
    XCTAssertEqualObjects([self rowsOf:every], (@[ @[ @"Ann", @10 ], @[ @"Ann", @11 ], @[ @"Bob", @12 ], @[ @"Cy", [NSNull null] ] ]),
                          @"Cy, with no orders, too");
}

- (void)testATableInTwiceUnderItsOwnAlias {
    UDSQLQueryDesign *design = [self design];
    [design addTable:[_schema tableNamed:@"people"]];
    UDSQLQueryTable *mentors = [design addTable:[_schema tableNamed:@"people"]];
    XCTAssertEqualObjects(mentors.alias, @"people2");
    XCTAssertEqual(design.joins.count, 1u, @"its key to itself, once");
    UDSQLQueryJoin *join = design.joins.firstObject;
    XCTAssertEqualObjects((@[ join.from, join.fromColumn, join.to, join.toColumn ]), (@[ @"people2", @"mentor", @"people", @"id" ]),
                          @"no column named: the primary key");
    [design addField:@"name" ofTable:@"people2"];
    [design addField:@"name" ofTable:@"people"];
    NSError *error = nil;
    XCTAssertEqualObjects([design SQL:&error], @"SELECT \"people2\".\"name\" AS \"people2.name\", \"people\".\"name\" AS \"people.name\"\n"
                                                "FROM \"people\" JOIN \"people\" AS \"people2\" ON \"people2\".\"mentor\" = \"people\".\"id\"",
                          @"two of a name: told apart");
    XCTAssertEqualObjects([self rowsOf:design], (@[ @[ @"Ben", @"Ada" ] ]), @"Ben's mentor");
}

- (void)testConditionsAndOr {
    UDSQLQueryDesign *design = [self design];
    [design addTable:[_schema tableNamed:@"orders"]];
    [design addTable:[_schema tableNamed:@"customers"]];
    [design addField:@"id" ofTable:@"orders"].sort = UDSQLFieldAscending;
    UDSQLQueryField *city = [design addField:@"city" ofTable:@"customers"];
    city.shown = NO;
    UDSQLQueryField *total = [design addField:@"total" ofTable:@"orders"];
    total.shown = NO;
    city.conditions = @[ @"Oslo" ];
    total.conditions = @[ @"> 10" ];
    XCTAssertEqualObjects([self rowsOf:design], (@[ @[ @11 ] ]), @"a row's: Oslo and over 10");
    design.conditionRows = 2;
    total.conditions = @[ @"> 10", @"< 6" ];
    city.conditions = @[ @"Oslo", @"" ];
    XCTAssertEqualObjects([self rowsOf:design], (@[ @[ @10 ], @[ @11 ] ]), @"or any order under 6");
    NSError *error = nil;
    UDSQLStatement *statement = [design statement:&error];
    XCTAssertTrue([statement.SQL containsString:@"WHERE (\"customers\".\"city\" = ? AND \"orders\".\"total\" > ?) OR \"orders\".\"total\" < ?"],
                  @"%@", statement.SQL);
    XCTAssertEqualObjects(statement.parameters, (@[ @"Oslo", @10, @6 ]));
    XCTAssertTrue([[design SQL:&error] containsString:@"\"customers\".\"city\" = 'Oslo'"], @"its values written in");
    total.conditions = @[ @">=" ];
    XCTAssertNil([design statement:&error]);
    XCTAssertEqualObjects(error.localizedDescription, @"orders.total: >= what?");
    XCTAssertEqualObjects(error.userInfo[@"UDSQLQbEColumn"], @2, @"the field's index");
}

- (void)testATableJoinedToNoneIsCrossedAndEverythingShown {
    UDSQLQueryDesign *design = [self design];
    [design addTable:[_schema tableNamed:@"customers"]];
    [design addTable:[_schema tableNamed:@"notes"]];
    XCTAssertEqualObjects([design unjoinedTables], @[ @"notes" ]);
    NSError *error = nil;
    XCTAssertEqualObjects([design SQL:&error], @"SELECT *\nFROM \"customers\" CROSS JOIN \"notes\"", @"no field: all of them");
    XCTAssertEqual([self rowsOf:design].count, 6u);
    [design removeTable:@"notes"];
    XCTAssertEqualObjects([design unjoinedTables], @[]);
    [design removeTable:@"customers"];
    XCTAssertNil([design SQL:&error]);
    XCTAssertEqualObjects(error.localizedDescription, @"Add a table to the query.");
}

- (void)testFieldsMovedAndTakenAway {
    UDSQLQueryDesign *design = [self design];
    [design addTable:[_schema tableNamed:@"customers"]];
    UDSQLQueryField *name = [design addField:@"name" ofTable:@"customers"];
    UDSQLQueryField *city = [design addField:@"city" ofTable:@"customers"];
    XCTAssertEqual([design addField:@"name" ofTable:@"customers"], name, @"the one there");
    [design moveField:city toIndex:0];
    XCTAssertEqualObjects([design.fields valueForKey:@"column"], (@[ @"city", @"name" ]));
    [design removeField:city];
    XCTAssertEqualObjects([design.fields valueForKey:@"column"], @[ @"name" ]);
}

@end
