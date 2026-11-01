//
//  UDSQLExampleHighlightTests.m
//
//  A query by example's syntax highlighting, as XFormsKit's XPath's is
//  tested (XFDXPathHighlightTests): the engine's tokens (one lexer, the
//  condition box's), and UDSQLExampleTextStorage driven the way typing
//  does, so that recolouring on every change is pinned rather than assumed.
//

#import <XCTest/XCTest.h>
#import "UDCodeTestCase.h"
#import <UDCodeKit/UDCodeKit.h>
#import "UDSQLExampleCondition.h"
#import "UDSQLExampleTextStorage.h"

static Class UDPluginClass(NSString *name) {
    (void)[UDLanguageModeRegistry sharedRegistry];
    return NSClassFromString(name);
}

@interface UDSQLExampleHighlightTests : UDCodeTestCase
@end

@implementation UDSQLExampleHighlightTests

- (NSTextStorage *)storageWith:(NSString *)text {
    NSTextStorage *storage = [[UDPluginClass(@"UDSQLExampleTextStorage") alloc] init];
    [storage replaceCharactersInRange:NSMakeRange(0, 0) withString:text];
    return storage;
}

- (NSColor *)colourIn:(NSTextStorage *)storage at:(NSUInteger)index {
    NSColor *colour = [storage attribute:NSForegroundColorAttributeName atIndex:index effectiveRange:NULL];
    return [colour colorUsingColorSpaceName:NSCalibratedRGBColorSpace] ?: colour;
}

- (NSArray *)kindsOf:(NSString *)text {
    return [[UDPluginClass(@"UDSQLExampleCondition") highlightTokensForString:text] valueForKey:@"kind"];
}

/// The engine's tokens: a skeleton's entries and the condition box's
/// lines, half typed too.
- (void)testTheTokens {
    XCTAssertEqualObjects([self kindsOf:@"P.G._d"], (@[ @"command", @"command", @"variable" ]));
    XCTAssertEqualObjects([self kindsOf:@"P.SUM.ALL. > 5"], (@[ @"command", @"function", @"operator", @"number" ]));
    XCTAssertEqualObjects([self kindsOf:@"Ann*, 'Bob'"], (@[ @"name", @"punct", @"string" ]));
    XCTAssertEqualObjects([self kindsOf:@"1..10"], (@[ @"number", @"operator", @"number" ]));
    XCTAssertEqualObjects([self kindsOf:@"CNT.UNQ._e > 5 AND (_c = 'x"], (@[ @"function", @"variable", @"operator", @"number",
                                                                          @"operator", @"punct", @"variable", @"operator", @"string" ]),
                          @"half typed: lexed all the same");
    NSArray *tokens = [UDPluginClass(@"UDSQLExampleCondition") highlightTokensForString:@"P.SUM.UNQ._x"];
    XCTAssertEqualObjects(tokens[1][@"range"], [NSValue valueWithRange:NSMakeRange(2, 8)], @"SUM.UNQ. one token");
}

- (void)testTokensAreColouredDifferently {
    NSTextStorage *storage = [self storageWith:@"CNT.ALL._e > 5 OR _c = 'Oslo'"];
    NSString *text = storage.string;
    NSColor *function = [self colourIn:storage at:0];
    NSColor *variable = [self colourIn:storage at:[text rangeOfString:@"_e"].location];
    NSColor *number = [self colourIn:storage at:[text rangeOfString:@"5"].location];
    NSColor *string = [self colourIn:storage at:[text rangeOfString:@"'Oslo'"].location];
    XCTAssertNotNil(function);
    // the point is that they DIFFER; the palette is UDSQLExampleTokenColor's
    NSArray *colours = @[ function, variable, number, string ];
    XCTAssertEqual([NSSet setWithArray:colours].count, colours.count, @"%@", colours);
}

/// The colours survive editing: a storage recolours itself, told of every change.
- (void)testColoursSurviveEveryEdit {
    NSTextStorage *storage = [self storageWith:@"P.SU"];
    for (NSString *typed in @[ @"M", @".", @" ", @">", @" ", @"5" ]) {
        [storage replaceCharactersInRange:NSMakeRange(storage.length, 0) withString:typed];
    }
    XCTAssertEqualObjects(storage.string, @"P.SUM. > 5");
    XCTAssertNotEqualObjects([self colourIn:storage at:2], [self colourIn:storage at:0], @"SUM. coloured as a function once typed");
}

/// The whole text re-lexed: a quote typed changes what follows it.
- (void)testAnOpenedQuoteRecoloursWhatFollows {
    NSTextStorage *storage = [self storageWith:@"a, b"];
    NSColor *plain = [self colourIn:storage at:3];
    [storage replaceCharactersInRange:NSMakeRange(0, 0) withString:@"'"];
    XCTAssertNotEqualObjects(plain, [self colourIn:storage at:4], @"text after a new quote is re-lexed");
}

- (void)testBaseAttributesCarryTheFont {
    UDSQLExampleTextStorage *storage = (UDSQLExampleTextStorage *)[self storageWith:@"_x"];
    NSFont *mono = [NSFont userFixedPitchFontOfSize:11];
    storage.baseAttributes = @{ NSFontAttributeName: mono };
    XCTAssertEqualObjects([storage attribute:NSFontAttributeName atIndex:0 effectiveRange:NULL], mono);
}

@end
