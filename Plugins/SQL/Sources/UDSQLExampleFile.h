/*---------------------------------------------------------------------------------------------
 *  UDSQLExampleFile.h
 *
 *  A query by example as it is kept (a .qbe file: JSON, as git diffs it):
 *  its skeletons by their tables' names (and schemas), their rows (what is
 *  typed under each column; ¬, !), its order. Not a connection: the same
 *  file is asked of any (staging, production), its tables found by name in
 *  the one asked (-queryForSchema:…).
 *
 *    { "kind": "UDCode query by example", "version": 1,
 *      "skeletons": [ { "table": "customers", "rows": [ { "entries": { "id": "_c", "name": "P." } } ] },
 *                     { "table": "orders", "rows": [ { "entries": { "customer": "_c" }, "inclusive": true } ] } ],
 *      "order": [ { "column": "name", "ascending": true } ] }
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import "UDSQLExampleQuery.h"

NS_ASSUME_NONNULL_BEGIN

/// A skeleton as kept: its table's name and schema, its rows.
@interface UDSQLExampleFileSkeleton : NSObject
+ (instancetype)skeletonOfTable:(NSString *)table schema:(nullable NSString *)schema;
@property (nonatomic, copy) NSString *table;
@property (nonatomic, copy, nullable) NSString *schema;
@property (nonatomic, copy) NSArray<UDSQLExampleRow *> *rows;
@end

@interface UDSQLExampleFile : NSObject

/// An empty one; one read from @a data (nil and why in @a error).
- (instancetype)init;
+ (nullable instancetype)fileWithData:(NSData *)data error:(NSError *_Nullable *_Nullable)error;
/// Its JSON: its keys sorted, indented.
- (NSData *)data;

@property (nonatomic, copy) NSArray<UDSQLExampleFileSkeleton *> *skeletons;
@property (nonatomic, copy) NSArray<NSSortDescriptor *> *order;

/// It asked of @a schema's database (@a dialect's): its tables found by
/// name; nil and why in @a error ("production has no table orders").
- (nullable UDSQLExampleQuery *)queryForSchema:(UDSQLSchema *)schema dialect:(UDSQLDialect)dialect
                                  databaseName:(NSString *)name error:(NSError *_Nullable *_Nullable)error;

@end

NS_ASSUME_NONNULL_END
