/*---------------------------------------------------------------------------------------------
 *  UDSQLText.h
 *
 *  SQL as text, read as far as running it needs and no further: its strings,
 *  quoted identifiers, comments and PostgreSQL's dollar quoting told apart
 *  from its code, so that a script splits at the semicolons between its
 *  statements, the statement at the caret is found, and a statement's
 *  parameters — ?, ?N, $N, :name, @name (not in MySQL, whose @x is a user
 *  variable) — are found and written as each driver takes them: $1, $2… for
 *  PostgreSQL, ? for SQLite and MySQL.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>
#import "UDSQLConnection.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDSQLText : NSObject

/// The statements of @a text, each its range (without the semicolon and the
/// space around it), empty ones left out.
+ (NSArray<NSValue *> *)statementRangesOfText:(NSString *)text dialect:(UDSQLDialect)dialect;

/// The statement holding character @a index (the caret), or the one ending
/// on its line before it; NSNotFound when there is none.
+ (NSRange)statementRangeAtIndex:(NSUInteger)index ofText:(NSString *)text dialect:(UDSQLDialect)dialect;

/// @a statement's parameters, each named as written ("?1", "?2" for plain
/// ?s, by their place; "$1"; ":name"), in their first appearance's order,
/// each once.
+ (NSArray<NSString *> *)parametersOfStatement:(NSString *)statement dialect:(UDSQLDialect)dialect;

/// @a statement with its parameters as @a dialect's driver takes them, and
/// in @a order the parameter names (of -parametersOfStatement:'s) to bind,
/// one for each placeholder written.
+ (NSString *)statement:(NSString *)statement convertedForDialect:(UDSQLDialect)dialect
                  order:(NSArray<NSString *> *_Nullable *_Nullable)order;

/// @a statement with its ?s (outside strings and comments) replaced by
/// @a literals, in turn: the MySQL driver's parameters.
+ (NSString *)statement:(NSString *)statement withParametersReplacedBy:(NSArray<NSString *> *)literals
                dialect:(UDSQLDialect)dialect;

@end

NS_ASSUME_NONNULL_END
