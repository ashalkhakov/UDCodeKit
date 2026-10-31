//
//  UDSQLDiagramTests.m
//
//  A database's ER diagram, without a window: its boxes and lines from the
//  schema (a foreign key's ends, many at the table that refers, one or zero
//  or one at the one referred to; a table referring to itself; a Core Data
//  store's links inferred, dashed), laid out in layers (referred-to tables
//  first), moved, kept and set again, and drawn (as SVG). DiagramKit's
//  classes are reached by name, as the extension's are.
//

#import <XCTest/XCTest.h>
#import "UDCodeTestCase.h"
#import <UDCodeKit/UDCodeKit.h>
#import "UDSQLConnection.h"
#import "UDSQLSchema.h"
#import "UDSQLDiagram.h"

static Class UDPluginClass(NSString *name) {
    (void)[UDLanguageModeRegistry sharedRegistry];
    return NSClassFromString(name);
}
#define UDPlugin(name) ((id)UDPluginClass(@#name))

@interface UDSQLDiagramTests : UDCodeTestCase
@property (nonatomic, copy) NSString *path;
@end

@implementation UDSQLDiagramTests

- (void)setUp {
    [super setUp];
    _path = [UDRealPath(NSTemporaryDirectory()) stringByAppendingPathComponent:[[[NSUUID UUID] UUIDString] stringByAppendingPathExtension:@"sqlite"]];
    [[NSData data] writeToFile:_path atomically:YES];
}

- (void)tearDown {
    [[NSFileManager defaultManager] removeItemAtPath:_path error:NULL];
    [super tearDown];
}

/// @a statements run on a new database, and its diagram.
- (UDSQLDiagram *)diagramOf:(NSArray<NSString *> *)statements {
    NSError *error = nil;
    UDSQLConnection *connection = [UDPlugin(UDSQLConnection) connectionToURL:[NSURL fileURLWithPath:_path] password:nil error:&error];
    XCTAssertNotNil(connection, @"%@", error);
    for (NSString *sql in statements) XCTAssertNotNil([connection execute:sql parameters:@[] maxRows:1 error:&error], @"%@: %@", sql, error);
    UDSQLSchema *schema = [UDPlugin(UDSQLSchema) schemaOfConnection:connection error:&error];
    XCTAssertNotNil(schema, @"%@", error);
    [connection close];
    id<DKSurface> measure = [[NSClassFromString(@"DKSVGSurface") alloc] initWithSize:NSMakeSize(100, 100)];
    return [[UDPluginClass(@"UDSQLDiagram") alloc] initWithSchema:schema measure:measure];
}

- (nullable UDSQLDiagramLink *)linkOf:(UDSQLDiagram *)diagram from:(NSString *)from to:(NSString *)to {
    for (UDSQLDiagramLink *link in diagram.links) {
        if ([link.from isEqualToString:from] && [link.to isEqualToString:to]) return link;
    }
    return nil;
}

- (void)testForeignKeys {
    UDSQLDiagram *diagram = [self diagramOf:@[
        @"CREATE TABLE teams (id INTEGER PRIMARY KEY, title TEXT)",
        @"CREATE TABLE people (id INTEGER PRIMARY KEY, name TEXT, team INTEGER NOT NULL REFERENCES teams(id), mentor INTEGER REFERENCES people(id))",
        @"CREATE TABLE badges (id INTEGER PRIMARY KEY, person INTEGER REFERENCES people(id))",
        @"CREATE VIEW names AS SELECT name FROM people" ]];
    XCTAssertEqualObjects([[diagram.tables valueForKey:@"identifier"] sortedArrayUsingSelector:@selector(compare:)],
                          (@[ @"badges", @"people", @"teams" ]), @"tables, not views");
    XCTAssertEqual(diagram.links.count, 3u);

    UDSQLDiagramLink *team = [self linkOf:diagram from:@"people" to:@"teams"];
    XCTAssertNotNil(team);
    XCTAssertEqualObjects(team.columns, @[ @"team" ]);
    XCTAssertFalse(team.inferred);
    XCTAssertEqual(team.fromEnd, DKEdgeEndCrowFootZeroOrMany, @"many people to a team");
    XCTAssertEqual(team.toEnd, DKEdgeEndCrowFootOne, @"NOT NULL: exactly one team");
    XCTAssertEqual([self linkOf:diagram from:@"badges" to:@"people"].toEnd, DKEdgeEndCrowFootZeroOrOne, @"a NULL person: zero or one");

    UDSQLDiagramLink *mentor = [self linkOf:diagram from:@"people" to:@"people"];
    XCTAssertNotNil(mentor, @"a table referring to itself");
    XCTAssertEqual(mentor.route.count, 5u, @"a loop out of its side");

    // in layers, what is referred to first; nothing overlapping
    NSRect teams = [diagram tableWithIdentifier:@"teams"].frame, people = [diagram tableWithIdentifier:@"people"].frame,
           badges = [diagram tableWithIdentifier:@"badges"].frame;
    XCTAssertLessThan(NSMaxX(teams), NSMinX(people));
    XCTAssertLessThan(NSMaxX(people), NSMinX(badges));
    XCTAssertGreaterThanOrEqual(NSHeight(people), 3 * 16.0, @"a row a column");
    XCTAssertTrue(NSContainsRect(diagram.bounds, people));
    XCTAssertGreaterThanOrEqual(team.route.count, 2u);
    XCTAssertEqualObjects([diagram tableAtPoint:NSMakePoint(NSMidX(people), NSMidY(people))], @"people");
    XCTAssertNil([diagram tableAtPoint:NSMakePoint(NSMinX(teams) - 20, NSMinY(teams))]);
    XCTAssertEqual([diagram tablesInRect:NSUnionRect(teams, people)].count, 2u);
}

- (void)testMovedKeptAndSetAgain {
    UDSQLDiagram *diagram = [self diagramOf:@[ @"CREATE TABLE teams (id INTEGER PRIMARY KEY)",
                                               @"CREATE TABLE people (id INTEGER PRIMARY KEY, team INTEGER REFERENCES teams(id))" ]];
    NSRect before = [diagram tableWithIdentifier:@"people"].frame;
    [diagram moveTables:@[ @"people" ] by:NSMakeSize(200, 120)];
    NSRect after = [diagram tableWithIdentifier:@"people"].frame;
    XCTAssertEqual(NSMinX(after), NSMinX(before) + 200);
    XCTAssertEqual(NSMinY(after), NSMinY(before) + 120);
    // the line still leaves the box that moved
    UDSQLDiagramLink *link = diagram.links.firstObject;
    NSPoint start = link.route.firstObject.pointValue;
    XCTAssertTrue(NSPointInRect(start, NSInsetRect(after, -1, -1)), @"%@ from %@", NSStringFromPoint(start), NSStringFromRect(after));

    NSDictionary *positions = [diagram positions];
    [diagram arrange];
    XCTAssertEqual(NSMinX([diagram tableWithIdentifier:@"people"].frame), NSMinX(before), @"laid out again");
    [diagram applyPositions:positions];
    XCTAssertEqual(NSMinX([diagram tableWithIdentifier:@"people"].frame), NSMinX(after), @"where it was left");
    [diagram applyPositions:@{ @"nothing": @"1 2", @"teams": @"oops" }];
    XCTAssertEqual(NSMinX([diagram tableWithIdentifier:@"people"].frame), NSMinX(after), @"what isn't one: left");
}

- (void)testDrawn {
    UDSQLDiagram *diagram = [self diagramOf:@[ @"CREATE TABLE teams (id INTEGER PRIMARY KEY, title TEXT)",
                                               @"CREATE TABLE people (id INTEGER PRIMARY KEY, team INTEGER REFERENCES teams(id))" ]];
    NSRect bounds = diagram.bounds;
    id surface = [[NSClassFromString(@"DKSVGSurface") alloc] initWithSize:bounds.size];
    id state = [[NSClassFromString(@"DKDrawingState") alloc] init];
    [state setValue:[NSSet setWithObject:@"people"] forKey:@"selection"];
    [diagram drawInRect:bounds surface:surface state:state];
    NSString *svg = [surface SVGString];
    XCTAssertTrue([svg containsString:@">teams<"], @"%@", svg);
    XCTAssertTrue([svg containsString:@">title<"]);
    XCTAssertTrue([svg containsString:@">PK<"], @"the keys marked");
    XCTAssertTrue([svg containsString:@">FK<"]);
}

- (void)testACoreDataStoresLinksAreInferred {
    UDSQLDiagram *diagram = [self diagramOf:@[
        @"CREATE TABLE Z_PRIMARYKEY (Z_ENT INTEGER PRIMARY KEY, Z_NAME VARCHAR, Z_SUPER INTEGER, Z_MAX INTEGER)",
        @"INSERT INTO Z_PRIMARYKEY VALUES (1, 'Person', 0, 0), (2, 'Employee', 1, 0), (3, 'Team', 0, 0)",
        @"CREATE TABLE Z_METADATA (Z_VERSION INTEGER PRIMARY KEY, Z_UUID VARCHAR(255), Z_PLIST BLOB)",
        @"CREATE TABLE ZPERSON (Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZNAME VARCHAR, ZTEAM INTEGER)",
        @"CREATE TABLE ZTEAM (Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZTITLE VARCHAR)",
        @"CREATE TABLE Z_1TEAMS (Z_1PEOPLE INTEGER, Z_3TEAMS INTEGER)" ]];
    XCTAssertEqualObjects([[diagram.tables valueForKey:@"identifier"] sortedArrayUsingSelector:@selector(compare:)],
                          (@[ @"ZPERSON", @"ZTEAM", @"Z_1TEAMS" ]), @"not Core Data's own bookkeeping");
    UDSQLDiagramLink *team = [self linkOf:diagram from:@"ZPERSON" to:@"ZTEAM"];
    XCTAssertTrue(team.inferred, @"a to-one: its column named as the table");
    XCTAssertEqual(team.toEnd, DKEdgeEndCrowFootZeroOrOne);
    XCTAssertTrue([self linkOf:diagram from:@"Z_1TEAMS" to:@"ZPERSON"].inferred, @"a join table's: Z_1… is Person's");
    XCTAssertTrue([self linkOf:diagram from:@"Z_1TEAMS" to:@"ZTEAM"].inferred, @"Z_3… is Team's");
    XCTAssertEqual(diagram.links.count, 3u);
    XCTAssertGreaterThan(NSHeight([diagram tableWithIdentifier:@"ZPERSON"].frame), NSHeight([diagram tableWithIdentifier:@"ZTEAM"].frame),
                         @"its entities under its name, and a column more");
}

@end
