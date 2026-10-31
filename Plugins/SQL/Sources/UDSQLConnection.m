/*---------------------------------------------------------------------------------------------
 *  UDSQLConnection.m
 *--------------------------------------------------------------------------------------------*/

#import "UDSQLDrivers.h"
#ifdef _WIN32
#include <windows.h>
#else
#include <dlfcn.h>
#endif

NSErrorDomain const UDSQLErrorDomain = @"UDSQLErrorDomain";
NSString *const UDSQLStateErrorKey = @"UDSQLState";

NSError *UDSQLError(NSInteger code, NSString *message, NSString *state) {
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithObject:message ?: @"The database failed." forKey:NSLocalizedDescriptionKey];
    if (state.length) info[UDSQLStateErrorKey] = state;
    return [NSError errorWithDomain:UDSQLErrorDomain code:code userInfo:info];
}

@implementation UDSQLColumn

- (instancetype)initWithName:(NSString *)name type:(NSString *)type {
    self = [super init];
    if (self) {
        _name = [name copy];
        _type = [type copy];
    }
    return self;
}

@end

@implementation UDSQLResult

- (instancetype)init {
    self = [super init];
    if (self) {
        _statement = @"";
        _columns = @[];
        _rows = @[];
        _rowsAffected = -1;
    }
    return self;
}

@end

@implementation UDSQLConnection

+ (NSArray<NSString *> *)schemes {
    return @[ @"file", @"sqlite", @"postgresql", @"postgres", @"mysql", @"mariadb" ];
}

+ (NSInteger)dialectOfURL:(NSURL *)url {
    NSString *scheme = url.scheme.lowercaseString;
    if ([scheme isEqualToString:@"file"] || [scheme isEqualToString:@"sqlite"]) return UDSQLDialectSQLite;
    if ([scheme isEqualToString:@"postgresql"] || [scheme isEqualToString:@"postgres"]) return UDSQLDialectPostgreSQL;
    if ([scheme isEqualToString:@"mysql"] || [scheme isEqualToString:@"mariadb"]) return UDSQLDialectMySQL;
    return -1;
}

+ (instancetype)connectionToURL:(NSURL *)url password:(NSString *)password error:(NSError **)error {
    switch ([self dialectOfURL:url]) {
        case UDSQLDialectSQLite: return [UDSQLiteConnection openURL:url password:password error:error];
        case UDSQLDialectPostgreSQL: return [UDPostgreSQLConnection openURL:url password:password error:error];
        case UDSQLDialectMySQL: return [UDMySQLConnection openURL:url password:password error:error];
        default:
            if (error) *error = UDSQLError(0, [NSString stringWithFormat:@"No driver speaks “%@:”.", url.scheme ?: @""], nil);
            return nil;
    }
}

- (instancetype)initWithURL:(NSURL *)url dialect:(UDSQLDialect)dialect {
    self = [super init];
    if (self) {
        _URL = [url copy];
        _dialect = dialect;
        _serverDescription = @"";
    }
    return self;
}

- (UDSQLResult *)execute:(NSString *)sql parameters:(NSArray *)parameters maxRows:(NSUInteger)maxRows error:(NSError **)error {
    if (error) *error = UDSQLError(0, @"Not connected.", nil);
    return nil;
}

- (void)cancel {
}

- (void)close {
}

- (NSString *)quotedIdentifier:(NSString *)name {
    return [NSString stringWithFormat:@"\"%@\"", [name stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""]];
}

@end

// ---------------------------------------------------------------------------
// MARK: - A library loaded when first needed
// ---------------------------------------------------------------------------

@implementation UDSQLLibrary {
    void *_handle;
}

+ (instancetype)libraryForKey:(NSString *)key names:(NSArray<NSString *> *)names install:(NSString *)install error:(NSError **)error {
    static NSMutableDictionary<NSString *, UDSQLLibrary *> *loaded;
    @synchronized (self) {
        if (!loaded) loaded = [NSMutableDictionary dictionary];
        UDSQLLibrary *library = loaded[key];
        if (library) return library;
        for (NSString *name in names) {
#ifdef _WIN32
            void *handle = (void *)LoadLibraryW((const wchar_t *)[name cStringUsingEncoding:NSUTF16LittleEndianStringEncoding]);
#else
            void *handle = dlopen(name.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
#endif
            if (!handle) continue;
            library = [[UDSQLLibrary alloc] init];
            library->_handle = handle;
            loaded[key] = library;
            return library;
        }
        if (error) {
            *error = UDSQLError(0, [NSString stringWithFormat:@"%@ isn't installed. %@", key, install], nil);
        }
        return nil;
    }
}

- (void *)function:(const char *)name {
#ifdef _WIN32
    return (void *)GetProcAddress((HMODULE)_handle, name);
#else
    return dlsym(_handle, name);
#endif
}

@end
