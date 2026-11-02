/*---------------------------------------------------------------------------------------------
 *  UDSQLExampleEntry.h
 *
 *  What is typed under a skeleton's column (P.SUM. > 5, Ann*, 1..10, _c),
 *  as the form's line shows it: Show (P.), Total (G. or an aggregate), an
 *  operator, a value and, for a range, another —
 *
 *    P.            Show ✓
 *    P.G._d        Show ✓  Total Group      =   _d
 *    P.SUM. > 5    Show ✓  Total Sum        >   5      (of the groups)
 *    Ann*                                   ≈   Ann*
 *    1..10                                  []  1      10
 *    !x                                     ¬   x
 *
 *  Read from the text and written back as it (the .qbe file keeps the
 *  text: Show as Text, the query, all as they were). A value typed whole
 *  (> 5 in the value, its operator =) is kept as typed.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, UDSQLExampleTotal) {
    UDSQLExampleTotalNone,
    UDSQLExampleTotalGroup,         // G.
    UDSQLExampleTotalSum,           // SUM.
    UDSQLExampleTotalAverage,       // AVG.
    UDSQLExampleTotalMinimum,       // MIN.
    UDSQLExampleTotalMaximum,       // MAX.
    UDSQLExampleTotalCount,         // CNT.
    UDSQLExampleTotalCountDistinct, // CNT.UNQ.
};

typedef NS_ENUM(NSInteger, UDSQLExampleOperator) {
    UDSQLExampleOperatorNone,       // nothing, or what is typed, as it is
    UDSQLExampleOperatorEqual,      // Ann, _c
    UDSQLExampleOperatorNotEqual,   // <> x
    UDSQLExampleOperatorGreater,
    UDSQLExampleOperatorAtLeast,
    UDSQLExampleOperatorLess,
    UDSQLExampleOperatorAtMost,
    UDSQLExampleOperatorBetween,    // a..b: the value and To
    UDSQLExampleOperatorLike,       // Ann*
    UDSQLExampleOperatorOneOf,      // a, b, c
    UDSQLExampleOperatorNot,        // !x
    UDSQLExampleOperatorIsNull,
    UDSQLExampleOperatorIsNotNull,
};

@interface UDSQLExampleEntry : NSObject

/// @a text read (nil or empty: nothing).
+ (instancetype)entryOfText:(nullable NSString *)text;

@property (nonatomic) BOOL shown;
@property (nonatomic) UDSQLExampleTotal total;
@property (nonatomic) UDSQLExampleOperator op;
@property (nonatomic, copy) NSString *value;
/// A range's end (Between).
@property (nonatomic, copy) NSString *to;

/// It as typed: P.G., P.SUM. > 5, 1..10.
@property (nonatomic, readonly, copy) NSString *text;

@end

NS_ASSUME_NONNULL_END
