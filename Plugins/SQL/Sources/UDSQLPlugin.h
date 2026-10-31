/*---------------------------------------------------------------------------------------------
 *  UDSQLPlugin.h
 *
 *  UDCode's databases, for everyday work with one (not its administration:
 *  for that, the database's own tools): a Databases navigator of the
 *  connections and what each holds, a Core Data store's read as one; a SQL
 *  document run against one (Run Statement ⌘↩, Run All ⇧⌘↩), its
 *  parameters asked for, its results under its text. SQLite, PostgreSQL,
 *  MySQL and MariaDB (UDSQLConnection). The SQL mode itself is
 *  tree-sitter-sql's bundle.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import <UDCodeKit/UDCodeKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface UDSQLPlugin : NSObject <UDExtension>
@end

NS_ASSUME_NONNULL_END
