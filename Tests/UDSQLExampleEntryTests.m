//
//  UDSQLExampleEntryTests.m
//
//  A skeleton's entry as the form's line shows it (Show, Total, operator,
//  value, To), and written back: what is
//  typed read so, and the text the same after.
//

#import <XCTest/XCTest.h>
#import "UDCodeTestCase.h"
#import <UDCodeKit/UDCodeKit.h>
#import "UDSQLExampleEntry.h"

static Class UDPluginClass(NSString *name) {
    (void)[UDLanguageModeRegistry sharedRegistry];
    return NSClassFromString(name);
}

@interface UDSQLExampleEntryTests : UDCodeTestCase
@end

@implementation UDSQLExampleEntryTests

- (UDSQLExampleEntry *)entry:(NSString *)text {
    return [UDPluginClass(@"UDSQLExampleEntry") entryOfText:text];
}

/// Read so, and the same text written back.
- (void)check:(NSString *)text shown:(BOOL)shown total:(UDSQLExampleTotal)total op:(UDSQLExampleOperator)op
        value:(NSString *)value to:(NSString *)to {
    UDSQLExampleEntry *entry = [self entry:text];
    XCTAssertEqual(entry.shown, shown, @"%@", text);
    XCTAssertEqual(entry.total, total, @"%@", text);
    XCTAssertEqual(entry.op, op, @"%@", text);
    XCTAssertEqualObjects(entry.value, value, @"%@", text);
    XCTAssertEqualObjects(entry.to, to, @"%@", text);
    XCTAssertEqualObjects(entry.text, text, @"written back as typed");
}

- (void)testWhatIsTypedRead {
    [self check:@"" shown:NO total:UDSQLExampleTotalNone op:UDSQLExampleOperatorNone value:@"" to:@""];
    [self check:@"P." shown:YES total:UDSQLExampleTotalNone op:UDSQLExampleOperatorNone value:@"" to:@""];
    [self check:@"P.G._d" shown:YES total:UDSQLExampleTotalGroup op:UDSQLExampleOperatorEqual value:@"_d" to:@""];
    [self check:@"G." shown:NO total:UDSQLExampleTotalGroup op:UDSQLExampleOperatorNone value:@"" to:@""];
    [self check:@"P.SUM. > 5" shown:YES total:UDSQLExampleTotalSum op:UDSQLExampleOperatorGreater value:@"5" to:@""];
    [self check:@"CNT.UNQ. >= 2" shown:NO total:UDSQLExampleTotalCountDistinct op:UDSQLExampleOperatorAtLeast value:@"2" to:@""];
    [self check:@"P.> 6" shown:YES total:UDSQLExampleTotalNone op:UDSQLExampleOperatorGreater value:@"6" to:@""];
    [self check:@"Ann" shown:NO total:UDSQLExampleTotalNone op:UDSQLExampleOperatorEqual value:@"Ann" to:@""];
    [self check:@"Ann*" shown:NO total:UDSQLExampleTotalNone op:UDSQLExampleOperatorLike value:@"Ann*" to:@""];
    [self check:@"1..10" shown:NO total:UDSQLExampleTotalNone op:UDSQLExampleOperatorBetween value:@"1" to:@"10"];
    [self check:@"A.." shown:NO total:UDSQLExampleTotalNone op:UDSQLExampleOperatorBetween value:@"A" to:@""];
    [self check:@"a, b" shown:NO total:UDSQLExampleTotalNone op:UDSQLExampleOperatorOneOf value:@"a, b" to:@""];
    [self check:@"!x" shown:NO total:UDSQLExampleTotalNone op:UDSQLExampleOperatorNot value:@"x" to:@""];
    [self check:@"NULL" shown:NO total:UDSQLExampleTotalNone op:UDSQLExampleOperatorIsNull value:@"" to:@""];
    [self check:@"NOT NULL" shown:NO total:UDSQLExampleTotalNone op:UDSQLExampleOperatorIsNotNull value:@"" to:@""];
    [self check:@"<> _c" shown:NO total:UDSQLExampleTotalNone op:UDSQLExampleOperatorNotEqual value:@"_c" to:@""];
    [self check:@"'5, 6'" shown:NO total:UDSQLExampleTotalNone op:UDSQLExampleOperatorEqual value:@"'5, 6'" to:@""];
}

/// Set through the form: written as typed text would be.
- (void)testTheFormWritten {
    UDSQLExampleEntry *entry = [self entry:@""];
    entry.shown = YES;
    entry.total = UDSQLExampleTotalSum;
    XCTAssertEqualObjects(entry.text, @"P.SUM.");
    entry.op = UDSQLExampleOperatorGreater;
    entry.value = @"5";
    XCTAssertEqualObjects(entry.text, @"P.SUM. > 5");
    entry = [self entry:@""];
    entry.op = UDSQLExampleOperatorBetween;
    entry.value = @"2024-05-01";
    entry.to = @"2024-06-30";
    XCTAssertEqualObjects(entry.text, @"2024-05-01..2024-06-30");
    entry = [self entry:@""];
    entry.op = UDSQLExampleOperatorLike;
    entry.value = @"Meet";
    XCTAssertEqualObjects(entry.text, @"Meet*", @"a pattern: its * where none is typed");
    // a value typed whole: as typed, its operator aside
    entry = [self entry:@""];
    entry.op = UDSQLExampleOperatorEqual;
    entry.value = @"> 5";
    XCTAssertEqualObjects(entry.text, @"> 5");
    // the operator changed, the value kept
    entry = [self entry:@"5"];
    entry.op = UDSQLExampleOperatorAtMost;
    XCTAssertEqualObjects(entry.text, @"<= 5");
    entry.op = UDSQLExampleOperatorIsNull;
    XCTAssertEqualObjects(entry.text, @"NULL");
}

@end
