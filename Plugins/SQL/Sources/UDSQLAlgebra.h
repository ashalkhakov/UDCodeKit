/*---------------------------------------------------------------------------------------------
 *  UDSQLAlgebra.h
 *
 *  Relational algebra, as SQL is written from it: relations (a table under
 *  an alias — a tuple variable — joined, inner or left, on a predicate;
 *  selected, σ; projected, π; united, ∪; ordered; a page of them; their
 *  count), predicates over them (comparisons, NULL, LIKE, IN, BETWEEN, and,
 *  or, not, a relation's rows existing) and expressions (a tuple
 *  variable's column, a value). A term's SQL is written in one pass, its
 *  values parameters in the dialect's style in the order they are written,
 *  or written in; its columns qualified by their variables where a query
 *  has more than one.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import "UDSQLConnection.h"
#import "UDSQLSchema.h"

NS_ASSUME_NONNULL_BEGIN

@class UDSQLRelation;

typedef NS_ENUM(NSInteger, UDSQLComparison) {
    UDSQLEqual,
    UDSQLNotEqual,
    UDSQLLess,
    UDSQLLessOrEqual,
    UDSQLGreater,
    UDSQLGreaterOrEqual,
};

/// A tuple variable's column, an output column (by its name), or a value.
@interface UDSQLExpression : NSObject
+ (instancetype)column:(NSString *)name of:(NSString *)variable;
/// A column of what a query gives, by its name (a union's, ordered).
+ (instancetype)outputColumn:(NSString *)name;
+ (instancetype)value:(id)value;
/// The variable (nil: an output column's, or a value), the column's name,
/// the value.
@property (nonatomic, readonly, copy, nullable) NSString *variable;
@property (nonatomic, readonly, copy, nullable) NSString *name;
@property (nonatomic, readonly, strong, nullable) id value;
@end

@interface UDSQLPredicate : NSObject
+ (instancetype)compare:(UDSQLExpression *)left op:(UDSQLComparison)op to:(UDSQLExpression *)right;
+ (instancetype)isNull:(UDSQLExpression *)expression;
/// LIKE, case aside (PostgreSQL's ILIKE, of the expression's text).
+ (instancetype)like:(UDSQLExpression *)expression pattern:(UDSQLExpression *)pattern;
+ (instancetype)in:(UDSQLExpression *)expression values:(NSArray<UDSQLExpression *> *)values;
+ (instancetype)between:(UDSQLExpression *)expression low:(UDSQLExpression *)low high:(UDSQLExpression *)high;
/// All of them (none: true), any of them, not it.
+ (instancetype)and:(NSArray<UDSQLPredicate *> *)predicates;
+ (instancetype)or:(NSArray<UDSQLPredicate *> *)predicates;
+ (instancetype)not:(UDSQLPredicate *)predicate;
/// Whether @a relation has a row (correlated: its predicates may name the
/// variables around it).
+ (instancetype)exists:(UDSQLRelation *)relation;
/// Its SQL, alone (its columns as qualified, or not).
- (NSString *)SQLForDialect:(UDSQLDialect)dialect qualified:(BOOL)qualified parameters:(nullable NSMutableArray *)parameters;
@end

typedef NS_ENUM(NSInteger, UDSQLJoinKind) {
    UDSQLJoinInner,
    UDSQLJoinLeft,      // every row of the left, the right's where it matches (else NULLs)
};

/// An order's key: an expression, ascending or not.
@interface UDSQLOrderKey : NSObject
+ (instancetype)key:(UDSQLExpression *)expression ascending:(BOOL)ascending;
@property (nonatomic, readonly) UDSQLExpression *expression;
@property (nonatomic, readonly) BOOL ascending;
@end

@interface UDSQLRelation : NSObject

/// @a table's rows, under @a variable (a tuple variable).
+ (instancetype)table:(UDSQLTable *)table variable:(NSString *)variable;
/// Its rows and @a right's, joined on @a on (left: all of its own).
- (UDSQLRelation *)join:(UDSQLRelation *)right on:(UDSQLPredicate *)on kind:(UDSQLJoinKind)kind;
/// σ: those meeting @a predicate.
- (UDSQLRelation *)select:(UDSQLPredicate *)predicate;
/// π: @a columns (named @a names, else by their own), or all of a
/// variable's (@a variable), or all (nil, nil).
- (UDSQLRelation *)project:(nullable NSArray<UDSQLExpression *> *)columns names:(nullable NSArray<NSString *> *)names;
- (UDSQLRelation *)projectAllOf:(NSString *)variable;
/// ∪: their rows, each once (the same columns, in the same order).
+ (UDSQLRelation *)union:(NSArray<UDSQLRelation *> *)relations;
- (UDSQLRelation *)order:(NSArray<UDSQLOrderKey *> *)keys;
/// @a limit rows from @a offset.
- (UDSQLRelation *)pageFrom:(NSUInteger)offset limit:(NSUInteger)limit;
/// How many rows it has.
- (UDSQLRelation *)count;

/// The tables it names (its subqueries' too), each tuple variable once.
@property (nonatomic, readonly) NSUInteger variableCount;

/// Its SQL: its values in @a parameters (placeholders numbered on from
/// those there), or written in when nil.
- (NSString *)SQLForDialect:(UDSQLDialect)dialect parameters:(nullable NSMutableArray *)parameters;
/// UDSQLPrettyPrinted(@a sql).
+ (NSString *)prettyPrinted:(NSString *)sql;

@end

/// @a name quoted for @a dialect ("x", `x`).
FOUNDATION_EXPORT NSString *UDSQLQuoted(NSString *name, UDSQLDialect dialect);

/// @a sql (as a relation writes it: one line) as it is written by hand: a
/// clause a line (FROM, JOIN, WHERE, ORDER BY, LIMIT, UNION), a WHERE's
/// ANDs a line each, a subquery indented under its "(" (NOT EXISTS, a
/// union's); what is quoted, as it is.
FOUNDATION_EXPORT NSString *UDSQLPrettyPrinted(NSString *sql);

NS_ASSUME_NONNULL_END
