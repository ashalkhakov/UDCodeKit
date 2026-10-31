/*---------------------------------------------------------------------------------------------
 *  UDSQLDrivers.h
 *
 *  The drivers behind UDSQLConnection (private to the extension): SQLite's,
 *  linked; PostgreSQL's over libpq and MySQL's (and MariaDB's) over
 *  libmariadb or libmysqlclient, each library loaded the first time it is
 *  needed (UDSQLLibrary), its functions looked up by name.
 *--------------------------------------------------------------------------------------------*/

#import "UDSQLConnection.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDSQLConnection ()
/// Made by a driver: its URL and dialect set.
- (instancetype)initWithURL:(NSURL *)url dialect:(UDSQLDialect)dialect;
@property (nonatomic, readwrite, copy) NSString *serverDescription;
@end

/// Each driver: a connection to @a url, or nil and @a error.
@interface UDSQLiteConnection : UDSQLConnection
+ (nullable instancetype)openURL:(NSURL *)url password:(nullable NSString *)password error:(NSError **)error;
@end

@interface UDPostgreSQLConnection : UDSQLConnection
+ (nullable instancetype)openURL:(NSURL *)url password:(nullable NSString *)password error:(NSError **)error;
@end

@interface UDMySQLConnection : UDSQLConnection
+ (nullable instancetype)openURL:(NSURL *)url password:(nullable NSString *)password error:(NSError **)error;
@end

/// A shared library loaded once, by the first of @a names found (each a file
/// name the system's loader looks for, or a path), its functions looked up.
@interface UDSQLLibrary : NSObject
/// The library, loaded; nil when none of @a names loads, and why: that it
/// isn't installed, and @a install, how to install it (UDCode doesn't
/// bring the client libraries: their users install them). Cached by @a key.
+ (nullable instancetype)libraryForKey:(NSString *)key names:(NSArray<NSString *> *)names install:(NSString *)install
                                 error:(NSError *_Nullable *_Nullable)error;
/// The function @a name; NULL when the library has none.
- (nullable void *)function:(const char *)name;
@end

NS_ASSUME_NONNULL_END
