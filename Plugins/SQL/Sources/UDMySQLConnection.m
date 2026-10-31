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

#if __has_include(<mysql.h>)
#include <mysql.h>
#define UD_HAS_MYSQL 1
#endif

#ifdef UD_HAS_MYSQL
// The client library's functions, as its header declares them (MariaDB
// Connector/C's; libmysqlclient's are the same): found in it once loaded.
#define UDMY(name) __typeof__(&name) name
static struct {
    UDMY(mysql_init);
    UDMY(mysql_real_connect);
    UDMY(mysql_error);
    UDMY(mysql_errno);
    UDMY(mysql_sqlstate);
    UDMY(mysql_close);
    UDMY(mysql_real_query);
    UDMY(mysql_use_result);
    UDMY(mysql_field_count);
    UDMY(mysql_num_fields);
    UDMY(mysql_fetch_field_direct);
    UDMY(mysql_fetch_row);
    UDMY(mysql_fetch_lengths);
    UDMY(mysql_free_result);
    UDMY(mysql_affected_rows);
    UDMY(mysql_real_escape_string);
    UDMY(mysql_set_character_set);
    UDMY(mysql_thread_id);
    UDMY(mysql_get_server_info);
    UDMY(mysql_next_result);
} MY;
#undef UDMY
#endif

static BOOL UDLoadClient(NSError **error) {
#ifndef UD_HAS_MYSQL
    if (error) *error = UDSQLError(0, @"This UDCode was built without MariaDB's or MySQL's header (mysql.h): it can't reach MySQL or MariaDB.", nil);
    return NO;
#else
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
#define UDFIND(name) MY.name = (__typeof__(MY.name))[library function:#name]; if (!MY.name) goto missing;
    UDFIND(mysql_init)
    UDFIND(mysql_real_connect)
    UDFIND(mysql_error)
    UDFIND(mysql_errno)
    UDFIND(mysql_sqlstate)
    UDFIND(mysql_close)
    UDFIND(mysql_real_query)
    UDFIND(mysql_use_result)
    UDFIND(mysql_field_count)
    UDFIND(mysql_num_fields)
    UDFIND(mysql_fetch_field_direct)
    UDFIND(mysql_fetch_row)
    UDFIND(mysql_fetch_lengths)
    UDFIND(mysql_free_result)
    UDFIND(mysql_affected_rows)
    UDFIND(mysql_real_escape_string)
    UDFIND(mysql_set_character_set)
    UDFIND(mysql_thread_id)
    UDFIND(mysql_get_server_info)
    UDFIND(mysql_next_result)
#undef UDFIND
    loaded = YES;
    return YES;
missing:
    if (error) *error = UDSQLError(0, @"The MySQL client library found lacks a function UDCode needs.", nil);
    return NO;
#endif
}

#ifdef UD_HAS_MYSQL

/// The character set of binary columns (BLOB, VARBINARY): theirs are bytes.
static const unsigned int UDBinaryCharset = 63;

/// MySQL's field types by name.
static NSString *UDTypeName(enum enum_field_types type, unsigned int charset) {
    switch (type) {
        case MYSQL_TYPE_DECIMAL: case MYSQL_TYPE_NEWDECIMAL: return @"decimal";
        case MYSQL_TYPE_TINY: return @"tinyint";
        case MYSQL_TYPE_SHORT: return @"smallint";
        case MYSQL_TYPE_LONG: return @"int";
        case MYSQL_TYPE_FLOAT: return @"float";
        case MYSQL_TYPE_DOUBLE: return @"double";
        case MYSQL_TYPE_TIMESTAMP: return @"timestamp";
        case MYSQL_TYPE_LONGLONG: return @"bigint";
        case MYSQL_TYPE_INT24: return @"mediumint";
        case MYSQL_TYPE_DATE: return @"date";
        case MYSQL_TYPE_TIME: return @"time";
        case MYSQL_TYPE_DATETIME: return @"datetime";
        case MYSQL_TYPE_YEAR: return @"year";
        case MYSQL_TYPE_BIT: return @"bit";
        case MYSQL_TYPE_JSON: return @"json";
        case MYSQL_TYPE_ENUM: return @"enum";
        case MYSQL_TYPE_SET: return @"set";
        case MYSQL_TYPE_TINY_BLOB: case MYSQL_TYPE_MEDIUM_BLOB: case MYSQL_TYPE_LONG_BLOB: case MYSQL_TYPE_BLOB: return charset == UDBinaryCharset ? @"blob" : @"text";
        case MYSQL_TYPE_VARCHAR: case MYSQL_TYPE_VAR_STRING: return charset == UDBinaryCharset ? @"varbinary" : @"varchar";
        case MYSQL_TYPE_STRING: return charset == UDBinaryCharset ? @"binary" : @"char";
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
    MYSQL *connection = MY.mysql_init(NULL);
    if (!connection) {
        if (error) *error = UDSQLError(0, @"The MySQL client library couldn't start a connection.", nil);
        return NULL;
    }
    if (!MY.mysql_real_connect(connection, host.UTF8String, user.UTF8String, password.UTF8String, database.length ? database.UTF8String : NULL,
                         port, socket.length ? socket.UTF8String : NULL, 0)) {
        if (error) *error = UDSQLError(MY.mysql_errno(connection), @(MY.mysql_error(connection)), @(MY.mysql_sqlstate(connection)));
        MY.mysql_close(connection);
        return NULL;
    }
    MY.mysql_set_character_set(connection, "utf8mb4");
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
    made->_threadId = MY.mysql_thread_id(connection);
    NSString *server = @(MY.mysql_get_server_info(connection) ?: "");
    made.serverDescription = [server rangeOfString:@"MariaDB"].location != NSNotFound
        ? [NSString stringWithFormat:@"MariaDB %@", [server componentsSeparatedByString:@"-"].firstObject]
        : [NSString stringWithFormat:@"MySQL %@", server];
    return made;
}

- (void)dealloc {
    [self close];
}

- (void)close {
    if (_connection) MY.mysql_close(_connection);
    _connection = NULL;
}

- (void)cancel {
    // the statement this connection runs, killed from another
    MYSQL *killer = UDConnect(_host, _user, _password, nil, _port, _socket, NULL);
    if (!killer) return;
    NSString *kill = [NSString stringWithFormat:@"KILL QUERY %lu", _threadId];
    MY.mysql_real_query(killer, kill.UTF8String, (unsigned long)strlen(kill.UTF8String));
    MY.mysql_close(killer);
}

- (NSString *)quotedIdentifier:(NSString *)name {
    return [NSString stringWithFormat:@"`%@`", [name stringByReplacingOccurrencesOfString:@"`" withString:@"``"]];
}

- (NSError *)_error {
    return UDSQLError(MY.mysql_errno(_connection), @(MY.mysql_error(_connection)), @(MY.mysql_sqlstate(_connection)));
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
    MY.mysql_real_escape_string(_connection, escaped, text, length);
    NSString *literal = [NSString stringWithFormat:@"'%s'", escaped];
    free(escaped);
    return literal;
}

static id UDValue(const char *bytes, unsigned long length, MYSQL_FIELD *field) {
    if (!bytes) return [NSNull null];
    BOOL binary = field->charsetnr == UDBinaryCharset &&
                  (field->type == MYSQL_TYPE_TINY_BLOB || field->type == MYSQL_TYPE_MEDIUM_BLOB || field->type == MYSQL_TYPE_LONG_BLOB ||
                   field->type == MYSQL_TYPE_BLOB || field->type == MYSQL_TYPE_VARCHAR || field->type == MYSQL_TYPE_VAR_STRING ||
                   field->type == MYSQL_TYPE_STRING);
    if (binary) return [NSData dataWithBytes:bytes length:length];
    switch (field->type) {
        case MYSQL_TYPE_TINY: case MYSQL_TYPE_SHORT: case MYSQL_TYPE_LONG: case MYSQL_TYPE_LONGLONG: case MYSQL_TYPE_INT24: case MYSQL_TYPE_YEAR: return @(strtoll(bytes, NULL, 10));
        case MYSQL_TYPE_FLOAT: case MYSQL_TYPE_DOUBLE: return @(strtod(bytes, NULL));
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
    if (MY.mysql_real_query(_connection, text, (unsigned long)strlen(text)) != 0) {
        if (error) *error = [self _error];
        return nil;
    }
    UDSQLResult *made = [[UDSQLResult alloc] init];
    made.statement = sql;
    if (MY.mysql_field_count(_connection) == 0) {
        made.rowsAffected = (long long)MY.mysql_affected_rows(_connection);
        made.duration = -start.timeIntervalSinceNow;
        return made;
    }
    MYSQL_RES *result = MY.mysql_use_result(_connection);
    if (!result) {
        if (error) *error = [self _error];
        return nil;
    }
    unsigned int count = MY.mysql_num_fields(result);
    NSMutableArray<UDSQLColumn *> *columns = [NSMutableArray array];
    for (unsigned int i = 0; i < count; i++) {
        MYSQL_FIELD *field = MY.mysql_fetch_field_direct(result, i);
        [columns addObject:[[UDSQLColumn alloc] initWithName:@(field->name ?: "") type:UDTypeName(field->type, field->charsetnr)]];
    }
    NSMutableArray *rows = [NSMutableArray array];
    MYSQL_ROW row;
    while ((row = MY.mysql_fetch_row(result))) {
        if (rows.count >= maxRows) {
            made.truncated = YES;
            [self cancel];          // the rest not read
            break;
        }
        unsigned long *lengths = MY.mysql_fetch_lengths(result);
        NSMutableArray *values = [NSMutableArray arrayWithCapacity:count];
        for (unsigned int i = 0; i < count; i++) [values addObject:UDValue(row[i], lengths[i], MY.mysql_fetch_field_direct(result, i))];
        [rows addObject:values];
    }
    MY.mysql_free_result(result);
    while (MY.mysql_next_result(_connection) == 0) {
        // another result (a procedure's): left unread
        MYSQL_RES *more = MY.mysql_use_result(_connection);
        if (more) MY.mysql_free_result(more);
    }
    made.columns = columns;
    made.rows = rows;
    made.duration = -start.timeIntervalSinceNow;
    return made;
}

@end

#else

@implementation UDMySQLConnection

+ (instancetype)openURL:(NSURL *)url password:(NSString *)password error:(NSError **)error {
    UDLoadClient(error);
    return nil;
}

@end

#endif
