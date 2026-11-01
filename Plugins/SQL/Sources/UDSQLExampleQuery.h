/*---------------------------------------------------------------------------------------------
 *  UDSQLExampleQuery.h
 *
 *  Query by example as Zloof made it (and Paradox kept it): a skeleton of
 *  each table asked of, the first the one browsed; each of a skeleton's
 *  rows a tuple variable over its table; under its columns what they are:
 *
 *    P.         printed (a column of the answer)
 *    _c         an example element: a domain variable, the column bound to
 *               it; the same element in two rows' columns is a join
 *    > _c       compared with what _c is bound to (= < <= >= <> too)
 *    Ann  > 5…  a condition on its value, as the browser reads them
 *               (UDSQLQbE: Ann*, 1..10, a, b, NULL, !x…)
 *
 *  ("P." may come before any of them: P._c, P.> 5.) A row may be ¬, there
 *  being no such row (an anti-join: customers no order refers to), or !,
 *  Paradox's inclusion: the rows it is linked to kept where it has no
 *  match (a left join: its columns NULL).
 *
 *  Rows linked by their example elements are one alternative, which must
 *  hold a row of the first skeleton; alternatives are any of them (OR,
 *  when each is a row of the first skeleton alone; else a union). What is
 *  printed is its P. columns, or, with none, the first skeleton's.
 *
 *  As relational algebra (UDSQLAlgebra): an alternative's first row's table
 *  ⋈ its other rows' (in the order they are linked; ! rows left, their
 *  conditions in their joins), σ its conditions and comparisons and ¬
 *  rows (NOT EXISTS), π its printed columns; the alternatives ∪.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import "UDSQLAlgebra.h"
#import "UDSQLRunner.h"

NS_ASSUME_NONNULL_BEGIN

/// An error's skeleton and row (NSNumber), and column (NSString).
FOUNDATION_EXPORT NSString *const UDSQLExampleSkeletonErrorKey;
FOUNDATION_EXPORT NSString *const UDSQLExampleRowErrorKey;
FOUNDATION_EXPORT NSString *const UDSQLExampleColumnErrorKey;

/// A skeleton's row: what is typed under its columns, and whether it is ¬
/// or !.
@interface UDSQLExampleRow : NSObject
+ (instancetype)rowWithEntries:(NSDictionary<NSString *, NSString *> *)entries;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *entries;
/// ¬: there is no such row.
@property (nonatomic) BOOL negated;
/// !: the rows it is linked to are kept where it has no match.
@property (nonatomic) BOOL inclusive;
/// Nothing typed, nor ¬ or !: no row of the query.
@property (nonatomic, readonly, getter=isEmpty) BOOL empty;
@end

@interface UDSQLExampleSkeleton : NSObject
+ (instancetype)skeletonOf:(UDSQLTable *)table rows:(NSArray<UDSQLExampleRow *> *)rows;
@property (nonatomic, readonly) UDSQLTable *table;
@property (nonatomic, copy) NSArray<UDSQLExampleRow *> *rows;
@end

@interface UDSQLExampleQuery : NSObject

- (instancetype)initWithSchema:(nullable UDSQLSchema *)schema dialect:(UDSQLDialect)dialect;

@property (nonatomic, readonly, nullable) UDSQLSchema *schema;
@property (nonatomic, readonly) UDSQLDialect dialect;

/// Its skeletons, the first the table browsed.
@property (nonatomic, copy) NSArray<UDSQLExampleSkeleton *> *skeletons;
/// What the first skeleton's rows always meet: @a column one of @a values
/// (an entity's rows: Z_ENT IN (2, 3)); nil: nothing.
@property (nonatomic, copy, nullable) NSString *restrictionColumn;
@property (nonatomic, copy, nullable) NSArray *restrictionValues;
/// Its order, by printed columns' names; none: the first skeleton's
/// primary key where it is printed (so pages don't overlap).
@property (nonatomic, copy) NSArray<NSSortDescriptor *> *order;

/// What it asks for, unordered; nil and why in @a error (a condition that
/// can't be read, a row linked to none: the error's keys say where).
- (nullable UDSQLRelation *)relation:(NSError *_Nullable *_Nullable)error;
/// The names of the columns it prints, in order.
- (nullable NSArray<NSString *> *)printedColumns:(NSError *_Nullable *_Nullable)error;

/// Its page of @a limit rows from @a offset, its rows' count (parameters
/// in the dialect's style); the page as written by hand, its values in.
- (nullable UDSQLStatement *)selectStatementWithLimit:(NSUInteger)limit offset:(NSUInteger)offset
                                                error:(NSError *_Nullable *_Nullable)error;
- (nullable UDSQLStatement *)countStatement:(NSError *_Nullable *_Nullable)error;
- (nullable NSString *)SQLWithLimit:(NSUInteger)limit offset:(NSUInteger)offset error:(NSError *_Nullable *_Nullable)error;

/// A value condition (the browser's: Ann, > 5, Ann*, 1..10, a, b, NULL,
/// !x, 'x') typed under @a column of the tuple variable @a variable, as a
/// predicate; nil and why in @a message.
+ (nullable UDSQLPredicate *)predicateOf:(NSString *)typed column:(UDSQLColumnInfo *)column variable:(NSString *)variable
                                  schema:(nullable UDSQLSchema *)schema message:(NSString *_Nullable *_Nullable)message;

@end

NS_ASSUME_NONNULL_END
