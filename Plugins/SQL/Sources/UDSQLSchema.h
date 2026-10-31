/*---------------------------------------------------------------------------------------------
 *  UDSQLSchema.h
 *
 *  What a database holds, as everyday work wants it: its tables and views,
 *  their columns (type, nullability, default, primary key), foreign keys and
 *  indexes — read from each database's own catalogue (SQLite's sqlite_master
 *  and PRAGMAs, information_schema and pg_indexes, MySQL's information_schema
 *  of DATABASE()).
 *
 *  A Core Data store (its Z_PRIMARYKEY and Z_METADATA tables) is read as one:
 *  each Z table named by its entities (a subentity's rows are its root
 *  entity's table's), the store's metadata (its type, UUID, model version
 *  identifiers), and Core Data's own columns (Z_PK, Z_ENT, Z_OPT) explained;
 *  a TIMESTAMP column of one holds seconds since 2001 (NSDate's reference
 *  date).
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import "UDSQLConnection.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDSQLColumnInfo : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *type;
@property (nonatomic) BOOL nullable;
@property (nonatomic, copy, nullable) NSString *defaultValue;
@property (nonatomic) BOOL primaryKey;
/// What Core Data means by it (Z_PK's "the row's key"…); nil: nothing.
@property (nonatomic, copy, nullable) NSString *coreDataMeaning;
@end

@interface UDSQLForeignKey : NSObject
@property (nonatomic, copy) NSArray<NSString *> *columns;
@property (nonatomic, copy) NSString *referencedTable;
@property (nonatomic, copy) NSArray<NSString *> *referencedColumns;
@end

@interface UDSQLIndex : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSArray<NSString *> *columns;
@property (nonatomic) BOOL unique;
@end

@interface UDSQLTable : NSObject
@property (nonatomic, copy) NSString *name;
/// Its schema (PostgreSQL's), nil where there is one only.
@property (nonatomic, copy, nullable) NSString *schema;
@property (nonatomic) BOOL view;
@property (nonatomic, copy) NSArray<UDSQLColumnInfo *> *columns;
@property (nonatomic, copy) NSArray<UDSQLForeignKey *> *foreignKeys;
@property (nonatomic, copy) NSArray<UDSQLIndex *> *indexes;
/// A Core Data store's: the entities whose rows it holds (the root first).
@property (nonatomic, copy) NSArray<NSString *> *entities;
/// The name to write in SQL: schema-qualified where there are schemas.
- (NSString *)qualifiedNameFor:(UDSQLConnection *)connection;
@end

@interface UDSQLSchema : NSObject

/// @a connection's schema, read (on the connection's thread); nil and
/// @a error when the catalogue can't be read.
+ (nullable instancetype)schemaOfConnection:(UDSQLConnection *)connection error:(NSError *_Nullable *_Nullable)error;

@property (nonatomic, readonly, copy) NSArray<UDSQLTable *> *tables;
- (nullable UDSQLTable *)tableNamed:(NSString *)name;

/// Whether it is a Core Data store, and its metadata (Z_METADATA's plist).
@property (nonatomic, readonly, getter=isCoreDataStore) BOOL coreDataStore;
@property (nonatomic, readonly, copy) NSDictionary *coreDataMetadata;
/// Z_ENT's values: the entity each numbers.
@property (nonatomic, readonly, copy) NSDictionary<NSNumber *, NSString *> *coreDataEntities;

@end

/// A Core Data timestamp (seconds since 2001-01-01, NSDate's reference date)
/// as a date.
FOUNDATION_EXPORT NSDate *UDSQLDateOfCoreDataTimestamp(double seconds);

NS_ASSUME_NONNULL_END
