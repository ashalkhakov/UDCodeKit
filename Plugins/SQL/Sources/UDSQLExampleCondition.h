/*---------------------------------------------------------------------------------------------
 *  UDSQLExampleCondition.h
 *
 *  A line of a query by example's condition box, Zloof's: what no column's
 *  entry can say, of its example elements —
 *
 *    _s > _b * 2                     elements compared, with arithmetic
 *    _c = 'Oslo' OR _c = 'Rome'      AND, OR, NOT, parentheses
 *    _d IS NOT NULL
 *    CNT.ALL._e > 5                  an aggregate of an element's values:
 *    AVG.ALL._s > 10000              the groups it keeps (HAVING)
 *
 *  Its elements are those the skeletons' rows bind (P._s, _c…); a line
 *  without an aggregate keeps rows (WHERE), one with one, groups.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import "UDSQLAlgebra.h"

NS_ASSUME_NONNULL_BEGIN

/// The aggregate @a text begins with, Zloof's (SUM. AVG. MIN. MAX. CNT.),
/// as SQL names it (SUM… COUNT), then ALL. (the default) or UNQ. (its
/// distinct values: @a distinct); what follows in @a rest. nil: none.
FOUNDATION_EXPORT NSString *_Nullable UDSQLAggregateOf(NSString *text, NSString *_Nullable *_Nullable rest,
                                                      BOOL *_Nullable distinct);
/// Zloof's name of SQL's @a function: CNT for COUNT.
FOUNDATION_EXPORT NSString *UDSQLZloofName(NSString *function);

@interface UDSQLExampleCondition : NSObject

/// @a text read; nil and why in @a message (what can't be read, and where).
+ (nullable instancetype)conditionOf:(NSString *)text message:(NSString *_Nullable *_Nullable)message;

@property (nonatomic, readonly, copy) NSString *text;
/// The example elements it names.
@property (nonatomic, readonly, copy) NSSet<NSString *> *elements;
/// Whether it has an aggregate: a group's condition (HAVING).
@property (nonatomic, readonly) BOOL aggregates;

/// As a predicate, each element @a bound's (its column's, in a query's
/// alternative); nil and why in @a message (an element bound nowhere).
- (nullable UDSQLPredicate *)predicateWithBound:(NSDictionary<NSString *, UDSQLExpression *> *)bound
                                        message:(NSString *_Nullable *_Nullable)message;

@end

NS_ASSUME_NONNULL_END
