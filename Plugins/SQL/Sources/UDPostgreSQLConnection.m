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

// libpq's, as its libpq-fe.h declares them: the library is loaded, not linked
typedef struct pg_conn PGconn;
typedef struct pg_result PGresult;
typedef struct pg_cancel PGcancel;
typedef unsigned int UDOid;
enum { UDConnectionOK = 0 };
enum { UDResCommandOK = 1, UDResTuplesOK = 2, UDResSingleTuple = 9 };
enum { UDDiagSQLState = 'C' };

typedef PGconn *(*UDPQconnectdbParams)(const char *const *keywords, const char *const *values, int expand);
typedef int (*UDPQstatus)(const PGconn *);
typedef char *(*UDPQerrorMessage)(const PGconn *);
typedef void (*UDPQfinish)(PGconn *);
typedef int (*UDPQsendQueryParams)(PGconn *, const char *, int, const UDOid *, const char *const *, const int *, const int *, int);
typedef int (*UDPQsetSingleRowMode)(PGconn *);
typedef PGresult *(*UDPQgetResult)(PGconn *);
typedef int (*UDPQresultStatus)(const PGresult *);
typedef char *(*UDPQresultErrorField)(const PGresult *, int);
typedef char *(*UDPQresultErrorMessage)(const PGresult *);
typedef int (*UDPQntuples)(const PGresult *);
typedef int (*UDPQnfields)(const PGresult *);
typedef char *(*UDPQfname)(const PGresult *, int);
typedef UDOid (*UDPQftype)(const PGresult *, int);
typedef char *(*UDPQgetvalue)(const PGresult *, int, int);
typedef int (*UDPQgetisnull)(const PGresult *, int, int);
typedef int (*UDPQgetlength)(const PGresult *, int, int);
typedef char *(*UDPQcmdTuples)(PGresult *);
typedef void (*UDPQclear)(PGresult *);
typedef PGcancel *(*UDPQgetCancel)(PGconn *);
typedef int (*UDPQcancel)(PGcancel *, char *, int);
typedef void (*UDPQfreeCancel)(PGcancel *);
typedef unsigned char *(*UDPQunescapeBytea)(const unsigned char *, size_t *);
typedef void (*UDPQfreemem)(void *);
typedef int (*UDPQserverVersion)(const PGconn *);

static struct {
    UDPQconnectdbParams connectdbParams;
    UDPQstatus status;
    UDPQerrorMessage errorMessage;
    UDPQfinish finish;
    UDPQsendQueryParams sendQueryParams;
    UDPQsetSingleRowMode setSingleRowMode;
    UDPQgetResult getResult;
    UDPQresultStatus resultStatus;
    UDPQresultErrorField resultErrorField;
    UDPQresultErrorMessage resultErrorMessage;
    UDPQntuples ntuples;
    UDPQnfields nfields;
    UDPQfname fname;
    UDPQftype ftype;
    UDPQgetvalue getvalue;
    UDPQgetisnull getisnull;
    UDPQgetlength getlength;
    UDPQcmdTuples cmdTuples;
    UDPQclear clear;
    UDPQgetCancel getCancel;
    UDPQcancel cancel;
    UDPQfreeCancel freeCancel;
    UDPQunescapeBytea unescapeBytea;
    UDPQfreemem freemem;
    UDPQserverVersion serverVersion;
} PQ;

/// libpq, its functions found; NO (and why) when it isn't installed.
static BOOL UDLoadLibPQ(NSError **error) {
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
#define UDFIND(field, name) PQ.field = (__typeof__(PQ.field))[library function:name]; if (!PQ.field) goto missing;
    UDFIND(connectdbParams, "PQconnectdbParams")
    UDFIND(status, "PQstatus")
    UDFIND(errorMessage, "PQerrorMessage")
    UDFIND(finish, "PQfinish")
    UDFIND(sendQueryParams, "PQsendQueryParams")
    UDFIND(setSingleRowMode, "PQsetSingleRowMode")
    UDFIND(getResult, "PQgetResult")
    UDFIND(resultStatus, "PQresultStatus")
    UDFIND(resultErrorField, "PQresultErrorField")
    UDFIND(resultErrorMessage, "PQresultErrorMessage")
    UDFIND(ntuples, "PQntuples")
    UDFIND(nfields, "PQnfields")
    UDFIND(fname, "PQfname")
    UDFIND(ftype, "PQftype")
    UDFIND(getvalue, "PQgetvalue")
    UDFIND(getisnull, "PQgetisnull")
    UDFIND(getlength, "PQgetlength")
    UDFIND(cmdTuples, "PQcmdTuples")
    UDFIND(clear, "PQclear")
    UDFIND(getCancel, "PQgetCancel")
    UDFIND(cancel, "PQcancel")
    UDFIND(freeCancel, "PQfreeCancel")
    UDFIND(unescapeBytea, "PQunescapeBytea")
    UDFIND(freemem, "PQfreemem")
    UDFIND(serverVersion, "PQserverVersion")
#undef UDFIND
    loaded = YES;
    return YES;
missing:
    if (error) *error = UDSQLError(0, @"The libpq found is too old (it lacks PQsetSingleRowMode or another function).", nil);
    return NO;
}

/// A few of PostgreSQL's built-in types by their OID: the names a column shows.
static NSString *UDTypeName(UDOid oid) {
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
    PGconn *connection = PQ.connectdbParams(keywords, values, 1);
    if (!connection || PQ.status(connection) != UDConnectionOK) {
        NSString *message = connection ? @(PQ.errorMessage(connection)) : @"libpq couldn't make a connection.";
        if (error) *error = UDSQLError(0, [message stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]], nil);
        if (connection) PQ.finish(connection);
        return nil;
    }
    UDPostgreSQLConnection *made = [[self alloc] initWithURL:url dialect:UDSQLDialectPostgreSQL];
    made->_connection = connection;
    made->_canceller = PQ.getCancel(connection);
    int version = PQ.serverVersion(connection);
    made.serverDescription = [NSString stringWithFormat:@"PostgreSQL %d.%d", version / 10000, version % 10000];
    return made;
}

- (void)dealloc {
    [self close];
}

- (void)close {
    @synchronized (self) {
        if (_canceller) PQ.freeCancel(_canceller);
        _canceller = NULL;
    }
    if (_connection) PQ.finish(_connection);
    _connection = NULL;
}

- (void)cancel {
    @synchronized (self) {
        char reason[256];
        if (_canceller) PQ.cancel(_canceller, reason, sizeof reason);
    }
}

- (NSError *)_errorOfResult:(PGresult *)result {
    NSString *message = @(result ? PQ.resultErrorMessage(result) : PQ.errorMessage(_connection));
    char *state = result ? PQ.resultErrorField(result, UDDiagSQLState) : NULL;
    return UDSQLError(0, [message stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]],
                      state ? @(state) : nil);
}

/// A value as text (libpq's text format) as what it is: numbers as numbers,
/// booleans as YES/NO, bytea as its bytes.
static id UDValue(PGresult *result, int row, int column, UDOid type) {
    if (PQ.getisnull(result, row, column)) return [NSNull null];
    char *text = PQ.getvalue(result, row, column);
    switch (type) {
        case 20: case 21: case 23: case 26: return @(strtoll(text, NULL, 10));
        case 700: case 701: return @(strtod(text, NULL));
        case 16: return @(text[0] == 't');
        case 17: {
            size_t length = 0;
            unsigned char *bytes = PQ.unescapeBytea((const unsigned char *)text, &length);
            NSData *data = [NSData dataWithBytes:bytes length:length];
            PQ.freemem(bytes);
            return data;
        }
        default:
            return [[NSString alloc] initWithBytes:text length:(NSUInteger)PQ.getlength(result, row, column)
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
    int sent = PQ.sendQueryParams(_connection, sql.UTF8String, count, NULL, values, NULL, NULL, 0);
    free(values);
    if (!sent) {
        if (error) *error = [self _errorOfResult:NULL];
        return nil;
    }
    PQ.setSingleRowMode(_connection);
    UDSQLResult *made = [[UDSQLResult alloc] init];
    made.statement = sql;
    NSMutableArray *rows = [NSMutableArray array];
    NSMutableArray<UDSQLColumn *> *columns = nil;
    NSMutableArray *types = [NSMutableArray array];
    NSError *failure = nil;
    BOOL stopped = NO;
    PGresult *result;
    while ((result = PQ.getResult(_connection))) {
        int status = PQ.resultStatus(result);
        if (status == UDResSingleTuple || status == UDResTuplesOK) {
            if (!columns) {
                columns = [NSMutableArray array];
                for (int column = 0; column < PQ.nfields(result); column++) {
                    UDOid type = PQ.ftype(result, column);
                    [columns addObject:[[UDSQLColumn alloc] initWithName:@(PQ.fname(result, column)) type:UDTypeName(type)]];
                    [types addObject:@(type)];
                }
            }
            for (int row = 0; row < PQ.ntuples(result); row++) {
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
        } else if (status == UDResCommandOK) {
            char *affected = PQ.cmdTuples(result);
            made.rowsAffected = affected && affected[0] ? strtoll(affected, NULL, 10) : -1;
        } else if (!stopped && !failure) {
            failure = [self _errorOfResult:result];
        }
        PQ.clear(result);
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
