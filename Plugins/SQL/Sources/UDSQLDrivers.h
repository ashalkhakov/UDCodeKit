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
/// A file name is looked for first in the directory UDCode carries its own
/// copies in (ownDirectory), then where the system keeps it.
@interface UDSQLLibrary : NSObject
/// Where UDCode carries the client libraries, MariaDB's plug-ins in its
/// mariadb/plugin: the app's Frameworks (macOS), the AppImage's usr/lib
/// (Linux), the executable's folder (Windows); nil when there is none (a
/// GNUstep build on Linux, not in an AppImage).
+ (nullable NSString *)ownDirectory;
/// What loading @a names tries, in order: each file name in ownDirectory,
/// then @a names as they are.
+ (NSArray<NSString *> *)candidatesForNames:(NSArray<NSString *> *)names;
/// The library, loaded; nil when none of @a names loads, and why: that it
/// isn't installed, and @a install, how to install it (for a UDCode that
/// doesn't carry it: a developer's own build). Cached by @a key.
+ (nullable instancetype)libraryForKey:(NSString *)key names:(NSArray<NSString *> *)names install:(NSString *)install
                                 error:(NSError *_Nullable *_Nullable)error;
/// What it was loaded by: a path in ownDirectory, or one of the names.
@property (nonatomic, readonly, copy) NSString *path;
/// Whether it is UDCode's own copy (loaded from ownDirectory).
@property (nonatomic, readonly, getter=isOwn) BOOL own;
/// The function @a name; NULL when the library has none.
- (nullable void *)function:(const char *)name;
@end

NS_ASSUME_NONNULL_END
