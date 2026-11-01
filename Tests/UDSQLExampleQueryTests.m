//
//  UDSQLExampleQueryTests.m
//
//  Query by example as Zloof and Paradox made it, and the relational
//  algebra it is written as: skeletons linked by example elements (a join;
//  a table to itself; a comparison), ! rows kept where they have no match
//  (a left join), ¬ rows not there (NOT EXISTS), P. what is printed,
//  alternatives united; what can't be asked said, and where. Run against
//  SQLite (the rows each finds); the algebra's SQL as written (its
//  parentheses, PostgreSQL's placeholders through joins and subqueries,
//  values written in, a union ordered, paged and counted).
//

#import <XCTest/XCTest.h>
#import "UDCodeTestCase.h"
#import <UDCodeKit/UDCodeKit.h>
#import "UDSQLConnection.h"
#import "UDSQLSchema.h"
#import "UDSQLAlgebra.h"
#import "UDSQLExampleQuery.h"

static Class UDPluginClass(NSString *name) {
    (void)[UDLanguageModeRegistry sharedRegistry];
    return NSClassFromString(name);
}
#define UDPlugin(name) ((id)UDPluginClass(@#name))
// the algebra's classes, the extension's: reached by name
#define UDExpr ((id)UDPluginClass(@"UDSQLExpression"))
#define UDPred ((id)UDPluginClass(@"UDSQLPredicate"))
#define UDRel ((id)UDPluginClass(@"UDSQLRelation"))
#define UDKey ((id)UDPluginClass(@"UDSQLOrderKey"))

@interface UDSQLExampleQueryTests : UDCodeTestCase
@property (nonatomic, copy) NSString *path;
@property (nonatomic, strong) UDSQLConnection *connection;
@property (nonatomic, strong) UDSQLSchema *schema;
@end

@implementation UDSQLExampleQueryTests

- (void)setUp {
    [super setUp];
    _path = [UDRealPath(NSTemporaryDirectory()) stringByAppendingPathComponent:[[[NSUUID UUID] UUIDString] stringByAppendingPathExtension:@"sqlite"]];
    [[NSData data] writeToFile:_path atomically:YES];
    NSError *error = nil;
    _connection = [UDPlugin(UDSQLConnection) connectionToURL:[NSURL fileURLWithPath:_path] password:nil error:&error];
    for (NSString *sql in @[
             @"CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT, city TEXT)",
             @"CREATE TABLE orders (id INTEGER PRIMARY KEY, customer INTEGER REFERENCES customers(id), total REAL)",
             @"CREATE TABLE people (id INTEGER PRIMARY KEY, name TEXT, mentor INTEGER REFERENCES people)",
             @"INSERT INTO customers VALUES (1, 'Ann', 'Oslo'), (2, 'Bob', 'Rome'), (3, 'Cy', 'Oslo')",
             @"INSERT INTO orders VALUES (10, 1, 5.5), (11, 1, 20), (12, 2, 7)",
             @"INSERT INTO people VALUES (1, 'Ada', NULL), (2, 'Ben', 1), (3, 'Cal', 2)" ]) {
        XCTAssertNotNil([_connection execute:sql parameters:@[] maxRows:1 error:&error], @"%@: %@", sql, error);
    }
    _schema = [UDPlugin(UDSQLSchema) schemaOfConnection:_connection error:&error];
}

- (void)tearDown {
    [_connection close];
    [[NSFileManager defaultManager] removeItemAtPath:_path error:NULL];
    [super tearDown];
}

- (UDSQLExampleRow *)row:(NSDictionary *)entries {
    return [UDPluginClass(@"UDSQLExampleRow") rowWithEntries:entries];
}

- (UDSQLExampleSkeleton *)skeleton:(NSString *)table rows:(NSArray *)rows {
    return [UDPluginClass(@"UDSQLExampleSkeleton") skeletonOf:[_schema tableNamed:table] rows:rows];
}

- (UDSQLExampleQuery *)queryOf:(NSArray *)skeletons {
    UDSQLExampleQuery *query = [[UDPluginClass(@"UDSQLExampleQuery") alloc] initWithSchema:_schema dialect:UDSQLDialectSQLite];
    query.skeletons = skeletons;
    return query;
}

/// Its rows, its SQL in @a sql.
- (NSArray *)rowsOf:(UDSQLExampleQuery *)query SQL:(NSString **)sql {
    NSError *error = nil;
    UDSQLStatement *statement = [query selectStatementWithLimit:100 offset:0 error:&error];
    XCTAssertNotNil(statement, @"%@", error);
    if (sql) *sql = statement.SQL;
    UDSQLResult *result = [_connection execute:statement.SQL parameters:statement.parameters maxRows:100 error:&error];
    XCTAssertNotNil(result, @"%@: %@", statement.SQL, error);
    return result.rows;
}

- (NSSortDescriptor *)by:(NSString *)name {
    return [NSSortDescriptor sortDescriptorWithKey:name ascending:YES];
}

// ---------------------------------------------------------------------------
// MARK: - Joins by example elements
// ---------------------------------------------------------------------------

- (void)testAnExampleElementJoins {
    // customers' names, and their orders over 6: _c in both
    UDSQLExampleQuery *query = [self queryOf:@[ [self skeleton:@"customers" rows:@[ [self row:@{ @"id": @"_c", @"name": @"P." }] ]],
                                                [self skeleton:@"orders" rows:@[ [self row:@{ @"customer": @"_c", @"total": @"P.> 6" }] ]] ]];
    query.order = @[ [self by:@"total"] ];
    NSString *sql = nil;
    XCTAssertEqualObjects([self rowsOf:query SQL:&sql], (@[ @[ @"Bob", @7 ], @[ @"Ann", @20 ] ]));
    XCTAssertEqualObjects(sql, @"SELECT \"customers\".\"name\", \"orders\".\"total\" FROM \"customers\" "
                                "JOIN \"orders\" ON \"orders\".\"customer\" = \"customers\".\"id\" "
                                "WHERE \"orders\".\"total\" > ? ORDER BY \"orders\".\"total\" LIMIT 100");
    XCTAssertEqualObjects([query printedColumns:NULL], (@[ @"name", @"total" ]));
}

- (void)testAJoinPrintingNothingPrintsAll {
    // customers and their orders, nothing marked P.: both tables' columns
    // (SELECT * of the join), the first's key first in its order
    UDSQLExampleQuery *query = [self queryOf:@[ [self skeleton:@"customers" rows:@[ [self row:@{ @"id": @"_c" }] ]],
                                                [self skeleton:@"orders" rows:@[ [self row:@{ @"customer": @"_c" }] ]] ]];
    NSString *sql = nil;
    XCTAssertEqualObjects([self rowsOf:query SQL:&sql], (@[ @[ @1, @"Ann", @"Oslo", @10, @1, @5.5 ], @[ @1, @"Ann", @"Oslo", @11, @1, @20 ],
                                                            @[ @2, @"Bob", @"Rome", @12, @2, @7 ] ]), @"%@", sql);
    XCTAssertEqualObjects([query printedColumns:NULL], (@[ @"customers.id", @"name", @"city", @"orders.id", @"customer", @"total" ]),
                          @"two of a name: told apart");
    XCTAssertTrue([sql containsString:@"ORDER BY \"customers\".\"id\""], @"%@", sql);
    // a row not there: none of its columns
    UDSQLExampleRow *none = [self row:@{ @"customer": @"_c" }];
    none.negated = YES;
    query.skeletons = @[ query.skeletons[0], [self skeleton:@"orders" rows:@[ none ]] ];
    XCTAssertEqualObjects([query printedColumns:NULL], (@[ @"id", @"name", @"city" ]));
}

- (void)testAnInclusionKeepsRowsWithoutAMatch {
    // every customer, an order's id where they have one (Paradox's !)
    UDSQLExampleRow *orders = [self row:@{ @"customer": @"_c", @"id": @"P." }];
    orders.inclusive = YES;
    UDSQLExampleQuery *query = [self queryOf:@[ [self skeleton:@"customers" rows:@[ [self row:@{ @"id": @"_c", @"name": @"P." }] ]],
                                                [self skeleton:@"orders" rows:@[ orders ]] ]];
    query.order = @[ [self by:@"name"], [self by:@"id"] ];
    NSString *sql = nil;
    XCTAssertEqualObjects([self rowsOf:query SQL:&sql], (@[ @[ @"Ann", @10 ], @[ @"Ann", @11 ], @[ @"Bob", @12 ], @[ @"Cy", [NSNull null] ] ]),
                          @"Cy, with no orders, too");
    XCTAssertTrue([sql containsString:@"LEFT JOIN \"orders\" ON \"orders\".\"customer\" = \"customers\".\"id\""], @"%@", sql);
    // its conditions in its join: they keep rows, not drop them
    orders.entries = @{ @"customer": @"_c", @"id": @"P.", @"total": @"> 10" };
    XCTAssertEqualObjects([self rowsOf:query SQL:&sql], (@[ @[ @"Ann", @11 ], @[ @"Bob", [NSNull null] ], @[ @"Cy", [NSNull null] ] ]));
    XCTAssertTrue([sql containsString:@"ON \"orders\".\"customer\" = \"customers\".\"id\" AND \"orders\".\"total\" > ?"], @"%@", sql);
}

- (void)testARowNotThereIsAnAntiJoin {
    // customers no order refers to (¬)
    UDSQLExampleRow *none = [self row:@{ @"customer": @"_c" }];
    none.negated = YES;
    UDSQLExampleQuery *query = [self queryOf:@[ [self skeleton:@"customers" rows:@[ [self row:@{ @"id": @"_c", @"name": @"P." }] ]],
                                                [self skeleton:@"orders" rows:@[ none ]] ]];
    NSString *sql = nil;
    XCTAssertEqualObjects([self rowsOf:query SQL:&sql], (@[ @[ @"Cy" ] ]));
    XCTAssertEqualObjects(sql, @"SELECT \"customers\".\"name\" FROM \"customers\" WHERE NOT EXISTS "
                                "(SELECT * FROM \"orders\" WHERE \"orders\".\"customer\" = \"customers\".\"id\") LIMIT 100");
    // with a condition of its own: no order over 10
    none.entries = @{ @"customer": @"_c", @"total": @"> 10" };
    query.order = @[ [self by:@"name"] ];
    XCTAssertEqualObjects([self rowsOf:query SQL:NULL], (@[ @[ @"Bob" ], @[ @"Cy" ] ]));
}

- (void)testATableJoinedToItself {
    // each person's mentor: a second skeleton of people, _m its id
    UDSQLExampleQuery *query = [self queryOf:@[ [self skeleton:@"people" rows:@[ [self row:@{ @"name": @"P.", @"mentor": @"_m" }] ]],
                                                [self skeleton:@"people" rows:@[ [self row:@{ @"id": @"_m", @"name": @"P." }] ]] ]];
    query.order = @[ [self by:@"people.name"] ];
    NSString *sql = nil;
    XCTAssertEqualObjects([self rowsOf:query SQL:&sql], (@[ @[ @"Ben", @"Ada" ], @[ @"Cal", @"Ben" ] ]));
    XCTAssertTrue([sql hasPrefix:@"SELECT \"people\".\"name\" AS \"people.name\", \"people2\".\"name\" AS \"people2.name\" FROM \"people\" "
                                  "JOIN \"people\" AS \"people2\" ON \"people2\".\"id\" = \"people\".\"mentor\""], @"%@", sql);
    XCTAssertEqualObjects([query printedColumns:NULL], (@[ @"people.name", @"people2.name" ]), @"two of a name: told apart");
}

- (void)testAComparisonWithAnElement {
    // orders bigger than order 12 (_t its total)
    UDSQLExampleQuery *query = [self queryOf:@[ [self skeleton:@"orders" rows:@[ [self row:@{ @"id": @"P.", @"total": @"> _t" }],
                                                                                  [self row:@{ @"id": @"12", @"total": @"_t" }] ]] ]];
    query.order = @[ [self by:@"id"] ];
    NSString *sql = nil;
    XCTAssertEqualObjects([self rowsOf:query SQL:&sql], (@[ @[ @11 ] ]), @"20 > 7; 5.5 is not");
    XCTAssertTrue([sql containsString:@"JOIN \"orders\" AS \"orders2\" ON \"orders\".\"total\" > \"orders2\".\"total\" WHERE \"orders2\".\"id\" = ?"],
                  @"the comparison in the join of the row giving its element a value: %@", sql);
}

- (void)testAlternativesUnited {
    // customers in Rome, or who have an order over 10
    UDSQLExampleQuery *query = [self queryOf:@[ [self skeleton:@"customers" rows:@[ [self row:@{ @"name": @"P.", @"city": @"Rome" }],
                                                                                     [self row:@{ @"name": @"P.", @"id": @"_c" }] ]],
                                                [self skeleton:@"orders" rows:@[ [self row:@{ @"customer": @"_c", @"total": @"> 10" }] ]] ]];
    query.order = @[ [self by:@"name"] ];
    NSString *sql = nil;
    XCTAssertEqualObjects([self rowsOf:query SQL:&sql], (@[ @[ @"Ann" ], @[ @"Bob" ] ]));
    XCTAssertTrue([sql hasPrefix:@"SELECT * FROM (SELECT \"customers\".\"name\" FROM \"customers\" WHERE \"customers\".\"city\" = ? UNION "
                                  "SELECT \"customers\".\"name\" FROM \"customers\" JOIN \"orders\""], @"%@", sql);
    NSError *error = nil;
    UDSQLStatement *count = [query countStatement:&error];
    XCTAssertTrue([count.SQL hasPrefix:@"SELECT count(*) FROM (SELECT"], @"%@", count.SQL);
    XCTAssertEqualObjects([[_connection execute:count.SQL parameters:count.parameters maxRows:1 error:&error].rows[0] firstObject], @2);
}

- (void)testAPlainOneIsAsTheBrowserWritesIt {
    // a row of the first skeleton alone, any of them: one OR, unqualified
    UDSQLExampleQuery *query = [self queryOf:@[ [self skeleton:@"customers" rows:@[ [self row:@{ @"city": @"Oslo", @"name": @"A*" }],
                                                                                     [self row:@{ @"name": @"Bob" }],
                                                                                     [self row:@{}] ]] ]];
    NSString *sql = nil;
    XCTAssertEqualObjects([self rowsOf:query SQL:&sql], (@[ @[ @1, @"Ann", @"Oslo" ], @[ @2, @"Bob", @"Rome" ] ]));
    XCTAssertEqualObjects(sql, @"SELECT * FROM \"customers\" WHERE (\"name\" LIKE ? AND \"city\" = ?) OR \"name\" = ? ORDER BY \"id\" LIMIT 100");
}

// ---------------------------------------------------------------------------
// MARK: - What can't be asked
// ---------------------------------------------------------------------------

- (void)testWhatCantBeAsked {
    NSError *error = nil;
    // a row linked to none of the first table's
    UDSQLExampleQuery *unlinked = [self queryOf:@[ [self skeleton:@"customers" rows:@[ [self row:@{ @"name": @"P." }] ]],
                                                   [self skeleton:@"orders" rows:@[ [self row:@{ @"total": @"> 6" }] ]] ]];
    XCTAssertNil([unlinked relation:&error]);
    XCTAssertTrue([error.localizedDescription hasPrefix:@"This row of orders is linked to no row of customers"], @"%@", error.localizedDescription);
    XCTAssertEqualObjects(error.userInfo[@"UDSQLExampleSkeleton"], @1);
    XCTAssertEqualObjects(error.userInfo[@"UDSQLExampleRow"], @0);
    // an element compared with, never given a value
    UDSQLExampleQuery *unbound = [self queryOf:@[ [self skeleton:@"orders" rows:@[ [self row:@{ @"total": @"> _t", @"id": @"P." }] ]] ]];
    XCTAssertNil([unbound relation:&error]);
    XCTAssertEqualObjects(error.localizedDescription, @"total: _t is never given a value: put it alone under a column of a row that is there");
    XCTAssertEqualObjects(error.userInfo[@"UDSQLExampleColumn"], @"total");
    // printed in a row not there
    UDSQLExampleRow *none = [self row:@{ @"customer": @"_c", @"total": @"P." }];
    none.negated = YES;
    UDSQLExampleQuery *printedNone = [self queryOf:@[ [self skeleton:@"customers" rows:@[ [self row:@{ @"id": @"_c" }] ]],
                                                      [self skeleton:@"orders" rows:@[ none ]] ]];
    XCTAssertNil([printedNone relation:&error]);
    XCTAssertEqualObjects(error.localizedDescription, @"total: a row that is not there (¬) prints nothing");
    // a condition that can't be read, where it is
    UDSQLExampleQuery *unread = [self queryOf:@[ [self skeleton:@"customers" rows:@[ [self row:@{ @"name": @"Ann" }], [self row:@{ @"id": @">=" }] ]] ]];
    XCTAssertNil([unread relation:&error]);
    XCTAssertEqualObjects(error.localizedDescription, @"id: >= what?");
    XCTAssertEqualObjects(error.userInfo[@"UDSQLExampleRow"], @1);
    // alternatives printing different columns
    UDSQLExampleQuery *uneven = [self queryOf:@[ [self skeleton:@"customers" rows:@[ [self row:@{ @"name": @"P.", @"id": @"_c" }],
                                                                                      [self row:@{ @"name": @"P.", @"city": @"P." }] ]],
                                                 [self skeleton:@"orders" rows:@[ [self row:@{ @"customer": @"_c" }] ]] ]];
    XCTAssertNil([uneven relation:&error]);
    XCTAssertEqualObjects(error.localizedDescription, @"Its alternatives print different columns: give each the same P. columns");
}

// ---------------------------------------------------------------------------
// MARK: - The algebra's SQL
// ---------------------------------------------------------------------------

- (void)testTheAlgebrasSQL {
    UDSQLTable *customers = [_schema tableNamed:@"customers"], *orders = [_schema tableNamed:@"orders"];
    UDSQLExpression *name = [UDExpr column:@"name" of:@"c"], *city = [UDExpr column:@"city" of:@"c"];
    // and within or, or within and: parenthesized; not, not exists
    UDSQLPredicate *predicate = [UDPred or:@[ [UDPred and:@[ [UDPred compare:name op:UDSQLEqual to:[UDExpr value:@"Ann"]],
                                                                             [UDPred not:[UDPred isNull:city]] ]],
                                                      [UDPred in:city values:@[ [UDExpr value:@"Rome"], [UDExpr value:@"Oslo"] ]] ]];
    XCTAssertEqualObjects([predicate SQLForDialect:UDSQLDialectSQLite qualified:YES parameters:nil],
                          @"(\"c\".\"name\" = 'Ann' AND \"c\".\"city\" IS NOT NULL) OR \"c\".\"city\" IN ('Rome', 'Oslo')");
    UDSQLPredicate *liked = [UDPred and:@[ predicate, [UDPred like:name pattern:[UDExpr value:@"A%"]] ]];
    NSString *postgres = [liked SQLForDialect:UDSQLDialectPostgreSQL qualified:NO parameters:[NSMutableArray array]];
    XCTAssertEqualObjects(postgres, @"((\"name\" = $1 AND \"city\" IS NOT NULL) OR \"city\" IN ($2, $3)) AND CAST(\"name\" AS TEXT) ILIKE $4",
                          @"PostgreSQL: its placeholders in order, its ILIKE");
    // a join and a subquery: PostgreSQL's numbering through both
    UDSQLRelation *some = [[UDRel table:orders variable:@"o"] select:[UDPred and:@[
        [UDPred compare:[UDExpr column:@"customer" of:@"o"] op:UDSQLEqual to:[UDExpr column:@"id" of:@"c"]],
        [UDPred compare:[UDExpr column:@"total" of:@"o"] op:UDSQLGreater to:[UDExpr value:@10]] ]]];
    UDSQLRelation *relation = [[[[UDRel table:customers variable:@"c"]
                                   select:[UDPred and:@[ [UDPred compare:city op:UDSQLEqual to:[UDExpr value:@"Oslo"]],
                                                                 [UDPred not:[UDPred exists:some]] ]]]
                                  project:@[ name ] names:nil]
                                 order:@[ [UDKey key:name ascending:NO] ]];
    NSMutableArray *parameters = [NSMutableArray array];
    XCTAssertEqualObjects([relation SQLForDialect:UDSQLDialectPostgreSQL parameters:parameters],
                          @"SELECT \"c\".\"name\" FROM \"customers\" AS \"c\" WHERE \"c\".\"city\" = $1 AND NOT EXISTS "
                           "(SELECT * FROM \"orders\" AS \"o\" WHERE \"o\".\"customer\" = \"c\".\"id\" AND \"o\".\"total\" > $2) "
                           "ORDER BY \"c\".\"name\" DESC");
    XCTAssertEqualObjects(parameters, (@[ @"Oslo", @10 ]));
    XCTAssertEqual(relation.variableCount, 2u);
    // one table: unqualified; a union paged and counted: wrapped
    UDSQLRelation *one = [[UDRel table:customers variable:@"customers"] select:[UDPred compare:[UDExpr column:@"city" of:@"customers"]
                                                                                                         op:UDSQLEqual to:[UDExpr value:@"O'Neil"]]];
    XCTAssertEqualObjects([one SQLForDialect:UDSQLDialectMySQL parameters:nil], @"SELECT * FROM `customers` WHERE `city` = 'O''Neil'");
    UDSQLRelation *both = [UDRel union:@[ [one project:@[ [UDExpr column:@"name" of:@"customers"] ] names:nil],
                                                  [[UDRel table:customers variable:@"customers"] project:@[ [UDExpr column:@"name" of:@"customers"] ] names:nil] ]];
    UDSQLRelation *paged = [[both order:@[ [UDKey key:[UDExpr outputColumn:@"name"] ascending:YES] ]] pageFrom:5 limit:10];
    XCTAssertEqualObjects([paged SQLForDialect:UDSQLDialectSQLite parameters:nil],
                          @"SELECT * FROM (SELECT \"name\" FROM \"customers\" WHERE \"city\" = 'O''Neil' UNION SELECT \"name\" FROM \"customers\") AS \"q\" "
                           "ORDER BY \"name\" LIMIT 10 OFFSET 5");
    XCTAssertEqualObjects([[both count] SQLForDialect:UDSQLDialectSQLite parameters:nil],
                          @"SELECT count(*) FROM (SELECT \"name\" FROM \"customers\" WHERE \"city\" = 'O''Neil' UNION SELECT \"name\" FROM \"customers\") AS \"q\"");
}

@end
