/*---------------------------------------------------------------------------------------------
 *  UDMySQLConnection.m
 *
 *  MySQL's and MariaDB's driver, over libmariadb (or libmysqlclient) loaded
 *  when first needed: mysql://user@host:port/database (mariadb:// too; a
 *  ?socket= of its own), nothing set on the server but the connection's
 *  character set (utf8mb4); "localhost" the client library's own (its
 *  socket). Parameters (?) are the text protocol's: each written into the
 *  statement as an escaped literal, outside strings, identifiers and
 *  comments. The result is streamed, so only the rows kept are read; a
 *  statement is stopped, and a long result cut short, by KILL QUERY from a
 *  second connection.
 *--------------------------------------------------------------------------------------------*/

#import "UDSQLDrivers.h"
#import "UDSQLText.h"

// The client library's, as mysql.h declares them: loaded, not linked.
typedef struct st_mysql MYSQL;
typedef struct st_mysql_res MYSQL_RES;
typedef char **MYSQL_ROW;

/// MYSQL_FIELD's start, as libmariadb 3 and libmysqlclient 5.7–8 lay it out.
typedef struct {
    char *name, *org_name, *table, *org_table, *db, *catalog, *def;
    unsigned long length, max_length;
    unsigned int name_length, org_name_length, table_length, org_table_length, db_length, catalog_length, def_length;
    unsigned int flags, decimals, charsetnr;
    int type;
} UDMySQLField;

typedef MYSQL *(*UDmysql_init)(MYSQL *);
typedef MYSQL *(*UDmysql_real_connect)(MYSQL *, const char *, const char *, const char *, const char *, unsigned int, const char *, unsigned long);
typedef const char *(*UDmysql_error)(MYSQL *);
typedef unsigned int (*UDmysql_errno)(MYSQL *);
typedef const char *(*UDmysql_sqlstate)(MYSQL *);
typedef void (*UDmysql_close)(MYSQL *);
typedef int (*UDmysql_real_query)(MYSQL *, const char *, unsigned long);
typedef MYSQL_RES *(*UDmysql_use_result)(MYSQL *);
typedef unsigned int (*UDmysql_field_count)(MYSQL *);
typedef unsigned int (*UDmysql_num_fields)(MYSQL_RES *);
typedef UDMySQLField *(*UDmysql_fetch_field_direct)(MYSQL_RES *, unsigned int);
typedef MYSQL_ROW (*UDmysql_fetch_row)(MYSQL_RES *);
typedef unsigned long *(*UDmysql_fetch_lengths)(MYSQL_RES *);
typedef void (*UDmysql_free_result)(MYSQL_RES *);
typedef unsigned long long (*UDmysql_affected_rows)(MYSQL *);
typedef unsigned long (*UDmysql_real_escape_string)(MYSQL *, char *, const char *, unsigned long);
typedef int (*UDmysql_set_character_set)(MYSQL *, const char *);
typedef unsigned long (*UDmysql_thread_id)(MYSQL *);
typedef const char *(*UDmysql_get_server_info)(MYSQL *);
typedef int (*UDmysql_next_result)(MYSQL *);

static struct {
    UDmysql_init init;
    UDmysql_real_connect real_connect;
    UDmysql_error error;
    UDmysql_errno errnum;
    UDmysql_sqlstate sqlstate;
    UDmysql_close close;
    UDmysql_real_query real_query;
    UDmysql_use_result use_result;
    UDmysql_field_count field_count;
    UDmysql_num_fields num_fields;
    UDmysql_fetch_field_direct fetch_field_direct;
    UDmysql_fetch_row fetch_row;
    UDmysql_fetch_lengths fetch_lengths;
    UDmysql_free_result free_result;
    UDmysql_affected_rows affected_rows;
    UDmysql_real_escape_string real_escape_string;
    UDmysql_set_character_set set_character_set;
    UDmysql_thread_id thread_id;
    UDmysql_get_server_info get_server_info;
    UDmysql_next_result next_result;
} MY;

static BOOL UDLoadClient(NSError **error) {
    static BOOL loaded;
    if (loaded) return YES;
    NSArray *names = @[
#if defined(__APPLE__)
        @"libmariadb.3.dylib", @"/opt/homebrew/opt/mariadb-connector-c/lib/mariadb/libmariadb.3.dylib",
        @"/usr/local/opt/mariadb-connector-c/lib/mariadb/libmariadb.3.dylib", @"/opt/homebrew/lib/mariadb/libmariadb.3.dylib",
        @"libmysqlclient.dylib", @"/opt/homebrew/opt/mysql-client/lib/libmysqlclient.dylib",
        @"/usr/local/opt/mysql-client/lib/libmysqlclient.dylib", @"/usr/local/mysql/lib/libmysqlclient.dylib",
#elif defined(_WIN32)
        @"libmariadb.dll", @"libmysql.dll",
#else
        @"libmariadb.so.3", @"libmariadb.so", @"libmysqlclient.so.21", @"libmysqlclient.so",
#endif
    ];
    UDSQLLibrary *library = [UDSQLLibrary libraryForKey:@"libmariadb (MariaDB's and MySQL's client library)" names:names error:error];
    if (!library) return NO;
#define UDFIND(field, name) MY.field = (__typeof__(MY.field))[library function:name]; if (!MY.field) goto missing;
    UDFIND(init, "mysql_init")
    UDFIND(real_connect, "mysql_real_connect")
    UDFIND(error, "mysql_error")
    UDFIND(errnum, "mysql_errno")
    UDFIND(sqlstate, "mysql_sqlstate")
    UDFIND(close, "mysql_close")
    UDFIND(real_query, "mysql_real_query")
    UDFIND(use_result, "mysql_use_result")
    UDFIND(field_count, "mysql_field_count")
    UDFIND(num_fields, "mysql_num_fields")
    UDFIND(fetch_field_direct, "mysql_fetch_field_direct")
    UDFIND(fetch_row, "mysql_fetch_row")
    UDFIND(fetch_lengths, "mysql_fetch_lengths")
    UDFIND(free_result, "mysql_free_result")
    UDFIND(affected_rows, "mysql_affected_rows")
    UDFIND(real_escape_string, "mysql_real_escape_string")
    UDFIND(set_character_set, "mysql_set_character_set")
    UDFIND(thread_id, "mysql_thread_id")
    UDFIND(get_server_info, "mysql_get_server_info")
    UDFIND(next_result, "mysql_next_result")
#undef UDFIND
    loaded = YES;
    return YES;
missing:
    if (error) *error = UDSQLError(0, @"The MySQL client library found lacks a function UDCode needs.", nil);
    return NO;
}

/// MySQL's field types (mysql_com.h's enum_field_types) by name.
static NSString *UDTypeName(int type, unsigned int charset) {
    switch (type) {
        case 0: case 246: return @"decimal";
        case 1: return @"tinyint";
        case 2: return @"smallint";
        case 3: return @"int";
        case 4: return @"float";
        case 5: return @"double";
        case 7: return @"timestamp";
        case 8: return @"bigint";
        case 9: return @"mediumint";
        case 10: return @"date";
        case 11: return @"time";
        case 12: return @"datetime";
        case 13: return @"year";
        case 16: return @"bit";
        case 245: return @"json";
        case 247: return @"enum";
        case 248: return @"set";
        case 249: case 250: case 251: case 252: return charset == 63 ? @"blob" : @"text";
        case 15: case 253: return charset == 63 ? @"varbinary" : @"varchar";
        case 254: return charset == 63 ? @"binary" : @"char";
        default: return nil;
    }
}

@implementation UDMySQLConnection {
    MYSQL *_connection;
    // for a second connection's KILL QUERY
    NSString *_host, *_user, *_password, *_socket;
    unsigned int _port;
    unsigned long _threadId;
}

/// A connection with what the URL says (nil, and @a error, when none).
static MYSQL *UDConnect(NSString *host, NSString *user, NSString *password, NSString *database, unsigned int port,
                        NSString *socket, NSError **error) {
    MYSQL *connection = MY.init(NULL);
    if (!connection) {
        if (error) *error = UDSQLError(0, @"The MySQL client library couldn't start a connection.", nil);
        return NULL;
    }
    if (!MY.real_connect(connection, host.UTF8String, user.UTF8String, password.UTF8String, database.length ? database.UTF8String : NULL,
                         port, socket.length ? socket.UTF8String : NULL, 0)) {
        if (error) *error = UDSQLError(MY.errnum(connection), @(MY.error(connection)), @(MY.sqlstate(connection)));
        MY.close(connection);
        return NULL;
    }
    MY.set_character_set(connection, "utf8mb4");
    return connection;
}

+ (instancetype)openURL:(NSURL *)url password:(NSString *)password error:(NSError **)error {
    if (!UDLoadClient(error)) return nil;
    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    NSString *socket = nil;
    for (NSURLQueryItem *item in components.queryItems) {
        if ([item.name isEqualToString:@"socket"]) socket = item.value;
    }
    NSString *host = components.host.length ? components.host : @"localhost";
    NSString *user = components.user.stringByRemovingPercentEncoding ?: @"";
    NSString *secret = password ?: components.password.stringByRemovingPercentEncoding ?: @"";
    NSString *database = [components.path stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]];
    unsigned int port = components.port ? components.port.unsignedIntValue : 0;
    MYSQL *connection = UDConnect(host, user, secret, database, port, socket, error);
    if (!connection) return nil;
    UDMySQLConnection *made = [[self alloc] initWithURL:url dialect:UDSQLDialectMySQL];
    made->_connection = connection;
    made->_host = host;
    made->_user = user;
    made->_password = secret;
    made->_socket = socket;
    made->_port = port;
    made->_threadId = MY.thread_id(connection);
    NSString *server = @(MY.get_server_info(connection) ?: "");
    made.serverDescription = [server rangeOfString:@"MariaDB"].location != NSNotFound
        ? [NSString stringWithFormat:@"MariaDB %@", [server componentsSeparatedByString:@"-"].firstObject]
        : [NSString stringWithFormat:@"MySQL %@", server];
    return made;
}

- (void)dealloc {
    [self close];
}

- (void)close {
    if (_connection) MY.close(_connection);
    _connection = NULL;
}

- (void)cancel {
    // the statement this connection runs, killed from another
    MYSQL *killer = UDConnect(_host, _user, _password, nil, _port, _socket, NULL);
    if (!killer) return;
    NSString *kill = [NSString stringWithFormat:@"KILL QUERY %lu", _threadId];
    MY.real_query(killer, kill.UTF8String, (unsigned long)strlen(kill.UTF8String));
    MY.close(killer);
}

- (NSString *)quotedIdentifier:(NSString *)name {
    return [NSString stringWithFormat:@"`%@`", [name stringByReplacingOccurrencesOfString:@"`" withString:@"``"]];
}

- (NSError *)_error {
    return UDSQLError(MY.errnum(_connection), @(MY.error(_connection)), @(MY.sqlstate(_connection)));
}

/// @a value as a literal of the statement.
- (NSString *)_literal:(id)value {
    if (!value || value == [NSNull null]) return @"NULL";
    if ([value isKindOfClass:[NSNumber class]]) return [value stringValue];
    if ([value isKindOfClass:[NSData class]]) {
        NSMutableString *hex = [NSMutableString stringWithString:@"X'"];
        const unsigned char *bytes = [value bytes];
        for (NSUInteger i = 0; i < [value length]; i++) [hex appendFormat:@"%02x", bytes[i]];
        [hex appendString:@"'"];
        return hex;
    }
    const char *text = [[value description] UTF8String];
    unsigned long length = (unsigned long)strlen(text);
    char *escaped = malloc(length * 2 + 1);
    MY.real_escape_string(_connection, escaped, text, length);
    NSString *literal = [NSString stringWithFormat:@"'%s'", escaped];
    free(escaped);
    return literal;
}

static id UDValue(const char *bytes, unsigned long length, UDMySQLField *field) {
    if (!bytes) return [NSNull null];
    BOOL binary = field->charsetnr == 63 && (field->type >= 249 || field->type == 15 || field->type == 253 || field->type == 254);
    if (binary) return [NSData dataWithBytes:bytes length:length];
    switch (field->type) {
        case 1: case 2: case 3: case 8: case 9: case 13: return @(strtoll(bytes, NULL, 10));
        case 4: case 5: return @(strtod(bytes, NULL));
        default: return [[NSString alloc] initWithBytes:bytes length:length encoding:NSUTF8StringEncoding] ?: @"";
    }
}

- (UDSQLResult *)execute:(NSString *)sql parameters:(NSArray *)parameters maxRows:(NSUInteger)maxRows error:(NSError **)error {
    if (!_connection) {
        if (error) *error = UDSQLError(0, @"The connection is closed.", nil);
        return nil;
    }
    NSDate *start = [NSDate date];
    NSMutableArray *literals = [NSMutableArray array];
    for (id value in parameters) [literals addObject:[self _literal:value]];
    NSString *statement = parameters.count ? [UDSQLText statement:sql withParametersReplacedBy:literals dialect:UDSQLDialectMySQL] : sql;
    const char *text = statement.UTF8String;
    if (MY.real_query(_connection, text, (unsigned long)strlen(text)) != 0) {
        if (error) *error = [self _error];
        return nil;
    }
    UDSQLResult *made = [[UDSQLResult alloc] init];
    made.statement = sql;
    if (MY.field_count(_connection) == 0) {
        made.rowsAffected = (long long)MY.affected_rows(_connection);
        made.duration = -start.timeIntervalSinceNow;
        return made;
    }
    MYSQL_RES *result = MY.use_result(_connection);
    if (!result) {
        if (error) *error = [self _error];
        return nil;
    }
    unsigned int count = MY.num_fields(result);
    NSMutableArray<UDSQLColumn *> *columns = [NSMutableArray array];
    for (unsigned int i = 0; i < count; i++) {
        UDMySQLField *field = MY.fetch_field_direct(result, i);
        [columns addObject:[[UDSQLColumn alloc] initWithName:@(field->name ?: "") type:UDTypeName(field->type, field->charsetnr)]];
    }
    NSMutableArray *rows = [NSMutableArray array];
    MYSQL_ROW row;
    while ((row = MY.fetch_row(result))) {
        if (rows.count >= maxRows) {
            made.truncated = YES;
            [self cancel];          // the rest not read
            break;
        }
        unsigned long *lengths = MY.fetch_lengths(result);
        NSMutableArray *values = [NSMutableArray arrayWithCapacity:count];
        for (unsigned int i = 0; i < count; i++) [values addObject:UDValue(row[i], lengths[i], MY.fetch_field_direct(result, i))];
        [rows addObject:values];
    }
    MY.free_result(result);
    while (MY.next_result(_connection) == 0) {
        // another result (a procedure's): left unread
        MYSQL_RES *more = MY.use_result(_connection);
        if (more) MY.free_result(more);
    }
    made.columns = columns;
    made.rows = rows;
    made.duration = -start.timeIntervalSinceNow;
    return made;
}

@end
