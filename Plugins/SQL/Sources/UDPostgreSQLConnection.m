/*---------------------------------------------------------------------------------------------
 *  UDPostgreSQLConnection.m
 *
 *  PostgreSQL's driver, over libpq loaded when first needed: the URL handed
 *  to libpq as it is (postgresql://user@host:port/db?sslmode=…, libpq's
 *  own), the password apart; parameters as $1, $2…; the result read a row
 *  at a time (single-row mode), so only the rows kept are fetched; a
 *  statement stopped by libpq's cancel request; errors with their SQLSTATE.
 *--------------------------------------------------------------------------------------------*/

#import "UDSQLDrivers.h"

#if __has_include(<libpq-fe.h>)
#include <libpq-fe.h>
#define UD_HAS_LIBPQ 1
#endif

#ifdef UD_HAS_LIBPQ
// libpq's functions, as its header declares them: found in the library once
// it is loaded (it is not linked: a machine without it still runs UDCode)
#define UDPQ(name) __typeof__(&name) name
static struct {
    UDPQ(PQconnectdbParams);
    UDPQ(PQstatus);
    UDPQ(PQerrorMessage);
    UDPQ(PQfinish);
    UDPQ(PQsendQueryParams);
    UDPQ(PQsetSingleRowMode);
    UDPQ(PQgetResult);
    UDPQ(PQresultStatus);
    UDPQ(PQresultErrorField);
    UDPQ(PQresultErrorMessage);
    UDPQ(PQntuples);
    UDPQ(PQnfields);
    UDPQ(PQfname);
    UDPQ(PQftype);
    UDPQ(PQgetvalue);
    UDPQ(PQgetisnull);
    UDPQ(PQgetlength);
    UDPQ(PQcmdTuples);
    UDPQ(PQclear);
    UDPQ(PQgetCancel);
    UDPQ(PQcancel);
    UDPQ(PQfreeCancel);
    UDPQ(PQunescapeBytea);
    UDPQ(PQfreemem);
    UDPQ(PQserverVersion);
} PQ;
#undef UDPQ
#endif

/// libpq, its functions found; NO (and why) when it isn't installed, or
/// UDCode was built without its header.
static BOOL UDLoadLibPQ(NSError **error) {
#ifndef UD_HAS_LIBPQ
    if (error) *error = UDSQLError(0, @"This UDCode was built without libpq's header (libpq-fe.h): it can't reach PostgreSQL.", nil);
    return NO;
#else
    static BOOL loaded;
    if (loaded) return YES;
    NSArray *names = @[
#if defined(__APPLE__)
        @"libpq.5.dylib", @"/opt/homebrew/opt/libpq/lib/libpq.5.dylib", @"/usr/local/opt/libpq/lib/libpq.5.dylib",
        @"/opt/homebrew/lib/libpq.5.dylib", @"/Applications/Postgres.app/Contents/Versions/latest/lib/libpq.5.dylib",
#elif defined(_WIN32)
        @"libpq.dll",
#else
        @"libpq.so.5", @"libpq.so",
#endif
    ];
    UDSQLLibrary *library = [UDSQLLibrary libraryForKey:@"libpq (PostgreSQL's client library)" names:names error:error];
    if (!library) return NO;
#define UDFIND(name) PQ.name = (__typeof__(PQ.name))[library function:#name]; if (!PQ.name) goto missing;
    UDFIND(PQconnectdbParams)
    UDFIND(PQstatus)
    UDFIND(PQerrorMessage)
    UDFIND(PQfinish)
    UDFIND(PQsendQueryParams)
    UDFIND(PQsetSingleRowMode)
    UDFIND(PQgetResult)
    UDFIND(PQresultStatus)
    UDFIND(PQresultErrorField)
    UDFIND(PQresultErrorMessage)
    UDFIND(PQntuples)
    UDFIND(PQnfields)
    UDFIND(PQfname)
    UDFIND(PQftype)
    UDFIND(PQgetvalue)
    UDFIND(PQgetisnull)
    UDFIND(PQgetlength)
    UDFIND(PQcmdTuples)
    UDFIND(PQclear)
    UDFIND(PQgetCancel)
    UDFIND(PQcancel)
    UDFIND(PQfreeCancel)
    UDFIND(PQunescapeBytea)
    UDFIND(PQfreemem)
    UDFIND(PQserverVersion)
#undef UDFIND
    loaded = YES;
    return YES;
missing:
    if (error) *error = UDSQLError(0, @"The libpq found is too old (it lacks PQsetSingleRowMode or another function).", nil);
    return NO;
#endif
}

#ifdef UD_HAS_LIBPQ

/// A few of PostgreSQL's built-in types by their OID: the names a column shows.
static NSString *UDTypeName(Oid oid) {
    switch (oid) {
        case 16: return @"boolean";
        case 17: return @"bytea";
        case 18: return @"char";
        case 19: return @"name";
        case 20: return @"bigint";
        case 21: return @"smallint";
        case 23: return @"integer";
        case 25: return @"text";
        case 26: return @"oid";
        case 114: return @"json";
        case 700: return @"real";
        case 701: return @"double precision";
        case 1042: return @"character";
        case 1043: return @"character varying";
        case 1082: return @"date";
        case 1083: return @"time";
        case 1114: return @"timestamp";
        case 1184: return @"timestamp with time zone";
        case 1186: return @"interval";
        case 1700: return @"numeric";
        case 2950: return @"uuid";
        case 3802: return @"jsonb";
        default: return nil;
    }
}

@implementation UDPostgreSQLConnection {
    PGconn *_connection;
    PGcancel *_canceller;
}

+ (instancetype)openURL:(NSURL *)url password:(NSString *)password error:(NSError **)error {
    if (!UDLoadLibPQ(error)) return nil;
    // the URL as libpq takes it (expand_dbname), the password beside it
    const char *keywords[] = { "dbname", password.length ? "password" : NULL, NULL };
    const char *values[] = { url.absoluteString.UTF8String, password.length ? password.UTF8String : NULL, NULL };
    PGconn *connection = PQ.PQconnectdbParams(keywords, values, 1);
    if (!connection || PQ.PQstatus(connection) != CONNECTION_OK) {
        NSString *message = connection ? @(PQ.PQerrorMessage(connection)) : @"libpq couldn't make a connection.";
        if (error) *error = UDSQLError(0, [message stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]], nil);
        if (connection) PQ.PQfinish(connection);
        return nil;
    }
    UDPostgreSQLConnection *made = [[self alloc] initWithURL:url dialect:UDSQLDialectPostgreSQL];
    made->_connection = connection;
    made->_canceller = PQ.PQgetCancel(connection);
    int version = PQ.PQserverVersion(connection);
    made.serverDescription = [NSString stringWithFormat:@"PostgreSQL %d.%d", version / 10000, version % 10000];
    return made;
}

- (void)dealloc {
    [self close];
}

- (void)close {
    @synchronized (self) {
        if (_canceller) PQ.PQfreeCancel(_canceller);
        _canceller = NULL;
    }
    if (_connection) PQ.PQfinish(_connection);
    _connection = NULL;
}

- (void)cancel {
    @synchronized (self) {
        char reason[256];
        if (_canceller) PQ.PQcancel(_canceller, reason, sizeof reason);
    }
}

- (NSError *)_errorOfResult:(PGresult *)result {
    NSString *message = @(result ? PQ.PQresultErrorMessage(result) : PQ.PQerrorMessage(_connection));
    char *state = result ? PQ.PQresultErrorField(result, PG_DIAG_SQLSTATE) : NULL;
    return UDSQLError(0, [message stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]],
                      state ? @(state) : nil);
}

/// A value as text (libpq's text format) as what it is: numbers as numbers,
/// booleans as YES/NO, bytea as its bytes.
static id UDValue(PGresult *result, int row, int column, Oid type) {
    if (PQ.PQgetisnull(result, row, column)) return [NSNull null];
    char *text = PQ.PQgetvalue(result, row, column);
    switch (type) {
        case 20: case 21: case 23: case 26: return @(strtoll(text, NULL, 10));
        case 700: case 701: return @(strtod(text, NULL));
        case 16: return @(text[0] == 't');
        case 17: {
            size_t length = 0;
            unsigned char *bytes = PQ.PQunescapeBytea((const unsigned char *)text, &length);
            NSData *data = [NSData dataWithBytes:bytes length:length];
            PQ.PQfreemem(bytes);
            return data;
        }
        default:
            return [[NSString alloc] initWithBytes:text length:(NSUInteger)PQ.PQgetlength(result, row, column)
                                          encoding:NSUTF8StringEncoding] ?: @"";
    }
}

static NSString *UDTextOfParameter(id value) {
    if (!value || value == [NSNull null]) return nil;
    if ([value isKindOfClass:[NSData class]]) {
        // bytea's hex input
        NSMutableString *hex = [NSMutableString stringWithString:@"\\x"];
        const unsigned char *bytes = [value bytes];
        for (NSUInteger i = 0; i < [value length]; i++) [hex appendFormat:@"%02x", bytes[i]];
        return hex;
    }
    return [value description];
}

- (UDSQLResult *)execute:(NSString *)sql parameters:(NSArray *)parameters maxRows:(NSUInteger)maxRows error:(NSError **)error {
    if (!_connection) {
        if (error) *error = UDSQLError(0, @"The connection is closed.", nil);
        return nil;
    }
    NSDate *start = [NSDate date];
    int count = (int)parameters.count;
    NSMutableArray *texts = [NSMutableArray array];        // kept while libpq reads them
    const char **values = count ? calloc((size_t)count, sizeof(char *)) : NULL;
    for (int i = 0; i < count; i++) {
        NSString *text = UDTextOfParameter(parameters[(NSUInteger)i]);
        if (text) [texts addObject:text];
        values[i] = text ? text.UTF8String : NULL;
    }
    int sent = PQ.PQsendQueryParams(_connection, sql.UTF8String, count, NULL, values, NULL, NULL, 0);
    free(values);
    if (!sent) {
        if (error) *error = [self _errorOfResult:NULL];
        return nil;
    }
    PQ.PQsetSingleRowMode(_connection);
    UDSQLResult *made = [[UDSQLResult alloc] init];
    made.statement = sql;
    NSMutableArray *rows = [NSMutableArray array];
    NSMutableArray<UDSQLColumn *> *columns = nil;
    NSMutableArray *types = [NSMutableArray array];
    NSError *failure = nil;
    BOOL stopped = NO;
    PGresult *result;
    while ((result = PQ.PQgetResult(_connection))) {
        int status = PQ.PQresultStatus(result);
        if (status == PGRES_SINGLE_TUPLE || status == PGRES_TUPLES_OK) {
            if (!columns) {
                columns = [NSMutableArray array];
                for (int column = 0; column < PQ.PQnfields(result); column++) {
                    Oid type = PQ.PQftype(result, column);
                    [columns addObject:[[UDSQLColumn alloc] initWithName:@(PQ.PQfname(result, column)) type:UDTypeName(type)]];
                    [types addObject:@(type)];
                }
            }
            for (int row = 0; row < PQ.PQntuples(result); row++) {
                if (rows.count >= maxRows) {
                    if (!stopped) {
                        // enough: the rest not fetched
                        made.truncated = YES;
                        stopped = YES;
                        [self cancel];
                    }
                    break;
                }
                NSMutableArray *values = [NSMutableArray arrayWithCapacity:columns.count];
                for (int column = 0; column < (int)columns.count; column++) {
                    [values addObject:UDValue(result, row, column, [types[(NSUInteger)column] unsignedIntValue])];
                }
                [rows addObject:values];
            }
        } else if (status == PGRES_COMMAND_OK) {
            char *affected = PQ.PQcmdTuples(result);
            made.rowsAffected = affected && affected[0] ? strtoll(affected, NULL, 10) : -1;
        } else if (!stopped && !failure) {
            failure = [self _errorOfResult:result];
        }
        PQ.PQclear(result);
    }
    if (failure) {
        if (error) *error = failure;
        return nil;
    }
    made.columns = columns ?: @[];
    made.rows = rows;
    made.duration = -start.timeIntervalSinceNow;
    return made;
}

@end

#else

@implementation UDPostgreSQLConnection

+ (instancetype)openURL:(NSURL *)url password:(NSString *)password error:(NSError **)error {
    UDLoadLibPQ(error);
    return nil;
}

@end

#endif
