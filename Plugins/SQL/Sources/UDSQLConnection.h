/*---------------------------------------------------------------------------------------------
 *  UDSQLConnection.h
 *
 *  A connection to a database, as everyday work needs one (not a database's
 *  administration): opened from a URL — file:///…/store.sqlite, postgresql://
 *  (postgres://), mysql:// (mariadb://) — with nothing changed on the server;
 *  a statement run with its parameters, its result's columns (names, types)
 *  and its first rows; a statement stopped from another thread; errors with
 *  the server's code (SQLSTATE where it has one).
 *
 *  SQLite is linked. libpq and libmariadb (or libmysqlclient) are built
 *  against, their own headers declaring what is used, and loaded the first
 *  time a connection needs them (UDSQLLibrary), so neither is needed to run
 *  UDCode without such a database. Built without a header, that driver says
 *  so instead.
 *
 *  A connection is used from one thread at a time (UDSQLRunner's); only
 *  -cancel may be sent from another.
 *--------------------------------------------------------------------------------------------*/

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// The databases spoken; what differs between them stays in their drivers.
typedef NS_ENUM(NSInteger, UDSQLDialect) {
    UDSQLDialectSQLite,
    UDSQLDialectPostgreSQL,
    UDSQLDialectMySQL,          // MySQL and MariaDB
};

FOUNDATION_EXPORT NSErrorDomain const UDSQLErrorDomain;
/// The error's SQLSTATE (NSString), when the database gives one.
FOUNDATION_EXPORT NSString *const UDSQLStateErrorKey;

/// A result's column: its name and, when the database says, its type.
@interface UDSQLColumn : NSObject
- (instancetype)initWithName:(NSString *)name type:(nullable NSString *)type;
@property (nonatomic, readonly, copy) NSString *name;
/// The type the database declares ("INTEGER", "timestamp with time zone");
/// nil when it doesn't say.
@property (nonatomic, readonly, copy, nullable) NSString *type;
@end

/// What a statement gave: its columns and rows (each value an NSString,
/// NSNumber, NSData or NSNull), or the rows it changed.
@interface UDSQLResult : NSObject
@property (nonatomic, copy) NSString *statement;
@property (nonatomic, copy) NSArray<UDSQLColumn *> *columns;
@property (nonatomic, copy) NSArray<NSArray *> *rows;
/// Rows changed (INSERT, UPDATE, DELETE); -1 when the statement says none.
@property (nonatomic) long long rowsAffected;
/// Whether there were more rows than were kept (the runner's maximum).
@property (nonatomic) BOOL truncated;
@property (nonatomic) NSTimeInterval duration;
@end

@interface UDSQLConnection : NSObject

/// The schemes connections are made for: file (SQLite), postgresql,
/// postgres, mysql, mariadb.
+ (NSArray<NSString *> *)schemes;
/// @a url's dialect; -1 when no driver speaks it.
+ (NSInteger)dialectOfURL:(NSURL *)url;

/// A connection to @a url, @a password given apart from it (a URL's own,
/// when nil); nil, and why in @a error, when it can't be made.
+ (nullable instancetype)connectionToURL:(NSURL *)url password:(nullable NSString *)password
                                   error:(NSError *_Nullable *_Nullable)error;

@property (nonatomic, readonly, copy) NSURL *URL;
@property (nonatomic, readonly) UDSQLDialect dialect;
/// What the server says it is ("PostgreSQL 16.2", "SQLite 3.45.1").
@property (nonatomic, readonly, copy) NSString *serverDescription;

/// Runs @a sql (one statement, its placeholders in the dialect's own style:
/// UDSQLText converts them) with @a parameters (NSString, NSNumber, NSData,
/// NSNull), keeping its first @a maxRows rows.
- (nullable UDSQLResult *)execute:(NSString *)sql parameters:(NSArray *)parameters maxRows:(NSUInteger)maxRows
                            error:(NSError *_Nullable *_Nullable)error;

/// Stops the statement running (from any thread); it fails with an error.
- (void)cancel;
- (void)close;

/// @a name quoted as an identifier ("x", `x`).
- (NSString *)quotedIdentifier:(NSString *)name;

@end

/// An error of the domain: @a message, the database's @a code and @a state.
FOUNDATION_EXPORT NSError *UDSQLError(NSInteger code, NSString *message, NSString *_Nullable state);

NS_ASSUME_NONNULL_END
