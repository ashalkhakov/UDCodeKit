/*---------------------------------------------------------------------------------------------
 *  UDSQLiteConnection.m
 *
 *  SQLite's driver: the file opened as it is (never made: a connection
 *  changes nothing), parameters bound by the index SQLite gives them (?, ?N,
 *  :name, @name, $name alike), each value as SQLite stores it.
 *--------------------------------------------------------------------------------------------*/

#import "UDSQLDrivers.h"
#include <sqlite3.h>

@implementation UDSQLiteConnection {
    sqlite3 *_database;
}

+ (instancetype)openURL:(NSURL *)url password:(NSString *)password error:(NSError **)error {
    NSString *path = url.path;
    if (!path.length || ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        if (error) *error = UDSQLError(SQLITE_CANTOPEN, [NSString stringWithFormat:@"There is no database at %@.", path ?: @"?"], nil);
        return nil;
    }
    sqlite3 *database = NULL;
    // UTF-8 on every platform (GNUstep's -fileSystemRepresentation is UTF-16 on Windows)
    int status = sqlite3_open_v2(path.UTF8String, &database, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, NULL);
    if (status != SQLITE_OK) {
        if (error) *error = UDSQLError(status, database ? @(sqlite3_errmsg(database)) : @"SQLite couldn't open the file.", nil);
        if (database) sqlite3_close(database);
        return nil;
    }
    sqlite3_busy_timeout(database, 5000);
    UDSQLiteConnection *connection = [[self alloc] initWithURL:url dialect:UDSQLDialectSQLite];
    connection->_database = database;
    connection.serverDescription = [NSString stringWithFormat:@"SQLite %s", sqlite3_libversion()];
    return connection;
}

- (void)dealloc {
    [self close];
}

- (void)close {
    if (_database) sqlite3_close_v2(_database);
    _database = NULL;
}

- (void)cancel {
    if (_database) sqlite3_interrupt(_database);
}

- (NSError *)_error {
    return UDSQLError(sqlite3_extended_errcode(_database), @(sqlite3_errmsg(_database)), nil);
}

static int UDBind(sqlite3_stmt *statement, int index, id value) {
    if (!value || value == [NSNull null]) return sqlite3_bind_null(statement, index);
    if ([value isKindOfClass:[NSData class]]) {
        return sqlite3_bind_blob64(statement, index, [value bytes], [value length], SQLITE_TRANSIENT);
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        const char *type = [value objCType];
        if (strcmp(type, @encode(double)) == 0 || strcmp(type, @encode(float)) == 0) {
            return sqlite3_bind_double(statement, index, [value doubleValue]);
        }
        return sqlite3_bind_int64(statement, index, [value longLongValue]);
    }
    return sqlite3_bind_text(statement, index, [[value description] UTF8String], -1, SQLITE_TRANSIENT);
}

static id UDValue(sqlite3_stmt *statement, int column) {
    switch (sqlite3_column_type(statement, column)) {
        case SQLITE_INTEGER: return @(sqlite3_column_int64(statement, column));
        case SQLITE_FLOAT: return @(sqlite3_column_double(statement, column));
        case SQLITE_BLOB: return [NSData dataWithBytes:sqlite3_column_blob(statement, column) length:(NSUInteger)sqlite3_column_bytes(statement, column)];
        case SQLITE_NULL: return [NSNull null];
        default: {
            const unsigned char *text = sqlite3_column_text(statement, column);
            return [[NSString alloc] initWithBytes:text length:(NSUInteger)sqlite3_column_bytes(statement, column)
                                          encoding:NSUTF8StringEncoding] ?: @"";
        }
    }
}

- (UDSQLResult *)execute:(NSString *)sql parameters:(NSArray *)parameters maxRows:(NSUInteger)maxRows error:(NSError **)error {
    if (!_database) {
        if (error) *error = UDSQLError(SQLITE_MISUSE, @"The connection is closed.", nil);
        return nil;
    }
    NSDate *start = [NSDate date];
    sqlite3_stmt *statement = NULL;
    if (sqlite3_prepare_v2(_database, sql.UTF8String, -1, &statement, NULL) != SQLITE_OK) {
        if (error) *error = [self _error];
        return nil;
    }
    UDSQLResult *result = [[UDSQLResult alloc] init];
    result.statement = sql;
    if (!statement) return result;              // only a comment, or nothing
    int count = sqlite3_bind_parameter_count(statement);
    for (int index = 1; index <= count; index++) {
        id value = (NSUInteger)index <= parameters.count ? parameters[(NSUInteger)index - 1] : [NSNull null];
        UDBind(statement, index, value);
    }
    int columns = sqlite3_column_count(statement);
    NSMutableArray<UDSQLColumn *> *described = [NSMutableArray array];
    for (int column = 0; column < columns; column++) {
        const char *type = sqlite3_column_decltype(statement, column);
        [described addObject:[[UDSQLColumn alloc] initWithName:@(sqlite3_column_name(statement, column) ?: "")
                                                          type:type ? @(type) : nil]];
    }
    NSMutableArray *rows = [NSMutableArray array];
    int status;
    while ((status = sqlite3_step(statement)) == SQLITE_ROW) {
        if (rows.count >= maxRows) {
            result.truncated = YES;
            break;
        }
        NSMutableArray *row = [NSMutableArray arrayWithCapacity:(NSUInteger)columns];
        for (int column = 0; column < columns; column++) [row addObject:UDValue(statement, column)];
        [rows addObject:row];
    }
    if (status != SQLITE_ROW && status != SQLITE_DONE) {
        if (error) *error = [self _error];
        sqlite3_finalize(statement);
        return nil;
    }
    sqlite3_finalize(statement);
    result.columns = described;
    result.rows = rows;
    result.rowsAffected = columns == 0 ? sqlite3_changes(_database) : -1;
    result.duration = -start.timeIntervalSinceNow;
    return result;
}

@end
