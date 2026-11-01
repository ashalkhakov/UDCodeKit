/*---------------------------------------------------------------------------------------------
 *  UDSQLQueryDesign.h
 *
 *  A query as its builder designs it, query by example's way: the tables
 *  in it (each under an alias, so one may be in twice), joined on columns
 *  (inner, or left: every row of the left one), and its fields: what is
 *  shown, in what order sorted, and under each the conditions its rows are
 *  to meet, as the browser reads them (UDSQLQbE: a row of conditions all,
 *  any row). Its SQL: the tables from the first, joined as they are
 *  connected (a table connected to none is crossed, and said to be), its
 *  values parameters, or written in to be shown.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import "UDSQLQbE.h"

NS_ASSUME_NONNULL_BEGIN

/// A table in it, under its alias.
@interface UDSQLQueryTable : NSObject
@property (nonatomic, readonly) UDSQLTable *table;
@property (nonatomic, readonly, copy) NSString *alias;
@end

typedef NS_ENUM(NSInteger, UDSQLJoinKind) {
    UDSQLJoinInner,
    UDSQLJoinLeft,      // every row of the left (from) table, the right's where they match
};

/// A join: @a from's column equal to @a to's.
@interface UDSQLQueryJoin : NSObject
@property (nonatomic, readonly, copy) NSString *from;
@property (nonatomic, readonly, copy) NSString *fromColumn;
@property (nonatomic, readonly, copy) NSString *to;
@property (nonatomic, readonly, copy) NSString *toColumn;
@property (nonatomic) UDSQLJoinKind kind;
@end

typedef NS_ENUM(NSInteger, UDSQLFieldSort) {
    UDSQLFieldUnsorted,
    UDSQLFieldAscending,
    UDSQLFieldDescending,
};

/// A field: a table's column, shown or not, sorted or not, its conditions.
@interface UDSQLQueryField : NSObject
@property (nonatomic, readonly, copy) NSString *alias;
@property (nonatomic, readonly, copy) NSString *column;
@property (nonatomic) BOOL shown;
@property (nonatomic) UDSQLFieldSort sort;
/// The conditions typed under it, a row of conditions each ("" none).
@property (nonatomic, copy) NSArray<NSString *> *conditions;
@end

@interface UDSQLQueryDesign : NSObject

- (instancetype)initWithSchema:(UDSQLSchema *)schema dialect:(UDSQLDialect)dialect;

@property (nonatomic, readonly) UDSQLSchema *schema;
@property (nonatomic, readonly) UDSQLDialect dialect;

@property (nonatomic, readonly, copy) NSArray<UDSQLQueryTable *> *tables;
@property (nonatomic, readonly, copy) NSArray<UDSQLQueryJoin *> *joins;
@property (nonatomic, readonly, copy) NSArray<UDSQLQueryField *> *fields;
/// How many rows of conditions there are (1 at least).
@property (nonatomic) NSUInteger conditionRows;

/// @a table added, under an alias of its own (its name, then name2…):
/// joined to those in it already along their foreign keys (inner).
- (UDSQLQueryTable *)addTable:(UDSQLTable *)table;
/// The table under @a alias taken away, with its joins and fields.
- (void)removeTable:(NSString *)alias;
- (nullable UDSQLQueryTable *)tableWithAlias:(NSString *)alias;

/// A join of @a from's @a fromColumn to @a to's @a toColumn (the one there:
/// it, not another).
- (UDSQLQueryJoin *)joinTable:(NSString *)from column:(NSString *)fromColumn
                      toTable:(NSString *)to column:(NSString *)toColumn kind:(UDSQLJoinKind)kind;
- (void)removeJoin:(UDSQLQueryJoin *)join;

/// A field of @a alias's @a column, shown, at the end (the one there: it);
/// taken away.
- (UDSQLQueryField *)addField:(NSString *)column ofTable:(NSString *)alias;
- (nullable UDSQLQueryField *)fieldOf:(NSString *)column table:(NSString *)alias;
- (void)removeField:(UDSQLQueryField *)field;
/// A field moved to @a index.
- (void)moveField:(UDSQLQueryField *)field toIndex:(NSUInteger)index;

/// Its select, its values parameters; nil and why in @a error (a condition
/// that can't be read: UDSQLQbE's keys, the field's index as its column).
- (nullable UDSQLStatement *)statement:(NSError *_Nullable *_Nullable)error;
/// The select as it would be written by hand: its values in it.
- (nullable NSString *)SQL:(NSError *_Nullable *_Nullable)error;
/// The tables in it connected to the first by no join (crossed), by alias.
- (NSArray<NSString *> *)unjoinedTables;

@end

NS_ASSUME_NONNULL_END
