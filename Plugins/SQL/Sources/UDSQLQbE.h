/*---------------------------------------------------------------------------------------------
 *  UDSQLQbE.h
 *
 *  A table's rows as query by example asks for them: under each column, a
 *  condition typed as one would say it, the conditions of a row all to
 *  hold (AND), any row of them (OR); in an order, a page at a time. What
 *  is typed is a value, never SQL: each becomes a parameter.
 *
 *    Ann  5           equal to it (a number where the column's is one)
 *    > 5  <= 3  <> x  compared ( >= < = != too)
 *    NULL  NOT NULL   which are NULL, which are not
 *    Ann*  %ann%      like it (* is any text; case not minded)
 *    1..10            between, both ends in
 *    a, b, c          one of them
 *    !x  not x        not so (any of the above)
 *    'x'  "5, 6"      the text as it is, quoted
 *
 *  A Core Data store's dates (TIMESTAMP) are typed as dates (2024-05-01,
 *  2024-05-01 14:30): a day alone is the whole day; its entities (Z_ENT)
 *  by name.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import "UDSQLConnection.h"
#import "UDSQLSchema.h"
#import "UDSQLRunner.h"

NS_ASSUME_NONNULL_BEGIN

/// What can be asked of a column, as its condition's menu offers it (the
/// menu items' tags).
typedef NS_ENUM(NSInteger, UDSQLQbEOperator) {
    UDSQLQbEEqual = 1,
    UDSQLQbENotEqual,
    UDSQLQbEGreater,
    UDSQLQbEAtLeast,
    UDSQLQbELess,
    UDSQLQbEAtMost,
    UDSQLQbELike,
    UDSQLQbEBetween,
    UDSQLQbEOneOf,
    UDSQLQbENull,
    UDSQLQbENotNull,
    UDSQLQbENot,
    UDSQLQbEClear,
};

/// The error's column (NSString) and its row of conditions (NSNumber).
FOUNDATION_EXPORT NSString *const UDSQLQbEColumnErrorKey;
FOUNDATION_EXPORT NSString *const UDSQLQbERowErrorKey;

@interface UDSQLQbE : NSObject

- (instancetype)initWithTable:(UDSQLTable *)table schema:(nullable UDSQLSchema *)schema dialect:(UDSQLDialect)dialect;

@property (nonatomic, readonly) UDSQLTable *table;
@property (nonatomic, readonly) UDSQLDialect dialect;

/// The rows of conditions: each the conditions typed, by column name.
@property (nonatomic, copy) NSArray<NSDictionary<NSString *, NSString *> *> *conditions;
/// The order: by column name, each ascending or not. None: the primary
/// key's, so pages don't overlap.
@property (nonatomic, copy) NSArray<NSSortDescriptor *> *order;
/// What always holds, as SQL (an entity's rows: Z_ENT IN (2, 3)); nil:
/// nothing.
@property (nonatomic, copy, nullable) NSString *restriction;

/// Its page of @a limit rows from @a offset; its rows' count; nil and why
/// in @a error when a condition can't be read.
- (nullable UDSQLStatement *)selectStatementWithLimit:(NSUInteger)limit offset:(NSUInteger)offset
                                                error:(NSError *_Nullable *_Nullable)error;
- (nullable UDSQLStatement *)countStatement:(NSError *_Nullable *_Nullable)error;
/// The select as it would be written by hand: its values in it.
- (nullable NSString *)SQLWithLimit:(NSUInteger)limit offset:(NSUInteger)offset error:(NSError *_Nullable *_Nullable)error;

/// @a text with @a op made of it, its value kept (5, Greater Than: > 5);
/// @a complete whether it asks for something as it is, or still wants a
/// value typed (> with none, 1.., a, ).
+ (NSString *)condition:(NSString *)text withOperator:(UDSQLQbEOperator)op complete:(BOOL *)complete;
/// What may be typed under @a column, by its type: an example (an empty
/// condition's placeholder: e.g. > 5), and all of it (its tooltip).
+ (NSString *)exampleForColumn:(UDSQLColumnInfo *)column schema:(nullable UDSQLSchema *)schema;
+ (NSString *)helpForColumn:(UDSQLColumnInfo *)column schema:(nullable UDSQLSchema *)schema;

/// @a name quoted for @a dialect ("x", `x`).
+ (NSString *)quotedIdentifier:(NSString *)name dialect:(UDSQLDialect)dialect;

@end

NS_ASSUME_NONNULL_END
